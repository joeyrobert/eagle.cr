module Eagle
  module Physics2D
    # Result of a narrow-phase test.
    struct Manifold
      getter normal : Vec2          # from A to B
      getter penetration : Float32
      getter contacts : Array(Vec2)
      def initialize(@normal, @penetration, @contacts); end
    end

    struct RayHit
      getter point : Vec2
      getter normal : Vec2
      getter distance : Float32
      getter body : Body
      getter shape : Shape
      def initialize(@point, @normal, @distance, @body, @shape); end
    end

    # Narrow-phase collision on world-space shapes.
    module Collision
      extend self

      def test(a : Shape, b : Shape) : Manifold?
        case {a, b}
        when {Circle, Circle} then circle_circle(a.as(Circle), b.as(Circle))
        when {Circle, Polygon} then circle_polygon(a.as(Circle), b.as(Polygon))
        when {Polygon, Circle}
          m = circle_polygon(b.as(Circle), a.as(Polygon))
          m ? Manifold.new(-m.normal, m.penetration, m.contacts) : nil
        when {Polygon, Polygon} then polygon_polygon(a.as(Polygon), b.as(Polygon))
        else nil
        end
      end

      def overlaps?(a : Shape, b : Shape) : Bool
        !test(a, b).nil?
      end

      def circle_circle(a : Circle, b : Circle) : Manifold?
        d = b.center - a.center
        dist2 = d.length_squared
        r = a.radius + b.radius
        return nil if dist2 >= r * r
        dist = Math.sqrt(dist2).to_f32
        normal = dist > 1e-6 ? d / dist : Vec2.new(1, 0)
        Manifold.new(normal, r - dist, [a.center + normal * a.radius])
      end

      def circle_polygon(c : Circle, p : Polygon) : Manifold?
        # find face with minimum penetration
        sep = -Float32::INFINITY
        face = 0
        p.points.size.times do |i|
          s = p.normals[i].dot(c.center - p.points[i])
          return nil if s > c.radius
          if s > sep
            sep = s; face = i
          end
        end
        v1 = p.points[face]; v2 = p.points[(face + 1) % p.points.size]
        if sep < 1e-6
          # centre inside polygon
          n = -p.normals[face]
          return Manifold.new(n, c.radius - sep, [c.center - n * c.radius])
        end
        # voronoi regions
        d1 = (c.center - v1).dot(v2 - v1)
        d2 = (c.center - v2).dot(v1 - v2)
        if d1 <= 0
          dist2 = c.center.distance_squared(v1)
          return nil if dist2 > c.radius * c.radius
          dist = Math.sqrt(dist2).to_f32
          n = dist > 1e-6 ? (v1 - c.center) / dist : p.normals[face] * -1
          Manifold.new(n, c.radius - dist, [v1])
        elsif d2 <= 0
          dist2 = c.center.distance_squared(v2)
          return nil if dist2 > c.radius * c.radius
          dist = Math.sqrt(dist2).to_f32
          n = dist > 1e-6 ? (v2 - c.center) / dist : p.normals[face] * -1
          Manifold.new(n, c.radius - dist, [v2])
        else
          n = -p.normals[face] # from circle towards polygon
          Manifold.new(n, c.radius - sep, [c.center + n * c.radius])
        end
      end

      # SAT with face clipping for contact points.
      def polygon_polygon(a : Polygon, b : Polygon) : Manifold?
        pa, fa = axis_of_least_penetration(a, b)
        return nil if pa >= 0
        pb, fb = axis_of_least_penetration(b, a)
        return nil if pb >= 0
        if pa >= pb * 0.95 + pa * 0.01 # bias towards A
          ref = a; inc = b; ref_face = fa; flip = false
        else
          ref = b; inc = a; ref_face = fb; flip = true
        end
        ref_normal = ref.normals[ref_face]
        # incident face: most anti-parallel to ref normal
        inc_face = 0; min_dot = Float32::INFINITY
        inc.normals.each_with_index { |n, i| d = ref_normal.dot(n); if d < min_dot; min_dot = d; inc_face = i; end }
        iv1 = inc.points[inc_face]; iv2 = inc.points[(inc_face + 1) % inc.points.size]
        rv1 = ref.points[ref_face]; rv2 = ref.points[(ref_face + 1) % ref.points.size]
        side = (rv2 - rv1).normalized
        neg_side = -side.dot(rv1)
        pos_side = side.dot(rv2)
        clipped = clip(-side, neg_side, iv1, iv2)
        return nil if clipped.size < 2
        clipped = clip(side, pos_side, clipped[0], clipped[1])
        return nil if clipped.size < 2
        ref_c = ref_normal.dot(rv1)
        contacts = [] of Vec2
        pen = 0_f32
        clipped.each do |cp|
          sep = ref_normal.dot(cp) - ref_c
          if sep <= 0
            contacts << cp
            pen += -sep
          end
        end
        return nil if contacts.empty?
        pen /= contacts.size
        normal = flip ? -ref_normal : ref_normal
        Manifold.new(normal, pen, contacts)
      end

      private def axis_of_least_penetration(a : Polygon, b : Polygon) : {Float32, Int32}
        best = -Float32::INFINITY; face = 0
        a.points.size.times do |i|
          n = a.normals[i]
          s = b.support(-n)
          d = n.dot(s - a.points[i])
          if d > best
            best = d; face = i
          end
        end
        {best, face}
      end

      private def clip(n : Vec2, c : Float32, v1 : Vec2, v2 : Vec2) : Array(Vec2)
        out_pts = [] of Vec2
        d1 = n.dot(v1) - c
        d2 = n.dot(v2) - c
        out_pts << v1 if d1 <= 0
        out_pts << v2 if d2 <= 0
        if d1 * d2 < 0
          alpha = d1 / (d1 - d2)
          out_pts << v1 + (v2 - v1) * alpha
        end
        out_pts
      end

      # Ray tests: returns {distance, normal} or nil.
      def ray_circle(origin : Vec2, dir : Vec2, max : Float32, c : Circle) : {Float32, Vec2}?
        oc = origin - c.center
        b = oc.dot(dir)
        cc = oc.length_squared - c.radius * c.radius
        disc = b * b - cc
        return nil if disc < 0
        t = -b - Math.sqrt(disc).to_f32
        return nil if t < 0 || t > max
        p = origin + dir * t
        {t, (p - c.center).normalized}
      end

      def ray_polygon(origin : Vec2, dir : Vec2, max : Float32, p : Polygon) : {Float32, Vec2}?
        tmin = 0_f32; tmax = max
        normal = Vec2::ZERO
        p.points.size.times do |i|
          n = p.normals[i]
          denom = n.dot(dir)
          num = n.dot(p.points[i] - origin)
          if denom.abs < 1e-8
            return nil if num < 0
          else
            t = num / denom
            if denom < 0
              if t > tmin
                tmin = t; normal = n
              end
            else
              tmax = Math.min(tmax, t)
            end
            return nil if tmin > tmax
          end
        end
        return nil if tmin <= 0 && p.contains?(origin)
        {tmin, normal}
      end
    end
  end
end
