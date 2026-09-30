module Portal3
  # Every surface in the game is generated at runtime, so the whole chamber set ships
  # in the executable. Each generator returns a tileable image sized to be a power of
  # two, drawn once at load and cached as a texture.
  module Textures
    extend self

    SIZE = 128

    @@cache = {} of Symbol => Texture

    # Returns a cached texture, generating it on first use. Wrapping repeats so large
    # walls tile, and mipmaps keep distant panels from shimmering.
    def get(key : Symbol) : Texture
      @@cache[key] ||= Texture.new(generate(key), GPU::Filter::Linear, GPU::Wrap::Repeat, true)
    end

    def generate(key : Symbol) : Image
      case key
      when :white  then white_panel
      when :panel  then dark_panel
      when :metal  then metal
      when :hazard then hazard_stripe
      when :floor  then floor_tile
      when :grid   then observation_grid
      else              white_panel
      end
    end

    # The signature Aperture panel: off-white plate, chamfered border, four bolt heads.
    def white_panel : Image
      img = Image.new(SIZE, SIZE)
      img.fill(Color.hex("#d7d7cf"))
      bevel(img, 3, Color.hex("#bcbcb2"), Color.hex("#ecece4"))
      inset(img, 10, Color.hex("#cfcfc6"))
      # A soft centre gradient keeps large walls from looking like flat paint.
      (0...SIZE).each do |y|
        (0...SIZE).each do |x|
          d = Math.sqrt((x - SIZE / 2) ** 2 + (y - SIZE / 2) ** 2) / (SIZE * 0.7)
          shade = (1.0 - d * 0.06).clamp(0_f64, 1_f64)
          if c = img[x, y]?
            img[x, y] = Color.new(c.r * shade, c.g * shade, c.b * shade, c.a)
          end
        end
      end
      bolt(img, 18, 18)
      bolt(img, SIZE - 18, 18)
      bolt(img, 18, SIZE - 18)
      bolt(img, SIZE - 18, SIZE - 18)
      img
    end

    # Dark structural panel used for trim, frames and non-portalable surfaces.
    def dark_panel : Image
      img = Image.new(SIZE, SIZE)
      img.fill(Color.hex("#33343c"))
      bevel(img, 3, Color.hex("#22232a"), Color.hex("#4e505c"))
      inset(img, 12, Color.hex("#2b2c34"))
      bolt(img, 20, 20)
      bolt(img, SIZE - 20, SIZE - 20)
      img
    end

    # Brushed metal, used for rails, frames and the portal device.
    def metal : Image
      img = Image.new(SIZE, SIZE)
      (0...SIZE).each do |y|
        streak = Math.sin(y * 0.9) * 0.05 + Math.sin(y * 3.3) * 0.02
        (0...SIZE).each { |x| img[x, y] = shade(Color.hex("#6d6f78"), streak) }
      end
      (0...SIZE).each { |y| img[0, y] = Color.hex("#83858f") }
      img
    end

    # Diagonal black and yellow hazard stripes for pits and drop edges.
    def hazard_stripe : Image
      img = Image.new(SIZE, SIZE)
      (0...SIZE).each do |y|
        (0...SIZE).each do |x|
          base = (x + y) / 16 % 2 == 0 ? Color.hex("#e3b520") : Color.hex("#1b1b1e")
          img[x, y] = shade(base, Math.sin((x - y) * 0.5) * 0.05)
        end
      end
      img
    end

    # Large floor tiles with a darker grout line and corner rivets.
    def floor_tile : Image
      img = Image.new(SIZE, SIZE)
      (0...SIZE).each do |y|
        (0...SIZE).each do |x|
          edge = x < 2 || y < 2 || x >= SIZE - 2 || y >= SIZE - 2
          img[x, y] = if edge
                        Color.hex("#45464e")
                      else
                        shade(Color.hex("#787a84"), Math.sin(x * 0.4) * 0.03 + Math.sin(y * 0.4) * 0.03)
                      end
        end
      end
      bolt(img, 12, 12)
      bolt(img, SIZE - 12, 12)
      bolt(img, 12, SIZE - 12)
      bolt(img, SIZE - 12, SIZE - 12)
      img
    end

    # The observation glass seen behind test chambers: a faint blue grid.
    def observation_grid : Image
      img = Image.new(SIZE, SIZE, Color.new(0.02_f64, 0.05_f64, 0.09_f64, 0.0_f64))
      (0...SIZE).each do |y|
        (0...SIZE).each do |x|
          if x % 32 == 0 || y % 32 == 0
            img[x, y] = Color.new(0.25, 0.55, 0.75, 0.5)
          end
        end
      end
      img
    end

    # A single round bolt head.
    private def bolt(img : Image, cx : Int, cy : Int) : Nil
      r = 4
      (-r..r).each do |dy|
        (-r..r).each do |dx|
          d = Math.sqrt(dx * dx + dy * dy)
          next if d > r
          x = cx + dx
          y = cy + dy
          next unless x >= 0 && y >= 0 && x < img.width && y < img.height
          img[x, y] = if d > r - 1
                        Color.hex("#9a9a92")
                      elsif dx + dy < 0
                        Color.hex("#e8e8e0")
                      else
                        Color.hex("#8e8e86")
                      end
        end
      end
    end

    # A one-pixel chamfered edge: light on the top-left, dark on the bottom-right.
    private def bevel(img : Image, width : Int, light : Color, dark : Color) : Nil
      (0...img.height).each do |y|
        (0...img.width).each do |x|
          on_top = y < width
          on_left = x < width
          on_bottom = y >= img.height - width
          on_right = x >= img.width - width
          if on_top || on_left
            inset_px(img, x, y, light, 0.25)
          elsif on_bottom || on_right
            inset_px(img, x, y, dark, 0.35)
          end
        end
      end
    end

    # A recessed inner border, dark on the top-left where it catches no light.
    private def inset(img : Image, margin : Int, color : Color) : Nil
      (0...img.height).each do |y|
        (0...img.width).each do |x|
          near_edge = x >= margin && x < img.width - margin &&
                      y >= margin && y < img.height - margin
          if near_edge && (x == margin || y == margin)
            inset_px(img, x, y, color, 0.5)
          end
        end
      end
    end

    # Darkens or lightens the existing pixel toward *color*.
    private def inset_px(img : Image, x : Int, y : Int, color : Color, amount : Float64) : Nil
      if c = img[x, y]?
        img[x, y] = Color.new(
          lerp(c.r.to_f64, color.r.to_f64, amount).clamp(0.0, 1.0),
          lerp(c.g.to_f64, color.g.to_f64, amount).clamp(0.0, 1.0),
          lerp(c.b.to_f64, color.b.to_f64, amount).clamp(0.0, 1.0),
          c.a.to_f64
        )
      end
    end

    # Multiplies every channel by (1 + amount), used for subtle surface variation.
    private def shade(color : Color, amount : Float64) : Color
      f = (1.0 + amount).clamp(0.0, 2.0)
      Color.new(
        (color.r.to_f64 * f).clamp(0.0, 1.0),
        (color.g.to_f64 * f).clamp(0.0, 1.0),
        (color.b.to_f64 * f).clamp(0.0, 1.0),
        color.a.to_f64
      )
    end

    private def lerp(a : Float64, b : Float64, t : Float64) : Float64
      a + (b - a) * t
    end
  end
end
