module Eagle
  # An RGBA color with `Float32` components from 0 to 1.
  #
  # Colors tint everything you draw: `Graphics#color`, the `color:` argument on draw
  # calls, `Node2D#modulate`, materials and lights. Multiplying a texture by a color
  # tints it, so `Color::WHITE` leaves it unchanged.
  #
  # ```
  # g.color = Color.hex("#e3a537")
  # g.circle(100, 100, 20)
  # g.rect(10, 10, 50, 50, color: Color::RED.with_alpha(0.5)) # translucent
  #
  # hurt = Color::WHITE.lerp(Color::RED, 0.8) # flash when damaged
  # rainbow = Color.hsv(Clock.elapsed * 90, 0.8, 1)
  # shadow = Color::BLACK.alpha(0.3)
  # ```
  #
  # Use `Color.rgb` for 0 to 255 byte values and `Color.hex` for web-style codes.
  # Components aren't clamped until they reach the GPU, so values above 1 work for
  # additive glow.
  struct Color
    # Fully transparent black. Exists so `Enumerable#sum` works on colors.
    def self.zero : Color; Color.new(0, 0, 0, 0); end
    property r : Float32
    property g : Float32
    property b : Float32
    property a : Float32

    # Creates a color from components in 0..1. Alpha defaults to opaque.
    def initialize(r : Number, g : Number, b : Number, a : Number = 1)
      @r = r.to_f32; @g = g.to_f32; @b = b.to_f32; @a = a.to_f32
    end

    # Creates opaque white.
    def initialize
      @r = @g = @b = @a = 1_f32
    end

    # Creates a color from 0..255 byte values.
    #
    # ```
    # Color.rgb(255, 136, 0) # orange
    # ```
    def self.rgb(r : Int, g : Int, b : Int, a : Int = 255) : Color
      Color.new(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
    end

    # Creates a color from a number: `0xRRGGBB`, or `0xRRGGBBAA` when the value is larger than 24 bits.
    def self.hex(v : Int) : Color
      if v > 0xFFFFFF
        rgb((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      else
        rgb((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      end
    end

    # Creates a color from a web-style string: `"#rgb"`, `"#rgba"`, `"#rrggbb"` or `"#rrggbbaa"`.
    # The `#` is optional.
    def self.hex(s : String) : Color
      s = s.lchop('#')
      s = s.chars.map { |c| "#{c}#{c}" }.join if s.size == 3 || s.size == 4
      v = s.to_u32(16)
      s.size == 8 ? hex(v.to_i64) : hex(v.to_i64)
    end

    # Creates a color from hue in degrees (0 to 360, wraps), plus saturation and value in 0..1.
    # Sweeping the hue is the easy way to get rainbows.
    def self.hsv(h : Number, s : Number, v : Number, a : Number = 1) : Color
      h = (h.to_f64 % 360.0) / 60.0
      i = h.floor.to_i
      f = h - i
      p = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
      case i
      when 0 then Color.new(v, t, p, a)
      when 1 then Color.new(q, v, p, a)
      when 2 then Color.new(p, v, t, a)
      when 3 then Color.new(p, q, v, a)
      when 4 then Color.new(t, p, v, a)
      else        Color.new(v, p, q, a)
      end
    end

    # A gray of brightness *v*.
    def self.gray(v : Number, a : Number = 1) : Color; Color.new(v, v, v, a); end

    # Opaque white. Draws textures untinted.
    WHITE       = Color.new(1, 1, 1)
    # Opaque black.
    BLACK       = Color.new(0, 0, 0)
    # Fully transparent. Use it to clear canvases.
    TRANSPARENT = Color.new(0, 0, 0, 0)
    # Pure red.
    RED         = Color.new(1, 0, 0)
    # Pure green.
    GREEN       = Color.new(0, 1, 0)
    # Pure blue.
    BLUE        = Color.new(0, 0, 1)
    # Pure yellow.
    YELLOW      = Color.new(1, 1, 0)
    # Pure cyan.
    CYAN        = Color.new(0, 1, 1)
    # Pure magenta.
    MAGENTA     = Color.new(1, 0, 1)
    # Orange.
    ORANGE      = Color.new(1, 0.5, 0)
    # 50% gray.
    GRAY        = Color.new(0.5, 0.5, 0.5)
    # Cornflower blue, the classic clear color.
    CORNFLOWER  = Color.rgb(100, 149, 237)

    # Component-wise multiply, which is how tinting works.
    def *(o : Color) : Color; Color.new(@r * o.r, @g * o.g, @b * o.b, @a * o.a); end
    # Scales red, green and blue by *s* and keeps alpha. Values above 1 brighten.
    def *(s : Number) : Color; Color.new(@r * s, @g * s, @b * s, @a); end
    # Component-wise addition, including alpha.
    def +(o : Color) : Color; Color.new(@r + o.r, @g + o.g, @b + o.b, @a + o.a); end
    def ==(o : Color) : Bool; @r == o.r && @g == o.g && @b == o.b && @a == o.a; end

    # The same color with a different alpha.
    def with_alpha(a : Number) : Color; Color.new(@r, @g, @b, a); end
    # Shorter name for `with_alpha`.
    def alpha(a : Number) : Color; with_alpha(a); end
    # Blends toward *o* by *t*, including alpha.
    def lerp(o : Color, t : Number) : Color
      Color.new(@r + (o.r - @r) * t, @g + (o.g - @g) * t, @b + (o.b - @b) * t, @a + (o.a - @a) * t)
    end
    # Blends toward white by *t* and keeps alpha.
    def lighten(t : Number) : Color; lerp(WHITE, t).with_alpha(@a); end
    # Blends toward black by *t* and keeps alpha.
    def darken(t : Number) : Color; lerp(BLACK, t).with_alpha(@a); end
    # Color with red, green and blue multiplied by alpha, for premultiplied blending.
    def premultiplied : Color; Color.new(@r * @a, @g * @a, @b * @a, @a); end

    # Packs the color into `0xRRGGBBAA`, clamped to 0..255.
    def to_rgba8 : UInt32
      ((@r.clamp(0, 1) * 255).round.to_u32 << 24) | ((@g.clamp(0, 1) * 255).round.to_u32 << 16) |
        ((@b.clamp(0, 1) * 255).round.to_u32 << 8) | (@a.clamp(0, 1) * 255).round.to_u32
    end

    # The four channels as bytes, clamped to 0..255.
    def to_bytes : {UInt8, UInt8, UInt8, UInt8}
      {(@r.clamp(0, 1) * 255).round.to_u8, (@g.clamp(0, 1) * 255).round.to_u8, (@b.clamp(0, 1) * 255).round.to_u8, (@a.clamp(0, 1) * 255).round.to_u8}
    end

    # The color as a `Vec4`, for shader uniforms.
    def to_vec4 : Vec4; Vec4.new(@r, @g, @b, @a); end
    def to_s(io : IO) : Nil; io << "Color(" << @r << ", " << @g << ", " << @b << ", " << @a << ")"; end
  end
end
