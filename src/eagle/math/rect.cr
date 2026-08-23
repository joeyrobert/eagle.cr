module Eagle
  struct Rect
    property x : Float32
    property y : Float32
    property w : Float32
    property h : Float32

    def initialize(x : Number, y : Number, w : Number, h : Number)
      @x = x.to_f32; @y = y.to_f32; @w = w.to_f32; @h = h.to_f32
    end

    def initialize(pos : Vec2, size : Vec2)
      @x = pos.x; @y = pos.y; @w = size.x; @h = size.y
    end

    def initialize
      @x = @y = @w = @h = 0_f32
    end

    def self.from_bounds(min : Vec2, max : Vec2) : Rect
      Rect.new(min.x, min.y, max.x - min.x, max.y - min.y)
    end

    def self.centered(center : Vec2, size : Vec2) : Rect
      Rect.new(center.x - size.x / 2, center.y - size.y / 2, size.x, size.y)
    end

    def position : Vec2; Vec2.new(@x, @y); end
    def size : Vec2; Vec2.new(@w, @h); end
    def left : Float32; @x; end
    def top : Float32; @y; end
    def right : Float32; @x + @w; end
    def bottom : Float32; @y + @h; end
    def center : Vec2; Vec2.new(@x + @w / 2, @y + @h / 2); end
    def min : Vec2; position; end
    def max : Vec2; Vec2.new(right, bottom); end
    def area : Float32; @w * @h; end
    def empty? : Bool; @w <= 0 || @h <= 0; end

    def ==(o : Rect) : Bool; @x == o.x && @y == o.y && @w == o.w && @h == o.h; end

    def contains?(p : Vec2) : Bool
      p.x >= @x && p.x < right && p.y >= @y && p.y < bottom
    end

    def contains?(o : Rect) : Bool
      o.x >= @x && o.right <= right && o.y >= @y && o.bottom <= bottom
    end

    def intersects?(o : Rect) : Bool
      @x < o.right && right > o.x && @y < o.bottom && bottom > o.y
    end

    def intersection(o : Rect) : Rect
      nx = Math.max(@x, o.x); ny = Math.max(@y, o.y)
      nr = Math.min(right, o.right); nb = Math.min(bottom, o.bottom)
      return Rect.new if nr <= nx || nb <= ny
      Rect.new(nx, ny, nr - nx, nb - ny)
    end

    def union(o : Rect) : Rect
      nx = Math.min(@x, o.x); ny = Math.min(@y, o.y)
      Rect.new(nx, ny, Math.max(right, o.right) - nx, Math.max(bottom, o.bottom) - ny)
    end

    def grow(amount : Number) : Rect
      Rect.new(@x - amount, @y - amount, @w + amount * 2, @h + amount * 2)
    end

    def translate(v : Vec2) : Rect; Rect.new(@x + v.x, @y + v.y, @w, @h); end
    def scale(s : Number) : Rect; Rect.new(@x * s, @y * s, @w * s, @h * s); end

    def to_s(io : IO) : Nil; io << "Rect(" << @x << ", " << @y << ", " << @w << ", " << @h << ")"; end
  end

  # Axis-aligned 3D box.
  struct AABB
    property min : Vec3
    property max : Vec3

    def initialize(@min : Vec3, @max : Vec3); end

    def self.from_center(center : Vec3, half : Vec3) : AABB
      AABB.new(center - half, center + half)
    end

    def self.from_points(points : Enumerable(Vec3)) : AABB
      mn = Vec3.new(Float32::INFINITY); mx = Vec3.new(-Float32::INFINITY)
      points.each { |p| mn = mn.min(p); mx = mx.max(p) }
      AABB.new(mn, mx)
    end

    def center : Vec3; (@min + @max) / 2; end
    def size : Vec3; @max - @min; end
    def half : Vec3; size / 2; end

    def contains?(p : Vec3) : Bool
      p.x >= @min.x && p.x <= @max.x && p.y >= @min.y && p.y <= @max.y && p.z >= @min.z && p.z <= @max.z
    end

    def intersects?(o : AABB) : Bool
      @min.x <= o.max.x && @max.x >= o.min.x &&
        @min.y <= o.max.y && @max.y >= o.min.y &&
        @min.z <= o.max.z && @max.z >= o.min.z
    end

    def union(o : AABB) : AABB; AABB.new(@min.min(o.min), @max.max(o.max)); end

    def transformed(m : Mat4) : AABB
      corners = [
        Vec3.new(@min.x, @min.y, @min.z), Vec3.new(@max.x, @min.y, @min.z),
        Vec3.new(@min.x, @max.y, @min.z), Vec3.new(@max.x, @max.y, @min.z),
        Vec3.new(@min.x, @min.y, @max.z), Vec3.new(@max.x, @min.y, @max.z),
        Vec3.new(@min.x, @max.y, @max.z), Vec3.new(@max.x, @max.y, @max.z),
      ]
      AABB.from_points(corners.map { |c| m.transform_point(c) })
    end
  end

  struct Ray
    property origin : Vec3
    property direction : Vec3

    def initialize(@origin : Vec3, direction : Vec3)
      @direction = direction.normalized
    end

    def at(t : Number) : Vec3; @origin + @direction * t; end

    # Returns distance along the ray or nil.
    def intersect_aabb(box : AABB) : Float32?
      tmin = -Float32::INFINITY; tmax = Float32::INFINITY
      {% for axis in %w(x y z) %}
        d = @direction.{{axis.id}}
        if d.abs < 1e-8
          return nil if @origin.{{axis.id}} < box.min.{{axis.id}} || @origin.{{axis.id}} > box.max.{{axis.id}}
        else
          t1 = (box.min.{{axis.id}} - @origin.{{axis.id}}) / d
          t2 = (box.max.{{axis.id}} - @origin.{{axis.id}}) / d
          t1, t2 = t2, t1 if t1 > t2
          tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2)
          return nil if tmin > tmax
        end
      {% end %}
      tmin >= 0 ? tmin : (tmax >= 0 ? tmax : nil)
    end

    def intersect_sphere(center : Vec3, radius : Number) : Float32?
      oc = @origin - center
      b = oc.dot(@direction)
      c = oc.length_squared - radius * radius
      disc = b * b - c
      return nil if disc < 0
      t = -b - Math.sqrt(disc)
      t = -b + Math.sqrt(disc) if t < 0
      t >= 0 ? t.to_f32 : nil
    end

    def intersect_plane(point : Vec3, normal : Vec3) : Float32?
      denom = normal.dot(@direction)
      return nil if denom.abs < 1e-8
      t = (point - @origin).dot(normal) / denom
      t >= 0 ? t.to_f32 : nil
    end
  end
end
