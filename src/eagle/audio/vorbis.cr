module Eagle
  module Codecs
    # Ogg container + Vorbis I decoder in pure Crystal (floor type 1, residues 0/1/2).
    module Vorbis
      def self.ogg?(data : Bytes) : Bool
        data.size >= 4 && data[0, 4] == "OggS".to_slice
      end

      class DecodeError < AssetError; end

      # --- Ogg pages -> packets -------------------------------------------------
      def self.packets(data : Bytes) : {Array(Bytes), Int64}
        packets = [] of Bytes
        current = IO::Memory.new
        pos = 0
        granule = 0_i64
        while pos + 27 <= data.size
          raise DecodeError.new("Bad Ogg page at #{pos}") unless data[pos, 4] == "OggS".to_slice
          granule = IO::ByteFormat::LittleEndian.decode(Int64, data[pos + 6, 8])
          nsegs = data[pos + 26].to_i
          table = data[pos + 27, nsegs]
          body = pos + 27 + nsegs
          nsegs.times do |i|
            len = table[i].to_i
            current.write(data[body, len]) if len > 0
            body += len
            if len < 255
              packets << current.to_slice.dup
              current = IO::Memory.new
            end
          end
          pos = body
        end
        {packets, granule}
      end

      # LSB-first bit reader.
      class BitReader
        @data : Bytes
        @pos = 0
        @bit = 0

        def initialize(@data); end

        def read(n : Int32) : UInt32
          v = 0_u32
          shift = 0
          while n > 0
            raise DecodeError.new("Unexpected end of packet") if @pos >= @data.size
            avail = 8 - @bit
            take = Math.min(avail, n)
            bits = (@data[@pos].to_u32 >> @bit) & ((1_u32 << take) - 1)
            v |= bits << shift
            shift += take
            n -= take
            @bit += take
            if @bit == 8
              @bit = 0; @pos += 1
            end
          end
          v
        end

        def read_bit : Int32; read(1).to_i; end
        def read_bool : Bool; read(1) == 1; end
        def eof? : Bool; @pos >= @data.size; end
      end

      def self.ilog(x : Int) : Int32
        n = 0
        while x > 0
          n += 1; x >>= 1
        end
        n
      end

      def self.float32_unpack(x : UInt32) : Float32
        mantissa = (x & 0x1fffff).to_f64
        sign = x & 0x80000000
        exponent = ((x & 0x7fe00000) >> 21).to_i
        mantissa = -mantissa if sign != 0
        (mantissa * (2.0 ** (exponent - 788))).to_f32
      end

      def self.lookup1_values(entries : Int32, dims : Int32) : Int32
        r = (entries.to_f64 ** (1.0 / dims)).floor.to_i
        while (r + 1).to_f64 ** dims <= entries
          r += 1
        end
        while r.to_f64 ** dims > entries
          r -= 1
        end
        r
      end

      class Codebook
        getter dims : Int32
        getter entries : Int32
        getter lengths : Array(Int32)
        getter lookup_type : Int32
        @codes = {} of UInt32 => Int32 # (len << 24 | code) -> entry
        @min_len = 32
        @max_len = 0
        getter values : Array(Float32) = [] of Float32 # VQ table: entries * dims (expanded)
        @sequence_p = false

        def initialize(r : BitReader)
          raise DecodeError.new("Bad codebook sync") unless r.read(24) == 0x564342
          @dims = r.read(16).to_i
          @entries = r.read(24).to_i
          ordered = r.read_bool
          @lengths = Array(Int32).new(@entries, -1)
          if ordered
            current = 0
            len = r.read(5).to_i + 1
            while current < @entries
              number = r.read(Vorbis.ilog(@entries - current)).to_i
              raise DecodeError.new("Codebook overflow") if current + number > @entries
              number.times { |i| @lengths[current + i] = len }
              current += number
              len += 1
            end
          else
            sparse = r.read_bool
            @entries.times do |i|
              if sparse
                @lengths[i] = r.read(5).to_i + 1 if r.read_bool
              else
                @lengths[i] = r.read(5).to_i + 1
              end
            end
          end
          assign_codewords
          @lookup_type = r.read(4).to_i
          case @lookup_type
          when 0
          when 1, 2
            minimum = Vorbis.float32_unpack(r.read(32))
            delta = Vorbis.float32_unpack(r.read(32))
            value_bits = r.read(4).to_i + 1
            @sequence_p = r.read_bool
            lookup_values = @lookup_type == 1 ? Vorbis.lookup1_values(@entries, @dims) : @entries * @dims
            mults = Array(UInt32).new(lookup_values) { r.read(value_bits) }
            @values = Array(Float32).new(@entries * @dims, 0_f32)
            @entries.times do |e|
              last = 0_f32
              if @lookup_type == 1
                div = 1
                @dims.times do |d|
                  off = (e // div) % lookup_values
                  v = mults[off] * delta + minimum + last
                  @values[e * @dims + d] = v
                  last = v if @sequence_p
                  div *= lookup_values
                end
              else
                @dims.times do |d|
                  v = mults[e * @dims + d] * delta + minimum + last
                  @values[e * @dims + d] = v
                  last = v if @sequence_p
                end
              end
            end
          else
            raise DecodeError.new("Bad lookup type #{@lookup_type}")
          end
        end

        # Canonical Huffman assignment (Vorbis I spec 3.2.1, as in stb_vorbis).
        private def assign_codewords
          available = Array(UInt32).new(32, 0_u32)
          first = @lengths.index { |l| l > 0 }
          return unless first
          k = first
          add(0_u32, @lengths[k], k)
          (1..@lengths[k]).each { |i| available[i] = 1_u32 << (32 - i) }
          (k + 1...@entries).each do |i|
            len = @lengths[i]
            next if len <= 0
            z = len
            while z > 0 && available[z] == 0
              z -= 1
            end
            raise DecodeError.new("Over-subscribed codebook") if z == 0
            res = available[z]
            available[z] = 0_u32
            add(res >> (32 - len), len, i)
            if z != len
              (z + 1..len).each { |y| available[y] = res + (1_u32 << (32 - y)) }
            end
          end
        end

        private def add(code : UInt32, len : Int32, entry : Int32)
          @codes[(len.to_u32 << 24) | code] = entry
          @min_len = Math.min(@min_len, len)
          @max_len = Math.max(@max_len, len)
        end

        # Read one codeword (MSB-first) and return its entry.
        def decode(r : BitReader) : Int32
          code = 0_u32
          len = 0
          while len < 32
            code = (code << 1) | r.read(1)
            len += 1
            next if len < @min_len
            if e = @codes[(len.to_u32 << 24) | code]?
              return e
            end
            break if len >= @max_len
          end
          raise DecodeError.new("Invalid codeword")
        end

        # Decode a VQ vector into `out` starting at offset, adding.
        def decode_vector_add(r : BitReader, out_v : Slice(Float32), offset : Int32, step : Int32 = 1) : Nil
          e = decode(r)
          base = e * @dims
          @dims.times do |d|
            i = offset + d * step
            out_v[i] += @values[base + d] if i < out_v.size
          end
        end
        def info : String; "dims=#{@dims} entries=#{@entries} lookup=#{@lookup_type} seq=#{@sequence_p}"; end
      end

      class Floor1
        getter partitions : Int32
        getter partition_classes : Array(Int32)
        getter class_dims : Array(Int32)
        getter class_subclasses : Array(Int32)
        getter class_masterbooks : Array(Int32)
        getter subclass_books : Array(Array(Int32))
        getter multiplier : Int32
        getter x_list : Array(Int32)
        getter sorted : Array(Int32) # indices sorted by x
        getter neighbors : Array({Int32, Int32}) # low, high neighbour indices for i >= 2

        def initialize(r : BitReader)
          @partitions = r.read(5).to_i
          @partition_classes = Array(Int32).new(@partitions) { r.read(4).to_i }
          max_class = @partition_classes.max? || -1
          @class_dims = [] of Int32; @class_subclasses = [] of Int32; @class_masterbooks = [] of Int32
          @subclass_books = [] of Array(Int32)
          (max_class + 1).times do
            @class_dims << r.read(3).to_i + 1
            sub = r.read(2).to_i
            @class_subclasses << sub
            @class_masterbooks << (sub != 0 ? r.read(8).to_i : -1)
            @subclass_books << Array(Int32).new(1 << sub) { r.read(8).to_i - 1 }
          end
          @multiplier = r.read(2).to_i + 1
          rangebits = r.read(4).to_i
          @x_list = [0, 1 << rangebits]
          @partitions.times do |i|
            c = @partition_classes[i]
            @class_dims[c].times { @x_list << r.read(rangebits).to_i }
          end
          raise DecodeError.new("Floor has too many values") if @x_list.size > 65
          @sorted = (0...@x_list.size).to_a.sort_by { |i| @x_list[i] }
          @neighbors = Array({Int32, Int32}).new(@x_list.size) { {0, 0} }
          (2...@x_list.size).each do |i|
            lo = 0; hi = 1
            (0...i).each do |j|
              lo = j if @x_list[j] < @x_list[i] && @x_list[j] >= @x_list[lo]
              hi = j if @x_list[j] > @x_list[i] && @x_list[j] <= @x_list[hi]
            end
            @neighbors[i] = {lo, hi}
          end
        end

        RANGES = [256, 128, 86, 64]

        # Returns the floor curve (length n2) or nil when the channel is silent.
        def decode(r : BitReader, books : Array(Codebook), n2 : Int32) : Slice(Float32)?
          return nil unless r.read_bool
          range = RANGES[@multiplier - 1]
          bits = Vorbis.ilog(range - 1)
          y = Array(Int32).new(@x_list.size, 0)
          y[0] = r.read(bits).to_i
          y[1] = r.read(bits).to_i
          offset = 2
          @partitions.times do |i|
            c = @partition_classes[i]
            cdim = @class_dims[c]; cbits = @class_subclasses[c]
            csub = (1 << cbits) - 1
            cval = cbits > 0 ? books[@class_masterbooks[c]].decode(r) : 0
            cdim.times do |j|
              book = @subclass_books[c][cval & csub]
              cval >>= cbits
              y[offset + j] = book >= 0 ? books[book].decode(r) : 0
            end
            offset += cdim
          end
          # amplitude synthesis (step 2)
          final = Array(Int32).new(@x_list.size, 0)
          step2 = Array(Bool).new(@x_list.size, false)
          step2[0] = step2[1] = true
          final[0] = y[0]; final[1] = y[1]
          (2...@x_list.size).each do |i|
            lo, hi = @neighbors[i]
            predicted = render_point(@x_list[lo], final[lo], @x_list[hi], final[hi], @x_list[i])
            val = y[i]
            highroom = range - predicted
            lowroom = predicted
            room = highroom < lowroom ? highroom * 2 : lowroom * 2
            if val != 0
              step2[lo] = true; step2[hi] = true; step2[i] = true
              if val >= room
                final[i] = highroom > lowroom ? val - lowroom + predicted : predicted - val + highroom - 1
              elsif val.odd?
                final[i] = predicted - ((val + 1) >> 1)
              else
                final[i] = predicted + (val >> 1)
              end
            else
              step2[i] = false
              final[i] = predicted
            end
          end
          # curve synthesis
          curve = Slice(Float32).new(n2, 0_f32)
          hx = 0; lx = 0
          ly = final[@sorted[0]] * @multiplier
          @sorted.each do |i|
            next unless step2[i]
            hy = final[i] * @multiplier
            hx = @x_list[i]
            render_line(lx, ly, hx, hy, curve)
            lx = hx; ly = hy
          end
          if hx < n2
            hy = ly
            render_line(hx, hy, n2, hy, curve)
          end
          curve
        end

        private def render_point(x0, y0, x1, y1, x) : Int32
          dy = y1 - y0
          adx = x1 - x0
          ady = dy.abs
          err = ady * (x - x0)
          off = err // adx
          dy < 0 ? y0 - off : y0 + off
        end

        private def render_line(x0 : Int32, y0 : Int32, x1 : Int32, y1 : Int32, v : Slice(Float32))
          dy = y1 - y0
          adx = x1 - x0
          return if adx <= 0
          ady = dy.abs
          base = dy.tdiv(adx)
          x = x0; y = y0; err = 0
          sy = dy < 0 ? base - 1 : base + 1
          ady -= base.abs * adx
          v[x] = INVERSE_DB[y.clamp(0, 255)] if x < v.size
          (x0 + 1...x1).each do |xx|
            err += ady
            if err >= adx
              err -= adx; y += sy
            else
              y += base
            end
            v[xx] = INVERSE_DB[y.clamp(0, 255)] if xx < v.size
          end
        end

        # floor1_inverse_dB_table: 1.0649863e-07 at 0 rising to 1.0 at 255 (exp(-16.055/255 per step)).
        INVERSE_DB = begin
          t = Slice(Float32).new(256)
          256.times { |i| t[i] = Math.exp((i - 255) * 0.062961).to_f32 }
          t[0] = 1.0649863e-07_f32
          t
        end
      end

      class Residue
        getter type : Int32
        getter begin_ : Int32
        getter end_ : Int32
        getter partition_size : Int32
        getter classifications : Int32
        getter classbook : Int32
        getter books : Array(Array(Int32))

        def initialize(r : BitReader, @type : Int32)
          @begin_ = r.read(24).to_i
          @end_ = r.read(24).to_i
          @partition_size = r.read(24).to_i + 1
          @classifications = r.read(6).to_i + 1
          @classbook = r.read(8).to_i
          cascade = Array(Int32).new(@classifications) do
            low = r.read(3).to_i
            high = r.read_bool ? r.read(5).to_i : 0
            high * 8 + low
          end
          @books = Array(Array(Int32)).new(@classifications) do |i|
            Array(Int32).new(8) { |j| (cascade[i] & (1 << j)) != 0 ? r.read(8).to_i : -1 }
          end
        end

        # Decodes into vectors[ch] (each of size n2). do_not_decode flags per channel.
        def decode(r : BitReader, books : Array(Codebook), vectors : Array(Slice(Float32)), do_not_decode : Array(Bool), n2 : Int32) : Nil
          ch = vectors.size
          if @type == 2
            return if do_not_decode.all?
            inter = Slice(Float32).new(n2 * ch, 0_f32)
            decode_into(r, books, [inter], [false], n2 * ch)
            ch.times { |c| n2.times { |i| vectors[c][i] = inter[i * ch + c] } }
          else
            decode_into(r, books, vectors, do_not_decode, n2)
          end
        end

        private def decode_into(r, books, vectors, dnd, actual_size)
          cb = books[@classbook]
          classwords = cb.dims
          lim_begin = Math.min(@begin_, actual_size)
          lim_end = Math.min(@end_, actual_size)
          n_to_read = lim_end - lim_begin
          return if n_to_read <= 0
          partitions_to_read = n_to_read // @partition_size
          ch = vectors.size
          classif = Array(Array(Int32)).new(ch) { Array(Int32).new(partitions_to_read + classwords, 0) }
          8.times do |pass|
            partition_count = 0
            while partition_count < partitions_to_read
              if pass == 0
                ch.times do |j|
                  next if dnd[j]
                  temp = cb.decode(r)
                  (classwords - 1).downto(0) do |i|
                    classif[j][partition_count + i] = temp % @classifications
                    temp //= @classifications
                  end
                end
              end
              classwords.times do
                break if partition_count >= partitions_to_read
                ch.times do |j|
                  next if dnd[j]
                  vqclass = classif[j][partition_count]
                  vqbook = @books[vqclass][pass]
                  next if vqbook < 0
                  book = books[vqbook]
                  offset = lim_begin + partition_count * @partition_size
                  if @type == 0
                    step = @partition_size // book.dims
                    step.times { |i| book.decode_vector_add(r, vectors[j], offset + i, step) }
                  else
                    i = 0
                    while i < @partition_size
                      book.decode_vector_add(r, vectors[j], offset + i)
                      i += book.dims
                    end
                  end
                end
                partition_count += 1
              end
            end
          end
        end
      end

      record Mapping, submaps : Int32, coupling : Array({Int32, Int32}), mux : Array(Int32), submap_floor : Array(Int32), submap_residue : Array(Int32)
      record Mode, blockflag : Bool, mapping : Int32

      class Decoder
        getter channels : Int32
        getter sample_rate : Int32
        getter blocksizes : {Int32, Int32}
        getter books = [] of Codebook
        @floors = [] of Floor1
        @residues = [] of Residue
        @mappings = [] of Mapping
        @modes = [] of Mode
        @windows = {} of Int32 => Slice(Float32)
        @imdct = {} of Int32 => IMDCT
        # overlap state
        @prev : Array(Slice(Float32))? = nil
        @prev_n = 0
        @prev_right_start = 0
        @prev_right_end = 0
        @prev_next_flag = false
        # Summary of the parsed setup header (for tools and tests).
        def info : String
          "floors=#{@floors.size} residues=#{@residues.map(&.type)} rbegin/end=#{@residues.map { |r| {r.begin_, r.end_, r.partition_size, r.classifications} }} mappings=#{@mappings.map { |m| {m.submaps, m.coupling, m.mux, m.submap_floor, m.submap_residue} }} modes=#{@modes.size} books=#{@books.size} floor_x=#{@floors.map { |f| f.x_list.size }} multipliers=#{@floors.map(&.multiplier)}"
        end

        def initialize(id : Bytes, setup : Bytes)
          r = BitReader.new(id)
          check_header(r, 1)
          raise DecodeError.new("Unsupported Vorbis version") unless r.read(32) == 0
          @channels = r.read(8).to_i
          @sample_rate = r.read(32).to_i
          r.read(32); r.read(32); r.read(32) # bitrates
          bs = r.read(8)
          @blocksizes = {1 << (bs & 0xF), 1 << (bs >> 4)}
          raise DecodeError.new("Bad framing") unless r.read_bool
          parse_setup(setup)
        end

        private def check_header(r, type)
          raise DecodeError.new("Bad header type") unless r.read(8) == type
          "vorbis".each_byte { |b| raise DecodeError.new("Bad header magic") unless r.read(8) == b }
        end

        private def parse_setup(data)
          r = BitReader.new(data)
          check_header(r, 5)
          (r.read(8).to_i + 1).times { @books << Codebook.new(r) }
          (r.read(6).to_i + 1).times { raise DecodeError.new("Bad time domain") unless r.read(16) == 0 }
          (r.read(6).to_i + 1).times do
            type = r.read(16)
            raise DecodeError.new("Floor type #{type} unsupported (only floor 1)") unless type == 1
            @floors << Floor1.new(r)
          end
          (r.read(6).to_i + 1).times do
            type = r.read(16).to_i
            raise DecodeError.new("Bad residue type") if type > 2
            @residues << Residue.new(r, type)
          end
          (r.read(6).to_i + 1).times do
            raise DecodeError.new("Bad mapping type") unless r.read(16) == 0
            submaps = r.read_bool ? r.read(4).to_i + 1 : 1
            coupling = [] of {Int32, Int32}
            if r.read_bool
              (r.read(8).to_i + 1).times do
                m = r.read(Vorbis.ilog(@channels - 1)).to_i
                a = r.read(Vorbis.ilog(@channels - 1)).to_i
                coupling << {m, a}
              end
            end
            raise DecodeError.new("Bad mapping reserved") unless r.read(2) == 0
            mux = Array(Int32).new(@channels, 0)
            mux = Array(Int32).new(@channels) { r.read(4).to_i } if submaps > 1
            fl = [] of Int32; res = [] of Int32
            submaps.times do
              r.read(8)
              fl << r.read(8).to_i
              res << r.read(8).to_i
            end
            @mappings << Mapping.new(submaps, coupling, mux, fl, res)
          end
          (r.read(6).to_i + 1).times do
            bf = r.read_bool
            raise DecodeError.new("Bad mode") unless r.read(16) == 0 && r.read(16) == 0
            @modes << Mode.new(bf, r.read(8).to_i)
          end
          raise DecodeError.new("Bad setup framing") unless r.read_bool
        end

        private def window(n : Int32) : Slice(Float32)
          @windows[n] ||= begin
            w = Slice(Float32).new(n)
            n.times { |i| w[i] = Math.sin(Math::PI / 2 * Math.sin((i + 0.5) / n * Math::PI) ** 2).to_f32 }
            w
          end
        end

        private def imdct(n : Int32) : IMDCT
          @imdct[n] ||= IMDCT.new(n)
        end

        # Decode one audio packet; returns finished PCM (per channel) or nil for the first packet.
        def decode_packet(packet : Bytes) : Array(Slice(Float32))?
          r = BitReader.new(packet)
          raise DecodeError.new("Not an audio packet") if r.read_bool
          mode = @modes[r.read(Vorbis.ilog(@modes.size - 1)).to_i]
          n = mode.blockflag ? @blocksizes[1] : @blocksizes[0]
          n2 = n // 2
          prev_flag = next_flag = false
          if mode.blockflag
            prev_flag = r.read_bool
            next_flag = r.read_bool
          end
          n0 = @blocksizes[0]
          left_start = mode.blockflag && !prev_flag ? n // 4 - n0 // 4 : 0
          left_end = mode.blockflag && !prev_flag ? n // 4 + n0 // 4 : n2
          left_n = mode.blockflag && !prev_flag ? n0 // 2 : n2
          right_start = mode.blockflag && !next_flag ? 3 * n // 4 - n0 // 4 : n2
          right_end = mode.blockflag && !next_flag ? 3 * n // 4 + n0 // 4 : n
          right_n = mode.blockflag && !next_flag ? n0 // 2 : n2

          mapping = @mappings[mode.mapping]
          floors = Array(Slice(Float32)?).new(@channels, nil)
          @channels.times do |c|
            sub = mapping.mux[c]
            floors[c] = @floors[mapping.submap_floor[sub]].decode(r, @books, n2)
          end
          no_residue = floors.map(&.nil?)
          # coupled channels: if either has a floor, both get residue
          mapping.coupling.each do |(m, a)|
            if !no_residue[m] || !no_residue[a]
              no_residue[m] = no_residue[a] = false
            end
          end
          vectors = Array(Slice(Float32)).new(@channels) { Slice(Float32).new(n2, 0_f32) }
          mapping.submaps.times do |s|
            chs = [] of Int32
            @channels.times { |c| chs << c if mapping.mux[c] == s }
            vecs = chs.map { |c| vectors[c] }
            dnd = chs.map { |c| no_residue[c] }
            @residues[mapping.submap_residue[s]].decode(r, @books, vecs, dnd, n2)
          end
          # inverse coupling
          mapping.coupling.reverse_each do |(mi, ai)|
            m = vectors[mi]; a = vectors[ai]
            n2.times do |i|
              mv = m[i]; av = a[i]
              if mv > 0
                if av > 0
                  m[i] = mv; a[i] = mv - av
                else
                  a[i] = mv; m[i] = mv + av
                end
              else
                if av > 0
                  m[i] = mv; a[i] = mv + av
                else
                  a[i] = mv; m[i] = mv - av
                end
              end
            end
          end
          # floor * residue, IMDCT, window
          w = window(n)
          pcm = Array(Slice(Float32)).new(@channels) do |c|
            spec = vectors[c]
            if fl = floors[c]
              n2.times { |i| spec[i] *= fl[i] }
            else
              spec.fill(0_f32)
            end
            out_ = imdct(n).run(spec)
            # apply window with the flat/zero regions
            n.times do |i|
              ww = if i < left_start
                     0_f32
                   elsif i < left_end
                     Math.sin(Math::PI / 2 * Math.sin((i - left_start + 0.5) / left_n * Math::PI / 2) ** 2).to_f32
                   elsif i < right_start
                     1_f32
                   elsif i < right_end
                     Math.sin(Math::PI / 2 * Math.sin((i - right_start + 0.5) / right_n * Math::PI / 2 + Math::PI / 2) ** 2).to_f32
                   else
                     0_f32
                   end
              out_[i] *= ww
            end
            out_
          end
          result = nil
          if prev = @prev
            pn = @prev_n
            len_a = @prev_right_start - pn // 2
            len_b = left_end - left_start
            len_c = n2 - left_end
            total = len_a + len_b + len_c
            result = Array(Slice(Float32)).new(@channels) do |c|
              o = Slice(Float32).new(total)
              p = prev[c]; q = pcm[c]
              len_a.times { |i| o[i] = p[pn // 2 + i] }
              len_b.times { |i| o[len_a + i] = p[@prev_right_start + i] + q[left_start + i] }
              len_c.times { |i| o[len_a + len_b + i] = q[left_end + i] }
              o
            end
          end
          @prev = pcm
          @prev_n = n
          @prev_right_start = right_start
          @prev_right_end = right_end
          result
        end
      end

      # Inverse MDCT: N/2 coefficients -> N samples. Computed as a DCT-IV of size
      # n = N/2 (via an n/2-point complex FFT) followed by the IMDCT symmetry.
      class IMDCT
        getter n : Int32
        @pre_c : Slice(Float32)
        @pre_s : Slice(Float32)
        @post_c : Slice(Float32)
        @post_s : Slice(Float32)
        @fft : FFT

        def initialize(@n)
          m = @n // 2   # DCT-IV size
          h = m // 2    # FFT size
          @pre_c = Slice(Float32).new(h); @pre_s = Slice(Float32).new(h)
          @post_c = Slice(Float32).new(h); @post_s = Slice(Float32).new(h)
          h.times do |k|
            a = -Math::PI * (4 * k + 1) / (4 * m)
            @pre_c[k] = Math.cos(a).to_f32; @pre_s[k] = Math.sin(a).to_f32
            b = -Math::PI * k / m
            @post_c[k] = Math.cos(b).to_f32; @post_s[k] = Math.sin(b).to_f32
          end
          @fft = FFT.new(h)
        end

        # Direct O(N^2) reference (used by specs).
        def naive(x : Slice(Float32)) : Slice(Float32)
          n2 = @n // 2
          out_ = Slice(Float32).new(@n, 0_f32)
          @n.times do |i|
            s = 0.0
            n2.times { |k| s += x[k] * Math.cos(2 * Math::PI / @n * (i + 0.5 + n2 / 2.0) * (k + 0.5)) }
            out_[i] = s.to_f32
          end
          out_
        end

        def run(x : Slice(Float32)) : Slice(Float32)
          m = @n // 2
          h = m // 2
          re = Slice(Float32).new(h); im = Slice(Float32).new(h)
          h.times do |k|
            a = x[2 * k]; b = x[m - 1 - 2 * k]
            c = @pre_c[k]; s = @pre_s[k]
            re[k] = a * c - b * s
            im[k] = a * s + b * c
          end
          @fft.forward(re, im)
          z = Slice(Float32).new(m)
          h.times do |k|
            c = @post_c[k]; s = @post_s[k]
            ur = re[k] * c - im[k] * s
            ui = re[k] * s + im[k] * c
            z[2 * k] = ur
            z[m - 1 - 2 * k] = -ui
          end
          y = Slice(Float32).new(@n)
          half = m // 2
          @n.times do |i|
            y[i] = if i < half
                     z[i + half]
                   elsif i < m + half
                     -z[m + half - 1 - i]
                   else
                     -z[i - m - half]
                   end
          end
          y
        end
      end

      # Iterative radix-2 complex FFT.
      class FFT
        @n : Int32
        @rev : Array(Int32)
        @cos : Slice(Float32)
        @sin : Slice(Float32)

        def initialize(@n)
          bits = Vorbis.ilog(@n) - 1
          @rev = Array(Int32).new(@n) do |i|
            r = 0
            bits.times { |b| r |= ((i >> b) & 1) << (bits - 1 - b) }
            r
          end
          @cos = Slice(Float32).new(@n // 2) { |k| Math.cos(-2 * Math::PI * k / @n).to_f32 }
          @sin = Slice(Float32).new(@n // 2) { |k| Math.sin(-2 * Math::PI * k / @n).to_f32 }
        end

        def forward(re : Slice(Float32), im : Slice(Float32)) : Nil
          n = @n
          n.times do |i|
            j = @rev[i]
            if j > i
              re[i], re[j] = re[j], re[i]
              im[i], im[j] = im[j], im[i]
            end
          end
          len = 2
          while len <= n
            half = len // 2
            step = n // len
            i = 0
            while i < n
              half.times do |k|
                c = @cos[k * step]; s = @sin[k * step]
                a = i + k; b = a + half
                tr = re[b] * c - im[b] * s
                ti = re[b] * s + im[b] * c
                re[b] = re[a] - tr; im[b] = im[a] - ti
                re[a] += tr; im[a] += ti
              end
              i += len
            end
            len *= 2
          end
        end
      end

      # Decode a whole Ogg Vorbis file into an AudioBuffer.
      def self.decode(data : Bytes) : AudioBuffer
        packets, granule = packets(data)
        raise DecodeError.new("Not enough Vorbis headers") if packets.size < 3
        dec = Decoder.new(packets[0], packets[2])
        BitReader.new(packets[1]).read(8) # comment header ignored
        ch = dec.channels
        chunks = [] of Array(Slice(Float32))
        total = 0
        packets[3..].each do |p|
          next if p.empty?
          if out_ = dec.decode_packet(p)
            chunks << out_
            total += out_[0].size
          end
        end
        total = Math.min(total, granule.to_i) if granule > 0 && granule < total
        samples = Slice(Float32).new(total * ch)
        pos = 0
        chunks.each do |chunk|
          len = chunk[0].size
          len.times do |i|
            break if pos >= total
            ch.times { |c| samples[pos * ch + c] = chunk[c][i] }
            pos += 1
          end
        end
        AudioBuffer.new(dec.sample_rate, ch, samples)
      end
    end
  end
end
