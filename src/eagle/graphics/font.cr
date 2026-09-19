require "./default_font_data"

module Eagle
  # A font you can draw text with, through `Graphics#print` or a `Label`.
  #
  # Eagle ships a crisp built-in pixel font, `Font.default`, so text works with no files.
  # For anything else, load a TrueType file at a pixel size. Glyphs are rasterized in
  # Crystal on first use and packed into an atlas texture.
  #
  # ```
  # title = Font.load("res://fonts/Inter.ttf", 48)
  # g.print("Eagle", 20, 20, font: title)
  #
  # w = Font.default.width("Score: 100") # measure before drawing
  # lines = Font.default.wrap("A long sentence that needs wrapping.", 120)
  # ```
  #
  # Load each size you need separately. Scaling a TrueType font with `scale:` blurs it,
  # while the pixel font scales cleanly by whole numbers.
  abstract class Font
    # One character's image in the font atlas, with how far to advance afterwards.
    struct Glyph
      # Where the glyph sits in the atlas.
      getter region : TextureRegion
      # How far to move the pen after this glyph, in pixels.
      getter advance : Float32
      # Offset from the pen position to the glyph's top-left corner.
      getter offset : Vec2
      # Creates a glyph.
      def initialize(@region, @advance, @offset = Vec2::ZERO); end
    end

    # The glyph for *char*, or `nil` if the font doesn't have it.
    abstract def glyph(char : Char) : Glyph?
    # Distance between baselines, in pixels, before `scale`.
    abstract def line_height : Float32
    # The atlas texture holding the glyphs.
    abstract def texture : Texture
    # Scale applied whenever this font is drawn. The pixel font defaults to 2 so it stays readable.
    property scale : Float32 = 1_f32
    # Extra space between characters, in pixels.
    property letter_spacing : Float32 = 0_f32

    # Extra horizontal adjustment between the pair *a*, *b*, such as pulling "AV" together.
    def kerning(a : Char, b : Char) : Float32; 0_f32; end

    # Line height after `scale`.
    def height : Float32; line_height * scale; end

    # Width of *text* in pixels, including kerning and scale. Uses the longest line for multi-line text.
    def width(text : String) : Float32
      w = 0_f32; best = 0_f32
      prev : Char? = nil
      text.each_char do |c|
        if c == '\n'
          best = w if w > best; w = 0_f32; prev = nil
          next
        end
        if g = glyph(c)
          w += kerning(prev, c) * scale if prev
          w += (g.advance + @letter_spacing) * scale
        end
        prev = c
      end
      Math.max(w, best)
    end

    # Width and height of *text*, counting every line.
    def measure(text : String) : Vec2
      lines = text.count('\n') + 1
      Vec2.new(width(text), lines * height)
    end

    # Splits *text* into lines that each fit within *max_width* pixels, breaking at spaces.
    def wrap(text : String, max_width : Number) : Array(String)
      out_lines = [] of String
      text.each_line do |para|
        line = ""
        para.split(' ').each do |word|
          candidate = line.empty? ? word : "#{line} #{word}"
          if width(candidate) <= max_width || line.empty?
            line = candidate
          else
            out_lines << line
            line = word
          end
        end
        out_lines << line
      end
      out_lines
    end

    @@default : Font? = nil

    # The built-in pixel font. It needs no files, so it works everywhere, including the web.
    def self.default : Font
      @@default ||= BitmapFont.builtin
    end

    # :nodoc:
    def self.reset_shared; @@default = nil; end
  end

  # A font drawn from a grid of glyph images, as used by classic and pixel-art games.
  #
  # ```
  # atlas = Texture.new(Image.new(96, 48))
  # font = BitmapFont.grid(atlas, 6, 8) # glyphs from ' ' onward, row by row
  # ```
  class BitmapFont < Font
    getter texture : Texture
    getter line_height : Float32
    @glyphs = {} of Char => Glyph

    # Creates an empty bitmap font. Add glyphs with `add`, or use `grid` to build one from a sheet.
    def initialize(@texture : Texture, @line_height : Float32)
    end

    # Adds a glyph for *char*. The advance defaults to the region width.
    def add(char : Char, region : TextureRegion, advance : Float32? = nil, offset : Vec2 = Vec2::ZERO) : self
      @glyphs[char] = Glyph.new(region, advance || region.width, offset)
      self
    end

    # The glyph for *char*, or `nil`.
    def glyph(char : Char) : Glyph?
      @glyphs[char]? || @glyphs['?']?
    end

    # Builds a font from a sheet where glyphs sit in equal cells, row by row, starting at *first*.
    def self.grid(texture : Texture, cell_w : Int32, cell_h : Int32, first : Char = ' ', count : Int32 = 95, advance : Int32? = nil) : BitmapFont
      f = new(texture, cell_h.to_f32)
      cols = texture.width // cell_w
      count.times do |i|
        c = (first.ord + i).chr
        f.add(c, texture.region((i % cols) * cell_w, (i // cols) * cell_w * 0 + (i // cols) * cell_h, cell_w, cell_h), (advance || cell_w).to_f32)
      end
      f
    end

    # Builds Eagle's embedded 5x7 pixel font. `Font.default` returns a shared copy.
    def self.builtin : BitmapFont
      glyphs = DEFAULT_FONT_GLYPHS.split(/\n\s*\n/).map { |g| g.lines.map(&.strip).reject(&.empty?) }
      raise Error.new("Built-in font is corrupt (#{glyphs.size} glyphs)") unless glyphs.size == 95
      cell_w = 6; cell_h = 8; cols = 16
      rows = (glyphs.size + cols - 1) // cols
      img = Image.new(cols * cell_w, rows * cell_h)
      glyphs.each_with_index do |rows7, i|
        ox = (i % cols) * cell_w; oy = (i // cols) * cell_h
        rows7.each_with_index do |row, y|
          row.each_char.with_index { |ch, x| img[ox + x, oy + y] = Color::WHITE if ch == '#' }
        end
      end
      tex = Texture.new(img, GPU::Filter::Nearest)
      # nearest filtering samples any solid pixel exactly, so shapes can batch with text
      if px = (0...img.width * img.height).find { |n| img[n % img.width, n // img.width] == Color::WHITE }
        tex.white_uv = Vec2.new((px % img.width + 0.5_f32) / img.width, (px // img.width + 0.5_f32) / img.height)
      end
      f = new(tex, cell_h.to_f32)
      glyphs.size.times do |i|
        f.add((32 + i).chr, tex.region((i % cols) * cell_w, (i // cols) * cell_h, cell_w, cell_h), cell_w.to_f32)
      end
      f.scale = 2_f32
      f
    end
  end
end
