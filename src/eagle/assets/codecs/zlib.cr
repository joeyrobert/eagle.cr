module Eagle
  module Codecs
    # Pure Crystal zlib/DEFLATE (RFC 1950/1951): full inflate; deflate with LZ77
    # hash chains and fixed Huffman codes. Used by the PNG codec so Eagle needs
    # no libz, including on WebAssembly.
    module Zlib
      class Error < AssetError; end

      # --- inflate -------------------------------------------------------------
      LENGTH_BASE  = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
      LENGTH_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
      DIST_BASE    = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
      DIST_EXTRA   = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
      CL_ORDER     = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

      private class BitReader
        @data : Bytes
        @pos = 0
        @bitbuf = 0_u32
        @bitcnt = 0

        def initialize(@data, @pos = 0); end

        def bits(n : Int32) : Int32
          while @bitcnt < n
            raise Error.new("Unexpected end of deflate stream") if @pos >= @data.size
            @bitbuf |= @data[@pos].to_u32 << @bitcnt
            @pos += 1
            @bitcnt += 8
          end
          v = (@bitbuf & ((1_u32 << n) - 1)).to_i
          @bitbuf >>= n
          @bitcnt -= n
          v
        end

        def align_byte
          @bitbuf = 0_u32; @bitcnt = 0
        end

        def read_byte : UInt8
          raise Error.new("Unexpected end of deflate stream") if @pos >= @data.size
          b = @data[@pos]; @pos += 1; b
        end

        def pos : Int32; @pos; end
      end

      # Canonical Huffman decoding table (count/symbol form, as in zlib's puff).
      private class Huffman
        @count : Array(Int32)
        @symbol : Array(Int32)

        def initialize(lengths : Array(Int32))
          @count = Array(Int32).new(16, 0)
          lengths.each { |l| @count[l] += 1 }
          @count[0] = 0
          offs = Array(Int32).new(16, 0)
          (1...15).each { |i| offs[i + 1] = offs[i] + @count[i] }
          @symbol = Array(Int32).new(lengths.size, 0)
          lengths.each_with_index do |l, sym|
            next if l == 0
            @symbol[offs[l]] = sym
            offs[l] += 1
          end
        end

        def decode(r : BitReader) : Int32
          code = 0; first = 0; index = 0
          (1..15).each do |len|
            code |= r.bits(1)
            count = @count[len]
            return @symbol[index + (code - first)] if code - count < first
            index += count
            first += count
            first <<= 1
            code <<= 1
          end
          raise Error.new("Invalid Huffman code")
        end
      end

      @@fixed_lit : Huffman? = nil
      @@fixed_dist : Huffman? = nil

      private def self.fixed_tables : {Huffman, Huffman}
        lit = @@fixed_lit ||= begin
          l = Array(Int32).new(288) { |i| i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8 }
          Huffman.new(l)
        end
        dist = @@fixed_dist ||= Huffman.new(Array(Int32).new(30, 5))
        {lit, dist}
      end

      # Inflate raw DEFLATE data.
      def self.inflate(data : Bytes, expected_size : Int32 = 0) : Bytes
        out_ = IO::Memory.new(expected_size > 0 ? expected_size : data.size * 4)
        r = BitReader.new(data)
        window = Bytes.new(32768)
        wpos = 0
        emit = ->(b : UInt8) do
          out_.write_byte(b)
          window[wpos] = b
          wpos = (wpos + 1) & 32767
        end
        loop do
          final = r.bits(1)
          type = r.bits(2)
          case type
          when 0
            r.align_byte
            len = r.read_byte.to_i | (r.read_byte.to_i << 8)
            nlen = r.read_byte.to_i | (r.read_byte.to_i << 8)
            raise Error.new("Stored block length mismatch") unless (len ^ 0xFFFF) == nlen
            len.times { emit.call(r.read_byte) }
          when 1, 2
            lit, dist = type == 1 ? fixed_tables : dynamic_tables(r)
            loop do
              sym = lit.decode(r)
              if sym < 256
                emit.call(sym.to_u8)
              elsif sym == 256
                break
              else
                sym -= 257
                raise Error.new("Bad length symbol") if sym >= 29
                length = LENGTH_BASE[sym] + r.bits(LENGTH_EXTRA[sym])
                dsym = dist.decode(r)
                raise Error.new("Bad distance symbol") if dsym >= 30
                distance = DIST_BASE[dsym] + r.bits(DIST_EXTRA[dsym])
                raise Error.new("Distance too far back") if distance > out_.size
                length.times do
                  emit.call(window[(wpos - distance) & 32767])
                end
              end
            end
          else
            raise Error.new("Invalid block type")
          end
          break if final == 1
        end
        out_.to_slice
      end

      private def self.dynamic_tables(r : BitReader) : {Huffman, Huffman}
        nlen = r.bits(5) + 257
        ndist = r.bits(5) + 1
        ncode = r.bits(4) + 4
        raise Error.new("Bad dynamic block counts") if nlen > 286 || ndist > 30
        cl = Array(Int32).new(19, 0)
        ncode.times { |i| cl[CL_ORDER[i]] = r.bits(3) }
        clh = Huffman.new(cl)
        lengths = Array(Int32).new(nlen + ndist, 0)
        i = 0
        while i < nlen + ndist
          sym = clh.decode(r)
          if sym < 16
            lengths[i] = sym; i += 1
          else
            rep = 0; val = 0
            case sym
            when 16
              raise Error.new("Repeat with no previous length") if i == 0
              val = lengths[i - 1]; rep = 3 + r.bits(2)
            when 17 then rep = 3 + r.bits(3)
            else rep = 11 + r.bits(7)
            end
            raise Error.new("Too many lengths") if i + rep > nlen + ndist
            rep.times { lengths[i] = val; i += 1 }
          end
        end
        {Huffman.new(lengths[0, nlen]), Huffman.new(lengths[nlen, ndist])}
      end

      # Decompress a zlib stream (2-byte header, DEFLATE, Adler-32 trailer).
      def self.decompress(data : Bytes, expected_size : Int32 = 0) : Bytes
        raise Error.new("zlib stream too short") if data.size < 6
        cmf = data[0]; flg = data[1]
        raise Error.new("Not a zlib stream") unless (cmf & 0x0F) == 8 && ((cmf.to_i << 8) | flg) % 31 == 0
        raise Error.new("Preset dictionary unsupported") if flg & 0x20 != 0
        out_ = inflate(data[2, data.size - 2], expected_size)
        out_
      end

      # --- deflate -------------------------------------------------------------
      def self.adler32(data : Bytes) : UInt32
        a = 1_u32; b = 0_u32
        i = 0
        while i < data.size
          n = Math.min(5552, data.size - i)
          n.times do |k|
            a += data[i + k]
            b += a
          end
          a %= 65521; b %= 65521
          i += n
        end
        (b << 16) | a
      end

      private class BitWriter
        getter io = IO::Memory.new
        @bitbuf = 0_u32
        @bitcnt = 0

        def write(value : Int, n : Int32)
          @bitbuf |= value.to_u32 << @bitcnt
          @bitcnt += n
          while @bitcnt >= 8
            @io.write_byte((@bitbuf & 0xFF).to_u8)
            @bitbuf >>= 8
            @bitcnt -= 8
          end
        end

        # Huffman codes are written MSB-first (bit-reversed).
        def write_code(code : Int, len : Int32)
          rev = 0
          len.times { |i| rev |= ((code >> i) & 1) << (len - 1 - i) }
          write(rev, len)
        end

        def flush
          @io.write_byte((@bitbuf & 0xFF).to_u8) if @bitcnt > 0
          @bitbuf = 0_u32; @bitcnt = 0
        end
      end

      # Fixed-Huffman literal/length code for a symbol: {code, length}.
      @[AlwaysInline]
      private def self.fixed_lit_code(sym : Int32) : {Int32, Int32}
        if sym < 144
          {0x30 + sym, 8}
        elsif sym < 256
          {0x190 + (sym - 144), 9}
        elsif sym < 280
          {sym - 256, 7}
        else
          {0xC0 + (sym - 280), 8}
        end
      end

      # Compress with LZ77 (hash chains) + fixed Huffman codes. `level` 0 stores.
      def self.deflate(data : Bytes, level : Int32 = 6) : Bytes
        w = BitWriter.new
        if level <= 0 || data.size < 4
          # stored blocks
          pos = 0
          loop do
            n = Math.min(65535, data.size - pos)
            last = pos + n >= data.size
            w.write(last ? 1 : 0, 1); w.write(0, 2)
            w.flush
            w.io.write_byte((n & 0xFF).to_u8); w.io.write_byte((n >> 8).to_u8)
            w.io.write_byte(((n ^ 0xFFFF) & 0xFF).to_u8); w.io.write_byte(((n ^ 0xFFFF) >> 8).to_u8)
            w.io.write(data[pos, n])
            pos += n
            break if last
          end
          return w.io.to_slice
        end
        w.write(1, 1); w.write(1, 2) # final block, fixed Huffman
        hash_size = 1 << 15
        head = Array(Int32).new(hash_size, -1)
        prev = Array(Int32).new(data.size, -1)
        max_chain = level >= 8 ? 128 : level >= 4 ? 32 : 8
        i = 0
        n = data.size
        hash = ->(p : Int32) { ((data[p].to_i << 10) ^ (data[p + 1].to_i << 5) ^ data[p + 2].to_i) & (hash_size - 1) }
        while i < n
          best_len = 0; best_dist = 0
          if i + 3 <= n
            h = hash.call(i)
            cand = head[h]
            chain = 0
            while cand >= 0 && chain < max_chain && i - cand <= 32768
              if data[cand + best_len] == data[i + best_len] && data[cand] == data[i]
                l = 0
                max = Math.min(258, n - i)
                while l < max && data[cand + l] == data[i + l]
                  l += 1
                end
                if l > best_len
                  best_len = l; best_dist = i - cand
                  break if l == max
                end
              end
              cand = prev[cand]
              chain += 1
            end
            prev[i] = head[h]; head[h] = i
          end
          if best_len >= 3
            # length code
            li = LENGTH_BASE.size - 1
            LENGTH_BASE.each_with_index { |b, k| li = k if b <= best_len }
            code, len = fixed_lit_code(257 + li)
            w.write_code(code, len)
            w.write(best_len - LENGTH_BASE[li], LENGTH_EXTRA[li]) if LENGTH_EXTRA[li] > 0
            di = DIST_BASE.size - 1
            DIST_BASE.each_with_index { |b, k| di = k if b <= best_dist }
            w.write_code(di, 5)
            w.write(best_dist - DIST_BASE[di], DIST_EXTRA[di]) if DIST_EXTRA[di] > 0
            # insert skipped positions into the hash chains
            (1...best_len).each do |k|
              p = i + k
              if p + 3 <= n
                h2 = hash.call(p)
                prev[p] = head[h2]; head[h2] = p
              end
            end
            i += best_len
          else
            code, len = fixed_lit_code(data[i].to_i)
            w.write_code(code, len)
            i += 1
          end
        end
        code, len = fixed_lit_code(256)
        w.write_code(code, len)
        w.flush
        w.io.to_slice
      end

      # zlib-wrapped deflate.
      def self.compress(data : Bytes, level : Int32 = 6) : Bytes
        io = IO::Memory.new
        io.write_byte(0x78_u8)
        io.write_byte(level >= 6 ? 0xDA_u8 : level >= 2 ? 0x9C_u8 : 0x01_u8)
        io.write(deflate(data, level))
        io.write_bytes(adler32(data), IO::ByteFormat::BigEndian)
        io.to_slice
      end
    end
  end
end
