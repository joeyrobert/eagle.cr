module Eagle
  struct Vec3
    # Additive identity (lets `Enumerable#sum` work on vectors).
    def self.zero : Vec3; Vec3.new(0, 0, 0); end
    property x : Float32
    property y : Float32
    property z : Float32

    ZERO    = Vec3.new(0, 0, 0)
    ONE     = Vec3.new(1, 1, 1)
    UP      = Vec3.new(0, 1, 0)
    DOWN    = Vec3.new(0, -1, 0)
    RIGHT   = Vec3.new(1, 0, 0)
    LEFT    = Vec3.new(-1, 0, 0)
    FORWARD = Vec3.new(0, 0, -1) # right-handed, -Z forward (OpenGL convention)
    BACK    = Vec3.new(0, 0, 1)

    def initialize(x : Number, y : Number, z : Number)
      @x = x.to_f32; @y = y.to_f32; @z = z.to_f32
    end

    def initialize(v : Number)
      @x = @y = @z = v.to_f32
    end

    def initialize
      @x = @y = @z = 0_f32
    end

    def +(o : Vec3) : Vec3; Vec3.new(@x + o.x, @y + o.y, @z + o.z); end
    def -(o : Vec3) : Vec3; Vec3.new(@x - o.x, @y - o.y, @z - o.z); end
    def *(o : Vec3) : Vec3; Vec3.new(@x * o.x, @y * o.y, @z * o.z); end
    def /(o : Vec3) : Vec3; Vec3.new(@x / o.x, @y / o.y, @z / o.z); end
    def *(s : Number) : Vec3; Vec3.new(@x * s, @y * s, @z * s); end
    def /(s : Number) : Vec3; Vec3.new(@x / s, @y / s, @z / s); end
    def - : Vec3; Vec3.new(-@x, -@y, -@z); end
    def ==(o : Vec3) : Bool; @x == o.x && @y == o.y && @z == o.z; end

    def dot(o : Vec3) : Float32; @x * o.x + @y * o.y + @z * o.z; end

    def cross(o : Vec3) : Vec3
      Vec3.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x)
    end

    def length : Float32; Math.sqrt(@x * @x + @y * @y + @z * @z).to_f32; end
    def length_squared : Float32; @x * @x + @y * @y + @z * @z; end
    def distance(o : Vec3) : Float32; (o - self).length; end
    def distance_squared(o : Vec3) : Float32; (o - self).length_squared; end

    def normalized : Vec3
      l = length
      l > 0 ? self / l : Vec3::ZERO
    end

    def lerp(o : Vec3, t : Number) : Vec3; self + (o - self) * t; end
    def abs : Vec3; Vec3.new(@x.abs, @y.abs, @z.abs); end
    def zero? : Bool; @x == 0 && @y == 0 && @z == 0; end
    def min(o : Vec3) : Vec3; Vec3.new(Math.min(@x, o.x), Math.min(@y, o.y), Math.min(@z, o.z)); end
    def max(o : Vec3) : Vec3; Vec3.new(Math.max(@x, o.x), Math.max(@y, o.y), Math.max(@z, o.z)); end
    def reflect(n : Vec3) : Vec3; self - n * (2 * dot(n)); end
    def project(onto : Vec3) : Vec3; onto * (dot(onto) / onto.length_squared); end

    def approx?(o : Vec3, eps = 1e-5) : Bool
      (@x - o.x).abs <= eps && (@y - o.y).abs <= eps && (@z - o.z).abs <= eps
    end

    def xy : Vec2; Vec2.new(@x, @y); end
    def xz : Vec2; Vec2.new(@x, @z); end
    def to_vec4(w : Number = 1) : Vec4; Vec4.new(@x, @y, @z, w); end
    def to_a; [@x, @y, @z]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ", " << @z << ")"; end
    def inspect(io : IO) : Nil; io << "Vec3" << self; end
    def hash(h); h = @x.hash(h); h = @y.hash(h); @z.hash(h); end
  end

  struct Vec4
    def self.zero : Vec4; Vec4.new(0, 0, 0, 0); end
    property x : Float32
    property y : Float32
    property z : Float32
    property w : Float32

    def initialize(x : Number, y : Number, z : Number, w : Number)
      @x = x.to_f32; @y = y.to_f32; @z = z.to_f32; @w = w.to_f32
    end

    def initialize
      @x = @y = @z = @w = 0_f32
    end

    def +(o : Vec4) : Vec4; Vec4.new(@x + o.x, @y + o.y, @z + o.z, @w + o.w); end
    def -(o : Vec4) : Vec4; Vec4.new(@x - o.x, @y - o.y, @z - o.z, @w - o.w); end
    def *(s : Number) : Vec4; Vec4.new(@x * s, @y * s, @z * s, @w * s); end
    def /(s : Number) : Vec4; Vec4.new(@x / s, @y / s, @z / s, @w / s); end
    def ==(o : Vec4) : Bool; @x == o.x && @y == o.y && @z == o.z && @w == o.w; end
    def dot(o : Vec4) : Float32; @x * o.x + @y * o.y + @z * o.z + @w * o.w; end
    def length : Float32; Math.sqrt(dot(self)).to_f32; end
    def xyz : Vec3; Vec3.new(@x, @y, @z); end
    def xy : Vec2; Vec2.new(@x, @y); end
    # Perspective divide.
    def homogenized : Vec3; Vec3.new(@x / @w, @y / @w, @z / @w); end
    def to_a; [@x, @y, @z, @w]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ", " << @z << ", " << @w << ")"; end
    def inspect(io : IO) : Nil; io << "Vec4" << self; end
  end
end

struct Number
  def *(v : Eagle::Vec3) : Eagle::Vec3; v * self; end
  def *(v : Eagle::Vec4) : Eagle::Vec4; v * self; end
end

def v3(x : Number, y : Number, z : Number) : Eagle::Vec3; Eagle::Vec3.new(x, y, z); end
def v4(x : Number, y : Number, z : Number, w : Number) : Eagle::Vec4; Eagle::Vec4.new(x, y, z, w); end
