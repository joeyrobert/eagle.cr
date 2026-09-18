module Eagle
  # A 2D vector of `Float32`, used for positions, velocities, sizes and directions.
  #
  # `Vec2` is an immutable value type. Every operation returns a new vector, so you
  # write `pos += vel * dt` rather than mutating in place. Eagle's 2D space is y-down,
  # matching the screen: `Vec2::UP` is `(0, -1)`.
  #
  # Build one with `v2(x, y)`, `Vec2.new(x, y)`, `Vec2.new(n)` for `(n, n)`, or
  # `Vec2.from_angle(radians, length)`.
  #
  # ```
  # pos = v2(100, 100)
  # vel = Vec2.from_angle(Mathf.deg2rad(30), 200) # 200 px/s at 30 degrees
  # pos += vel * 0.016
  #
  # to_mouse = Input.mouse - pos
  # if to_mouse.length < 50
  #   pos -= to_mouse.normalized * 5 # flee
  # end
  #
  # g.circle(pos, 8)
  # ```
  #
  # Arithmetic works component-wise between vectors (`a * b`) and with scalars on
  # either side (`v * 2`, `2 * v`).
  struct Vec2
    # Returns `(0, 0)`. Exists so `Enumerable#sum` works on arrays of vectors.
    def self.zero : Vec2; Vec2.new(0, 0); end
    # Horizontal component.
    property x : Float32
    # Vertical component. Grows downward on screen.
    property y : Float32

    # `(0, 0)`.
    ZERO  = Vec2.new(0, 0)
    # `(1, 1)`, the identity for scaling.
    ONE   = Vec2.new(1, 1)
    # `(0, -1)`. Up on screen, because y grows downward.
    UP    = Vec2.new(0, -1)
    # `(0, 1)`.
    DOWN  = Vec2.new(0, 1)
    # `(-1, 0)`.
    LEFT  = Vec2.new(-1, 0)
    # `(1, 0)`. Also the direction a `Node2D` with rotation 0 faces.
    RIGHT = Vec2.new(1, 0)

    # Creates a vector from any two numbers. The shorthand is `v2(x, y)`.
    def initialize(x : Number, y : Number)
      @x = x.to_f32
      @y = y.to_f32
    end

    # Creates `(v, v)`, which suits uniform scale: `Vec2.new(2)`.
    def initialize(v : Number)
      @x = @y = v.to_f32
    end

    # Creates `(0, 0)`.
    def initialize
      @x = @y = 0_f32
    end

    # A vector pointing at *radians* with the given *length*. Angle 0 points right, and
    # positive angles turn clockwise on screen.
    #
    # ```
    # ship = Node2D.new(rotation: Mathf.deg2rad(90))
    # bullet_vel = Vec2.from_angle(ship.rotation, 600) # => (0, 600), straight down
    # ```
    def self.from_angle(radians : Number, length : Number = 1) : Vec2
      Vec2.new(Math.cos(radians) * length, Math.sin(radians) * length)
    end

    # Component-wise sum.
    def +(o : Vec2) : Vec2; Vec2.new(@x + o.x, @y + o.y); end
    # Component-wise difference.
    def -(o : Vec2) : Vec2; Vec2.new(@x - o.x, @y - o.y); end
    # Component-wise product.
    def *(o : Vec2) : Vec2; Vec2.new(@x * o.x, @y * o.y); end
    # Component-wise quotient.
    def /(o : Vec2) : Vec2; Vec2.new(@x / o.x, @y / o.y); end
    # Scales both components.
    def *(s : Number) : Vec2; Vec2.new(@x * s, @y * s); end
    # Divides both components.
    def /(s : Number) : Vec2; Vec2.new(@x / s, @y / s); end
    # The vector pointing the opposite way.
    def - : Vec2; Vec2.new(-@x, -@y); end
    # Returns self.
    def +; self; end

    # Exact equality. Use `approx?` for computed values.
    def ==(o : Vec2) : Bool; @x == o.x && @y == o.y; end

    # Dot product. Positive when the vectors point the same way, zero when perpendicular,
    # and negative when opposed. Useful for "is the enemy in front of me?".
    def dot(o : Vec2) : Float32; @x * o.x + @y * o.y; end
    # 2D cross product (the z of the 3D cross). Its sign tells you which side of this
    # vector *o* lies on.
    def cross(o : Vec2) : Float32; @x * o.y - @y * o.x; end

    # Length (magnitude). Prefer `length_squared` when you only compare distances.
    def length : Float32; Math.sqrt(@x * @x + @y * @y).to_f32; end
    # Squared length. Cheaper than `length` because it skips the square root.
    #
    # ```
    # player, enemy = v2(0, 0), v2(60, 80)
    # in_range = (enemy - player).length_squared < 100 * 100 # => true
    # ```
    def length_squared : Float32; @x * @x + @y * @y; end
    # Distance to another point.
    def distance(o : Vec2) : Float32; (o - self).length; end
    # Squared distance to another point.
    def distance_squared(o : Vec2) : Float32; (o - self).length_squared; end

    # A vector in the same direction with length 1. The zero vector stays zero instead of producing NaN.
    def normalized : Vec2
      l = length
      l > 0 ? self / l : Vec2::ZERO
    end

    # Clamps the length to at most *max* and keeps the direction. Good for capping speed.
    #
    # ```
    # vel, accel = v2(250, 0), v2(0, 900)
    # vel = (vel + accel * dt).limit(300)
    # ```
    def limit(max : Number) : Vec2
      l = length
      l > max ? self * (max / l) : self
    end

    # The vector's angle in radians, from the +x axis.
    def angle : Float32; Math.atan2(@y, @x).to_f32; end
    # Signed angle from this vector to *o*, in -π..π.
    def angle_to(o : Vec2) : Float32; Math.atan2(cross(o), dot(o)).to_f32; end

    # The vector rotated by *radians* (clockwise on screen).
    def rotated(radians : Number) : Vec2
      c = Math.cos(radians); s = Math.sin(radians)
      Vec2.new(@x * c - @y * s, @x * s + @y * c)
    end

    # The vector rotated 90°. Use it for normals of 2D edges or for strafing directions.
    def perpendicular : Vec2; Vec2.new(-@y, @x); end

    # Linear interpolation toward *o*. For smooth following that doesn't depend on
    # frame rate, use `Mathf.damp` instead.
    def lerp(o : Vec2, t : Number) : Vec2; self + (o - self) * t; end

    # Component-wise absolute value.
    def abs : Vec2; Vec2.new(@x.abs, @y.abs); end
    # Component-wise floor, for snapping to whole pixels or grid cells.
    def floor : Vec2; Vec2.new(@x.floor, @y.floor); end
    # Component-wise ceiling.
    def ceil : Vec2; Vec2.new(@x.ceil, @y.ceil); end
    # Component-wise rounding.
    def round : Vec2; Vec2.new(@x.round, @y.round); end
    # Component-wise minimum.
    def min(o : Vec2) : Vec2; Vec2.new(Math.min(@x, o.x), Math.min(@y, o.y)); end
    # Component-wise maximum.
    def max(o : Vec2) : Vec2; Vec2.new(Math.max(@x, o.x), Math.max(@y, o.y)); end
    # Clamps each component between *lo* and *hi*, for keeping a player inside the arena.
    #
    # ```
    # pos = v2(-20, 900)
    # pos = pos.clamp(Vec2::ZERO, Window.size) # stays on screen
    # ```
    def clamp(lo : Vec2, hi : Vec2) : Vec2; max(lo).min(hi); end

    # Mirrors the vector across a surface with unit *normal*. This is how a ball bounces off a wall.
    #
    # ```
    # vel = v2(120, 300)
    # vel = vel.reflect(Vec2::UP) # hit the floor => (120, -300)
    # ```
    def reflect(normal : Vec2) : Vec2; self - normal * (2 * dot(normal)); end
    # The component of this vector along *onto*.
    def project(onto : Vec2) : Vec2; onto * (dot(onto) / onto.length_squared); end

    # True when both components are within *eps* of *o*'s.
    def approx?(o : Vec2, eps = 1e-5) : Bool
      (@x - o.x).abs <= eps && (@y - o.y).abs <= eps
    end

    # True for `(0, 0)` exactly.
    def zero? : Bool; @x == 0 && @y == 0; end

    # Extends to 3D with the given *z*.
    def to_vec3(z : Number = 0) : Vec3; Vec3.new(@x, @y, z); end
    # Returns `[x, y]`.
    def to_a; [@x, @y]; end
    def to_s(io : IO) : Nil; io << "(" << @x << ", " << @y << ")"; end
    def inspect(io : IO) : Nil; io << "Vec2" << self; end
    def hash(h); h = @x.hash(h); @y.hash(h); end
  end
end

struct Number
  def *(v : Eagle::Vec2) : Eagle::Vec2; v * self; end
end

# Shorthand for `Eagle::Vec2.new(x, y)`, available everywhere.
def v2(x : Number, y : Number) : Eagle::Vec2; Eagle::Vec2.new(x, y); end
