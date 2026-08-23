module Eagle
  # RGBA color with Float32 components in 0..1.
  struct Color
    property r : Float32
    property g : Float32
    property b : Float32
    property a : Float32

    def initialize(r : Number, g : Number, b : Number, a : Number = 1)
      @r = r.to_f32; @g = g.to_f32; @b = b.to_f32; @a = a.to_f32
    end

    def initialize
      @r = @g = @b = @a = 1_f32
    end

    # 0..255 bytes
    def self.rgb(r : Int, g : Int, b : Int, a : Int = 255) : Color
      Color.new(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
    end

    # `Color.hex(0xFF8800)` or `Color.hex("#ff8800")` / `"#ff8800cc"`
    def self.hex(v : Int) : Color
      if v > 0xFFFFFF
        rgb((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      else
        rgb((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      end
    end

    def self.hex(s : String) : Color
      s = s.lchop('#')
      s = s.chars.map { |c| "#{c}#{c}" }.join if s.size == 3 || s.size == 4
      v = s.to_u32(16)
      s.size == 8 ? hex(v.to_i64) : hex(v.to_i64)
    end

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

    def self.gray(v : Number, a : Number = 1) : Color; Color.new(v, v, v, a); end

    WHITE       = Color.new(1, 1, 1)
    BLACK       = Color.new(0, 0, 0)
    TRANSPARENT = Color.new(0, 0, 0, 0)
    RED         = Color.new(1, 0, 0)
    GREEN       = Color.new(0, 1, 0)
    BLUE        = Color.new(0, 0, 1)
    YELLOW      = Color.new(1, 1, 0)
    CYAN        = Color.new(0, 1, 1)
    MAGENTA     = Color.new(1, 0, 1)
    ORANGE      = Color.new(1, 0.5, 0)
    GRAY        = Color.new(0.5, 0.5, 0.5)
    CORNFLOWER  = Color.rgb(100, 149, 237)

    def *(o : Color) : Color; Color.new(@r * o.r, @g * o.g, @b * o.b, @a * o.a); end
    def *(s : Number) : Color; Color.new(@r * s, @g * s, @b * s, @a); end
    def +(o : Color) : Color; Color.new(@r + o.r, @g + o.g, @b + o.b, @a + o.a); end
    def ==(o : Color) : Bool; @r == o.r && @g == o.g && @b == o.b && @a == o.a; end

    def with_alpha(a : Number) : Color; Color.new(@r, @g, @b, a); end
    def alpha(a : Number) : Color; with_alpha(a); end
    def lerp(o : Color, t : Number) : Color
      Color.new(@r + (o.r - @r) * t, @g + (o.g - @g) * t, @b + (o.b - @b) * t, @a + (o.a - @a) * t)
    end
    def lighten(t : Number) : Color; lerp(WHITE, t).with_alpha(@a); end
    def darken(t : Number) : Color; lerp(BLACK, t).with_alpha(@a); end
    def premultiplied : Color; Color.new(@r * @a, @g * @a, @b * @a, @a); end

    def to_rgba8 : UInt32
      ((@r.clamp(0, 1) * 255).round.to_u32 << 24) | ((@g.clamp(0, 1) * 255).round.to_u32 << 16) |
        ((@b.clamp(0, 1) * 255).round.to_u32 << 8) | (@a.clamp(0, 1) * 255).round.to_u32
    end

    def to_bytes : {UInt8, UInt8, UInt8, UInt8}
      {(@r.clamp(0, 1) * 255).round.to_u8, (@g.clamp(0, 1) * 255).round.to_u8, (@b.clamp(0, 1) * 255).round.to_u8, (@a.clamp(0, 1) * 255).round.to_u8}
    end

    def to_vec4 : Vec4; Vec4.new(@r, @g, @b, @a); end
    def to_s(io : IO) : Nil; io << "Color(" << @r << ", " << @g << ", " << @b << ", " << @a << ")"; end
  end
end
