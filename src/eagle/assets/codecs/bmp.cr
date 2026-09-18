module Eagle
  module Codecs
    # Windows BMP decoding (24- and 32-bit, uncompressed or bitfields) and encoding.
    module BMP
      # True when *data* starts with the BMP signature.
      def self.bmp?(data : Bytes) : Bool
        data.size >= 26 && data[0] == 'B'.ord && data[1] == 'M'.ord
      end

      # Decodes BMP bytes into an image.
      def self.decode(data : Bytes) : Image
        le = IO::ByteFormat::LittleEndian
        offset = le.decode(UInt32, data[10, 4]).to_i
        header_size = le.decode(UInt32, data[14, 4]).to_i
        w = le.decode(Int32, data[18, 4])
        h = le.decode(Int32, data[22, 4])
        bpp = le.decode(UInt16, data[28, 2]).to_i
        compression = header_size >= 40 ? le.decode(UInt32, data[30, 4]) : 0_u32
        raise AssetError.new("Unsupported BMP (bpp=#{bpp}, compression=#{compression})") unless (bpp == 24 || bpp == 32) && (compression == 0 || compression == 3)
        top_down = h < 0
        h = h.abs
        row_size = ((bpp * w + 31) // 32) * 4
        img = Image.new(w, h)
        h.times do |y|
          src_y = top_down ? y : h - 1 - y
          base = offset + src_y * row_size
          w.times do |x|
            i = base + x * (bpp // 8)
            b = data[i]; g = data[i + 1]; r = data[i + 2]
            a = bpp == 32 ? data[i + 3] : 255_u8
            img[x, y] = Color.rgb(r, g, b, a)
          end
        end
        img
      end

      # Encodes an image as a 32-bit BMP.
      def self.encode(img : Image) : Bytes
        le = IO::ByteFormat::LittleEndian
        row_size = img.width * 4
        size = 54 + row_size * img.height
        buf_out = IO::Memory.new(size)
        buf_out.write("BM".to_slice)
        buf_out.write_bytes(size.to_u32, le); buf_out.write_bytes(0_u32, le); buf_out.write_bytes(54_u32, le)
        buf_out.write_bytes(40_u32, le); buf_out.write_bytes(img.width, le); buf_out.write_bytes(img.height, le)
        buf_out.write_bytes(1_u16, le); buf_out.write_bytes(32_u16, le); buf_out.write_bytes(0_u32, le)
        buf_out.write_bytes((row_size * img.height).to_u32, le)
        buf_out.write_bytes(2835, le); buf_out.write_bytes(2835, le); buf_out.write_bytes(0_u32, le); buf_out.write_bytes(0_u32, le)
        (img.height - 1).downto(0) do |y|
          img.width.times do |x|
            i = img.index(x, y)
            buf_out.write_byte(img.pixels[i + 2]); buf_out.write_byte(img.pixels[i + 1]); buf_out.write_byte(img.pixels[i]); buf_out.write_byte(img.pixels[i + 3])
          end
        end
        buf_out.to_slice
      end
    end
  end
end
