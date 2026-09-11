module Eagle
  # 2D vector of Float32. Immutable struct; all operations return new values.
  struct Vec2
    # Additive identity (lets `Enumerable#sum` work on vectors).
    def self.zero : Vec2; Vec2.new(0, 0); end
    property x : Float32
    property y : Float32

    ZERO  = Vec2.new(0, 0)
    ONE   = Vec2.new(1, 1)
    UP    = Vec2.new(0, -1) # screen space: y grows downward
    DOWN  = Vec2.new(0, 1)
    LEFT  = Vec2.new(-1, 0)
    RIGHT = Vec2.new(1, 0)

    def initialize(x : Number, y : Number)
      @x = x.to_f32
      @y = y.to_f32
    end

    def initialize(v : Number)
      @x = @y = v.to_f32
    end

    def initialize
      @x = @y = 0_f32
    end

    def self.from_angle(radians : Number, length : Number = 1) : Vec2
      Vec2.new(Math.cos(radians) * length, Math.sin(radians) * length)
    end

    def +(o : Vec2) : Vec2; Vec2.new(@x + o.x, @y + o.y); end
    def -(o : Vec2) : Vec2; Vec2.new(@x - o.x, @y - o.y); end
    def *(o : Vec2) : Vec2; Vec2.new(@x * o.x, @y * o.y); end
    def /(o : Vec2) : Vec2; Vec2.new(@x / o.x, @y / o.y); end
    def *(s : Number) : Vec2; Vec2.new(@x * s, @y * s); end
    def /(s : Number) : Vec2; Vec2.new(@x / s, @y / s); end
    def - : Vec2; Vec2.new(-@x, -@y); end
    def +; self; end

    def ==(o : Vec2) : Bool; @x == o.x && @y == o.y; end

    def dot(o : Vec2) : Float32; @x * o.x + @y * o.y; end
    # 2D cross product (z component of the 3D cross).
    def cross(o : Vec2) : Float32; @x * o.y - @y * o.x; end

    def length : Float32; Math.sqrt(@x * @x + @y * @y).to_f32; end
    def length_squared : Float32; @x * @x + @y * @y; end
    def distance(o : Vec2) : Float32; (o - self).length; end
    def distance_squared(o : Vec2) : Float32; (o - self).length_squared; end

    def normalized : Vec2
      l = length
      l > 0 ? self / l : Vec2::ZERO
    end

    def limit(max : Number) : Vec2
      l = length
      l > max ? self * (max / l) : self
    end

    def angle : Float32; Math.atan2(@y, @x).to_f32; end
    def angle_to(o : Vec2) : Float32; Math.atan2(cross(o), dot(o)).to_f32; end

    def rotated(radians : Number) : Vec2
      c = Math.cos(radians); s = Math.sin(radians)
      Vec2.new(@x * c - @y * s, @x * s + @y * c)
    end

    # Perpendicular vector (rotated 90° counter-clockwise in y-down space).
    def perpendicular : Vec2; Vec2.new(-@y, @x); end

    def lerp(o : Vec2, t : Number) : Vec2; self + (o - self) * t; end

    def abs : Vec2; Vec2.new(@x.abs, @y.abs); end
    def floor : Vec2; Vec2.new(@x.floor, @y.floor); end
    def ceil : Vec2; Vec2.new(@x.ceil, @y.ceil); end
    def round : Vec2; Vec2.new(@x.round, @y.round); end
    def min(o : Vec2) : Vec2; Vec2.new(Math.min(@x, o.x), Math.min(@y, o.y)); end
    def max(o : Vec2) : Vec2; Vec2.new(Math.max(@x, o.x), Math.max(@y, o.y)); end
    def clamp(lo : Vec2, hi : Vec2) : Vec2; max(lo).min(hi); end

    def reflect(normal : Vec2) : Vec2; self - normal * (2 * dot(normal)); end
    def project(onto : Vec2) : Vec2; onto * (dot(onto) / onto.length_squared); end

    def approx?(o : Vec2, eps = 1e-5) : Bool
      (@x - o.x).abs <= eps && (@y - o.y).abs <= eps
    end

    def zero? : Bool; @x == 0 && @y == 0; end

    def to_vec3(z : Number = 0) : Vec3; Vec3.new(@x, @y, z); end
    def to_a; [@x, @y]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ")"; end
    def inspect(io : IO) : Nil; io << "Vec2" << self; end
    def hash(h); h = @x.hash(h); @y.hash(h); end
  end
end

struct Number
  def *(v : Eagle::Vec2) : Eagle::Vec2; v * self; end
end

# Terse constructor: `v2(1, 2)`
def v2(x : Number, y : Number) : Eagle::Vec2; Eagle::Vec2.new(x, y); end
