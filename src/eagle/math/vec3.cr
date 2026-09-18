module Eagle
  # A 3D vector of `Float32`, used for positions, directions, scales and velocities in 3D.
  #
  # Like `Vec2`, it is an immutable value type, so every operation returns a new vector.
  # Eagle's 3D space is right-handed with +Y up, and cameras look down -Z:
  # `Vec3::FORWARD` is `(0, 0, -1)`.
  #
  # ```
  # pos = v3(0, 1, 5)
  # target = v3(0, 0, 0)
  # dir = (target - pos).normalized
  # pos += dir * 2 * dt
  #
  # side = dir.cross(Vec3::UP).normalized # a vector pointing to the right of dir
  # ground = pos.xz                       # drop the height for top-down maths
  # ```
  struct Vec3
    # Returns `(0, 0, 0)`. Exists so `Enumerable#sum` works on arrays of vectors.
    def self.zero : Vec3; Vec3.new(0, 0, 0); end
    # X component: right.
    property x : Float32
    # Y component: up.
    property y : Float32
    # Z component: toward the viewer. Forward is -Z.
    property z : Float32

    # `(0, 0, 0)`.
    ZERO    = Vec3.new(0, 0, 0)
    # `(1, 1, 1)`, the identity for scaling.
    ONE     = Vec3.new(1, 1, 1)
    # `(0, 1, 0)`. +Y is up in 3D.
    UP      = Vec3.new(0, 1, 0)
    # `(0, -1, 0)`, the direction gravity usually points.
    DOWN    = Vec3.new(0, -1, 0)
    # `(1, 0, 0)`.
    RIGHT   = Vec3.new(1, 0, 0)
    # `(-1, 0, 0)`.
    LEFT    = Vec3.new(-1, 0, 0)
    # `(0, 0, -1)`, the direction an unrotated `Camera3D` or `Node3D` faces.
    FORWARD = Vec3.new(0, 0, -1) # right-handed, -Z forward (OpenGL convention)
    # `(0, 0, 1)`.
    BACK    = Vec3.new(0, 0, 1)

    # Creates a vector from any three numbers. The shorthand is `v3(x, y, z)`.
    def initialize(x : Number, y : Number, z : Number)
      @x = x.to_f32; @y = y.to_f32; @z = z.to_f32
    end

    # Creates `(v, v, v)`.
    def initialize(v : Number)
      @x = @y = @z = v.to_f32
    end

    # Creates `(0, 0, 0)`.
    def initialize
      @x = @y = @z = 0_f32
    end

    # Component-wise sum.
    def +(o : Vec3) : Vec3; Vec3.new(@x + o.x, @y + o.y, @z + o.z); end
    # Component-wise difference.
    def -(o : Vec3) : Vec3; Vec3.new(@x - o.x, @y - o.y, @z - o.z); end
    # Component-wise product.
    def *(o : Vec3) : Vec3; Vec3.new(@x * o.x, @y * o.y, @z * o.z); end
    # Component-wise quotient.
    def /(o : Vec3) : Vec3; Vec3.new(@x / o.x, @y / o.y, @z / o.z); end
    # Scales every component.
    def *(s : Number) : Vec3; Vec3.new(@x * s, @y * s, @z * s); end
    # Divides every component.
    def /(s : Number) : Vec3; Vec3.new(@x / s, @y / s, @z / s); end
    # The vector pointing the opposite way.
    def - : Vec3; Vec3.new(-@x, -@y, -@z); end
    # Exact equality. Use `approx?` for computed values.
    def ==(o : Vec3) : Bool; @x == o.x && @y == o.y && @z == o.z; end

    # Dot product. For unit vectors it is the cosine of the angle between them,
    # so `a.dot(b) > 0.7` means "roughly the same direction".
    def dot(o : Vec3) : Float32; @x * o.x + @y * o.y + @z * o.z; end

    # Cross product: a vector perpendicular to both, following the right-hand rule.
    # Use it to build a right vector from forward and up, or a surface normal from two edges.
    def cross(o : Vec3) : Vec3
      Vec3.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x)
    end

    # Length (magnitude).
    def length : Float32; Math.sqrt(@x * @x + @y * @y + @z * @z).to_f32; end
    # Squared length. Cheaper than `length` for comparisons.
    def length_squared : Float32; @x * @x + @y * @y + @z * @z; end
    # Distance to another point.
    def distance(o : Vec3) : Float32; (o - self).length; end
    # Squared distance to another point.
    def distance_squared(o : Vec3) : Float32; (o - self).length_squared; end

    # A unit-length vector in the same direction. The zero vector stays zero.
    def normalized : Vec3
      l = length
      l > 0 ? self / l : Vec3::ZERO
    end

    # Linear interpolation toward *o*.
    def lerp(o : Vec3, t : Number) : Vec3; self + (o - self) * t; end
    # Component-wise absolute value.
    def abs : Vec3; Vec3.new(@x.abs, @y.abs, @z.abs); end
    # True for `(0, 0, 0)` exactly.
    def zero? : Bool; @x == 0 && @y == 0 && @z == 0; end
    # Component-wise minimum.
    def min(o : Vec3) : Vec3; Vec3.new(Math.min(@x, o.x), Math.min(@y, o.y), Math.min(@z, o.z)); end
    # Component-wise maximum.
    def max(o : Vec3) : Vec3; Vec3.new(Math.max(@x, o.x), Math.max(@y, o.y), Math.max(@z, o.z)); end
    # Mirrors the vector across a surface with unit normal *n*, for bounces.
    def reflect(n : Vec3) : Vec3; self - n * (2 * dot(n)); end
    # The component of this vector along *onto*. Subtract it to slide along a surface:
    # `vel - vel.project(normal)`.
    def project(onto : Vec3) : Vec3; onto * (dot(onto) / onto.length_squared); end

    # True when all components are within *eps*.
    def approx?(o : Vec3, eps = 1e-5) : Bool
      (@x - o.x).abs <= eps && (@y - o.y).abs <= eps && (@z - o.z).abs <= eps
    end

    # The x and y components as a `Vec2`.
    def xy : Vec2; Vec2.new(@x, @y); end
    # The x and z components as a `Vec2`. This is the ground plane for top-down logic in 3D.
    def xz : Vec2; Vec2.new(@x, @z); end
    # Extends to a `Vec4`. Use `w = 1` for points and `w = 0` for directions.
    def to_vec4(w : Number = 1) : Vec4; Vec4.new(@x, @y, @z, w); end
    # Returns `[x, y, z]`.
    def to_a; [@x, @y, @z]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ", " << @z << ")"; end
    def inspect(io : IO) : Nil; io << "Vec3" << self; end
    def hash(h); h = @x.hash(h); h = @y.hash(h); @z.hash(h); end
  end

  # A 4-component vector, mostly used for homogeneous coordinates and shader uniforms.
  #
  # Game code rarely needs it directly. It shows up when multiplying by a `Mat4`, and
  # `Color#to_vec4` produces one for passing colors to shaders.
  struct Vec4
    # Returns `(0, 0, 0, 0)`.
    def self.zero : Vec4; Vec4.new(0, 0, 0, 0); end
    # First component.
    property x : Float32
    # Second component.
    property y : Float32
    # Third component.
    property z : Float32
    # Fourth component: 1 for points, 0 for directions.
    property w : Float32

    # Creates a vector from four numbers. The shorthand is `v4(x, y, z, w)`.
    def initialize(x : Number, y : Number, z : Number, w : Number)
      @x = x.to_f32; @y = y.to_f32; @z = z.to_f32; @w = w.to_f32
    end

    # Creates `(0, 0, 0, 0)`.
    def initialize
      @x = @y = @z = @w = 0_f32
    end

    # Component-wise sum.
    def +(o : Vec4) : Vec4; Vec4.new(@x + o.x, @y + o.y, @z + o.z, @w + o.w); end
    # Component-wise difference.
    def -(o : Vec4) : Vec4; Vec4.new(@x - o.x, @y - o.y, @z - o.z, @w - o.w); end
    # Scales every component.
    def *(s : Number) : Vec4; Vec4.new(@x * s, @y * s, @z * s, @w * s); end
    # Divides every component.
    def /(s : Number) : Vec4; Vec4.new(@x / s, @y / s, @z / s, @w / s); end
    # Exact equality.
    def ==(o : Vec4) : Bool; @x == o.x && @y == o.y && @z == o.z && @w == o.w; end
    # Dot product of all four components.
    def dot(o : Vec4) : Float32; @x * o.x + @y * o.y + @z * o.z + @w * o.w; end
    # Length of all four components.
    def length : Float32; Math.sqrt(dot(self)).to_f32; end
    # The first three components.
    def xyz : Vec3; Vec3.new(@x, @y, @z); end
    # The first two components.
    def xy : Vec2; Vec2.new(@x, @y); end
    # Divides x, y and z by w: the perspective divide after a projection matrix.
    def homogenized : Vec3; Vec3.new(@x / @w, @y / @w, @z / @w); end
    # Returns `[x, y, z, w]`.
    def to_a; [@x, @y, @z, @w]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ", " << @z << ", " << @w << ")"; end
    def inspect(io : IO) : Nil; io << "Vec4" << self; end
  end
end

struct Number
  def *(v : Eagle::Vec3) : Eagle::Vec3; v * self; end
  def *(v : Eagle::Vec4) : Eagle::Vec4; v * self; end
end

# Shorthand for `Eagle::Vec3.new(x, y, z)`, available everywhere.
def v3(x : Number, y : Number, z : Number) : Eagle::Vec3; Eagle::Vec3.new(x, y, z); end
# Shorthand for `Eagle::Vec4.new(x, y, z, w)`, available everywhere.
def v4(x : Number, y : Number, z : Number, w : Number) : Eagle::Vec4; Eagle::Vec4.new(x, y, z, w); end
