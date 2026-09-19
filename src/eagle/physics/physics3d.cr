module Eagle
  # 3D rigid-body physics in pure Crystal: spheres, oriented boxes, capsules and static
  # triangle meshes, stacking, friction, joints, sleeping, raycasts, overlap queries and
  # kinematic character movement.
  #
  # It mirrors `Physics2D`. Most games use the 3D physics nodes (`RigidBody3D`,
  # `StaticBody3D`, `KinematicBody3D`, `Area3D`, `RayCast3D`), which share `Physics3D.world`.
  # Units are meters and seconds, and gravity defaults to 9.81 m/s² downward.
  #
  # ```
  # world = Physics3D::World.new
  # world.add(Physics3D::BodyType::Static, v3(0, -0.5, 0), Physics3D::Cuboid.new(v3(20, 1, 20)))
  # ball = world.add(Physics3D::BodyType::Dynamic, v3(0, 5, 0), Physics3D::Sphere.new(0.5))
  # cap = world.add(Physics3D::BodyType::Dynamic, v3(1, 4, 0), Physics3D::Capsule.new(0.3, 1))
  # 120.times { world.step(1_f32 / 60) }
  # nearby = world.query_sphere(ball.position, 2)
  # ```
  module Physics3D
    # A 3D collision shape in a body's local space: a `Sphere`, `Cuboid`, `Capsule` or `MeshCollider`.
    abstract class Shape
      # Offset from the body's origin.
      property offset : Vec3 = Vec3::ZERO
      # Volume, used for mass.
      abstract def volume : Float32
      # Diagonal of the inertia tensor per unit mass.
      abstract def inertia_factor : Vec3
      # Bounds in the body's local space.
      abstract def local_aabb : AABB
    end

    # A sphere collision shape.
    class Sphere < Shape
      # Radius in meters.
      property radius : Float32
      # Creates a sphere.
      def initialize(radius : Number, offset : Vec3 = Vec3::ZERO)
        @radius = radius.to_f32; @offset = offset
      end
      # Volume.
      def volume : Float32; (4 / 3.0 * Math::PI * @radius ** 3).to_f32; end
      # Inertia per unit mass.
      def inertia_factor : Vec3; Vec3.new(0.4 * @radius * @radius); end
      # Bounds in local space.
      def local_aabb : AABB; AABB.from_center(@offset, Vec3.new(@radius)); end
    end

    # A box collision shape that rotates with its body.
    class Cuboid < Shape
      # Half the box's size along each axis.
      property half : Vec3
      # Creates a box of full *size*.
      def initialize(size : Vec3, offset : Vec3 = Vec3::ZERO)
        @half = size / 2; @offset = offset
      end
      # A cube with sides of *size*.
      def self.cube(size : Number) : Cuboid; new(Vec3.new(size)); end
      # Full size along each axis.
      def size : Vec3; @half * 2; end
      # Volume.
      def volume : Float32; @half.x * @half.y * @half.z * 8; end
      # Inertia per unit mass.
      def inertia_factor : Vec3
        s = size
        Vec3.new((s.y * s.y + s.z * s.z) / 12, (s.x * s.x + s.z * s.z) / 12, (s.x * s.x + s.y * s.y) / 12)
      end
      # Bounds in local space.
      def local_aabb : AABB; AABB.from_center(@offset, @half); end
    end

    # A capsule collision shape: a cylinder along local Y with hemispherical caps.
    # *height* is the cylinder length (distance between cap centres). Total length is
    # `height + 2 * radius`. Use it for characters and anything long and round; lock its
    # rotation to keep it upright.
    #
    # ```
    # world = Physics3D::World.new
    # player = world.add(Physics3D::BodyType::Dynamic, v3(0, 2, 0), Physics3D::Capsule.new(0.3, 1.0))
    # player.fixed_rotation = true
    # ```
    class Capsule < Shape
      # Hemisphere and cylinder radius in meters.
      property radius : Float32
      # Cylinder height in meters. The caps sit on each end.
      property height : Float32
      # Local-space cap centre at one end of the cylinder.
      property point_a : Vec3
      # Local-space cap centre at the other end.
      property point_b : Vec3

      # Creates a capsule along local Y. *height* is the cylinder between the caps.
      def initialize(radius : Number, height : Number, offset : Vec3 = Vec3::ZERO)
        @radius = radius.to_f32
        @height = height.to_f32
        @offset = offset
        hh = @height * 0.5_f32
        @point_a = Vec3.new(0, -hh, 0)
        @point_b = Vec3.new(0, hh, 0)
      end

      # Half the cylinder height: distance from the origin to a cap centre.
      def half_height : Float32; @height * 0.5_f32; end

      # A capsule whose cylinder runs along local Y from `-half_height` to `+half_height`.
      def self.with_half_height(radius : Number, half_height : Number, offset : Vec3 = Vec3::ZERO) : Capsule
        new(radius, half_height * 2, offset)
      end

      # A capsule from two endpoints. The midpoint becomes `offset`, so a body at the origin
      # with identity rotation lines up with *start* and *finish*.
      def self.from_segment(start : Vec3, finish : Vec3, radius : Number) : Capsule
        mid = (start + finish) / 2
        cap = new(radius, (finish - start).length, mid)
        cap.point_a = start - mid
        cap.point_b = finish - mid
        cap
      end

      # Volume of the cylinder plus a full sphere.
      def volume : Float32
        r2 = @radius * @radius
        (Math::PI * r2 * @height + 4 / 3.0 * Math::PI * r2 * @radius).to_f32
      end
      # Inertia per unit mass. Y is the long axis for an upright capsule.
      def inertia_factor : Vec3
        r = @radius; h = @height
        v_cyl = Math::PI * r * r * h
        v_sph = 4 / 3.0 * Math::PI * r * r * r
        v = v_cyl + v_sph
        return Vec3.new(0.4 * r * r) if v <= 0
        mc = (v_cyl / v).to_f32
        ms = (v_sph / v).to_f32
        iy = mc * 0.5_f32 * r * r + ms * 0.4_f32 * r * r
        ix = mc * (h * h / 12 + r * r / 4) + ms * (0.4_f32 * r * r + (h * 0.5_f32) ** 2)
        Vec3.new(ix.to_f32, iy, ix.to_f32)
      end
      # Bounds in local space, including the caps.
      def local_aabb : AABB
        r = Vec3.new(@radius)
        AABB.from_center(@offset + @point_a, r).union(AABB.from_center(@offset + @point_b, r))
      end
    end

    # A static triangle-mesh collider. Build it from an `Eagle::Mesh` or an array of
    # triangles. It is a surface, not a volume, so use it on `StaticBody3D` (floors,
    # terrain, imported level geometry). Dynamic bodies should keep using spheres,
    # boxes and capsules; a deforming mesh is not supported.
    #
    # ```
    # world = Physics3D::World.new
    # hill = Physics3D::MeshCollider.from_mesh(Mesh.cone(2, 3, 8))
    # world.add(Physics3D::BodyType::Static, v3(0, 0, 0), hill)
    # ```
    class MeshCollider < Shape
      # Triangle vertices in shape-local space.
      getter triangles : Array({Vec3, Vec3, Vec3})
      # :nodoc:
      getter triangle_aabbs : Array(AABB)
      @cached_aabb : AABB

      # Creates a collider from already-local triangles.
      @cell : Float32 = 1_f32
      @grid = {} of {Int32, Int32, Int32} => Array(Int32)

      def initialize(@triangles : Array({Vec3, Vec3, Vec3}), offset : Vec3 = Vec3::ZERO)
        @offset = offset
        @triangle_aabbs = @triangles.map { |t| AABB.from_points([t[0], t[1], t[2]]) }
        @cached_aabb = @triangle_aabbs.empty? ? AABB.new(Vec3::ZERO, Vec3::ZERO) : @triangle_aabbs.reduce { |a, b| a.union(b) }
        build_grid
      end

      # Builds a collider from a render `Mesh`'s triangles.
      def self.from_mesh(mesh : Mesh, offset : Vec3 = Vec3::ZERO) : MeshCollider
        from_triangles(mesh.positions, mesh.indices.map(&.to_i), offset)
      end

      # Builds a collider from vertices. Pass *indices* (three per triangle) or omit it
      # and the vertices are read in groups of three.
      def self.from_triangles(vertices : Array(Vec3), indices : Array(Int32) = [] of Int32, offset : Vec3 = Vec3::ZERO) : MeshCollider
        tris = [] of {Vec3, Vec3, Vec3}
        if indices.empty?
          (0...vertices.size).step(3) do |i|
            break if i + 2 >= vertices.size
            tris << {vertices[i], vertices[i + 1], vertices[i + 2]}
          end
        else
          (0...indices.size).step(3) do |i|
            break if i + 2 >= indices.size
            tris << {vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]}
          end
        end
        new(tris, offset)
      end

      # A surface has no volume; dynamic bodies with only a mesh get a fallback mass.
      def volume : Float32; 0_f32; end
      # A surface has no inertia of its own.
      def inertia_factor : Vec3; Vec3::ZERO; end
      # Bounds of every triangle, in local space.
      def local_aabb : AABB; @cached_aabb; end

      # :nodoc:
      def each_candidate(box : AABB, & : Int32 ->)
        if @grid.empty?
          @triangles.each_index { |i| yield i }
          return
        end
        seen = Set(Int32).new
        x0 = (box.min.x / @cell).floor.to_i; x1 = (box.max.x / @cell).floor.to_i
        y0 = (box.min.y / @cell).floor.to_i; y1 = (box.max.y / @cell).floor.to_i
        z0 = (box.min.z / @cell).floor.to_i; z1 = (box.max.z / @cell).floor.to_i
        (x0..x1).each do |x|
          (y0..y1).each do |y|
            (z0..z1).each do |z|
              @grid[{x, y, z}]?.try &.each do |i|
                next if seen.includes?(i)
                seen << i
                yield i
              end
            end
          end
        end
      end

      private def build_grid
        @grid.clear
        return if @triangle_aabbs.empty?
        avg = @triangle_aabbs.sum { |b| Math.max(b.size.x, Math.max(b.size.y, b.size.z)) } / @triangle_aabbs.size
        @cell = Math.max(0.25_f32, avg)
        @triangle_aabbs.each_with_index do |box, i|
          x0 = (box.min.x / @cell).floor.to_i; x1 = (box.max.x / @cell).floor.to_i
          y0 = (box.min.y / @cell).floor.to_i; y1 = (box.max.y / @cell).floor.to_i
          z0 = (box.min.z / @cell).floor.to_i; z1 = (box.max.z / @cell).floor.to_i
          (x0..x1).each { |x| (y0..y1).each { |y| (z0..z1).each { |z| (@grid[{x, y, z}] ||= [] of Int32) << i } } }
        end
      end
    end

    # :nodoc:
    struct WorldShape
      getter shape : Shape
      getter center : Vec3
      getter rotation : Quat
      getter axes : {Vec3, Vec3, Vec3}
      # :nodoc:
      def initialize(@shape, @center, @rotation)
        @axes = {@rotation * Vec3::RIGHT, @rotation * Vec3::UP, @rotation * Vec3::BACK}
      end

      def aabb : AABB
        case (s = @shape)
        when Sphere then AABB.from_center(@center, Vec3.new(s.radius))
        when Cuboid
          ext = Vec3.new(
            (@axes[0].x * s.half.x).abs + (@axes[1].x * s.half.y).abs + (@axes[2].x * s.half.z).abs,
            (@axes[0].y * s.half.x).abs + (@axes[1].y * s.half.y).abs + (@axes[2].y * s.half.z).abs,
            (@axes[0].z * s.half.x).abs + (@axes[1].z * s.half.y).abs + (@axes[2].z * s.half.z).abs)
          AABB.from_center(@center, ext)
        when Capsule
          a, b = capsule_ends
          r = Vec3.new(s.radius)
          AABB.from_center(a, r).union(AABB.from_center(b, r))
        when MeshCollider
          s.local_aabb.transformed(Mat4.trs(@center, @rotation, Vec3::ONE))
        else AABB.new(@center, @center)
        end
      end

      def capsule_ends : {Vec3, Vec3}
        s = @shape.as(Capsule)
        {@center + @rotation * s.point_a, @center + @rotation * s.point_b}
      end

      # Closest point on the shape surface/volume to p.
      def closest_point(p : Vec3) : Vec3
        case (s = @shape)
        when Sphere
          d = p - @center
          l = d.length
          l <= s.radius ? p : @center + d / l * s.radius
        when Cuboid
          d = p - @center
          q = @center
          3.times do |i|
            ax = @axes[i]
            h = i == 0 ? s.half.x : (i == 1 ? s.half.y : s.half.z)
            dist = d.dot(ax).clamp(-h, h)
            q += ax * dist
          end
          q
        when Capsule
          a, b = capsule_ends
          q = Collision.closest_on_segment(p, a, b)
          d = p - q
          l = d.length
          l <= s.radius ? p : q + d / l * s.radius
        when MeshCollider
          best = @center
          best_d = Float32::INFINITY
          s.triangles.each do |tri|
            wa = @center + @rotation * tri[0]
            wb = @center + @rotation * tri[1]
            wc = @center + @rotation * tri[2]
            q = Collision.closest_on_triangle(p, wa, wb, wc)
            d2 = p.distance_squared(q)
            if d2 < best_d
              best_d = d2; best = q
            end
          end
          best
        else @center
        end
      end

      def contains?(p : Vec3) : Bool
        case (s = @shape)
        when Sphere then p.distance_squared(@center) <= s.radius * s.radius
        when Cuboid
          d = p - @center
          d.dot(@axes[0]).abs <= s.half.x && d.dot(@axes[1]).abs <= s.half.y && d.dot(@axes[2]).abs <= s.half.z
        when Capsule
          a, b = capsule_ends
          p.distance_squared(Collision.closest_on_segment(p, a, b)) <= s.radius * s.radius
        when MeshCollider
          closest_point(p).distance_squared(p) <= 1e-6
        else false
        end
      end

      def cuboid_vertices : Array(Vec3)
        s = @shape.as(Cuboid)
        out_v = [] of Vec3
        [-1, 1].each do |sx|
          [-1, 1].each do |sy|
            [-1, 1].each do |sz|
              out_v << @center + @axes[0] * (s.half.x * sx) + @axes[1] * (s.half.y * sy) + @axes[2] * (s.half.z * sz)
            end
          end
        end
        out_v
      end

      def support(d : Vec3) : Vec3
        case (s = @shape)
        when Sphere then @center + d.normalized * s.radius
        when Cuboid
          @center + @axes[0] * (s.half.x * Mathf.sign(d.dot(@axes[0]))) + @axes[1] * (s.half.y * Mathf.sign(d.dot(@axes[1]))) + @axes[2] * (s.half.z * Mathf.sign(d.dot(@axes[2])))
        when Capsule
          a, b = capsule_ends
          n = d.normalized
          ((a.dot(n) > b.dot(n) ? a : b) + n * s.radius)
        else @center
        end
      end
    end

    # The result of a collision test: separation normal, depth and contact points.
    struct Manifold
      # Unit normal pointing from A to B.
      getter normal : Vec3 # from A to B
      # Overlap depth.
      getter penetration : Float32
      # Contact points in world space.
      getter contacts : Array(Vec3)
      # Creates a manifold.
      def initialize(@normal, @penetration, @contacts); end
    end

    # Where a ray hit: point, normal, distance and body.
    struct RayHit
      # Where the ray hit, in world space.
      getter point : Vec3
      # Surface normal at the hit.
      getter normal : Vec3
      # Distance from the ray's origin to the hit.
      getter distance : Float32
      # The body that was hit.
      getter body : Body
      def initialize(@point, @normal, @distance, @body); end
    end

    # :nodoc:
    module Collision
      extend self

      def test(a : WorldShape, b : WorldShape) : Manifold?
        case {a.shape, b.shape}
        when {Sphere, Sphere} then sphere_sphere(a, b)
        when {Sphere, Cuboid} then sphere_box(a, b)
        when {Cuboid, Sphere} then flip(sphere_box(b, a))
        when {Cuboid, Cuboid} then box_box(a, b)
        when {Sphere, Capsule} then flip(capsule_sphere(b, a))
        when {Capsule, Sphere} then capsule_sphere(a, b)
        when {Capsule, Capsule} then capsule_capsule(a, b)
        when {Capsule, Cuboid} then capsule_box(a, b)
        when {Cuboid, Capsule} then flip(capsule_box(b, a))
        when {MeshCollider, Sphere}, {MeshCollider, Cuboid}, {MeshCollider, Capsule}
          mesh_primitive(a, b)
        when {Sphere, MeshCollider}, {Cuboid, MeshCollider}, {Capsule, MeshCollider}
          flip(mesh_primitive(b, a))
        else nil
        end
      end

      def flip(m : Manifold?) : Manifold?
        m ? Manifold.new(-m.normal, m.penetration, m.contacts) : nil
      end

      def sphere_sphere(a, b) : Manifold?
        ra = a.shape.as(Sphere).radius; rb = b.shape.as(Sphere).radius
        d = b.center - a.center
        dist2 = d.length_squared
        r = ra + rb
        return nil if dist2 >= r * r
        dist = Math.sqrt(dist2).to_f32
        n = dist > 1e-6 ? d / dist : Vec3::UP
        Manifold.new(n, r - dist, [a.center + n * ra])
      end

      def sphere_box(s, b) : Manifold?
        r = s.shape.as(Sphere).radius
        q = b.closest_point(s.center)
        d = q - s.center
        dist2 = d.length_squared
        if dist2 > 1e-10
          return nil if dist2 >= r * r
          dist = Math.sqrt(dist2).to_f32
          n = d / dist
          Manifold.new(n, r - dist, [q])
        else
          # centre inside the box: push out along the axis of least penetration
          bx = b.shape.as(Cuboid)
          rel = s.center - b.center
          best = Float32::INFINITY; n = Vec3::UP
          3.times do |i|
            h = i == 0 ? bx.half.x : (i == 1 ? bx.half.y : bx.half.z)
            proj = rel.dot(b.axes[i])
            pen = h - proj.abs
            if pen < best
              best = pen; n = b.axes[i] * -Mathf.sign(proj)
              n = -b.axes[i] if proj == 0
            end
          end
          Manifold.new(n, best + r, [s.center])
        end
      end

      def capsule_sphere(cap : WorldShape, sph : WorldShape) : Manifold?
        ra = cap.shape.as(Capsule).radius
        rb = sph.shape.as(Sphere).radius
        a, b = cap.capsule_ends
        q = closest_on_segment(sph.center, a, b)
        d = sph.center - q
        dist2 = d.length_squared
        r = ra + rb
        return nil if dist2 >= r * r
        dist = Math.sqrt(dist2).to_f32
        n = dist > 1e-6 ? d / dist : cap.axes[1]
        Manifold.new(n, r - dist, [q + n * ra])
      end

      def capsule_capsule(a : WorldShape, b : WorldShape) : Manifold?
        ra = a.shape.as(Capsule).radius; rb = b.shape.as(Capsule).radius
        a0, a1 = a.capsule_ends
        b0, b1 = b.capsule_ends
        pa, pb = closest_points_on_segments(a0, a1, b0, b1)
        d = pb - pa
        dist2 = d.length_squared
        r = ra + rb
        return nil if dist2 >= r * r
        dist = Math.sqrt(dist2).to_f32
        n = if dist > 1e-6
              d / dist
            else
              t = a.axes[1].cross(b.axes[1])
              t.length_squared > 1e-8 ? t.normalized : Vec3::RIGHT
            end
        Manifold.new(n, r - dist, [pa + n * ra])
      end

      def capsule_box(cap : WorldShape, box : WorldShape) : Manifold?
        r = cap.shape.as(Capsule).radius
        bx = box.shape.as(Cuboid)
        inv = box.rotation.inverse
        a0, a1 = cap.capsule_ends
        la = inv * (a0 - box.center)
        lb = inv * (a1 - box.center)
        ps, pb, interior = closest_segment_aabb(la, lb, bx.half)
        if interior
          best = Float32::INFINITY; nloc = Vec3::UP
          3.times do |i|
            h = i == 0 ? bx.half.x : (i == 1 ? bx.half.y : bx.half.z)
            proj = i == 0 ? ps.x : (i == 1 ? ps.y : ps.z)
            pen = h - proj.abs
            if pen < best
              best = pen
              ax = i == 0 ? Vec3::RIGHT : (i == 1 ? Vec3::UP : Vec3::BACK)
              nloc = ax * -Mathf.sign(proj)
              nloc = -ax if proj == 0
            end
          end
          n = box.rotation * nloc
          Manifold.new(n, best + r, [box.center + box.rotation * ps])
        else
          d = pb - ps
          dist2 = d.length_squared
          return nil if dist2 >= r * r
          dist = Math.sqrt(dist2).to_f32
          nloc = dist > 1e-6 ? d / dist : Vec3::UP
          n = box.rotation * nloc
          Manifold.new(n, r - dist, [box.center + box.rotation * pb])
        end
      end

      def mesh_primitive(mesh_ws : WorldShape, other : WorldShape) : Manifold?
        mesh = mesh_ws.shape.as(MeshCollider)
        inv = mesh_ws.rotation.inverse
        local_other = WorldShape.new(other.shape, inv * (other.center - mesh_ws.center), (inv * other.rotation).normalized)
        best : Manifold? = nil
        mesh.each_candidate(local_other.aabb) do |i|
          next unless mesh.triangle_aabbs[i].intersects?(local_other.aabb)
          if m = triangle_shape(mesh.triangles[i], local_other)
            best = m if best.nil? || m.penetration > best.penetration
          end
        end
        return nil unless best
        n = mesh_ws.rotation * best.normal
        contacts = best.contacts.map { |c| mesh_ws.center + mesh_ws.rotation * c }
        Manifold.new(n, best.penetration, contacts)
      end

      def triangle_shape(tri : {Vec3, Vec3, Vec3}, other : WorldShape) : Manifold?
        case (s = other.shape)
        when Sphere then triangle_sphere(tri, other.center, s.radius)
        when Capsule
          a, b = other.capsule_ends
          triangle_capsule(tri, a, b, s.radius)
        when Cuboid then triangle_box(tri, other)
        else nil
        end
      end

      def triangle_sphere(tri : {Vec3, Vec3, Vec3}, center : Vec3, radius : Float32) : Manifold?
        q = closest_on_triangle(center, tri[0], tri[1], tri[2])
        d = center - q
        dist2 = d.length_squared
        return nil if dist2 >= radius * radius
        dist = Math.sqrt(dist2).to_f32
        n = if dist > 1e-6
              d / dist
            else
              tn = (tri[1] - tri[0]).cross(tri[2] - tri[0])
              tn.length_squared > 1e-12 ? tn.normalized : Vec3::UP
            end
        Manifold.new(n, radius - dist, [q])
      end

      def triangle_capsule(tri : {Vec3, Vec3, Vec3}, a : Vec3, b : Vec3, radius : Float32) : Manifold?
        ps, pt = closest_segment_triangle(a, b, tri[0], tri[1], tri[2])
        d = pt - ps
        dist2 = d.length_squared
        return nil if dist2 >= radius * radius
        dist = Math.sqrt(dist2).to_f32
        n = if dist > 1e-6
              -d / dist
            else
              tn = (tri[1] - tri[0]).cross(tri[2] - tri[0])
              tn.length_squared > 1e-12 ? tn.normalized : Vec3::UP
            end
        # n from triangle (A/mesh) to capsule: if d = pt-ps is from capsule to tri, n = -d
        Manifold.new(n, radius - dist, [pt])
      end

      def triangle_box(tri : {Vec3, Vec3, Vec3}, box : WorldShape) : Manifold?
        bx = box.shape.as(Cuboid)
        inv = box.rotation.inverse
        ta = inv * (tri[0] - box.center)
        tb = inv * (tri[1] - box.center)
        tc = inv * (tri[2] - box.center)
        half = bx.half
        tn = (tb - ta).cross(tc - ta)
        return nil if tn.length_squared < 1e-16
        axes = [] of Vec3
        axes << tn.normalized
        axes << Vec3::RIGHT << Vec3::UP << Vec3::BACK
        {tb - ta, tc - tb, ta - tc}.each do |edge|
          {Vec3::RIGHT, Vec3::UP, Vec3::BACK}.each do |ba|
            cr = edge.cross(ba)
            axes << cr.normalized if cr.length_squared > 1e-8
          end
        end
        verts = {ta, tb, tc}
        best_pen = Float32::INFINITY
        best_ax = axes[0]
        axes.each do |ax|
          tmin = verts[0].dot(ax); tmax = tmin
          1.upto(2) do |i|
            p = verts[i].dot(ax)
            tmin = p if p < tmin
            tmax = p if p > tmax
          end
          r = half.x * ax.x.abs + half.y * ax.y.abs + half.z * ax.z.abs
          return nil if tmax < -r || tmin > r
          # push distance to clear the triangle along +ax or -ax (a flat triangle has zero interval overlap)
          push_pos = tmax + r
          push_neg = r - tmin
          pen = Math.min(push_pos, push_neg)
          if pen < best_pen
            best_pen = pen
            best_ax = push_pos <= push_neg ? ax : -ax
          end
        end
        nloc = best_ax
        q_tri = closest_on_triangle(Vec3::ZERO, ta, tb, tc)
        q_box = clamp_aabb(q_tri, half)
        contact = (q_tri + q_box) / 2
        Manifold.new(box.rotation * nloc, best_pen, [box.center + box.rotation * contact])
      end

      # SAT over 15 axes; contacts from the incident box's vertices behind the reference face.
      def box_box(a, b) : Manifold?
        ba = a.shape.as(Cuboid); bb = b.shape.as(Cuboid)
        axes = [] of Vec3
        3.times { |i| axes << a.axes[i] }
        3.times { |i| axes << b.axes[i] }
        3.times do |i|
          3.times do |j|
            c = a.axes[i].cross(b.axes[j])
            axes << c.normalized if c.length_squared > 1e-8
          end
        end
        d = b.center - a.center
        best_pen = Float32::INFINITY; best_axis = Vec3::UP; best_index = 0
        axes.each_with_index do |ax, idx|
          ra = ba.half.x * a.axes[0].dot(ax).abs + ba.half.y * a.axes[1].dot(ax).abs + ba.half.z * a.axes[2].dot(ax).abs
          rb = bb.half.x * b.axes[0].dot(ax).abs + bb.half.y * b.axes[1].dot(ax).abs + bb.half.z * b.axes[2].dot(ax).abs
          dist = d.dot(ax).abs
          pen = ra + rb - dist
          return nil if pen <= 0
          # prefer face axes slightly (more stable contacts)
          weighted = idx < 6 ? pen : pen * 1.05_f32
          if weighted < best_pen
            best_pen = weighted; best_axis = ax; best_index = idx
          end
        end
        n = best_axis
        n = -n if d.dot(n) < 0 # from A to B
        pen = best_pen / (best_index < 6 ? 1 : 1.05_f32)
        if best_index < 6
          ref_is_a = best_index < 3
          ref = ref_is_a ? a : b
          inc = ref_is_a ? b : a
          # reference face plane: the face of `ref` facing towards `inc`
          face_n = ref_is_a ? n : -n # outward from ref
          ref_half = ref.shape.as(Cuboid).half
          face_center = ref.center + face_n * (ref_half.x * face_n.dot(ref.axes[0]).abs + ref_half.y * face_n.dot(ref.axes[1]).abs + ref_half.z * face_n.dot(ref.axes[2]).abs)
          contacts = [] of Vec3
          deepest = nil.as(Vec3?); deepest_d = Float32::INFINITY
          inc.cuboid_vertices.each do |v|
            depth = (v - face_center).dot(face_n)
            if depth < deepest_d
              deepest_d = depth; deepest = v
            end
            next if depth > 0.001
            # inside the (slightly grown) face rectangle?
            rel = v - ref.center
            inside = true
            3.times do |i|
              next if face_n.dot(ref.axes[i]).abs > 0.9
              h = i == 0 ? ref_half.x : (i == 1 ? ref_half.y : ref_half.z)
              inside = false if rel.dot(ref.axes[i]).abs > h + 0.02
            end
            contacts << v - face_n * depth if inside # project onto the face
          end
          contacts = [deepest.not_nil!] if contacts.empty?
          contacts = contacts.first(4)
          Manifold.new(n, pen, contacts)
        else
          # edge-edge: closest points between the two support edges along n
          pa = a.support(n); pb = b.support(-n)
          ea = edge_dir(a, best_index)
          eb = edge_dir_b(b, best_index)
          p1, p2 = closest_points_on_lines(pa, ea, pb, eb)
          Manifold.new(n, pen, [(p1 + p2) / 2])
        end
      end

      private def edge_dir(a, idx) : Vec3
        i = (idx - 6) // 3
        a.axes[i]
      end

      private def edge_dir_b(b, idx) : Vec3
        j = (idx - 6) % 3
        b.axes[j]
      end

      private def closest_points_on_lines(p1 : Vec3, d1 : Vec3, p2 : Vec3, d2 : Vec3) : {Vec3, Vec3}
        r = p1 - p2
        a = d1.dot(d1); e = d2.dot(d2); b = d1.dot(d2)
        c = d1.dot(r); f = d2.dot(r)
        denom = a * e - b * b
        s = denom.abs > 1e-8 ? (b * f - c * e) / denom : 0_f32
        t = (b * s + f) / e
        {p1 + d1 * s, p2 + d2 * t}
      end

      def closest_on_segment(p : Vec3, a : Vec3, b : Vec3) : Vec3
        ab = b - a
        t = ab.length_squared > 1e-12 ? ((p - a).dot(ab) / ab.length_squared).clamp(0_f32, 1_f32) : 0_f32
        a + ab * t
      end

      def closest_points_on_segments(p1 : Vec3, q1 : Vec3, p2 : Vec3, q2 : Vec3) : {Vec3, Vec3}
        d1 = q1 - p1; d2 = q2 - p2; r = p1 - p2
        a = d1.dot(d1); e = d2.dot(d2); f = d2.dot(r)
        if a < 1e-12 && e < 1e-12
          return {p1, p2}
        end
        s = 0_f32; t = 0_f32
        if a < 1e-12
          t = (f / e).clamp(0_f32, 1_f32)
        else
          c = d1.dot(r)
          if e < 1e-12
            s = (-c / a).clamp(0_f32, 1_f32)
          else
            b = d1.dot(d2)
            denom = a * e - b * b
            s = denom.abs > 1e-8 ? ((b * f - c * e) / denom).clamp(0_f32, 1_f32) : 0_f32
            t = (b * s + f) / e
            if t < 0
              t = 0_f32
              s = (-c / a).clamp(0_f32, 1_f32)
            elsif t > 1
              t = 1_f32
              s = ((b - c) / a).clamp(0_f32, 1_f32)
            end
          end
        end
        {p1 + d1 * s, p2 + d2 * t}
      end

      def closest_on_triangle(p : Vec3, a : Vec3, b : Vec3, c : Vec3) : Vec3
        ab = b - a; ac = c - a; ap = p - a
        d1 = ab.dot(ap); d2 = ac.dot(ap)
        return a if d1 <= 0 && d2 <= 0
        bp = p - b
        d3 = ab.dot(bp); d4 = ac.dot(bp)
        return b if d3 >= 0 && d4 <= d3
        vc = d1 * d4 - d3 * d2
        return a + ab * (d1 / (d1 - d3)) if vc <= 0 && d1 >= 0 && d3 <= 0
        cp = p - c
        d5 = ab.dot(cp); d6 = ac.dot(cp)
        return c if d6 >= 0 && d5 <= d6
        vb = d5 * d2 - d1 * d6
        return a + ac * (d2 / (d2 - d6)) if vb <= 0 && d2 >= 0 && d6 <= 0
        va = d3 * d6 - d5 * d4
        return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0
        denom = 1 / (va + vb + vc)
        a + ab * (vb * denom) + ac * (vc * denom)
      end

      def closest_segment_triangle(p : Vec3, q : Vec3, a : Vec3, b : Vec3, c : Vec3) : {Vec3, Vec3}
        if hit = segment_triangle(p, q, a, b, c)
          return {hit, hit}
        end
        best_a = p
        best_b = closest_on_triangle(p, a, b, c)
        best_d = best_a.distance_squared(best_b)
        q_tri = closest_on_triangle(q, a, b, c)
        d2 = q.distance_squared(q_tri)
        if d2 < best_d
          best_d = d2; best_a = q; best_b = q_tri
        end
        [{a, b}, {b, c}, {c, a}].each do |e0, e1|
          sa, sb = closest_points_on_segments(p, q, e0, e1)
          d2 = sa.distance_squared(sb)
          if d2 < best_d
            best_d = d2; best_a = sa; best_b = sb
          end
        end
        {best_a, best_b}
      end

      def segment_triangle(p : Vec3, q : Vec3, a : Vec3, b : Vec3, c : Vec3) : Vec3?
        dir = q - p
        e1 = b - a; e2 = c - a
        pv = dir.cross(e2)
        det = e1.dot(pv)
        return nil if det.abs < 1e-8
        inv = 1 / det
        tvec = p - a
        u = tvec.dot(pv) * inv
        return nil if u < 0 || u > 1
        qv = tvec.cross(e1)
        v = dir.dot(qv) * inv
        return nil if v < 0 || u + v > 1
        t = e2.dot(qv) * inv
        return nil if t < 0 || t > 1
        p + dir * t
      end

      def closest_segment_aabb(p0 : Vec3, p1 : Vec3, half : Vec3) : {Vec3, Vec3, Bool}
        d = p1 - p0
        tmin = 0_f32
        tmax = 1_f32
        hit = true
        {% for axis in %w(x y z) %}
          if hit
            if d.{{axis.id}}.abs < 1e-8
              hit = false if p0.{{axis.id}} < -half.{{axis.id}} || p0.{{axis.id}} > half.{{axis.id}}
            else
              invd = 1_f32 / d.{{axis.id}}
              t1 = (-half.{{axis.id}} - p0.{{axis.id}}) * invd
              t2 = (half.{{axis.id}} - p0.{{axis.id}}) * invd
              t1, t2 = t2, t1 if t1 > t2
              tmin = Math.max(tmin, t1)
              tmax = Math.min(tmax, t2)
              hit = false if tmin > tmax
            end
          end
        {% end %}
        if hit && tmin <= tmax
          t = ((tmin + Math.min(tmax, 1_f32)) * 0.5_f32).clamp(0_f32, 1_f32)
          p = p0 + d * t
          return {p, p, true}
        end
        len2 = d.length_squared
        t = 0.5_f32
        ps = p0
        pb = clamp_aabb(p0, half)
        8.times do
          ps = p0 + d * t
          pb = clamp_aabb(ps, half)
          t = len2 > 1e-12 ? ((pb - p0).dot(d) / len2).clamp(0_f32, 1_f32) : 0_f32
        end
        ps = p0 + d * t
        pb = clamp_aabb(ps, half)
        best_d = ps.distance_squared(pb)
        q0 = clamp_aabb(p0, half)
        d0 = p0.distance_squared(q0)
        if d0 < best_d
          best_d = d0; ps = p0; pb = q0
        end
        q1 = clamp_aabb(p1, half)
        if p1.distance_squared(q1) < best_d
          ps = p1; pb = q1
        end
        {ps, pb, false}
      end

      def clamp_aabb(p : Vec3, half : Vec3) : Vec3
        Vec3.new(p.x.clamp(-half.x, half.x), p.y.clamp(-half.y, half.y), p.z.clamp(-half.z, half.z))
      end

      def ray(origin : Vec3, dir : Vec3, max : Float32, ws : WorldShape) : {Float32, Vec3}?
        case (s = ws.shape)
        when Sphere
          t = Ray.new(origin, dir).intersect_sphere(ws.center, s.radius)
          return nil unless t && t <= max
          {t, (origin + dir * t - ws.center).normalized}
        when Cuboid
          inv = ws.rotation.inverse
          lo = inv * (origin - ws.center)
          ld = inv * dir
          t = Ray.new(lo, ld).intersect_aabb(AABB.new(-s.half, s.half))
          return nil unless t && t <= max
          hit = lo + ld.normalized * t
          nx = hit.x / s.half.x; ny = hit.y / s.half.y; nz = hit.z / s.half.z
          ln = if nx.abs >= ny.abs && nx.abs >= nz.abs
                 Vec3.new(Mathf.sign(nx), 0, 0)
               elsif ny.abs >= nz.abs
                 Vec3.new(0, Mathf.sign(ny), 0)
               else
                 Vec3.new(0, 0, Mathf.sign(nz))
               end
          {t, ws.rotation * ln}
        when Capsule then ray_capsule(origin, dir, max, ws)
        when MeshCollider then ray_mesh(origin, dir, max, ws)
        else nil
        end
      end

      def ray_capsule(origin : Vec3, dir : Vec3, max : Float32, ws : WorldShape) : {Float32, Vec3}?
        cap = ws.shape.as(Capsule)
        a, b = ws.capsule_ends
        r = cap.radius
        best : {Float32, Vec3}? = nil
        {a, b}.each do |c|
          t = Ray.new(origin, dir).intersect_sphere(c, r)
          next unless t && t <= max
          nrm = (origin + dir * t - c)
          nrm = nrm.length_squared > 1e-12 ? nrm.normalized : Vec3::UP
          best = {t, nrm} if best.nil? || t < best[0]
        end
        ba = b - a
        m = origin - a
        nn = ba.dot(ba)
        nd = ba.dot(dir)
        md = m.dot(dir)
        mn = m.dot(ba)
        mm = m.dot(m)
        aq = nn - nd * nd
        cq = nn * (mm - r * r) - mn * mn
        bq = nn * md - nd * mn
        if aq.abs > 1e-8
          disc = bq * bq - aq * cq
          if disc >= 0
            sq = Math.sqrt(disc).to_f32
            {(-bq - sq) / aq, (-bq + sq) / aq}.each do |t|
              next unless t >= 0 && t <= max
              s = (mn + t * nd) / nn
              next unless s >= 0 && s <= 1
              axis_p = a + ba * s
              nrm = origin + dir * t - axis_p
              nrm = nrm.length_squared > 1e-12 ? nrm.normalized : Vec3::UP
              best = {t, nrm} if best.nil? || t < best[0]
            end
          end
        end
        best
      end

      def ray_mesh(origin : Vec3, dir : Vec3, max : Float32, ws : WorldShape) : {Float32, Vec3}?
        mesh = ws.shape.as(MeshCollider)
        inv = ws.rotation.inverse
        lo = inv * (origin - ws.center)
        ld = inv * dir
        end_p = lo + ld * max
        ray_box = AABB.from_points([lo, end_p])
        best_t : Float32? = nil
        best_n = Vec3::UP
        mesh.each_candidate(ray_box) do |i|
          next unless mesh.triangle_aabbs[i].intersects?(ray_box)
          tri = mesh.triangles[i]
          if hit = ray_triangle(lo, ld, max, tri[0], tri[1], tri[2])
            t, n = hit
            if best_t.nil? || t < best_t
              best_t = t; best_n = n
            end
          end
        end
        best_t ? {best_t, ws.rotation * best_n} : nil
      end

      def ray_triangle(origin : Vec3, dir : Vec3, max : Float32, a : Vec3, b : Vec3, c : Vec3) : {Float32, Vec3}?
        e1 = b - a; e2 = c - a
        pvec = dir.cross(e2)
        det = e1.dot(pvec)
        return nil if det.abs < 1e-8
        inv = 1 / det
        tvec = origin - a
        u = tvec.dot(pvec) * inv
        return nil if u < 0 || u > 1
        qvec = tvec.cross(e1)
        v = dir.dot(qvec) * inv
        return nil if v < 0 || u + v > 1
        t = e2.dot(qvec) * inv
        return nil if t < 0 || t > max
        n = e1.cross(e2)
        return nil if n.length_squared < 1e-16
        n = n.normalized
        n = -n if n.dot(dir) > 0
        {t, n}
      end
    end

    # How a body moves: `Static`, `Kinematic` (moved by code) or `Dynamic` (moved by the simulation).
    enum BodyType
      # Never moves.
      Static
      # Moved by your code.
      Kinematic
      # Moved by the simulation.
      Dynamic
    end

    # A 3D physics body: position, rotation, velocities, mass and shapes. Physics nodes create
    # them for you.
    class Body
      # Static, kinematic or dynamic.
      property type : BodyType
      # World-space position.
      property position : Vec3
      # Orientation.
      property rotation : Quat = Quat::IDENTITY
      # Linear velocity in meters per second.
      property velocity : Vec3 = Vec3::ZERO
      # Spin axis scaled by radians per second.
      property angular_velocity : Vec3 = Vec3::ZERO
      # Force accumulated for the next step.
      property force : Vec3 = Vec3::ZERO
      # Torque accumulated for the next step.
      property torque : Vec3 = Vec3::ZERO
      # Bounciness from 0 to 1.
      property restitution : Float32 = 0_f32
      # Surface grip.
      property friction : Float32 = 0.5_f32
      # Multiplies gravity for this body.
      property gravity_scale : Float32 = 1_f32
      # Drag on linear velocity.
      property linear_damping : Float32 = 0.05_f32
      # Drag on spin.
      property angular_damping : Float32 = 0.05_f32
      # Prevents rotation.
      property? fixed_rotation = false
      # Sensors report overlaps but don't collide.
      property? sensor = false
      # Layer bits. See `Physics2D::Body#layer` for how layers and masks combine.
      property layer : UInt32 = 1_u32
      # Mask bits.
      property mask : UInt32 = 0xFFFFFFFF_u32
      # Disabled bodies are skipped.
      property? enabled = true
      # The node that owns this body, if any.
      property owner : Node? = nil
      # Mass per unit volume.
      property density : Float32 = 1_f32
      # Shapes in local space.
      getter shapes = [] of Shape
      # Mass.
      getter mass : Float32 = 1_f32
      # 1 / mass, or 0 for non-dynamic bodies.
      getter inv_mass : Float32 = 1_f32
      # Inverse inertia in body space.
      getter inv_inertia_local : Vec3 = Vec3::ONE
      # :nodoc:
      getter world_shapes = [] of WorldShape
      # World-space bounds.
      getter aabb : AABB = AABB.new(Vec3::ZERO, Vec3::ZERO)
      # Bodies touching this one after the last step.
      getter contacts = Set(Body).new
      # True when the body is at rest and skipped by the solver. Call `wake` after you move it.
      getter? sleeping = false
      # :nodoc:
      property sleep_timer : Float32 = 0_f32
      # A unique id.
      getter id : Int32
      @@next_id = 0

      # Creates a body, optionally with a first shape.
      def initialize(@type : BodyType = BodyType::Dynamic, @position : Vec3 = Vec3::ZERO, shape : Shape? = nil)
        @id = (@@next_id += 1)
        add_shape(shape) if shape
        update_mass
      end

      # True for static bodies.
      def static? : Bool; @type.static?; end
      # True for dynamic bodies.
      def dynamic? : Bool; @type.dynamic?; end
      # True for kinematic bodies.
      def kinematic? : Bool; @type.kinematic?; end

      # Adds a shape and recomputes mass. Returns the shape.
      def add_shape(s : Shape) : Shape
        @shapes << s
        update_mass
        s
      end

      # Removes a shape and recomputes mass.
      def remove_shape(s : Shape) : Nil
        @shapes.delete(s)
        update_mass
      end

      # Wakes a sleeping body so it is simulated again.
      def wake : Nil
        @sleeping = false
        @sleep_timer = 0
      end

      # :nodoc:
      def sleep! : Nil
        @sleeping = true
        @sleep_timer = 0
        @velocity = Vec3::ZERO
        @angular_velocity = Vec3::ZERO
        @force = Vec3::ZERO
        @torque = Vec3::ZERO
      end

      # Sets the mass directly.
      def mass=(m : Number)
        @mass = m.to_f32
        @inv_mass = dynamic? && @mass > 0 ? 1 / @mass : 0_f32
        recompute_inertia
      end

      # Changes the body type.
      def type=(t : BodyType); @type = t; update_mass; end
      # Enables or disables rotation.
      def fixed_rotation=(v : Bool); @fixed_rotation = v; recompute_inertia; end

      # :nodoc:
      def update_mass : Nil
        if dynamic?
          vol = @shapes.sum(&.volume)
          @mass = vol > 0 ? Math.max(vol * @density, 0.01_f32) : 1_f32
          @inv_mass = 1 / @mass
        else
          @mass = 0_f32; @inv_mass = 0_f32
        end
        recompute_inertia
      end

      private def recompute_inertia
        if dynamic? && !@fixed_rotation && !@shapes.empty?
          f = @shapes.sum { |s| s.inertia_factor + Vec3.new(s.offset.y ** 2 + s.offset.z ** 2, s.offset.x ** 2 + s.offset.z ** 2, s.offset.x ** 2 + s.offset.y ** 2) } / @shapes.size
          i = f * @mass
          @inv_inertia_local = Vec3.new(i.x > 0 ? 1 / i.x : 0, i.y > 0 ? 1 / i.y : 0, i.z > 0 ? 1 / i.z : 0)
        else
          @inv_inertia_local = Vec3::ZERO
        end
      end

      # Applies the world-space inverse inertia to *v*.
      def inv_inertia_apply(v : Vec3) : Vec3
        local = @rotation.inverse * v
        @rotation * (local * @inv_inertia_local)
      end

      # The body's transform.
      def transform : Mat4; Mat4.trs(@position, @rotation, Vec3::ONE); end

      # Adds a force for the next step, at *point* if given.
      def apply_force(f : Vec3, point : Vec3? = nil) : Nil
        wake
        @force += f
        @torque += (point - @position).cross(f) if point
      end

      # Changes velocity instantly, at *point* if given.
      def apply_impulse(i : Vec3, point : Vec3? = nil) : Nil
        wake
        @velocity += i * @inv_mass
        @angular_velocity += inv_inertia_apply((point - @position).cross(i)) if point && !@fixed_rotation
      end

      # Adds torque for the next step.
      def apply_torque(t : Vec3) : Nil
        wake
        @torque += t
      end

      # Velocity of a world-space point on the body.
      def velocity_at(point : Vec3) : Vec3
        @velocity + @angular_velocity.cross(point - @position)
      end

      # :nodoc:
      def update_world_shapes : Nil
        @world_shapes.clear
        first = true
        box = AABB.new(Vec3::ZERO, Vec3::ZERO)
        @shapes.each do |s|
          ws = WorldShape.new(s, @position + @rotation * s.offset, @rotation)
          @world_shapes << ws
          box = first ? ws.aabb : box.union(ws.aabb)
          first = false
        end
        @aabb = box
      end

      # True when a world-space point is inside any shape.
      def contains_point?(p : Vec3) : Bool; @world_shapes.any?(&.contains?(p)); end
      # True when layer and mask bits allow a collision.
      def collides_with?(o : Body) : Bool; (@layer & o.mask) != 0 && (o.layer & @mask) != 0; end
      def to_s(io : IO) : Nil; io << "Body3D#" << @id << "(" << @type << " " << @position << ")"; end
    end

    # A constraint between two bodies, solved as extra impulse rows alongside contacts. Create
    # joints with `World#distance_joint`, `World#ball_joint`, `World#hinge_joint` and
    # `World#fixed_joint`, and remove them with `World#remove_joint`.
    #
    # ```
    # world = Physics3D::World.new
    # a = world.add(Physics3D::BodyType::Static, v3(0, 5, 0), Physics3D::Sphere.new(0.1))
    # b = world.add(Physics3D::BodyType::Dynamic, v3(1, 5, 0), Physics3D::Sphere.new(0.2))
    # joint = world.ball_joint(a, b, v3(0, 5, 0))
    # world.remove_joint(joint)
    # ```
    abstract class Joint
      # First body.
      getter a : Body
      # Second body.
      getter b : Body
      # Anchor on *a*, in *a*'s local space.
      property anchor_a : Vec3
      # Anchor on *b*, in *b*'s local space.
      property anchor_b : Vec3
      # Disabled joints are skipped.
      property? enabled = true

      # Creates a joint between *a* and *b*.
      def initialize(@a : Body, @b : Body, @anchor_a : Vec3 = Vec3::ZERO, @anchor_b : Vec3 = Vec3::ZERO)
      end

      # World-space location of `anchor_a`.
      def world_anchor_a : Vec3; @a.position + @a.rotation * @anchor_a; end
      # World-space location of `anchor_b`.
      def world_anchor_b : Vec3; @b.position + @b.rotation * @anchor_b; end

      # :nodoc:
      abstract def solve(world : World, dt : Float32)

      # :nodoc:
      def wake_bodies : Nil
        @a.wake if @b.dynamic? && !@b.sleeping?
        @b.wake if @a.dynamic? && !@a.sleeping?
      end
    end

    # Keeps two anchors a fixed distance apart. A length of 0 pins the points together
    # along one axis; use `BallJoint` to lock all three. Good for ropes, tethers and pendulums.
    #
    # ```
    # world = Physics3D::World.new
    # ceiling = world.add(Physics3D::BodyType::Static, v3(0, 5, 0), Physics3D::Sphere.new(0.1))
    # bob = world.add(Physics3D::BodyType::Dynamic, v3(2, 5, 0), Physics3D::Sphere.new(0.3))
    # world.distance_joint(ceiling, bob)
    # ```
    class DistanceJoint < Joint
      # Rest length in meters.
      property length : Float32

      # Creates a distance joint. *length* defaults to the current separation of the anchors.
      def initialize(a : Body, b : Body, anchor_a : Vec3 = Vec3::ZERO, anchor_b : Vec3 = Vec3::ZERO, length : Number? = nil)
        super(a, b, anchor_a, anchor_b)
        @length = (length ? length.to_f32 : (world_anchor_b - world_anchor_a).length)
      end

      # A distance joint whose anchors sit at a shared world-space point, with rest *length*.
      def self.at(a : Body, b : Body, world_a : Vec3, world_b : Vec3, length : Number? = nil) : DistanceJoint
        ja = a.rotation.inverse * (world_a - a.position)
        jb = b.rotation.inverse * (world_b - b.position)
        new(a, b, ja, jb, length)
      end

      # :nodoc:
      def solve(world : World, dt : Float32)
        pa = world_anchor_a; pb = world_anchor_b
        d = pb - pa
        dist = d.length
        n = dist > 1e-6 ? d / dist : Vec3::UP
        world.solve_linear(@a, @b, pa - @a.position, pb - @b.position, n, dist - @length, dt)
      end
    end

    # A spherical joint: the two anchors stay on top of each other. The bodies can still
    # tumble around that point. Good for ragdoll shoulders and hanging lamps.
    #
    # ```
    # world = Physics3D::World.new
    # post = world.add(Physics3D::BodyType::Static, v3(0, 5, 0), Physics3D::Sphere.new(0.1))
    # lamp = world.add(Physics3D::BodyType::Dynamic, v3(0, 4, 0), Physics3D::Cuboid.cube(0.5))
    # world.ball_joint(post, lamp, v3(0, 5, 0))
    # ```
    class BallJoint < Joint
      # A ball joint whose anchors meet at *world_point*.
      def self.at(a : Body, b : Body, world_point : Vec3) : BallJoint
        new(a, b, a.rotation.inverse * (world_point - a.position), b.rotation.inverse * (world_point - b.position))
      end

      # :nodoc:
      def solve(world : World, dt : Float32)
        pa = world_anchor_a; pb = world_anchor_b
        err = pb - pa
        ra = pa - @a.position; rb = pb - @b.position
        world.solve_linear(@a, @b, ra, rb, Vec3::RIGHT, err.x, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::UP, err.y, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::BACK, err.z, dt)
      end
    end

    # A hinge: a ball joint plus two angular rows so the bodies can only spin around *axis*.
    # Good for doors, wheels and levers.
    #
    # ```
    # world = Physics3D::World.new
    # frame = world.add(Physics3D::BodyType::Static, v3(0, 1, 0), Physics3D::Sphere.new(0.1))
    # door = world.add(Physics3D::BodyType::Dynamic, v3(1, 1, 0), Physics3D::Cuboid.new(v3(2, 2, 0.1)))
    # world.hinge_joint(frame, door, v3(0, 1, 0), Vec3::UP)
    # ```
    class HingeJoint < Joint
      # Hinge axis in *a*'s local space.
      property axis_a : Vec3
      # Hinge axis in *b*'s local space.
      property axis_b : Vec3
      @rest : Quat

      # Creates a hinge. Axes are local to each body.
      def initialize(a : Body, b : Body, anchor_a : Vec3 = Vec3::ZERO, anchor_b : Vec3 = Vec3::ZERO, axis_a : Vec3 = Vec3::RIGHT, axis_b : Vec3 = Vec3::RIGHT)
        super(a, b, anchor_a, anchor_b)
        @axis_a = axis_a.normalized
        @axis_b = axis_b.normalized
        @rest = a.rotation.inverse * b.rotation
      end

      # A hinge at *world_pivot* whose free axis is the world-space *axis*.
      def self.at(a : Body, b : Body, world_pivot : Vec3, axis : Vec3 = Vec3::RIGHT) : HingeJoint
        n = axis.normalized
        new(a, b,
          a.rotation.inverse * (world_pivot - a.position),
          b.rotation.inverse * (world_pivot - b.position),
          (a.rotation.inverse * n).normalized,
          (b.rotation.inverse * n).normalized)
      end

      # :nodoc:
      def solve(world : World, dt : Float32)
        pa = world_anchor_a; pb = world_anchor_b
        err = pb - pa
        ra = pa - @a.position; rb = pb - @b.position
        world.solve_linear(@a, @b, ra, rb, Vec3::RIGHT, err.x, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::UP, err.y, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::BACK, err.z, dt)
        axis = (@a.rotation * @axis_a).normalized
        q_rel = @a.rotation.inverse * @b.rotation
        q_err = @rest.inverse * q_rel
        q_err = Quat.new(-q_err.x, -q_err.y, -q_err.z, -q_err.w) if q_err.w < 0
        err_w = @a.rotation * Vec3.new(q_err.x, q_err.y, q_err.z) * 2
        err_w -= axis * err_w.dot(axis)
        t1, t2 = World.orthonormal(axis)
        world.solve_angular(@a, @b, t1, err_w.dot(t1), dt)
        world.solve_angular(@a, @b, t2, err_w.dot(t2), dt)
      end
    end

    # Locks two bodies together in position and orientation, like welding them. Good for
    # compound objects that can be knocked loose by removing the joint.
    #
    # ```
    # world = Physics3D::World.new
    # a = world.add(Physics3D::BodyType::Dynamic, v3(0, 3, 0), Physics3D::Cuboid.cube(1))
    # b = world.add(Physics3D::BodyType::Dynamic, v3(1.2, 3, 0), Physics3D::Cuboid.cube(1))
    # world.fixed_joint(a, b, v3(0.6, 3, 0))
    # ```
    class FixedJoint < Joint
      @rest : Quat

      # Creates a weld at the current relative pose.
      def initialize(a : Body, b : Body, anchor_a : Vec3 = Vec3::ZERO, anchor_b : Vec3 = Vec3::ZERO)
        super(a, b, anchor_a, anchor_b)
        @rest = a.rotation.inverse * b.rotation
      end

      # A weld whose anchors meet at *world_point*.
      def self.at(a : Body, b : Body, world_point : Vec3) : FixedJoint
        new(a, b, a.rotation.inverse * (world_point - a.position), b.rotation.inverse * (world_point - b.position))
      end

      # :nodoc:
      def solve(world : World, dt : Float32)
        pa = world_anchor_a; pb = world_anchor_b
        err = pb - pa
        ra = pa - @a.position; rb = pb - @b.position
        world.solve_linear(@a, @b, ra, rb, Vec3::RIGHT, err.x, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::UP, err.y, dt)
        world.solve_linear(@a, @b, ra, rb, Vec3::BACK, err.z, dt)
        q_rel = @a.rotation.inverse * @b.rotation
        q_err = @rest.inverse * q_rel
        q_err = Quat.new(-q_err.x, -q_err.y, -q_err.z, -q_err.w) if q_err.w < 0
        err_w = @a.rotation * Vec3.new(q_err.x, q_err.y, q_err.z) * 2
        world.solve_angular(@a, @b, Vec3::RIGHT, err_w.x, dt)
        world.solve_angular(@a, @b, Vec3::UP, err_w.y, dt)
        world.solve_angular(@a, @b, Vec3::BACK, err_w.z, dt)
      end
    end

    # A 3D physics simulation. See `Physics3D` for an example.
    class World
      # Acceleration applied to dynamic bodies, in m/s².
      property gravity : Vec3 = Vec3.new(0, -9.81, 0)
      # Solver iterations per step.
      property iterations : Int32 = 10
      # How aggressively overlap is corrected, from 0 to 1.
      property bias_factor : Float32 = 0.2_f32
      # Overlap allowed before correction, in meters.
      property slop : Float32 = 0.005_f32
      # Broad-phase grid cell size in meters.
      property cell_size : Float32 = 4_f32
      # Speed below which resting bodies stop being simulated. 0 disables sleeping.
      property sleep_threshold : Float32 = 0_f32
      # How long a body must stay under `sleep_threshold` before it sleeps, in seconds.
      property sleep_time : Float32 = 0.5_f32
      # Every body in the world.
      getter bodies = [] of Body
      # Joints solved each step.
      getter joints = [] of Joint
      # Pairs of bodies that started touching in the last step.
      getter began = [] of {Body, Body}
      # Pairs of bodies that stopped touching in the last step.
      getter ended = [] of {Body, Body}
      @pairs = Set({Int32, Int32}).new
      @grid = {} of {Int32, Int32, Int32} => Array(Body)

      # Emitted during a step when two bodies start touching.
      signal contact_begin(a : Body, b : Body)
      # Emitted during a step when two bodies stop touching.
      signal contact_end(a : Body, b : Body)

      # Adds an existing body and returns it.
      def add_body(b : Body) : Body
        @bodies << b unless @bodies.includes?(b)
        b.wake
        b.update_world_shapes
        b
      end

      # Creates a body with one shape, adds it and returns it.
      def add(type : BodyType, position : Vec3, shape : Shape) : Body
        add_body(Body.new(type, position, shape))
      end

      # Adds a joint and returns it.
      def add_joint(j : Joint) : Joint
        @joints << j unless @joints.includes?(j)
        j.a.wake; j.b.wake
        j
      end

      # A distance joint between *a* and *b*. Anchors default to each body's origin.
      def distance_joint(a : Body, b : Body, length : Number? = nil, anchor_a : Vec3 = Vec3::ZERO, anchor_b : Vec3 = Vec3::ZERO) : DistanceJoint
        add_joint(DistanceJoint.new(a, b, anchor_a, anchor_b, length)).as(DistanceJoint)
      end

      # A ball (spherical) joint pinning both bodies at *world_point*.
      def ball_joint(a : Body, b : Body, world_point : Vec3) : BallJoint
        add_joint(BallJoint.at(a, b, world_point)).as(BallJoint)
      end

      # A hinge at *world_pivot* that spins around world-space *axis*.
      def hinge_joint(a : Body, b : Body, world_pivot : Vec3, axis : Vec3 = Vec3::RIGHT) : HingeJoint
        add_joint(HingeJoint.at(a, b, world_pivot, axis)).as(HingeJoint)
      end

      # A weld that keeps *a* and *b* in their current relative pose, pinned at *world_point*.
      def fixed_joint(a : Body, b : Body, world_point : Vec3) : FixedJoint
        add_joint(FixedJoint.at(a, b, world_point)).as(FixedJoint)
      end

      # Removes a joint.
      def remove_joint(j : Joint) : Nil
        @joints.delete(j)
      end

      # Removes a body.
      def remove_body(b : Body) : Nil
        @bodies.delete(b)
        @joints.reject! { |j| j.a == b || j.b == b }
        b.contacts.each { |o| o.contacts.delete(b); @pairs.delete(pair_key(b, o)) }
        b.contacts.clear
      end

      # Removes every body and joint.
      def clear : Nil
        @bodies.clear; @joints.clear; @pairs.clear; @began.clear; @ended.clear
      end

      private record Contact, a : Body, b : Body, manifold : Manifold, sensor : Bool

      # Advances the simulation by *dt* seconds.
      def step(dt : Float32) : Nil
        return if dt <= 0
        @began.clear; @ended.clear
        @bodies.each do |b|
          next unless b.enabled?
          if b.dynamic? && !b.sleeping?
            b.velocity += (@gravity * b.gravity_scale + b.force * b.inv_mass) * dt
            b.angular_velocity += b.inv_inertia_apply(b.torque) * dt
            b.velocity *= (1 / (1 + dt * b.linear_damping)) if b.linear_damping > 0
            b.angular_velocity *= (1 / (1 + dt * b.angular_damping)) if b.angular_damping > 0
          end
          b.force = Vec3::ZERO; b.torque = Vec3::ZERO
          b.update_world_shapes unless b.sleeping?
        end
        contacts = find_contacts
        touching = Set({Int32, Int32}).new
        contacts.each do |c|
          key = pair_key(c.a, c.b)
          touching << key
          unless @pairs.includes?(key)
            @pairs << key
            c.a.contacts << c.b; c.b.contacts << c.a
            @began << {c.a, c.b}
          end
        end
        @pairs.each do |key|
          next if touching.includes?(key)
          a = @bodies.find { |b| b.id == key[0] }; b = @bodies.find { |x| x.id == key[1] }
          if a && b
            a.contacts.delete(b); b.contacts.delete(a)
            @ended << {a, b}
          end
        end
        @pairs = touching
        solid = contacts.reject(&.sensor)
        @joints.each(&.wake_bodies)
        @iterations.times do
          solid.each { |c| resolve(c, dt) }
          @joints.each { |j| j.solve(self, dt) if j.enabled? }
        end
        @bodies.each do |b|
          next if b.static? || !b.enabled? || b.sleeping?
          b.position += b.velocity * dt
          unless b.fixed_rotation? || b.angular_velocity.zero?
            w = b.angular_velocity
            dq = Quat.new(w.x * dt / 2, w.y * dt / 2, w.z * dt / 2, 1)
            b.rotation = (dq * b.rotation).normalized
          end
          b.update_world_shapes
        end
        update_sleeping(dt) if @sleep_threshold > 0
        @began.each { |(a, b)| emit_contact_begin(a, b) }
        @ended.each { |(a, b)| emit_contact_end(a, b) }
      end

      private def pair_key(a : Body, b : Body) : {Int32, Int32}
        a.id < b.id ? {a.id, b.id} : {b.id, a.id}
      end

      private def build_grid
        @grid.each_value(&.clear)
        @bodies.each do |b|
          next unless b.enabled?
          r = b.aabb
          x0 = (r.min.x / @cell_size).floor.to_i; x1 = (r.max.x / @cell_size).floor.to_i
          y0 = (r.min.y / @cell_size).floor.to_i; y1 = (r.max.y / @cell_size).floor.to_i
          z0 = (r.min.z / @cell_size).floor.to_i; z1 = (r.max.z / @cell_size).floor.to_i
          (x0..x1).each { |x| (y0..y1).each { |y| (z0..z1).each { |z| (@grid[{x, y, z}] ||= [] of Body) << b } } }
        end
      end

      private def find_contacts : Array(Contact)
        build_grid
        out_c = [] of Contact
        seen = Set({Int32, Int32}).new
        @grid.each_value do |cell|
          next if cell.size < 2
          cell.each_with_index do |a, i|
            (i + 1...cell.size).each do |j|
              b = cell[j]
              next if !a.dynamic? && !b.dynamic? && !(a.sensor? || b.sensor?)
              next unless a.enabled? && b.enabled? && a.collides_with?(b)
              next unless a.aabb.intersects?(b.aabb)
              key = pair_key(a, b)
              next if seen.includes?(key)
              seen << key
              best : Manifold? = nil
              a.world_shapes.each do |sa|
                b.world_shapes.each do |sb|
                  if m = Collision.test(sa, sb)
                    best = m if best.nil? || m.penetration > best.penetration
                  end
                end
              end
              out_c << Contact.new(a, b, best, a.sensor? || b.sensor?) if best
            end
          end
        end
        out_c
      end

      private def resolve(c : Contact, dt : Float32)
        a = c.a; b = c.b; m = c.manifold
        return if a.sleeping? && b.sleeping?
        return if (a.sleeping? && !awake_mover?(b)) || (b.sleeping? && !awake_mover?(a))
        inv_mass_sum = a.inv_mass + b.inv_mass
        return if inv_mass_sum == 0
        n = m.normal
        bias = @bias_factor / dt * Math.max(m.penetration - @slop, 0_f32)
        e = Math.max(a.restitution, b.restitution)
        mu = Math.sqrt(a.friction * b.friction).to_f32
        count = m.contacts.size
        js = Array(Float32).new(count, 0_f32)
        m.contacts.each_with_index do |cp, i|
          ra = cp - a.position; rb = cp - b.position
          rv = b.velocity_at(cp) - a.velocity_at(cp)
          vn = rv.dot(n)
          next if vn > 0 && bias == 0
          ta = a.inv_inertia_apply(ra.cross(n)).cross(ra)
          tb = b.inv_inertia_apply(rb.cross(n)).cross(rb)
          k = inv_mass_sum + (ta + tb).dot(n)
          bounce = vn.abs > 1.0 ? e : 0_f32
          j = (-(1 + bounce) * vn + bias) / k / count
          js[i] = Math.max(j, 0_f32)
        end
        m.contacts.each_with_index do |cp, i|
          next if js[i] == 0
          impulse = n * js[i]
          apply(a, -impulse, cp); apply(b, impulse, cp)
        end
        m.contacts.each_with_index do |cp, i|
          next if js[i] == 0
          ra = cp - a.position; rb = cp - b.position
          rv = b.velocity_at(cp) - a.velocity_at(cp)
          t = rv - n * rv.dot(n)
          tl = t.length
          next if tl < 1e-6
          t = t / tl
          ta = a.inv_inertia_apply(ra.cross(t)).cross(ra)
          tb = b.inv_inertia_apply(rb.cross(t)).cross(rb)
          kt = inv_mass_sum + (ta + tb).dot(t)
          jt = (-rv.dot(t) / kt / count).clamp(-js[i] * mu, js[i] * mu)
          fi = t * jt
          apply(a, -fi, cp); apply(b, fi, cp)
        end
      end

      private def apply(b : Body, impulse : Vec3, point : Vec3)
        return if b.inv_mass == 0
        b.wake if b.sleeping?
        b.velocity += impulse * b.inv_mass
        b.angular_velocity += b.inv_inertia_apply((point - b.position).cross(impulse)) unless b.fixed_rotation?
      end

      private def awake_mover?(b : Body) : Bool
        return false if b.static? || !b.enabled?
        if b.kinematic?
          b.velocity.length_squared + b.angular_velocity.length_squared > 1e-8
        else
          b.dynamic? && !b.sleeping?
        end
      end

      private def update_sleeping(dt : Float32)
        jointed = Set(Body).new
        @joints.each { |j| jointed << j.a << j.b if j.enabled? }
        @bodies.each do |b|
          next unless b.dynamic? && b.enabled?
          next if jointed.includes?(b)
          speed = b.velocity.length + b.angular_velocity.length
          if speed < @sleep_threshold
            b.sleep_timer += dt
            b.sleep! if !b.sleeping? && b.sleep_timer >= @sleep_time
          else
            b.wake
          end
        end
      end

      # :nodoc:
      def solve_linear(a : Body, b : Body, ra : Vec3, rb : Vec3, n : Vec3, c_err : Float32, dt : Float32) : Nil
        inv_mass = a.inv_mass + b.inv_mass
        ta = a.inv_inertia_apply(ra.cross(n)).cross(ra)
        tb = b.inv_inertia_apply(rb.cross(n)).cross(rb)
        k = inv_mass + (ta + tb).dot(n)
        return if k.abs < 1e-8
        va = a.velocity + a.angular_velocity.cross(ra)
        vb = b.velocity + b.angular_velocity.cross(rb)
        cdot = (vb - va).dot(n)
        bias = @bias_factor / dt * c_err
        lam = -(cdot + bias) / k
        impulse = n * lam
        apply(a, -impulse, a.position + ra)
        apply(b, impulse, b.position + rb)
      end

      # :nodoc:
      def solve_angular(a : Body, b : Body, n : Vec3, c_err : Float32, dt : Float32) : Nil
        ia = a.inv_inertia_apply(n)
        ib = b.inv_inertia_apply(n)
        k = n.dot(ia) + n.dot(ib)
        return if k.abs < 1e-8
        rel = (b.angular_velocity - a.angular_velocity).dot(n)
        bias = @bias_factor / dt * c_err
        lam = -(rel + bias) / k
        a.wake if a.sleeping?; b.wake if b.sleeping?
        a.angular_velocity -= a.inv_inertia_apply(n * lam) unless a.fixed_rotation? || a.inv_mass == 0
        b.angular_velocity += b.inv_inertia_apply(n * lam) unless b.fixed_rotation? || b.inv_mass == 0
      end

      # :nodoc:
      def self.orthonormal(n : Vec3) : {Vec3, Vec3}
        t1 = n.cross(n.y.abs > 0.9 ? Vec3::RIGHT : Vec3::UP)
        t1 = t1.normalized
        {t1, n.cross(t1)}
      end

      # Casts a ray and returns the closest hit, or `nil`.
      def raycast(origin : Vec3, direction : Vec3, max_distance : Number = 1e6, mask : UInt32 = 0xFFFFFFFF_u32, exclude : Body? = nil) : RayHit?
        dir = direction.normalized
        best : RayHit? = nil
        @bodies.each do |b|
          next if b == exclude || !b.enabled? || (b.layer & mask) == 0
          b.world_shapes.each do |ws|
            hit = Collision.ray(origin, dir, max_distance.to_f32, ws)
            next unless hit
            t, nrm = hit
            best = RayHit.new(origin + dir * t, nrm, t, b) if best.nil? || t < best.distance
          end
        end
        best
      end

      # Every body containing *p*.
      def query_point(p : Vec3, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        @bodies.select { |b| b.enabled? && (b.layer & mask) != 0 && b.aabb.contains?(p) && b.contains_point?(p) }
      end

      # Every body whose bounds overlap *box*.
      def query_aabb(box : AABB, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        @bodies.select { |b| b.enabled? && (b.layer & mask) != 0 && b.aabb.intersects?(box) }
      end

      # Every body overlapping a sphere, for explosions and proximity checks.
      def query_sphere(center : Vec3, radius : Number, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        probe = WorldShape.new(Sphere.new(radius), center, Quat::IDENTITY)
        @bodies.select do |b|
          b.enabled? && (b.layer & mask) != 0 && b.aabb.intersects?(probe.aabb) && b.world_shapes.any? { |ws| !Collision.test(probe, ws).nil? }
        end
      end

      # Moves a body by *motion*, sliding along obstacles. Returns the normals hit.
      def move_and_slide(body : Body, motion : Vec3, max_slides : Int32 = 4) : Array(Vec3)
        normals = [] of Vec3
        extent = Math.max(0.05_f32, Math.min(body.aabb.size.x, Math.min(body.aabb.size.y, body.aabb.size.z)) / 2)
        len = motion.length
        steps = len > extent ? (len / extent).ceil.to_i : 1
        sub = motion / steps
        steps.times do
          body.position += sub
          slide_out(body, max_slides).each { |n| normals << n unless normals.any?(&.approx?(n, 1e-3)) }
        end
        body.update_world_shapes
        normals
      end

      private def slide_out(body : Body, max_slides : Int32) : Array(Vec3)
        normals = [] of Vec3
        max_slides.times do
          body.update_world_shapes
          hit : Manifold? = nil
          @bodies.each do |o|
            next if o == body || o.sensor? || o.dynamic? || !o.enabled? || !body.collides_with?(o)
            next unless body.aabb.intersects?(o.aabb)
            body.world_shapes.each do |sa|
              o.world_shapes.each do |sb|
                if m = Collision.test(sa, sb)
                  hit = m if hit.nil? || m.penetration > hit.penetration
                end
              end
            end
          end
          break unless hit
          n = -hit.normal
          body.position += n * (hit.penetration + 0.001_f32)
          normals << n
        end
        normals
      end

      # Looks for ground below the body without moving it. Returns the floor normal if found.
      def probe_floor(body : Body, up : Vec3, distance : Float32, max_angle : Float32) : Vec3?
        start = body.position
        body.position += -up * distance
        normals = slide_out(body, 2)
        body.position = start
        body.update_world_shapes
        normals.find { |n| n.dot(up) >= Math.cos(max_angle) }
      end
    end

    @@world = World.new
    # The shared world used by the 3D physics nodes.
    def self.world : World; @@world; end
    # Replaces the shared world.
    def self.world=(w : World); @@world = w; end
    # True when the shared world has bodies.
    def self.active? : Bool; !@@world.bodies.empty?; end
    # Replaces the shared world with an empty one.
    def self.reset : Nil; @@world = World.new; end
  end
end
