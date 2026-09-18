module Eagle
  # A 2D affine transform: translation, rotation and scale packed into a 3x2 matrix.
  #
  # Most code never builds one by hand, because `Node2D` has `position`, `rotation`
  # and `scale` and composes them for you. Reach for `Transform2D` when you need the
  # matrix itself: converting points between spaces, drawing with `Graphics#apply`, or
  # baking a pose.
  #
  # The matrix layout is:
  #
  # ```text
  # [ a c tx ]
  # [ b d ty ]
  # ```
  #
  # Multiplying transforms composes them right to left, and multiplying by a `Vec2`
  # transforms a point.
  #
  # ```
  # t = Transform2D.trs(v2(200, 150), Mathf.deg2rad(45), v2(2, 2))
  # tip = t * v2(10, 0)             # local point to world
  # back = t.inverse * tip          # world point back to local => (10, 0)
  # dir = t.transform_dir(Vec2::RIGHT) # direction only, ignores translation
  #
  # g.with_transform(t) { g.rect(-5, -5, 10, 10) } # draw in the transformed space
  # ```
  struct Transform2D
    property a : Float32
    property b : Float32
    property c : Float32
    property d : Float32
    property tx : Float32
    property ty : Float32

    def initialize(@a : Float32 = 1_f32, @b : Float32 = 0_f32, @c : Float32 = 0_f32, @d : Float32 = 1_f32, @tx : Float32 = 0_f32, @ty : Float32 = 0_f32); end

    # The transform that changes nothing.
    IDENTITY = Transform2D.new

    # Returns `IDENTITY`.
    def self.identity : Transform2D; Transform2D.new; end

    # A pure translation by *v*.
    def self.translation(v : Vec2) : Transform2D; Transform2D.new(tx: v.x, ty: v.y); end
    # A pure rotation by *rad* radians around the origin.
    def self.rotation(rad : Number) : Transform2D
      c = Math.cos(rad).to_f32; s = Math.sin(rad).to_f32
      Transform2D.new(c, s, -s, c, 0_f32, 0_f32)
    end
    # A pure scale by *v*.
    def self.scale(v : Vec2) : Transform2D; Transform2D.new(a: v.x, d: v.y); end

    # Builds translation * rotation * scale in one step. *pivot* is the local point that
    # ends up at *pos*, so the shape rotates and scales around it.
    def self.trs(pos : Vec2, rot : Number, scale : Vec2, pivot : Vec2 = Vec2::ZERO) : Transform2D
      c = Math.cos(rot).to_f32; s = Math.sin(rot).to_f32
      a = c * scale.x; b = s * scale.x; cc = -s * scale.y; d = c * scale.y
      tx = pos.x - (a * pivot.x + cc * pivot.y)
      ty = pos.y - (b * pivot.x + d * pivot.y)
      Transform2D.new(a, b, cc, d, tx, ty)
    end

    # Composes two transforms: `(a * b) * p == a * (b * p)`.
    def *(o : Transform2D) : Transform2D
      Transform2D.new(
        @a * o.a + @c * o.b, @b * o.a + @d * o.b,
        @a * o.c + @c * o.d, @b * o.c + @d * o.d,
        @a * o.tx + @c * o.ty + @tx, @b * o.tx + @d * o.ty + @ty)
    end

    # Transforms a point, applying translation.
    def *(p : Vec2) : Vec2
      Vec2.new(@a * p.x + @c * p.y + @tx, @b * p.x + @d * p.y + @ty)
    end

    # Transforms a direction, ignoring translation.
    def transform_dir(v : Vec2) : Vec2; Vec2.new(@a * v.x + @c * v.y, @b * v.x + @d * v.y); end

    # The translation part.
    def translation : Vec2; Vec2.new(@tx, @ty); end
    # The rotation part in radians.
    def rotation : Float32; Math.atan2(@b, @a).to_f32; end
    # The scale along each axis.
    def scale : Vec2; Vec2.new(Math.sqrt(@a * @a + @b * @b), Math.sqrt(@c * @c + @d * @d)); end

    # The inverse transform, which maps back from world to local space.
    # Returns identity if the matrix can't be inverted, for example with a zero scale.
    def inverse : Transform2D
      det = @a * @d - @b * @c
      return Transform2D.identity if det == 0
      ia = @d / det; ib = -@b / det; ic = -@c / det; id = @a / det
      Transform2D.new(ia, ib, ic, id, -(ia * @tx + ic * @ty), -(ib * @tx + id * @ty))
    end

    # The same transform as a 4x4 matrix, for passing to shaders.
    def to_mat4 : Mat4
      m = Mat4.identity
      m[0, 0] = @a; m[0, 1] = @b
      m[1, 0] = @c; m[1, 1] = @d
      m[3, 0] = @tx; m[3, 1] = @ty
      m
    end

    def ==(o : Transform2D) : Bool
      @a == o.a && @b == o.b && @c == o.c && @d == o.d && @tx == o.tx && @ty == o.ty
    end

    # Component-wise comparison within *eps*.
    def approx?(o : Transform2D, eps = 1e-5) : Bool
      (@a - o.a).abs <= eps && (@b - o.b).abs <= eps && (@c - o.c).abs <= eps &&
        (@d - o.d).abs <= eps && (@tx - o.tx).abs <= eps && (@ty - o.ty).abs <= eps
    end
  end
end
