module Eagle
  # An axis-aligned 2D rectangle: `x`, `y` for the top-left corner, then `w` and `h`.
  #
  # Rects are used for hit areas, UI layout, texture regions, camera limits and quick
  # overlap tests. The right and bottom edges are exclusive, so `contains?` treats a
  # point on the right edge as outside, just as pixels work.
  #
  # ```
  # player = Rect.new(100, 100, 32, 48)
  # coin = Rect.centered(v2(120, 110), v2(16, 16))
  # if player.intersects?(coin)
  #   # pick it up
  # end
  #
  # button = Rect.new(20, 20, 120, 40)
  # hovered = button.contains?(Input.mouse)
  # g.rect(button, color: hovered ? Color::YELLOW : Color::GRAY)
  # ```
  struct Rect
    property x : Float32
    property y : Float32
    property w : Float32
    property h : Float32

    # Creates a rect from its top-left corner and size.
    def initialize(x : Number, y : Number, w : Number, h : Number)
      @x = x.to_f32; @y = y.to_f32; @w = w.to_f32; @h = h.to_f32
    end

    # Creates a rect from a position and a size.
    def initialize(pos : Vec2, size : Vec2)
      @x = pos.x; @y = pos.y; @w = size.x; @h = size.y
    end

    # Creates an empty rect at the origin.
    def initialize
      @x = @y = @w = @h = 0_f32
    end

    # Creates a rect spanning from the *min* corner to the *max* corner.
    def self.from_bounds(min : Vec2, max : Vec2) : Rect
      Rect.new(min.x, min.y, max.x - min.x, max.y - min.y)
    end

    # Creates a rect of *size* centered on *center*.
    def self.centered(center : Vec2, size : Vec2) : Rect
      Rect.new(center.x - size.x / 2, center.y - size.y / 2, size.x, size.y)
    end

    # The top-left corner.
    def position : Vec2; Vec2.new(@x, @y); end
    # `(w, h)`.
    def size : Vec2; Vec2.new(@w, @h); end
    # The x of the left edge.
    def left : Float32; @x; end
    # The y of the top edge.
    def top : Float32; @y; end
    # The x of the right edge (`x + w`).
    def right : Float32; @x + @w; end
    # The y of the bottom edge (`y + h`).
    def bottom : Float32; @y + @h; end
    # The center point.
    def center : Vec2; Vec2.new(@x + @w / 2, @y + @h / 2); end
    # The top-left corner.
    def min : Vec2; position; end
    # The bottom-right corner.
    def max : Vec2; Vec2.new(right, bottom); end
    # `w * h`.
    def area : Float32; @w * @h; end
    # True when the width or height is zero or negative.
    def empty? : Bool; @w <= 0 || @h <= 0; end

    def ==(o : Rect) : Bool; @x == o.x && @y == o.y && @w == o.w && @h == o.h; end

    # True when the point is inside. Left and top edges count as inside; right and bottom don't.
    def contains?(p : Vec2) : Bool
      p.x >= @x && p.x < right && p.y >= @y && p.y < bottom
    end

    # True when *o* lies entirely inside this rect.
    def contains?(o : Rect) : Bool
      o.x >= @x && o.right <= right && o.y >= @y && o.bottom <= bottom
    end

    # True when the rects overlap. Touching edges don't count.
    def intersects?(o : Rect) : Bool
      @x < o.right && right > o.x && @y < o.bottom && bottom > o.y
    end

    # The overlapping area, or an empty rect when they don't overlap.
    def intersection(o : Rect) : Rect
      nx = Math.max(@x, o.x); ny = Math.max(@y, o.y)
      nr = Math.min(right, o.right); nb = Math.min(bottom, o.bottom)
      return Rect.new if nr <= nx || nb <= ny
      Rect.new(nx, ny, nr - nx, nb - ny)
    end

    # The smallest rect containing both.
    def union(o : Rect) : Rect
      nx = Math.min(@x, o.x); ny = Math.min(@y, o.y)
      Rect.new(nx, ny, Math.max(right, o.right) - nx, Math.max(bottom, o.bottom) - ny)
    end

    # The rect expanded by *amount* on every side. A negative amount shrinks it.
    def grow(amount : Number) : Rect
      Rect.new(@x - amount, @y - amount, @w + amount * 2, @h + amount * 2)
    end

    # The rect moved by *v*.
    def translate(v : Vec2) : Rect; Rect.new(@x + v.x, @y + v.y, @w, @h); end
    # Position and size multiplied by *s*.
    def scale(s : Number) : Rect; Rect.new(@x * s, @y * s, @w * s, @h * s); end

    def to_s(io : IO) : Nil; io << "Rect(" << @x << ", " << @y << ", " << @w << ", " << @h << ")"; end
  end

  # An axis-aligned 3D box, given by its `min` and `max` corners.
  #
  # Eagle uses it for mesh bounds, picking and culling. `MeshInstance3D#global_bounds`
  # returns one, and `Ray#intersect_aabb` tests against it.
  #
  # ```
  # box = AABB.from_center(v3(0, 1, 0), v3(1, 1, 1))
  # box.contains?(v3(0.5, 1.5, 0)) # => true
  #
  # ray = Ray.new(v3(0, 1, 10), Vec3::FORWARD)
  # if dist = ray.intersect_aabb(box)
  #   hit_point = ray.at(dist) # => (0, 1, 1)
  # end
  # ```
  struct AABB
    property min : Vec3
    property max : Vec3

    # Creates a box from its *min* and *max* corners.
    def initialize(@min : Vec3, @max : Vec3); end

    # Creates a box from its center and half-extents.
    def self.from_center(center : Vec3, half : Vec3) : AABB
      AABB.new(center - half, center + half)
    end

    # The smallest box containing all *points*.
    def self.from_points(points : Enumerable(Vec3)) : AABB
      mn = Vec3.new(Float32::INFINITY); mx = Vec3.new(-Float32::INFINITY)
      points.each { |p| mn = mn.min(p); mx = mx.max(p) }
      AABB.new(mn, mx)
    end

    # The center point.
    def center : Vec3; (@min + @max) / 2; end
    # The full extent along each axis.
    def size : Vec3; @max - @min; end
    # Half the extent: the distance from the center to each face.
    def half : Vec3; size / 2; end

    # True when the point is inside or on the surface.
    def contains?(p : Vec3) : Bool
      p.x >= @min.x && p.x <= @max.x && p.y >= @min.y && p.y <= @max.y && p.z >= @min.z && p.z <= @max.z
    end

    # True when the boxes overlap or touch.
    def intersects?(o : AABB) : Bool
      @min.x <= o.max.x && @max.x >= o.min.x &&
        @min.y <= o.max.y && @max.y >= o.min.y &&
        @min.z <= o.max.z && @max.z >= o.min.z
    end

    # The smallest box containing both.
    def union(o : AABB) : AABB; AABB.new(@min.min(o.min), @max.max(o.max)); end

    # The box that bounds this box after transforming it by *m*. It can be larger than
    # the original when *m* rotates.
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

  # A 3D ray: an `origin` and a unit `direction`. Use it for picking, line of sight and
  # simple hit-scan weapons.
  #
  # `Camera3D#mouse_ray` gives you the ray under the mouse cursor. Each `intersect_*`
  # method returns the distance along the ray to the hit, or `nil` on a miss. Pass that
  # distance to `at` to get the hit point.
  #
  # ```
  # ray = Ray.new(v3(0, 2, 0), v3(0, -1, 0))
  # if t = ray.intersect_plane(Vec3::ZERO, Vec3::UP)
  #   ground = ray.at(t) # => (0, 0, 0)
  # end
  # ray.intersect_sphere(v3(0, -5, 0), 1) # => 6.0
  # ```
  struct Ray
    property origin : Vec3
    property direction : Vec3

    # Creates a ray. *direction* is normalized for you.
    def initialize(@origin : Vec3, direction : Vec3)
      @direction = direction.normalized
    end

    # The point at distance *t* along the ray.
    def at(t : Number) : Vec3; @origin + @direction * t; end

    # Distance to the first hit on *box*, or `nil`. If the ray starts inside the box,
    # this is the distance to where it exits.
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

    # Distance to the first hit on a sphere, or `nil`.
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

    # Distance to where the ray crosses the plane through *point* with *normal*, or `nil`
    # when the ray is parallel to it or pointing away.
    def intersect_plane(point : Vec3, normal : Vec3) : Float32?
      denom = normal.dot(@direction)
      return nil if denom.abs < 1e-8
      t = (point - @origin).dot(normal) / denom
      t >= 0 ? t.to_f32 : nil
    end
  end
end
