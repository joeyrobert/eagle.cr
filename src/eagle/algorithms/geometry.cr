module Eagle
  # Small, allocation-conscious computational geometry and curve helpers: convex hulls,
  # segment intersection, point-in-polygon tests, and Bezier / Catmull-Rom evaluation.
  #
  # ```
  # hull = Geometry.convex_hull([v2(0, 0), v2(4, 0), v2(2, 3), v2(2, 1)])
  # Geometry.point_in_polygon?(v2(2, 1), hull) # => true
  # mid = Geometry.bezier_quadratic(v2(0, 0), v2(1, 2), v2(2, 0), 0.5)
  # ```
  module Geometry
    # Monotone-chain convex hull in counter-clockwise order. Duplicate points are removed.
    def self.convex_hull(points : Enumerable(Vec2)) : Array(Vec2)
      sorted = points.to_a.uniq.sort_by { |point| {point.x, point.y} }
      return sorted if sorted.size <= 2
      lower = [] of Vec2
      sorted.each do |point|
        while lower.size >= 2 && (lower[-1] - lower[-2]).cross(point - lower[-1]) <= 0
          lower.pop
        end
        lower << point
      end
      upper = [] of Vec2
      sorted.reverse_each do |point|
        while upper.size >= 2 && (upper[-1] - upper[-2]).cross(point - upper[-1]) <= 0
          upper.pop
        end
        upper << point
      end
      lower.pop
      upper.pop
      lower + upper
    end

    # Intersection point of two closed line segments, or nil when they do not meet.
    # Collinear overlaps return the first shared endpoint when one exists.
    def self.segment_intersection(a : Vec2, b : Vec2, c : Vec2, d : Vec2, epsilon = 1e-6) : Vec2?
      r = b - a
      s = d - c
      denominator = r.cross(s)
      offset = c - a
      if denominator.abs <= epsilon
        return a if point_on_segment?(a, c, d, epsilon)
        return b if point_on_segment?(b, c, d, epsilon)
        return c if point_on_segment?(c, a, b, epsilon)
        return d if point_on_segment?(d, a, b, epsilon)
        return nil
      end
      t = offset.cross(s) / denominator
      u = offset.cross(r) / denominator
      (t >= -epsilon && t <= 1 + epsilon && u >= -epsilon && u <= 1 + epsilon) ? a + r * t : nil
    end

    def self.point_on_segment?(point : Vec2, a : Vec2, b : Vec2, epsilon = 1e-6) : Bool
      (b - a).cross(point - a).abs <= epsilon &&
        point.x >= Math.min(a.x, b.x) - epsilon && point.x <= Math.max(a.x, b.x) + epsilon &&
        point.y >= Math.min(a.y, b.y) - epsilon && point.y <= Math.max(a.y, b.y) + epsilon
    end

    # Even-odd point-in-polygon test. Boundary points count as inside.
    def self.point_in_polygon?(point : Vec2, polygon : Indexable(Vec2)) : Bool
      return false if polygon.size < 3
      inside = false
      j = polygon.size - 1
      polygon.each_with_index do |a, i|
        b = polygon[j]
        return true if point_on_segment?(point, a, b)
        if (a.y > point.y) != (b.y > point.y) &&
           point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
          inside = !inside
        end
        j = i
      end
      inside
    end

    def self.bezier_quadratic(a : Vec2, control : Vec2, b : Vec2, t : Number) : Vec2
      u = 1.0 - t
      a * (u * u) + control * (2 * u * t) + b * (t * t)
    end

    def self.bezier_cubic(a : Vec2, c1 : Vec2, c2 : Vec2, b : Vec2, t : Number) : Vec2
      u = 1.0 - t
      a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t)
    end

    # Catmull-Rom segment from p1 to p2. Tension 0.5 is the common centripetal-looking default.
    def self.catmull_rom(p0 : Vec2, p1 : Vec2, p2 : Vec2, p3 : Vec2, t : Number, tension = 0.5) : Vec2
      t2 = t * t
      t3 = t2 * t
      tangent1 = (p2 - p0) * tension
      tangent2 = (p3 - p1) * tension
      p1 * (2 * t3 - 3 * t2 + 1) + tangent1 * (t3 - 2 * t2 + t) +
        p2 * (-2 * t3 + 3 * t2) + tangent2 * (t3 - t2)
    end
  end

  # A sampled curve parameterized by approximate distance instead of raw curve t.
  class ArcLengthPath
    getter points : Array(Vec2)
    getter distances : Array(Float32)
    getter length : Float32

    def initialize(&curve : Float32 -> Vec2)
      initialize(100, &curve)
    end

    def initialize(segments : Int, &curve : Float32 -> Vec2)
      raise ArgumentError.new("segments must be positive") if segments <= 0
      @points = Array(Vec2).new(segments + 1) { |i| curve.call(i.to_f32 / segments) }
      @distances = Array(Float32).new(@points.size, 0_f32)
      (1...@points.size).each { |i| @distances[i] = @distances[i - 1] + @points[i - 1].distance(@points[i]) }
      @length = @distances.last
    end

    # Point at a clamped distance along the curve.
    def at(distance : Number) : Vec2
      return @points.first if @length == 0
      target = distance.to_f32.clamp(0_f32, @length)
      high = @distances.bsearch_index { |value| value >= target } || @distances.size - 1
      return @points.first if high == 0
      low = high - 1
      span = @distances[high] - @distances[low]
      @points[low].lerp(@points[high], span == 0 ? 0 : (target - @distances[low]) / span)
    end

    def normalized(t : Number) : Vec2
      at(t.to_f32.clamp(0_f32, 1_f32) * @length)
    end
  end

  # Frame-rate-independent critically damped spring for scalar values.
  class Spring
    property value : Float32
    property velocity : Float32

    def initialize(value : Number = 0, velocity : Number = 0)
      @value = value.to_f32
      @velocity = velocity.to_f32
    end

    def update(target : Number, half_life : Number, dt : Number) : Float32
      decay = Math.exp(-Math.log(2.0) * dt / Math.max(half_life.to_f64, 1e-5)).to_f32
      offset = @value - target
      j = @velocity + offset * Math.log(2.0).to_f32 / Math.max(half_life.to_f32, 1e-5_f32)
      @value = (target + (offset + j * dt) * decay).to_f32
      @velocity = (@velocity - j * Math.log(2.0) * dt / Math.max(half_life.to_f64, 1e-5)) * decay
      @value
    end
  end

  # Critically damped spring for positions and other 2D vectors.
  class Spring2
    property value : Vec2
    property velocity : Vec2

    def initialize(@value = Vec2::ZERO, @velocity = Vec2::ZERO); end

    def update(target : Vec2, half_life : Number, dt : Number) : Vec2
      rate = Math.log(2.0).to_f32 / Math.max(half_life.to_f32, 1e-5_f32)
      decay = Math.exp(-rate * dt).to_f32
      offset = @value - target
      j = @velocity + offset * rate
      @value = target + (offset + j * dt) * decay
      @velocity = (@velocity - j * rate * dt) * decay
      @value
    end
  end
end
