module Eagle
  module Physics2D
    # Local-space shapes attached to bodies. World-space copies are built per step.
    abstract class Shape
      # Offset from the body origin (local space).
      property offset : Vec2 = Vec2::ZERO
      abstract def area : Float32
      abstract def local_aabb : Rect
      # World-space AABB (valid on transformed shapes).
      abstract def aabb : Rect
      abstract def transformed(t : Transform2D) : Shape
      # Moment of inertia per unit mass about the shape's own centre.
      abstract def inertia_factor : Float32
    end

    class Circle < Shape
      property radius : Float32
      # World-space centre (for transformed shapes)
      property center : Vec2

      def initialize(radius : Number, offset : Vec2 = Vec2::ZERO)
        @radius = radius.to_f32
        @offset = offset
        @center = offset
      end

      def area : Float32; (Math::PI * @radius * @radius).to_f32; end
      def local_aabb : Rect; Rect.new(@offset.x - @radius, @offset.y - @radius, @radius * 2, @radius * 2); end
      def inertia_factor : Float32; 0.5_f32 * @radius * @radius; end

      def transformed(t : Transform2D) : Shape
        c = Circle.new(@radius * t.scale.x, @offset)
        c.center = t * @offset
        c
      end

      def aabb : Rect; Rect.new(@center.x - @radius, @center.y - @radius, @radius * 2, @radius * 2); end
      def contains?(p : Vec2) : Bool; p.distance_squared(@center) <= @radius * @radius; end
    end

    # Convex polygon, points in local space (either winding; normalised to clockwise in y-down).
    class Polygon < Shape
      getter points : Array(Vec2)
      getter normals : Array(Vec2)

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

      def self.box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : Polygon
        hw = w / 2; hh = h / 2
        new([Vec2.new(-hw, -hh), Vec2.new(hw, -hh), Vec2.new(hw, hh), Vec2.new(-hw, hh)], offset)
      end

      def self.regular(sides : Int32, radius : Number, offset : Vec2 = Vec2::ZERO) : Polygon
        new(Array(Vec2).new(sides) { |i| Vec2.from_angle(Math::PI * 2 * i / sides, radius) }, offset)
      end

      def area : Float32
        a = 0_f32
        n = @points.size
        n.times { |i| a += @points[i].cross(@points[(i + 1) % n]) }
        (a / 2).abs
      end

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

      def local_aabb : Rect
        mn = @points.reduce { |a, b| a.min(b) }; mx = @points.reduce { |a, b| a.max(b) }
        Rect.from_bounds(mn, mx)
      end

      def aabb : Rect; local_aabb; end

      def transformed(t : Transform2D) : Shape
        pts = @points.map { |p| t * p }
        Polygon.new(pts, compute_normals(pts), @offset)
      end

      def contains?(p : Vec2) : Bool
        n = @points.size
        n.times do |i|
          return false if (p - @points[i]).dot(@normals[i]) > 0
        end
        true
      end

      # Support point in direction d.
      def support(d : Vec2) : Vec2
        best = @points[0]; bd = best.dot(d)
        @points.each { |p| pd = p.dot(d); if pd > bd; bd = pd; best = p; end }
        best
      end
    end
  end
end
