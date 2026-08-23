module Eagle
  # 2D affine transform (position, rotation, scale, skew-free) with a cached 3x2 matrix.
  #   [ a c tx ]
  #   [ b d ty ]
  struct Transform2D
    property a : Float32
    property b : Float32
    property c : Float32
    property d : Float32
    property tx : Float32
    property ty : Float32

    def initialize(@a : Float32 = 1_f32, @b : Float32 = 0_f32, @c : Float32 = 0_f32, @d : Float32 = 1_f32, @tx : Float32 = 0_f32, @ty : Float32 = 0_f32); end

    IDENTITY = Transform2D.new

    def self.identity : Transform2D; Transform2D.new; end

    def self.translation(v : Vec2) : Transform2D; Transform2D.new(tx: v.x, ty: v.y); end
    def self.rotation(rad : Number) : Transform2D
      c = Math.cos(rad).to_f32; s = Math.sin(rad).to_f32
      Transform2D.new(c, s, -s, c, 0_f32, 0_f32)
    end
    def self.scale(v : Vec2) : Transform2D; Transform2D.new(a: v.x, d: v.y); end

    # translation * rotation * scale, around an optional pivot
    def self.trs(pos : Vec2, rot : Number, scale : Vec2, pivot : Vec2 = Vec2::ZERO) : Transform2D
      c = Math.cos(rot).to_f32; s = Math.sin(rot).to_f32
      a = c * scale.x; b = s * scale.x; cc = -s * scale.y; d = c * scale.y
      tx = pos.x - (a * pivot.x + cc * pivot.y)
      ty = pos.y - (b * pivot.x + d * pivot.y)
      Transform2D.new(a, b, cc, d, tx, ty)
    end

    def *(o : Transform2D) : Transform2D
      Transform2D.new(
        @a * o.a + @c * o.b, @b * o.a + @d * o.b,
        @a * o.c + @c * o.d, @b * o.c + @d * o.d,
        @a * o.tx + @c * o.ty + @tx, @b * o.tx + @d * o.ty + @ty)
    end

    def *(p : Vec2) : Vec2
      Vec2.new(@a * p.x + @c * p.y + @tx, @b * p.x + @d * p.y + @ty)
    end

    def transform_dir(v : Vec2) : Vec2; Vec2.new(@a * v.x + @c * v.y, @b * v.x + @d * v.y); end

    def translation : Vec2; Vec2.new(@tx, @ty); end
    def rotation : Float32; Math.atan2(@b, @a).to_f32; end
    def scale : Vec2; Vec2.new(Math.sqrt(@a * @a + @b * @b), Math.sqrt(@c * @c + @d * @d)); end

    def inverse : Transform2D
      det = @a * @d - @b * @c
      return Transform2D.identity if det == 0
      ia = @d / det; ib = -@b / det; ic = -@c / det; id = @a / det
      Transform2D.new(ia, ib, ic, id, -(ia * @tx + ic * @ty), -(ib * @tx + id * @ty))
    end

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

    def approx?(o : Transform2D, eps = 1e-5) : Bool
      (@a - o.a).abs <= eps && (@b - o.b).abs <= eps && (@c - o.c).abs <= eps &&
        (@d - o.d).abs <= eps && (@tx - o.tx).abs <= eps && (@ty - o.ty).abs <= eps
    end
  end
end
