module Eagle
  # 3D rigid-body physics in pure Crystal: spheres and oriented boxes, stacking, friction,
  # raycasts, overlap queries and kinematic character movement.
  #
  # It mirrors `Physics2D`. Most games use the 3D physics nodes (`RigidBody3D`,
  # `StaticBody3D`, `KinematicBody3D`, `Area3D`, `RayCast3D`), which share `Physics3D.world`.
  # Units are meters and seconds, and gravity defaults to 9.81 m/s² downward.
  #
  # ```
  # world = Physics3D::World.new
  # world.add(Physics3D::BodyType::Static, v3(0, -0.5, 0), Physics3D::Cuboid.new(v3(20, 1, 20)))
  # ball = world.add(Physics3D::BodyType::Dynamic, v3(0, 5, 0), Physics3D::Sphere.new(0.5))
  # 120.times { world.step(1_f32 / 60) }
  # nearby = world.query_sphere(ball.position, 2)
  # ```
  module Physics3D
    # A 3D collision shape in a body's local space: a `Sphere` or a `Cuboid`.
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

    # :nodoc:
    struct WorldShape
      getter shape : Shape
      getter center : Vec3
      getter rotation : Quat
      getter axes : {Vec3, Vec3, Vec3}
      # Creates a body, optionally with a first shape.
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
        else AABB.new(@center, @center)
        end
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
        else @center
        end
      end

      def contains?(p : Vec3) : Bool
        case (s = @shape)
        when Sphere then p.distance_squared(@center) <= s.radius * s.radius
        when Cuboid
          d = p - @center
          d.dot(@axes[0]).abs <= s.half.x && d.dot(@axes[1]).abs <= s.half.y && d.dot(@axes[2]).abs <= s.half.z
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
      def initialize(@normal, @penetration, @contacts); end
    end

    # Where a ray hit: point, normal, distance and body.
    struct RayHit
      getter point : Vec3
      # Surface normal at the hit.
      getter normal : Vec3
      getter distance : Float32
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
        when {Cuboid, Sphere}
          m = sphere_box(b, a)
          m ? Manifold.new(-m.normal, m.penetration, m.contacts) : nil
        when {Cuboid, Cuboid} then box_box(a, b)
        else nil
        end
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

      def ray(origin : Vec3, dir : Vec3, max : Float32, ws : WorldShape) : {Float32, Vec3}?
        case (s = ws.shape)
        when Sphere
          t = Ray.new(origin, dir).intersect_sphere(ws.center, s.radius)
          return nil unless t && t <= max
          {t, (origin + dir * t - ws.center).normalized}
        when Cuboid
          # transform ray into box space
          inv = ws.rotation.inverse
          lo = inv * (origin - ws.center)
          ld = inv * dir
          t = Ray.new(lo, ld).intersect_aabb(AABB.new(-s.half, s.half))
          return nil unless t && t <= max
          hit = lo + ld.normalized * t
          # normal: axis with the largest normalised coordinate
          nx = hit.x / s.half.x; ny = hit.y / s.half.y; nz = hit.z / s.half.z
          ln = if nx.abs >= ny.abs && nx.abs >= nz.abs
                 Vec3.new(Mathf.sign(nx), 0, 0)
               elsif ny.abs >= nz.abs
                 Vec3.new(0, Mathf.sign(ny), 0)
               else
                 Vec3.new(0, 0, Mathf.sign(nz))
               end
          {t, ws.rotation * ln}
        else nil
        end
      end
    end

    # How a body moves: `Static`, `Kinematic` (moved by code) or `Dynamic` (moved by the simulation).
    enum BodyType
      Static
      Kinematic
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
      # A unique id.
      getter id : Int32
      @@next_id = 0

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
        @force += f
        @torque += (point - @position).cross(f) if point
      end

      # Changes velocity instantly, at *point* if given.
      def apply_impulse(i : Vec3, point : Vec3? = nil) : Nil
        @velocity += i * @inv_mass
        @angular_velocity += inv_inertia_apply((point - @position).cross(i)) if point && !@fixed_rotation
      end

      # Adds torque for the next step.
      def apply_torque(t : Vec3) : Nil; @torque += t; end

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
      # Every body in the world.
      getter bodies = [] of Body
      # Pairs of bodies that started touching in the last step.
      getter began = [] of {Body, Body}
      # Pairs of bodies that stopped touching in the last step.
      getter ended = [] of {Body, Body}
      @pairs = Set({Int32, Int32}).new
      @grid = {} of {Int32, Int32, Int32} => Array(Body)

      signal contact_begin(a : Body, b : Body)
      signal contact_end(a : Body, b : Body)

      # Adds an existing body and returns it.
      def add_body(b : Body) : Body
        @bodies << b unless @bodies.includes?(b)
        b.update_world_shapes
        b
      end

      # Creates a body with one shape, adds it and returns it.
      def add(type : BodyType, position : Vec3, shape : Shape) : Body
        add_body(Body.new(type, position, shape))
      end

      # Removes a body.
      def remove_body(b : Body) : Nil
        @bodies.delete(b)
        b.contacts.each { |o| o.contacts.delete(b); @pairs.delete(pair_key(b, o)) }
        b.contacts.clear
      end

      # Removes every body.
      def clear : Nil; @bodies.clear; @pairs.clear; @began.clear; @ended.clear; end

      private record Contact, a : Body, b : Body, manifold : Manifold, sensor : Bool

      # Advances the simulation by *dt* seconds.
      def step(dt : Float32) : Nil
        return if dt <= 0
        @began.clear; @ended.clear
        @bodies.each do |b|
          next unless b.enabled?
          if b.dynamic?
            b.velocity += (@gravity * b.gravity_scale + b.force * b.inv_mass) * dt
            b.angular_velocity += b.inv_inertia_apply(b.torque) * dt
            b.velocity *= (1 / (1 + dt * b.linear_damping)) if b.linear_damping > 0
            b.angular_velocity *= (1 / (1 + dt * b.angular_damping)) if b.angular_damping > 0
          end
          b.force = Vec3::ZERO; b.torque = Vec3::ZERO
          b.update_world_shapes
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
        @iterations.times { solid.each { |c| resolve(c, dt) } }
        @bodies.each do |b|
          next if b.static? || !b.enabled?
          b.position += b.velocity * dt
          unless b.fixed_rotation? || b.angular_velocity.zero?
            w = b.angular_velocity
            dq = Quat.new(w.x * dt / 2, w.y * dt / 2, w.z * dt / 2, 1)
            b.rotation = (dq * b.rotation).normalized
          end
          b.update_world_shapes
        end
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
        b.velocity += impulse * b.inv_mass
        b.angular_velocity += b.inv_inertia_apply((point - b.position).cross(impulse)) unless b.fixed_rotation?
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
