module Eagle
  module Physics2D
    # Simulation container. Units: pixels and seconds; gravity defaults to 980 px/s².
    class World
      property gravity : Vec2 = Vec2.new(0, 980)
      property iterations : Int32 = 10
      # Extra post-step positional correction (0 = rely on the velocity bias only).
      property position_correction : Float32 = 0_f32
      # Baumgarte velocity bias factor (0..1) for resolving penetration.
      property bias_factor : Float32 = 0.2_f32
      property slop : Float32 = 0.05_f32
      property cell_size : Float32 = 128_f32
      getter bodies = [] of Body
      # (a, b) pairs that began/ended touching in the last step.
      getter began = [] of {Body, Body}
      getter ended = [] of {Body, Body}
      @pairs = Set({Int32, Int32}).new
      @grid = {} of {Int32, Int32} => Array(Body)

      signal contact_begin(a : Body, b : Body)
      signal contact_end(a : Body, b : Body)

      def add_body(b : Body) : Body
        @bodies << b unless @bodies.includes?(b)
        b.update_world_shapes
        b
      end

      def add(type : BodyType, position : Vec2, shape : Shape) : Body
        add_body(Body.new(type, position, shape))
      end

      def remove_body(b : Body) : Nil
        @bodies.delete(b)
        b.contacts.each { |o| o.contacts.delete(b); @pairs.delete(pair_key(b, o)) }
        b.contacts.clear
      end

      def clear : Nil
        @bodies.clear; @pairs.clear; @began.clear; @ended.clear
      end

      private record Contact, a : Body, b : Body, manifold : Manifold, sensor : Bool

      def step(dt : Float32) : Nil
        return if dt <= 0
        @began.clear; @ended.clear
        # integrate forces
        @bodies.each do |b|
          next unless b.enabled?
          if b.dynamic?
            b.velocity += (@gravity * b.gravity_scale + b.force * b.inv_mass) * dt
            b.angular_velocity += b.torque * b.inv_inertia * dt
            b.velocity *= (1 / (1 + dt * b.linear_damping)) if b.linear_damping > 0
            b.angular_velocity *= (1 / (1 + dt * b.angular_damping)) if b.angular_damping > 0
          end
          b.force = Vec2::ZERO; b.torque = 0_f32
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

        # integrate velocities
        @bodies.each do |b|
          next unless b.enabled? || !b.static?
          next if b.static?
          b.position += b.velocity * dt
          b.rotation += b.angular_velocity * dt unless b.fixed_rotation?
        end

        solid.each { |c| correct_position(c) } if @position_correction > 0
        @bodies.each { |b| b.update_world_shapes unless b.static? }

        @began.each { |(a, b)| emit_contact_begin(a, b) }
        @ended.each { |(a, b)| emit_contact_end(a, b) }
      end

      private def pair_key(a : Body, b : Body) : {Int32, Int32}
        a.id < b.id ? {a.id, b.id} : {b.id, a.id}
      end

      private def find_contacts : Array(Contact)
        build_grid
        out_contacts = [] of Contact
        seen = Set({Int32, Int32}).new
        @grid.each_value do |cell|
          next if cell.size < 2
          cell.each_with_index do |a, i|
            (i + 1...cell.size).each do |j|
              b = cell[j]
              next if a.static? && b.static?
              next if (a.static? || a.kinematic?) && (b.static? || b.kinematic?) && !(a.sensor? || b.sensor?)
              next unless a.enabled? && b.enabled?
              next unless a.collides_with?(b)
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
              if m = best
                out_contacts << Contact.new(a, b, m, a.sensor? || b.sensor?)
              end
            end
          end
        end
        out_contacts
      end

      private def build_grid
        @grid.each_value(&.clear)
        @bodies.each do |b|
          next unless b.enabled?
          r = b.aabb
          x0 = (r.x / @cell_size).floor.to_i; x1 = (r.right / @cell_size).floor.to_i
          y0 = (r.y / @cell_size).floor.to_i; y1 = (r.bottom / @cell_size).floor.to_i
          (y0..y1).each { |y| (x0..x1).each { |x| (@grid[{x, y}] ||= [] of Body) << b } }
        end
      end

      private def resolve(c : Contact, dt : Float32)
        a = c.a; b = c.b; m = c.manifold
        inv_mass_sum = a.inv_mass + b.inv_mass
        return if inv_mass_sum == 0
        bias = @bias_factor / dt * Math.max(m.penetration - @slop, 0_f32)
        e = Math.max(a.restitution, b.restitution)
        mu = Math.sqrt(a.friction * b.friction).to_f32
        n = m.normal
        count = m.contacts.size
        # Normal impulses: computed for every contact from the same state, then
        # applied together so symmetric contacts don't induce spurious spin.
        js = StaticArray(Float32, 2).new(0_f32)
        m.contacts.each_with_index do |cp, i|
          next if i >= 2
          ra = cp - a.position; rb = cp - b.position
          rv = b.velocity_at(cp) - a.velocity_at(cp)
          vn = rv.dot(n)
          next if vn > 0
          ra_n = ra.cross(n); rb_n = rb.cross(n)
          k = inv_mass_sum + ra_n * ra_n * a.inv_inertia + rb_n * rb_n * b.inv_inertia
          bounce = vn.abs > 60 ? e : 0_f32
          js[i] = (-(1 + bounce) * vn + bias) / k / count
        end
        m.contacts.each_with_index do |cp, i|
          next if i >= 2 || js[i] == 0
          impulse = n * js[i]
          apply(a, -impulse, cp - a.position); apply(b, impulse, cp - b.position)
        end
        # Friction, same scheme; clamped by this iteration's normal impulse.
        jts = StaticArray(Float32, 2).new(0_f32)
        ts = StaticArray(Vec2, 2).new(Vec2::ZERO)
        m.contacts.each_with_index do |cp, i|
          next if i >= 2 || js[i] == 0
          ra = cp - a.position; rb = cp - b.position
          rv = b.velocity_at(cp) - a.velocity_at(cp)
          t = rv - n * rv.dot(n)
          tl = t.length
          next if tl < 1e-6
          t = t / tl
          ra_t = ra.cross(t); rb_t = rb.cross(t)
          kt = inv_mass_sum + ra_t * ra_t * a.inv_inertia + rb_t * rb_t * b.inv_inertia
          jt = -rv.dot(t) / kt / count
          jts[i] = jt.clamp(-js[i] * mu, js[i] * mu)
          ts[i] = t
        end
        m.contacts.each_with_index do |cp, i|
          next if i >= 2 || jts[i] == 0
          fi = ts[i] * jts[i]
          apply(a, -fi, cp - a.position); apply(b, fi, cp - b.position)
        end
      end

      private def apply(b : Body, impulse : Vec2, r : Vec2)
        return if b.inv_mass == 0
        b.velocity += impulse * b.inv_mass
        b.angular_velocity += r.cross(impulse) * b.inv_inertia unless b.fixed_rotation?
      end

      private def correct_position(c : Contact)
        a = c.a; b = c.b; m = c.manifold
        inv = a.inv_mass + b.inv_mass
        return if inv == 0
        amount = Math.max(m.penetration - @slop, 0_f32) / inv * @position_correction
        corr = m.normal * amount
        a.position -= corr * a.inv_mass
        b.position += corr * b.inv_mass
      end

      # --- queries -------------------------------------------------------------
      def raycast(origin : Vec2, direction : Vec2, max_distance : Number = 1e6, mask : UInt32 = 0xFFFFFFFF_u32, exclude : Body? = nil) : RayHit?
        dir = direction.normalized
        best : RayHit? = nil
        @bodies.each do |b|
          next if b == exclude || !b.enabled? || (b.layer & mask) == 0
          b.world_shapes.each do |s|
            hit = case s
                  when Circle then Collision.ray_circle(origin, dir, max_distance.to_f32, s)
                  when Polygon then Collision.ray_polygon(origin, dir, max_distance.to_f32, s)
                  else nil
                  end
            next unless hit
            t, n = hit
            if best.nil? || t < best.distance
              best = RayHit.new(origin + dir * t, n, t, b, s)
            end
          end
        end
        best
      end

      def query_point(p : Vec2, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        @bodies.select { |b| b.enabled? && (b.layer & mask) != 0 && b.aabb.contains?(p) && b.contains_point?(p) }
      end

      def query_rect(r : Rect, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        @bodies.select { |b| b.enabled? && (b.layer & mask) != 0 && b.aabb.intersects?(r) }
      end

      # Bodies overlapping a world-space shape.
      def query_shape(shape : Shape, mask : UInt32 = 0xFFFFFFFF_u32) : Array(Body)
        sa = shape.aabb
        @bodies.select do |b|
          b.enabled? && (b.layer & mask) != 0 && b.aabb.intersects?(sa) && b.world_shapes.any? { |s| Collision.overlaps?(shape, s) }
        end
      end

      # Kinematic character movement: move by `motion`, sliding along
      # obstacles. Returns the collision normals hit (empty when free).
      def move_and_slide(body : Body, motion : Vec2, max_slides : Int32 = 4) : Array(Vec2)
        normals = [] of Vec2
        # Substep long motions so thin obstacles are not tunnelled through.
        extent = body.aabb.empty? ? 8_f32 : Math.max(2_f32, Math.min(body.aabb.w, body.aabb.h) / 2)
        len = motion.length
        steps = len > extent ? (len / extent).ceil.to_i : 1
        sub = motion / steps
        steps.times do
          body.position += sub
          n = slide_out(body, max_slides)
          n.each { |x| normals << x unless normals.any?(&.approx?(x, 1e-3)) }
        end
        body.update_world_shapes
        normals
      end

      # Push `body` out of static/kinematic obstacles; returns contact normals.
      private def slide_out(body : Body, max_slides : Int32) : Array(Vec2)
        normals = [] of Vec2
        max_slides.times do
          body.update_world_shapes
          hit : Manifold? = nil
          hit_body : Body? = nil
          @bodies.each do |o|
            next if o == body || o.sensor? || !o.enabled? || !body.collides_with?(o)
            next if o.dynamic? # kinematic bodies push through dynamic ones
            next unless body.aabb.intersects?(o.aabb)
            body.world_shapes.each do |sa|
              o.world_shapes.each do |sb|
                if m = Collision.test(sa, sb)
                  if hit.nil? || m.penetration > hit.penetration
                    hit = m; hit_body = o
                  end
                end
              end
            end
          end
          break unless hit
          n = -hit.normal # push body away from obstacle
          body.position += n * (hit.penetration + 0.01_f32)
          normals << n
        end
        normals
      end

      # Probe for ground within `distance` along -up without moving the body.
      # Returns the floor normal if found.
      def probe_floor(body : Body, up : Vec2, distance : Float32, max_angle : Float32) : Vec2?
        start = body.position
        body.position += -up * distance
        normals = slide_out(body, 2)
        body.position = start
        body.update_world_shapes
        normals.find { |n| n.dot(up) >= Math.cos(max_angle) }
      end
    end
  end
end
