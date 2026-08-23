require "compress/zlib"
require "digest/crc32"

module Eagle
  module Codecs
    # Pure Crystal PNG decoder/encoder. Decodes all standard color types and bit
    # depths (incl. 16-bit, palette, tRNS, Adam7 interlace) into RGBA8.
    module PNG
      SIGNATURE = Bytes[137, 80, 78, 71, 13, 10, 26, 10]

      def self.png?(data : Bytes) : Bool
        data.size >= 8 && data[0, 8] == SIGNATURE
      end

      def self.decode(data : Bytes) : Image
        raise AssetError.new("Not a PNG") unless png?(data)
        io = IO::Memory.new(data)
        io.skip(8)
        width = height = 0
        bit_depth = 0_u8; color_type = 0_u8; interlace = 0_u8
        palette = Bytes.empty
        trns = Bytes.empty
        idat = IO::Memory.new
        loop do
          len = io.read_bytes(UInt32, IO::ByteFormat::BigEndian)
          type = io.read_string(4)
          chunk = Bytes.new(len)
          io.read_fully(chunk)
          io.skip(4) # CRC (not verified for speed)
          case type
          when "IHDR"
            cio = IO::Memory.new(chunk)
            width = cio.read_bytes(UInt32, IO::ByteFormat::BigEndian).to_i
            height = cio.read_bytes(UInt32, IO::ByteFormat::BigEndian).to_i
            bit_depth = cio.read_byte.not_nil!
            color_type = cio.read_byte.not_nil!
            cio.read_byte # compression
            cio.read_byte # filter
            interlace = cio.read_byte.not_nil!
          when "PLTE" then palette = chunk
          when "tRNS" then trns = chunk
          when "IDAT" then idat.write(chunk)
          when "IEND" then break
          end
          break if io.pos >= data.size
        end
        raise AssetError.new("PNG missing IHDR") if width == 0

        channels = case color_type
                   when 0 then 1
                   when 2 then 3
                   when 3 then 1
                   when 4 then 2
                   when 6 then 4
                   else raise AssetError.new("Unsupported PNG color type #{color_type}")
                   end
        bpp = Math.max(1, (channels * bit_depth) // 8) # bytes per complete pixel (filter unit)

        idat.rewind
        raw = IO::Memory.new
        Compress::Zlib::Reader.open(idat) { |z| IO.copy(z, raw) }
        raw_bytes = raw.to_slice

        img = Image.new(width, height)
        if interlace == 0
          decode_pass(raw_bytes, 0, width, height, bit_depth, color_type, channels, bpp, palette, trns) do |x, y, r, g, b, a|
            i = img.index(x, y)
            px = img.pixels
            px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a
          end
        else
          # Adam7
          passes = [{0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8}, {2, 0, 4, 4}, {0, 2, 2, 4}, {1, 0, 2, 2}, {0, 1, 1, 2}]
          offset = 0
          passes.each do |(sx, sy, dx, dy)|
            pw = (width - sx + dx - 1) // dx
            ph = (height - sy + dy - 1) // dy
            next if pw <= 0 || ph <= 0
            offset = decode_pass(raw_bytes, offset, pw, ph, bit_depth, color_type, channels, bpp, palette, trns) do |x, y, r, g, b, a|
              i = img.index(sx + x * dx, sy + y * dy)
              px = img.pixels
              px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a
            end
          end
        end
        img
      end

      # Decodes one (sub)image starting at `offset` in raw; returns new offset.
      private def self.decode_pass(raw : Bytes, offset : Int32, width : Int32, height : Int32, bit_depth : UInt8, color_type : UInt8, channels : Int32, bpp : Int32, palette : Bytes, trns : Bytes, &block : Int32, Int32, UInt8, UInt8, UInt8, UInt8 ->) : Int32
        stride = (width * channels * bit_depth + 7) // 8
        prev = Bytes.new(stride)
        cur = Bytes.new(stride)
        pos = offset
        max = (1 << bit_depth) - 1
        height.times do |y|
          raise AssetError.new("PNG data truncated") if pos + 1 + stride > raw.size
          filter = raw[pos]; pos += 1
          cur.copy_from(raw[pos, stride]); pos += stride
          unfilter(filter, cur, prev, bpp)
          width.times do |x|
            r = g = b = 0_u8; a = 255_u8
            case color_type
            when 0 # gray
              v = sample(cur, x, bit_depth)
              gray = bit_depth == 16 ? (v >> 8).to_u8 : (v * 255 // max).to_u8
              r = g = b = gray
              a = 0_u8 if trns.size >= 2 && v == ((trns[0].to_i << 8) | trns[1])
            when 2 # rgb
              r, g, b = sample3(cur, x, bit_depth)
              if trns.size >= 6
                if bit_depth == 8 && cur[x * 3] == trns[1] && cur[x * 3 + 1] == trns[3] && cur[x * 3 + 2] == trns[5]
                  a = 0_u8
                end
              end
            when 3 # palette
              idx = sample(cur, x, bit_depth)
              if idx * 3 + 2 < palette.size
                r = palette[idx * 3]; g = palette[idx * 3 + 1]; b = palette[idx * 3 + 2]
              end
              a = trns[idx] if idx < trns.size
            when 4 # gray + alpha
              if bit_depth == 16
                r = g = b = cur[x * 4]; a = cur[x * 4 + 2]
              else
                r = g = b = cur[x * 2]; a = cur[x * 2 + 1]
              end
            when 6 # rgba
              if bit_depth == 16
                r = cur[x * 8]; g = cur[x * 8 + 2]; b = cur[x * 8 + 4]; a = cur[x * 8 + 6]
              else
                r = cur[x * 4]; g = cur[x * 4 + 1]; b = cur[x * 4 + 2]; a = cur[x * 4 + 3]
              end
            end
            block.call(x, y, r, g, b, a)
          end
          prev, cur = cur, prev
        end
        pos
      end

      private def self.sample(row : Bytes, x : Int32, bit_depth : UInt8) : Int32
        case bit_depth
        when 8 then row[x].to_i
        when 16 then (row[x * 2].to_i << 8) | row[x * 2 + 1]
        else
          per_byte = 8 // bit_depth
          byte = row[x // per_byte]
          shift = 8 - bit_depth * (x % per_byte + 1)
          ((byte >> shift) & ((1 << bit_depth) - 1)).to_i
        end
      end

      private def self.sample3(row : Bytes, x : Int32, bit_depth : UInt8) : {UInt8, UInt8, UInt8}
        if bit_depth == 16
          {row[x * 6], row[x * 6 + 2], row[x * 6 + 4]}
        else
          {row[x * 3], row[x * 3 + 1], row[x * 3 + 2]}
        end
      end

      private def self.unfilter(filter : UInt8, cur : Bytes, prev : Bytes, bpp : Int32) : Nil
        n = cur.size
        case filter
        when 0 then nil
        when 1 # Sub
          (bpp...n).each { |i| cur[i] = (cur[i].to_i + cur[i - bpp]) .to_u8! }
        when 2 # Up
          n.times { |i| cur[i] = (cur[i].to_i + prev[i]).to_u8! }
        when 3 # Average
          n.times do |i|
            left = i >= bpp ? cur[i - bpp].to_i : 0
            cur[i] = (cur[i].to_i + ((left + prev[i]) >> 1)).to_u8!
          end
        when 4 # Paeth
          n.times do |i|
            a = i >= bpp ? cur[i - bpp].to_i : 0
            b = prev[i].to_i
            c = i >= bpp ? prev[i - bpp].to_i : 0
            p = a + b - c
            pa = (p - a).abs; pb = (p - b).abs; pc = (p - c).abs
            pred = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
            cur[i] = (cur[i].to_i + pred).to_u8!
          end
        else
          raise AssetError.new("Bad PNG filter #{filter}")
        end
      end

      # Encodes RGBA8 with per-row adaptive (Sub/Up/None) filtering.
      def self.encode(img : Image, level : Int32 = 6) : Bytes
        buf_out = IO::Memory.new
        buf_out.write(SIGNATURE)
        ihdr = IO::Memory.new
        ihdr.write_bytes(img.width.to_u32, IO::ByteFormat::BigEndian)
        ihdr.write_bytes(img.height.to_u32, IO::ByteFormat::BigEndian)
        ihdr.write_byte(8_u8); ihdr.write_byte(6_u8); ihdr.write_byte(0_u8); ihdr.write_byte(0_u8); ihdr.write_byte(0_u8)
        write_chunk(buf_out, "IHDR", ihdr.to_slice)

        stride = img.width * 4
        raw = IO::Memory.new((stride + 1) * img.height)
        prev = Bytes.new(stride)
        filtered = Bytes.new(stride)
        img.height.times do |y|
          row = img.pixels[y * stride, stride]
          # choose Sub vs Up vs None by minimum sum of absolute values
          best_f = 0_u8; best_sum = Int64::MAX
          {0_u8, 1_u8, 2_u8}.each do |f|
            sum = 0_i64
            stride.times do |i|
              v = case f
                  when 1 then (row[i].to_i - (i >= 4 ? row[i - 4].to_i : 0)).to_u8!
                  when 2 then (row[i].to_i - prev[i].to_i).to_u8!
                  else row[i]
                  end
              sum += v > 127 ? 256 - v : v
              break if sum >= best_sum
            end
            if sum < best_sum
              best_sum = sum; best_f = f
            end
          end
          raw.write_byte(best_f)
          stride.times do |i|
            filtered[i] = case best_f
                          when 1 then (row[i].to_i - (i >= 4 ? row[i - 4].to_i : 0)).to_u8!
                          when 2 then (row[i].to_i - prev[i].to_i).to_u8!
                          else row[i]
                          end
          end
          raw.write(filtered)
          prev.copy_from(row)
        end
        compressed = IO::Memory.new
        Compress::Zlib::Writer.open(compressed, level: level) { |z| z.write(raw.to_slice) }
        write_chunk(buf_out, "IDAT", compressed.to_slice)
        write_chunk(buf_out, "IEND", Bytes.empty)
        buf_out.to_slice
      end

      private def self.write_chunk(io : IO, type : String, data : Bytes) : Nil
        io.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
        crc = Digest::CRC32.checksum(type.to_slice)
        crc = Digest::CRC32.update(data, crc)
        io.write(type.to_slice)
        io.write(data)
        io.write_bytes(crc, IO::ByteFormat::BigEndian)
      end
    end
  end
end
