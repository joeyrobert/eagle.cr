module Eagle
  module Codecs
    # QOI ("Quite OK Image") decoding and encoding. Lossless like PNG, but much faster to
    # encode and decode, which makes it good for screenshots and caches.
    module QOI
      MAGIC = Bytes[0x71, 0x6f, 0x69, 0x66] # "qoif"

      # True when *data* starts with the QOI magic.
      def self.qoi?(data : Bytes) : Bool
        data.size >= 14 && data[0, 4] == MAGIC
      end

      @[AlwaysInline]
      private def self.hash(r, g, b, a) : Int32
        (r.to_i * 3 + g.to_i * 5 + b.to_i * 7 + a.to_i * 11) % 64
      end

      # Decodes QOI bytes into an image.
      def self.decode(data : Bytes) : Image
        raise AssetError.new("Not a QOI") unless qoi?(data)
        w = IO::ByteFormat::BigEndian.decode(UInt32, data[4, 4]).to_i
        h = IO::ByteFormat::BigEndian.decode(UInt32, data[8, 4]).to_i
        img = Image.new(w, h)
        px = img.pixels
        index = Array({UInt8, UInt8, UInt8, UInt8}).new(64, {0_u8, 0_u8, 0_u8, 0_u8})
        r = 0_u8; g = 0_u8; b = 0_u8; a = 255_u8
        p = 14
        i = 0
        total = w * h * 4
        run = 0
        while i < total
          if run > 0
            run -= 1
          elsif p < data.size - 8
            b1 = data[p]; p += 1
            if b1 == 0xfe # RGB
              r = data[p]; g = data[p + 1]; b = data[p + 2]; p += 3
            elsif b1 == 0xff # RGBA
              r = data[p]; g = data[p + 1]; b = data[p + 2]; a = data[p + 3]; p += 4
            else
              case b1 >> 6
              when 0 # INDEX
                r, g, b, a = index[b1 & 0x3f]
              when 1 # DIFF
                r = (r.to_i + ((b1 >> 4) & 3).to_i - 2).to_u8!
                g = (g.to_i + ((b1 >> 2) & 3).to_i - 2).to_u8!
                b = (b.to_i + (b1 & 3).to_i - 2).to_u8!
              when 2 # LUMA
                b2 = data[p]; p += 1
                vg = (b1 & 0x3f).to_i - 32
                r = (r.to_i + vg - 8 + ((b2 >> 4) & 0x0f).to_i).to_u8!
                g = (g.to_i + vg).to_u8!
                b = (b.to_i + vg - 8 + (b2 & 0x0f).to_i).to_u8!
              when 3 # RUN
                run = (b1 & 0x3f).to_i
              end
            end
            index[hash(r, g, b, a)] = {r, g, b, a}
          end
          px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a
          i += 4
        end
        img
      end

      # Encodes an image as QOI.
      def self.encode(img : Image) : Bytes
        buf_out = IO::Memory.new
        buf_out.write(MAGIC)
        buf_out.write_bytes(img.width.to_u32, IO::ByteFormat::BigEndian)
        buf_out.write_bytes(img.height.to_u32, IO::ByteFormat::BigEndian)
        buf_out.write_byte(4_u8) # channels
        buf_out.write_byte(0_u8) # sRGB
        index = Array({UInt8, UInt8, UInt8, UInt8}).new(64, {0_u8, 0_u8, 0_u8, 0_u8})
        pr = 0_u8; pg = 0_u8; pb = 0_u8; pa = 255_u8
        run = 0
        px = img.pixels
        total = px.size
        i = 0
        while i < total
          r = px[i]; g = px[i + 1]; b = px[i + 2]; a = px[i + 3]
          if r == pr && g == pg && b == pb && a == pa
            run += 1
            if run == 62 || i + 4 >= total
              buf_out.write_byte((0xc0 | (run - 1)).to_u8)
              run = 0
            end
          else
            if run > 0
              buf_out.write_byte((0xc0 | (run - 1)).to_u8)
              run = 0
            end
            h = hash(r, g, b, a)
            if index[h] == {r, g, b, a}
              buf_out.write_byte(h.to_u8)
            else
              index[h] = {r, g, b, a}
              if a == pa
                vr = r.to_i - pr.to_i; vg = g.to_i - pg.to_i; vb = b.to_i - pb.to_i
                vr -= 256 if vr > 127; vr += 256 if vr < -128
                vg -= 256 if vg > 127; vg += 256 if vg < -128
                vb -= 256 if vb > 127; vb += 256 if vb < -128
                vgr = vr - vg; vgb = vb - vg
                if vr > -3 && vr < 2 && vg > -3 && vg < 2 && vb > -3 && vb < 2
                  buf_out.write_byte((0x40 | ((vr + 2) << 4) | ((vg + 2) << 2) | (vb + 2)).to_u8)
                elsif vgr > -9 && vgr < 8 && vg > -33 && vg < 32 && vgb > -9 && vgb < 8
                  buf_out.write_byte((0x80 | (vg + 32)).to_u8)
                  buf_out.write_byte((((vgr + 8) << 4) | (vgb + 8)).to_u8)
                else
                  buf_out.write_byte(0xfe_u8); buf_out.write_byte(r); buf_out.write_byte(g); buf_out.write_byte(b)
                end
              else
                buf_out.write_byte(0xff_u8); buf_out.write_byte(r); buf_out.write_byte(g); buf_out.write_byte(b); buf_out.write_byte(a)
              end
            end
          end
          pr = r; pg = g; pb = b; pa = a
          i += 4
        end
        7.times { buf_out.write_byte(0_u8) }
        buf_out.write_byte(1_u8)
        buf_out.to_slice
      end
    end
  end
end
