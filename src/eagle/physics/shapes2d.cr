module Eagle
  module Physics2D
    # A collision shape in a body's local space. Eagle has circles and convex polygons;
    # build concave objects from several convex shapes on one body.
    abstract class Shape
      # Offset from the body's origin.
      property offset : Vec2 = Vec2::ZERO
      # Area in square pixels, used for mass.
      abstract def area : Float32
      # Bounds in the body's local space.
      abstract def local_aabb : Rect
      # Bounds in world space. Valid on transformed shapes.
      abstract def aabb : Rect
      # A world-space copy of the shape.
      abstract def transformed(t : Transform2D) : Shape
      # Moment of inertia per unit mass about the shape's center.
      abstract def inertia_factor : Float32
    end

    # A circle collision shape.
    #
    # ```
    # Physics2D::Circle.new(16)
    # Physics2D::Circle.new(8, offset: v2(0, -20)) # a head above the body's origin
    # ```
    class Circle < Shape
      # Radius in pixels.
      property radius : Float32
      # Center in world space, on transformed shapes.
      property center : Vec2

      # Creates a circle of *radius*, offset from the body's origin.
      def initialize(radius : Number, offset : Vec2 = Vec2::ZERO)
        @radius = radius.to_f32
        @offset = offset
        @center = offset
      end

      # Area of the circle.
      def area : Float32; (Math::PI * @radius * @radius).to_f32; end
      # Bounds in local space.
      def local_aabb : Rect; Rect.new(@offset.x - @radius, @offset.y - @radius, @radius * 2, @radius * 2); end
      # Inertia per unit mass.
      def inertia_factor : Float32; 0.5_f32 * @radius * @radius; end

      # A world-space copy.
      def transformed(t : Transform2D) : Shape
        c = Circle.new(@radius * t.scale.x, @offset)
        c.center = t * @offset
        c
      end

      # Bounds in world space.
      def aabb : Rect; Rect.new(@center.x - @radius, @center.y - @radius, @radius * 2, @radius * 2); end
      # True when *p* is inside the circle.
      def contains?(p : Vec2) : Bool; p.distance_squared(@center) <= @radius * @radius; end
    end

    # A convex polygon collision shape. Points can be in either winding order. Concave input
    # isn't supported; split it into several convex polygons.
    #
    # ```
    # Physics2D::Polygon.box(32, 48)
    # Physics2D::Polygon.new([v2(0, -20), v2(15, 10), v2(-15, 10)]) # triangle
    # ```
    class Polygon < Shape
      # Vertices in local space, stored clockwise.
      getter points : Array(Vec2)
      # Outward edge normals.
      getter normals : Array(Vec2)

      # Creates a polygon from convex points.
      def initialize(points : Array(Vec2), offset : Vec2 = Vec2::ZERO)
        raise ArgumentError.new("polygon needs at least 3 points") if points.size < 3
        @offset = offset
        @points = points.map { |p| p + offset }
        # ensure consistent winding: positive signed area in y-down means clockwise on screen
        area = 0_f32
        n = @points.size
        n.times { |i| area += @points[i].cross(@points[(i + 1) % n]) }
        @points.reverse! if area < 0
        @normals = compute_normals(@points)
      end

      protected def initialize(@points : Array(Vec2), @normals : Array(Vec2), @offset : Vec2)
      end

      private def compute_normals(pts) : Array(Vec2)
        n = pts.size
        Array(Vec2).new(n) do |i|
          e = pts[(i + 1) % n] - pts[i]
          # outward normal for clockwise (y-down) winding
          Vec2.new(-e.y, e.x).normalized * -1
        end
      end

      # A *w* by *h* box centered on *offset*.
      def self.box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : Polygon
        hw = w / 2; hh = h / 2
        new([Vec2.new(-hw, -hh), Vec2.new(hw, -hh), Vec2.new(hw, hh), Vec2.new(-hw, hh)], offset)
      end

      # A regular polygon with *sides* corners.
      def self.regular(sides : Int32, radius : Number, offset : Vec2 = Vec2::ZERO) : Polygon
        new(Array(Vec2).new(sides) { |i| Vec2.from_angle(Math::PI * 2 * i / sides, radius) }, offset)
      end

      # Area of the polygon.
      def area : Float32
        a = 0_f32
        n = @points.size
        n.times { |i| a += @points[i].cross(@points[(i + 1) % n]) }
        (a / 2).abs
      end

      # The polygon's center of mass.
      def centroid : Vec2
        c = Vec2::ZERO; a = 0_f32
        n = @points.size
        n.times do |i|
          cr = @points[i].cross(@points[(i + 1) % n])
          c += (@points[i] + @points[(i + 1) % n]) * cr
          a += cr
        end
        a == 0 ? @points[0] : c / (3 * a)
      end

      # Inertia per unit mass.
      def inertia_factor : Float32
        # polygon inertia per unit mass about centroid
        c = centroid
        num = 0_f32; den = 0_f32
        n = @points.size
        n.times do |i|
          p0 = @points[i] - c; p1 = @points[(i + 1) % n] - c
          cr = p0.cross(p1).abs
          num += cr * (p0.dot(p0) + p0.dot(p1) + p1.dot(p1))
          den += cr
        end
        den == 0 ? 0_f32 : num / (6 * den)
      end

      # Bounds in local space.
      def local_aabb : Rect
        mn = @points.reduce { |a, b| a.min(b) }; mx = @points.reduce { |a, b| a.max(b) }
        Rect.from_bounds(mn, mx)
      end

      # Bounds in world space.
      def aabb : Rect; local_aabb; end

      # A world-space copy.
      def transformed(t : Transform2D) : Shape
        pts = @points.map { |p| t * p }
        Polygon.new(pts, compute_normals(pts), @offset)
      end

      # True when *p* is inside the polygon.
      def contains?(p : Vec2) : Bool
        n = @points.size
        n.times do |i|
          return false if (p - @points[i]).dot(@normals[i]) > 0
        end
        true
      end

      # The vertex furthest in direction *d*, used by collision tests.
      def support(d : Vec2) : Vec2
        best = @points[0]; bd = best.dot(d)
        @points.each { |p| pd = p.dot(d); if pd > bd; bd = pd; best = p; end }
        best
      end
    end
  end
end
