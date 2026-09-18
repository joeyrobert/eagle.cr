module Eagle
  # An RGBA image in CPU memory: 8 bits per channel, rows from top to bottom.
  #
  # Images are what you load, generate, edit and save. To draw one, upload it with
  # `Texture.new(image)`. Eagle decodes PNG, QOI and BMP itself, with no system libraries.
  #
  # ```
  # img = Image.new(64, 64, Color::TRANSPARENT)
  # img.fill_rect(8, 8, 48, 48, Color::RED)
  # img[32, 32] = Color::WHITE
  # img.blit(Image.circle(16, Color::YELLOW), 24, 24, blend: true)
  # tex = Texture.new(img)
  #
  # img.save("out.png") # format follows the extension: .png, .qoi or .bmp
  # ```
  #
  # The `checkerboard`, `circle` and `gradient` helpers make placeholder art, so a
  # prototype can run before any assets exist.
  class Image
    # Width in pixels.
    getter width : Int32
    # Height in pixels.
    getter height : Int32
    # Raw RGBA bytes, row by row from the top. Four bytes per pixel.
    getter pixels : Bytes

    # Wraps existing RGBA bytes. *pixels* must hold `width * height * 4` bytes.
    def initialize(@width : Int32, @height : Int32, @pixels : Bytes)
      raise ArgumentError.new("pixel buffer size mismatch") unless @pixels.size == @width * @height * 4
    end

    # Creates an image filled with one color, transparent by default.
    def initialize(@width : Int32, @height : Int32, fill : Color = Color::TRANSPARENT)
      @pixels = Bytes.new(@width * @height * 4)
      fill(fill) unless fill == Color::TRANSPARENT
    end

    # Loads an image file through the asset cache.
    def self.load(path : String) : Image
      data = File.read(path).to_slice
      decode(data, path)
    end

    # Decodes PNG, QOI or BMP bytes. The format is detected from the data, and *hint* (a file
    # name) is used only in error messages.
    def self.decode(data : Bytes, hint : String = "") : Image
      if Codecs::PNG.png?(data)
        Codecs::PNG.decode(data)
      elsif Codecs::QOI.qoi?(data)
        Codecs::QOI.decode(data)
      elsif Codecs::BMP.bmp?(data)
        Codecs::BMP.decode(data)
      else
        raise AssetError.new("Unknown image format#{hint.empty? ? "" : " for #{hint}"}")
      end
    end

    # Writes the image to *path*, choosing PNG, QOI or BMP from the extension.
    def save(path : String) : Nil
      ext = File.extname(path).downcase
      bytes = case ext
              when ".png" then Codecs::PNG.encode(self)
              when ".qoi" then Codecs::QOI.encode(self)
              when ".bmp" then Codecs::BMP.encode(self)
              else raise AssetError.new("Unsupported image extension #{ext}")
              end
      File.write(path, bytes)
    end

    # `(width, height)`.
    def size : Vec2; Vec2.new(@width, @height); end

    @[AlwaysInline]
    # Byte offset of pixel *x*, *y* in `pixels`.
    def index(x : Int, y : Int) : Int32; (y * @width + x) * 4; end

    # True when *x*, *y* is inside the image.
    def in_bounds?(x : Int, y : Int) : Bool; x >= 0 && y >= 0 && x < @width && y < @height; end

    # The color of pixel *x*, *y*. Raises when out of bounds.
    def [](x : Int, y : Int) : Color
      i = index(x, y)
      Color.rgb(@pixels[i], @pixels[i + 1], @pixels[i + 2], @pixels[i + 3])
    end

    # The color of pixel *x*, *y*, or `nil` when out of bounds.
    def []?(x : Int, y : Int) : Color?
      in_bounds?(x, y) ? self[x, y] : nil
    end

    # Sets pixel *x*, *y*. Raises when out of bounds, so check `in_bounds?` for coordinates you didn't compute yourself.
    def []=(x : Int, y : Int, c : Color)
      i = index(x, y)
      r, g, b, a = c.to_bytes
      @pixels[i] = r; @pixels[i + 1] = g; @pixels[i + 2] = b; @pixels[i + 3] = a
    end

    # Fills the whole image with *c*. Returns self.
    def fill(c : Color) : self
      r, g, b, a = c.to_bytes
      i = 0
      while i < @pixels.size
        @pixels[i] = r; @pixels[i + 1] = g; @pixels[i + 2] = b; @pixels[i + 3] = a
        i += 4
      end
      self
    end

    # Fills a rectangle with *c*, clipped to the image. Returns self.
    def fill_rect(x : Int, y : Int, w : Int, h : Int, c : Color) : self
      x0 = Math.max(x, 0); y0 = Math.max(y, 0)
      x1 = Math.min(x + w, @width); y1 = Math.min(y + h, @height)
      (y0...y1).each { |yy| (x0...x1).each { |xx| self[xx, yy] = c } }
      self
    end

    # Copies *src* onto this image at *x*, *y*. With *blend*, transparent parts of *src* let this
    # image show through; without it, pixels are overwritten. Returns self.
    def blit(src : Image, x : Int, y : Int, blend : Bool = false) : self
      src.height.times do |sy|
        dy = y + sy
        next unless dy >= 0 && dy < @height
        src.width.times do |sx|
          dx = x + sx
          next unless dx >= 0 && dx < @width
          if blend
            s = src[sx, sy]
            next if s.a <= 0
            d = self[dx, dy]
            self[dx, dy] = d.lerp(s, s.a).with_alpha(Math.max(d.a, s.a))
          else
            si = src.index(sx, sy); di = index(dx, dy)
            @pixels[di, 4].copy_from(src.pixels[si, 4])
          end
        end
      end
      self
    end

    # A new image holding the rectangle *x*, *y*, *w*, *h*.
    def sub(x : Int, y : Int, w : Int, h : Int) : Image
      buf_out = Image.new(w, h)
      h.times { |yy| w.times { |xx| c = self[x + xx, y + yy]?; buf_out[xx, yy] = c if c } }
      buf_out
    end

    # Flips the image upside down in place.
    def flip_vertical! : self
      row = @width * 4
      tmp = Bytes.new(row)
      (@height // 2).times do |r|
        a = @pixels[r * row, row]; b = @pixels[(@height - 1 - r) * row, row]
        tmp.copy_from(a); a.copy_from(b); b.copy_from(tmp)
      end
      self
    end

    # Multiplies color by alpha in place, for premultiplied-alpha blending.
    def premultiply! : self
      i = 0
      while i < @pixels.size
        a = @pixels[i + 3].to_i
        if a < 255
          @pixels[i] = (@pixels[i] * a // 255).to_u8
          @pixels[i + 1] = (@pixels[i + 1] * a // 255).to_u8
          @pixels[i + 2] = (@pixels[i + 2] * a // 255).to_u8
        end
        i += 4
      end
      self
    end

    # A copy scaled to *w* by *h* with nearest-neighbor sampling, which keeps pixel art crisp.
    def resized(w : Int, h : Int) : Image
      buf_out = Image.new(w, h)
      h.times do |y|
        sy = (y * @height // h)
        w.times { |x| buf_out[x, y] = self[x * @width // w, sy] }
      end
      buf_out
    end

    # A deep copy.
    def clone : Image
      Image.new(@width, @height, @pixels.dup)
    end

    # True when sizes and every pixel match.
    def ==(o : Image) : Bool
      @width == o.width && @height == o.height && @pixels == o.pixels
    end

    # Mean absolute difference per channel, from 0 to 255. Use it in tests to compare
    # rendered frames with a tolerance.
    def difference(o : Image) : Float64
      raise ArgumentError.new("size mismatch") unless @width == o.width && @height == o.height
      return 0.0 if @pixels.empty?
      sum = 0_i64
      @pixels.size.times { |i| sum += (@pixels[i].to_i - o.pixels[i].to_i).abs }
      sum.to_f64 / @pixels.size
    end

    # The average color over a rectangle, or the whole image.
    def average(x = 0, y = 0, w = @width, h = @height) : Color
      r = g = b = a = 0_i64; n = 0
      (y...y + h).each do |yy|
        (x...x + w).each do |xx|
          next unless in_bounds?(xx, yy)
          i = index(xx, yy)
          r += @pixels[i]; g += @pixels[i + 1]; b += @pixels[i + 2]; a += @pixels[i + 3]; n += 1
        end
      end
      return Color::TRANSPARENT if n == 0
      Color.new(r / 255.0 / n, g / 255.0 / n, b / 255.0 / n, a / 255.0 / n)
    end

    # A checkerboard of two colors, handy as a placeholder or a debug floor.
    def self.checkerboard(w : Int32, h : Int32, cell : Int32 = 8, a : Color = Color::WHITE, b : Color = Color::GRAY) : Image
      img = Image.new(w, h)
      h.times { |y| w.times { |x| img[x, y] = ((x // cell + y // cell) % 2 == 0) ? a : b } }
      img
    end

    # A filled, anti-aliased circle on a transparent background.
    def self.circle(diameter : Int32, color : Color = Color::WHITE) : Image
      img = Image.new(diameter, diameter)
      r = diameter / 2.0
      diameter.times do |y|
        diameter.times do |x|
          dx = x + 0.5 - r; dy = y + 0.5 - r
          d = Math.sqrt(dx * dx + dy * dy)
          # 1px antialiased edge
          cov = (r - d + 0.5).clamp(0.0, 1.0)
          img[x, y] = color.with_alpha(color.a * cov) if cov > 0
        end
      end
      img
    end

    # A linear gradient from *from* to *to*, top to bottom or left to right.
    def self.gradient(w : Int32, h : Int32, from : Color, to : Color, horizontal : Bool = false) : Image
      img = Image.new(w, h)
      h.times do |y|
        w.times do |x|
          t = horizontal ? x / Math.max(w - 1, 1).to_f : y / Math.max(h - 1, 1).to_f
          img[x, y] = from.lerp(to, t)
        end
      end
      img
    end
  end
end
