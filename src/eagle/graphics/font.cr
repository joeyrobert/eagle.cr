require "./default_font_data"

module Eagle
  # Text rendering. A Font is an atlas texture plus glyph metrics.
  # `Font.default` is the embedded pixel font; `Font.load("x.ttf", 24)` uses
  # the Crystal TrueType rasterizer.
  abstract class Font
    struct Glyph
      getter region : TextureRegion
      getter advance : Float32
      getter offset : Vec2
      def initialize(@region, @advance, @offset = Vec2::ZERO); end
    end

    abstract def glyph(char : Char) : Glyph?
    abstract def line_height : Float32
    abstract def texture : Texture
    # Base scale used by `Graphics#print` (pixel fonts look better at 2x).
    property scale : Float32 = 1_f32
    # Extra spacing between glyphs.
    property letter_spacing : Float32 = 0_f32

    def kerning(a : Char, b : Char) : Float32; 0_f32; end

    def height : Float32; line_height * scale; end

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

    def measure(text : String) : Vec2
      lines = text.count('\n') + 1
      Vec2.new(width(text), lines * height)
    end

    # Word-wrap `text` into lines no wider than `max_width`.
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

    def self.default : Font
      @@default ||= BitmapFont.builtin
    end

    # :nodoc:
    def self.reset_shared; @@default = nil; end
  end

  # Fixed-cell bitmap font from an atlas.
  class BitmapFont < Font
    getter texture : Texture
    getter line_height : Float32
    @glyphs = {} of Char => Glyph

    def initialize(@texture : Texture, @line_height : Float32)
    end

    def add(char : Char, region : TextureRegion, advance : Float32? = nil, offset : Vec2 = Vec2::ZERO) : self
      @glyphs[char] = Glyph.new(region, advance || region.width, offset)
      self
    end

    def glyph(char : Char) : Glyph?
      @glyphs[char]? || @glyphs['?']?
    end

    # Load a grid atlas where glyphs are laid out row-major starting at `first`.
    def self.grid(texture : Texture, cell_w : Int32, cell_h : Int32, first : Char = ' ', count : Int32 = 95, advance : Int32? = nil) : BitmapFont
      f = new(texture, cell_h.to_f32)
      cols = texture.width // cell_w
      count.times do |i|
        c = (first.ord + i).chr
        f.add(c, texture.region((i % cols) * cell_w, (i // cols) * cell_w * 0 + (i // cols) * cell_h, cell_w, cell_h), (advance || cell_w).to_f32)
      end
      f
    end

    # Rasterise the embedded 5x7 font into a 6x8-cell atlas.
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
      f = new(tex, cell_h.to_f32)
      glyphs.size.times do |i|
        f.add((32 + i).chr, tex.region((i % cols) * cell_w, (i // cols) * cell_h, cell_w, cell_h), cell_w.to_f32)
      end
      f.scale = 2_f32
      f
    end
  end
end
