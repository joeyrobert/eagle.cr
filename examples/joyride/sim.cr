require "./world"

# Joyride simulation: arcade car physics, traffic, police, pedestrians and missions.
# Plain logic on the ground plane (Vec2 is x, z), testable without a window.
module Joyride
  # Tuning for one kind of car.
  record CarSpec, max_speed : Float32 = 46_f32, accel : Float32 = 15_f32, brake : Float32 = 28_f32,
    reverse_speed : Float32 = 11_f32, grip : Float32 = 9_f32, drift_grip : Float32 = 1.1_f32,
    steer_low : Float32 = 0.6_f32, steer_high : Float32 = 0.1_f32, wheelbase : Float32 = 2.7_f32,
    mass : Float32 = 1_f32, radius : Float32 = 1.0_f32, spacing : Float32 = 1.35_f32

  PLAYER_SPEC  = CarSpec.new
  TRAFFIC_SPEC = CarSpec.new(max_speed: 22, accel: 7, mass: 1.2_f32)
  POLICE_SPEC  = CarSpec.new(max_speed: 43, accel: 14, mass: 1.5_f32, grip: 10)

  def self.forward(heading : Float32) : Vec2
    Vec2.new(-Math.sin(heading), -Math.cos(heading))
  end

  def self.right(heading : Float32) : Vec2
    Vec2.new(Math.cos(heading), -Math.sin(heading))
  end

  # Heading that faces direction *d*.
  def self.heading_of(d : Vec2) : Float32
    Math.atan2(-d.x, -d.y).to_f32
  end

  # 2D cross product in yaw terms: positive when *b* is counter-clockwise from *a* seen from above.
  def self.yaw_cross(a : Vec2, b : Vec2) : Float32
    a.y * b.x - a.x * b.y
  end

  # An arcade car: throttle, brake/reverse, speed-scaled steering, handbrake drifts,
  # pushed out of static colliders with sub-stepping so it never tunnels.
  class Car
    property pos : Vec2
    property heading : Float32
    property vel : Vec2 = Vec2::ZERO
    property spin : Float32 = 0_f32
    property steer : Float32 = 0_f32
    getter spec : CarSpec
    # inputs, set every step
    property throttle : Float32 = 0_f32
    property brake : Float32 = 0_f32
    property steer_input : Float32 = 0_f32
    property? handbrake = false
    # outputs
    getter slip : Float32 = 0_f32
    getter last_impact : Float32 = 0_f32
    property y : Float32 = 0_f32

    def initialize(@pos : Vec2, @heading : Float32 = 0_f32, @spec : CarSpec = PLAYER_SPEC); end

    def forward : Vec2
      Joyride.forward(@heading)
    end

    def right : Vec2
      Joyride.right(@heading)
    end

    def speed : Float32
      @vel.length
    end

    def forward_speed : Float32
      @vel.dot(forward)
    end

    # Centers of the collision circles, rear to front.
    def circles : StaticArray(Vec2, 3)
      f = forward * @spec.spacing
      StaticArray[@pos - f, @pos, @pos + f]
    end

    def clear_inputs : Nil
      @throttle = 0_f32; @brake = 0_f32; @steer_input = 0_f32; @handbrake = false
    end

    # Advances the car. Returns the strongest impact speed against static colliders.
    def step(dt : Float32, world : World?) : Float32
      drive(dt)
      @last_impact = 0_f32
      dist = speed * dt
      n = Math.max(1, (dist / 0.4_f32).ceil.to_i)
      sub = dt / n
      n.times do
        @pos += @vel * sub
        if w = world
          @last_impact = Math.max(@last_impact, collide_static(w))
        end
      end
      @last_impact
    end

    private def drive(dt : Float32) : Nil
      s = @spec
      f = forward; r = right
      vf = @vel.dot(f); vl = @vel.dot(r)
      if @throttle > 0
        if vf < -0.5
          vf = Math.min(0_f32, vf + s.brake * @throttle * dt)
        else
          k = (1 - (vf / s.max_speed) ** 2).clamp(0_f32, 1_f32)
          vf += s.accel * @throttle * (0.35_f32 + 0.65_f32 * k) * dt
          vf = Math.min(vf, s.max_speed)
        end
      end
      if @brake > 0
        if vf > 0.5
          vf = Math.max(0_f32, vf - s.brake * @brake * dt)
        else
          vf = Math.max(-s.reverse_speed, vf - s.accel * 0.7_f32 * @brake * dt)
        end
      end
      # rolling resistance and drag when coasting
      if @throttle <= 0 && @brake <= 0
        vf = Mathf.move_toward(vf, 0, (1.5_f32 + vf.abs * 0.02_f32) * dt).to_f32
      end
      vf = Mathf.move_toward(vf, 0, 5 * dt).to_f32 if @handbrake
      # steering: narrower at speed, smoothed so taps don't jerk
      t = (vf.abs / (s.max_speed * 0.8_f32)).clamp(0_f32, 1_f32)
      max_steer = s.steer_low + (s.steer_high - s.steer_low) * t
      target = @steer_input.clamp(-1_f32, 1_f32) * max_steer
      @steer += (target - @steer) * Math.min(1_f32, dt * 8)
      yaw = -vf * Math.tan(@steer) / s.wheelbase
      yaw *= 1.45_f32 if @handbrake
      @heading += (yaw + @spin) * dt
      @spin *= Math.exp(-3.5_f32 * dt).to_f32
      # re-express the world velocity in the new frame and bleed off sideways motion
      world_v = f * vf + r * vl
      f2 = forward; r2 = right
      vf2 = world_v.dot(f2); vl2 = world_v.dot(r2)
      grip = @handbrake ? s.drift_grip : s.grip
      # powersliding: flooring it at speed while steering hard loosens the rear
      grip *= 0.55_f32 if @throttle > 0.9 && @steer_input.abs > 0.9 && vf > 20
      vl2 *= Math.exp(-grip * dt).to_f32
      @slip = vl2.abs
      @vel = f2 * vf2 + r2 * vl2
    end

    # Pushes the car out of static colliders. Returns the impact speed.
    def collide_static(world : World) : Float32
      impact = 0_f32
      r = @spec.radius
      2.times do
        hit = false
        circles.each_with_index do |c, i|
          world.each_collider_near(c, r + 0.5_f32) do |col|
            next unless (pen = col.penetration(c, r))
            n, depth = pen
            @pos += n * depth
            c += n * depth
            vn = @vel.dot(n)
            if vn < 0
              impact = Math.max(impact, -vn)
              @vel -= n * (vn * 1.25_f32)
              @vel *= 0.92_f32
              lever = (c - @pos)
              @spin += Joyride.yaw_cross(lever, n * -vn) * 0.12_f32
            end
            hit = true
          end
        end
        break unless hit
      end
      impact
    end

    # Resolves overlap between two cars. Returns the relative impact speed, or 0.
    def self.collide(a : Car, b : Car) : Float32
      best = nil
      a.circles.each do |ca|
        b.circles.each do |cb|
          d = ca - cb
          dist = d.length
          rr = a.spec.radius + b.spec.radius
          next if dist >= rr
          if best.nil? || rr - dist > best[1]
            best = {dist > 1e-4 ? d / dist : Vec2.new(1, 0), rr - dist, ca, cb}
          end
        end
      end
      return 0_f32 unless best
      n, depth, ca, cb = best
      ima = 1 / a.spec.mass; imb = 1 / b.spec.mass
      a.pos += n * (depth * ima / (ima + imb))
      b.pos -= n * (depth * imb / (ima + imb))
      vrel = (a.vel - b.vel).dot(n)
      return 0_f32 if vrel >= 0
      j = -(1 + 0.3_f32) * vrel / (ima + imb)
      a.vel += n * (j * ima)
      b.vel -= n * (j * imb)
      a.spin += Joyride.yaw_cross(ca - a.pos, n * j) * 0.08_f32 * ima
      b.spin -= Joyride.yaw_cross(cb - b.pos, n * j) * 0.08_f32 * imb
      -vrel
    end
  end

  # A path along the road network, consumed as a car drives it.
  class RoutePath
    getter points = [] of Vec2

    def empty? : Bool
      @points.size < 2
    end

    def clear : Nil
      @points.clear
    end

    def append(pts : Array(Vec2)) : Nil
      pts.each { |p| @points << p unless (l = @points.last?) && l.distance(p) < 0.05 }
    end

    def remaining : Float32
      l = 0_f32
      (1...@points.size).each { |i| l += @points[i - 1].distance(@points[i]) }
      l
    end

    # Drops points the car has passed (closest segment search near the start).
    def advance(pos : Vec2) : Nil
      return if @points.size < 2
      best = 0; best_d = Float32::INFINITY
      Math.min(@points.size - 1, 12).times do |i|
        d = Joyride.segment_distance(@points[i], @points[i + 1], pos)
        if d < best_d
          best_d = d; best = i
        end
      end
      @points.shift(best) if best > 0
    end

    # The point *dist* along the path from the projection of *pos*.
    def lookahead(pos : Vec2, dist : Float32) : Vec2
      return @points.last? || pos if @points.size < 2
      a = @points[0]; b = @points[1]
      ab = b - a
      t = ((pos - a).dot(ab) / Math.max(ab.length_squared, 1e-6_f32)).clamp(0_f32, 1_f32)
      cur = a + ab * t
      left = dist
      i = 1
      while i < @points.size
        seg = @points[i] - cur
        l = seg.length
        return cur + seg * (left / l) if l >= left && l > 0
        left -= l
        cur = @points[i]
        i += 1
      end
      cur
    end
  end

  # Builds lane-following paths through the road graph: straight on, or turning at nodes.
  module Lanes
    # A path from the node of *a* to the node of *b* (adjacent chunks), offset to the right lane
    # and trimmed so it can be joined with turn curves at the intersections.
    def self.leg(world : World, a : {Int32, Int32}, b : {Int32, Int32}, lane : Bool = true) : Array(Vec2)
      center = world.leg(a, b)
      hw = world.arms(*a).max_of(&.half_width)
      off = lane ? Joyride.lane_offset(Math.min(hw, world.arms(*b).max_of(&.half_width))) : 0_f32
      pts = offset(center, off)
      trim_a = world.arms(*a).max_of(&.half_width) + 1
      trim_b = world.arms(*b).max_of(&.half_width) + 1
      na = world.node(*a); nb = world.node(*b)
      pts = pts.select { |p| p.distance(na) > trim_a && p.distance(nb) > trim_b }
      pts.size >= 2 ? pts : [center.first, center.last]
    end

    def self.offset(pts : Array(Vec2), off : Float32) : Array(Vec2)
      return pts.dup if off == 0
      pts.map_with_index do |p, i|
        d = (pts[Math.min(i + 1, pts.size - 1)] - pts[Math.max(i - 1, 0)]).normalized
        p + Vec2.new(-d.y, d.x) * off
      end
    end

    # Smooth curve joining the end of one leg to the start of the next.
    def self.junction(p : Vec2, pd : Vec2, q : Vec2, qd : Vec2) : Array(Vec2)
      k = Math.max(p.distance(q) * 0.5_f32, 4_f32)
      c1 = p + pd * k; c2 = q - qd * k
      (1..7).map { |i| Joyride.bezier(p, c1, c2, q, i / 8_f32) }
    end

    # Picks the next chunk from *cur*, avoiding a U-turn unless it is a dead end.
    def self.next_chunk(world : World, cur : {Int32, Int32}, came_from : {Int32, Int32}?, rng : Rng) : {Int32, Int32}?
      nbs = world.neighbors(*cur)
      return nil if nbs.empty?
      opts = nbs.reject { |n| n == came_from }
      opts = nbs if opts.empty?
      rng.pick(opts)
    end
  end

  # Wanders the road network, appending legs and turns as the path runs short.
  class Wanderer
    getter path = RoutePath.new
    getter cur : {Int32, Int32}
    getter prev : {Int32, Int32}?
    @rng : Rng

    def initialize(@cur, @prev = nil, seed : UInt64 = 1_u64)
      @rng = Rng.new(seed)
    end

    def extend(world : World, min_length : Float32 = 80_f32) : Nil
      guard = 0
      while @path.remaining < min_length && guard < 8
        guard += 1
        nxt = Lanes.next_chunk(world, @cur, @prev, @rng)
        break unless nxt
        leg = Lanes.leg(world, @cur, nxt)
        if (last = @path.points.last?) && @path.points.size >= 2
          pd = (last - @path.points[-2]).normalized
          qd = (leg[1] - leg[0]).normalized
          @path.append(Lanes.junction(last, pd, leg[0], qd))
        end
        @path.append(leg)
        @prev = @cur
        @cur = nxt
      end
    end
  end

  # Steers a physical car along a path (pure pursuit) with speed control and unsticking.
  class Pilot
    property target_speed : Float32 = 20_f32
    @stuck = 0_f32
    @reversing = 0_f32

    def drive(car : Car, path : RoutePath, dt : Float32, chase : Vec2? = nil) : Nil
      path.advance(car.pos)
      speed = car.forward_speed
      look = path.lookahead(car.pos, 7_f32 + speed.abs * 0.45_f32)
      look = chase if chase
      to = look - car.pos
      ang = to.length > 0.1 ? Math.atan2(Joyride.yaw_cross(car.forward, to), car.forward.dot(to)).to_f32 : 0_f32
      car.clear_inputs
      if @reversing > 0
        @reversing -= dt
        car.brake = 1_f32
        car.steer_input = ang > 0 ? 1_f32 : -1_f32
        return
      end
      # steer toward the lookahead (positive angle is to the left, steering right is positive)
      car.steer_input = (-ang * 2.2_f32).clamp(-1_f32, 1_f32)
      # slow for curves ahead
      far = path.lookahead(car.pos, 25_f32 + speed * 0.8_f32)
      bend = (far - car.pos).normalized.dot(car.forward)
      want = @target_speed * (bend > 0.9 ? 1_f32 : Math.max(0.35_f32, bend))
      want = Math.min(want, @target_speed * 0.5_f32) if ang.abs > 0.6
      if speed < want
        car.throttle = speed < want - 2 ? 1_f32 : 0.5_f32
      elsif speed > want + 3
        car.brake = ((speed - want) / 8).clamp(0.2_f32, 1_f32)
      end
      car.handbrake = ang.abs > 1.2 && speed > 12
      if speed.abs < 1 && car.throttle > 0
        @stuck += dt
        if @stuck > 1.5
          @stuck = 0_f32; @reversing = 1.2_f32
        end
      else
        @stuck = 0_f32
      end
    end
  end

  # A civilian car that keeps to its lane, brakes for whatever is ahead, and gets knocked
  # around (then gives up) when rammed.
  class TrafficCar
    getter car : Car
    getter wanderer : Wanderer
    getter color_index : Int32
    getter? wrecked = false
    property honk = 0_f32
    @speed = 0_f32
    @blocked = 0_f32
    @ignore_ai = 0_f32
    @wreck_time = 0_f32

    def initialize(world : World, cur : {Int32, Int32}, prev : {Int32, Int32}?, seed : UInt64, @color_index = 0)
      @wanderer = Wanderer.new(cur, prev, seed)
      @wanderer.extend(world, 120_f32)
      pts = @wanderer.path.points
      start = pts.first? || world.node(*cur)
      dir = pts.size > 1 ? (pts[1] - pts[0]).normalized : Vec2.new(0, -1)
      @car = Car.new(start, Joyride.heading_of(dir), TRAFFIC_SPEC)
      @speed = 8_f32
    end

    def position : Vec2
      @car.pos
    end

    # Knocks this car out of traffic. It slides to a stop and stays put.
    def wreck! : Nil
      @wrecked = true
    end

    # *others* are positions + velocities of cars to keep a distance from; player first.
    def update(dt : Float32, world : World, player : Car, others : Array(TrafficCar)) : Nil
      if @wrecked
        @wreck_time += dt
        @car.clear_inputs
        @car.brake = 0.3_f32
        @car.step(dt, world)
        return
      end
      @wanderer.extend(world)
      path = @wanderer.path
      path.advance(@car.pos)
      dir = @car.forward
      side = @car.right
      # how fast may we go: road type, curves ahead, obstacles ahead
      cx, cz = World.chunk_of(@car.pos)
      want = world.zone(cx, cz).country? ? 19_f32 : 12_f32
      far = path.lookahead(@car.pos, 18)
      bend = (far - @car.pos).normalized.dot(dir)
      want *= Math.max(0.45_f32, bend) if bend < 0.95
      clear_ahead = ->(p : Vec2, v : Vec2) do
        rel = p - @car.pos
        ahead = rel.dot(dir)
        if ahead < 0 || ahead > 26 || rel.dot(side).abs > 2.4
          Float32::INFINITY
        else
          ahead
        end
      end
      gap = clear_ahead.call(player.pos, player.vel)
      player_block = gap < 26
      @ignore_ai -= dt
      if @ignore_ai <= 0
        others.each do |o|
          next if o.same?(self)
          g = clear_ahead.call(o.car.pos, o.car.vel)
          gap = Math.min(gap, g)
        end
      end
      if gap < 26
        want = Math.min(want, Math.max(0_f32, (gap - 6.5_f32) * 0.9_f32))
      end
      if want < 0.5 && gap < 12
        @blocked += dt
        if player_block && @blocked > 2
          @honk = 1_f32 if @honk <= 0
        elsif !player_block && @blocked > 3
          @ignore_ai = 2_f32; @blocked = 0_f32 # nudge through a standoff
        end
      else
        @blocked = 0_f32
      end
      acc = want > @speed ? 4_f32 : 9_f32
      @speed = Mathf.move_toward(@speed, want, acc * dt).to_f32
      # move exactly along the lane
      target = path.lookahead(@car.pos, Math.max(@speed * dt, 0.001_f32))
      step = target - @car.pos
      if step.length > 1e-4
        @car.vel = step / dt
        @car.pos = target
        head_to = path.lookahead(@car.pos, 3)
        if head_to.distance(@car.pos) > 0.2
          @car.heading = Mathf.lerp_angle(@car.heading, Joyride.heading_of(head_to - @car.pos), Math.min(1_f32, dt * 10)).to_f32
        end
      else
        @car.vel = Vec2::ZERO
      end
      @honk -= dt if @honk > 0
    end
  end

  # Pedestrians stroll along sidewalks, dive away from cars, and get knocked down if hit.
  class Pedestrian
    enum State
      Walking
      Dodging
      Down
    end

    getter pos : Vec2
    getter heading : Float32 = 0_f32
    getter state = State::Walking
    getter shirt : Color
    getter pants : Color
    getter phase : Float32 = 0_f32
    property fly : Vec2 = Vec2::ZERO
    @a : Vec2
    @b : Vec2
    @toward_b = true
    @timer = 0_f32
    @dodge = Vec2::ZERO
    @speed : Float32

    def initialize(@a : Vec2, @b : Vec2, t : Float32, @shirt : Color, @pants : Color, @speed = 1.4_f32)
      @pos = @a + (@b - @a) * t
    end

    def down? : Bool
      @state.down?
    end

    # Returns true when this pedestrian was just knocked down by a car.
    def update(dt : Float32, cars : Array(Car)) : Bool
      @phase += dt * @speed * 5
      case @state
      in .down?
        @timer -= dt
        @pos += @fly * dt
        @fly *= Math.exp(-4 * dt).to_f32
        @state = State::Walking if @timer <= 0
        return false
      in .dodging?
        @timer -= dt
        @pos += @dodge * dt
        @state = State::Walking if @timer <= 0
      in .walking?
        goal = @toward_b ? @b : @a
        d = goal - @pos
        if d.length < 0.3
          @toward_b = !@toward_b
        else
          dir = d.normalized
          @pos += dir * (@speed * dt)
          @heading = Joyride.heading_of(dir)
        end
      end
      cars.each do |car|
        rel = @pos - car.pos
        dist = rel.length
        spd = car.speed
        if dist < 2.1 && spd > 3
          # hit: thrown along the car's motion
          @state = State::Down
          @timer = 4_f32
          @fly = car.vel * 0.6_f32 + rel.normalized * 2
          return true
        end
        if @state.walking? && spd > 4 && dist < 12 && car.vel.dot(rel) > 0
          # the car is coming at us: jump sideways out of its path
          side = Vec2.new(-car.vel.y, car.vel.x).normalized
          side = -side if side.dot(rel) < 0
          @dodge = side * 5
          @state = State::Dodging
          @timer = 0.6_f32
          @heading = Joyride.heading_of(side)
        end
      end
      false
    end
  end

  # One mission: reach a sequence of targets, some needing a full stop, within a time limit.
  class Mission
    enum Kind
      Delivery
      Race
    end

    enum State
      Active
      Complete
      Failed
    end

    record Target, pos : Vec2, radius : Float32, stop : Bool, label : String

    getter kind : Kind
    getter targets : Array(Target)
    getter index = 0
    getter state = State::Active
    getter time_left : Float32?
    getter reward = 0
    getter route_length : Float32
    @stop_timer = 0_f32

    def initialize(@kind, @targets, @route_length, @time_left = nil); end

    def target : Target?
      @targets[@index]?
    end

    def done? : Bool
      !@state.active?
    end

    def title : String
      case @kind
      in .delivery? then @index == 0 ? "Pick up the package" : "Deliver the package"
      in .race?     then "Checkpoint race #{Math.min(@index + 1, @targets.size)}/#{@targets.size}"
      end
    end

    # Advances timers and checks the car against the current target.
    # Returns :checkpoint, :complete, :failed or nil.
    def update(dt : Float32, pos : Vec2, speed : Float32) : Symbol?
      return nil unless @state.active?
      if t = @time_left
        t -= dt
        @time_left = t
        if t <= 0
          @time_left = 0_f32
          @state = State::Failed
          return :failed
        end
      end
      tg = target.not_nil!
      inside = pos.distance(tg.pos) <= tg.radius
      if inside && tg.stop
        # must come to a (near) stop inside the marker
        @stop_timer = speed < 4 ? @stop_timer + dt : 0_f32
        inside = @stop_timer >= 0.3
      end
      return nil unless inside
      @stop_timer = 0_f32
      @index += 1
      if @index >= @targets.size
        @state = State::Complete
        @reward = compute_reward
        return :complete
      end
      if @kind.delivery? && @index == 1
        # the clock starts once the package is on board
        @time_left = (@route_length / 13_f32 + 25).round.to_f32
      end
      :checkpoint
    end

    private def compute_reward : Int32
      bonus = ((@time_left || 0_f32) * 10).to_i
      case @kind
      in .delivery? then 150 + (@route_length * 0.6).to_i + bonus
      in .race?     then 250 + (@route_length * 0.5).to_i + bonus * 2
      end
    end

    # Walks the road graph from the nearest node to *pos* and puts targets on the roads.
    def self.generate(world : World, pos : Vec2, kind : Kind, rng : Rng) : Mission
      start = world.nearest_node_chunk(pos) || World.chunk_of(pos)
      walk = [start]
      prev = nil.as({Int32, Int32}?)
      legs = kind.race? ? 7 + rng.int(3) : 9 + rng.int(4)
      seen = Set{start}
      legs.times do
        opts = world.neighbors(*walk.last).reject { |n| n == prev }
        fresh = opts.reject { |n| seen.includes?(n) }
        opts = fresh unless fresh.empty?
        break if opts.empty?
        nxt = rng.pick(opts)
        prev = walk.last
        walk << nxt
        seen << nxt
      end
      points = [] of Vec2
      (1...walk.size).each { |i| points.concat(world.leg(walk[i - 1], walk[i])) }
      points = [pos, world.node(*start)] if points.size < 2
      length = 0_f32
      (1...points.size).each { |i| length += points[i - 1].distance(points[i]) }
      # place targets partway along legs (never inside an intersection)
      spot = ->(i : Int32) do
        a = walk[Math.max(i - 1, 0)]; b = walk[Math.min(i, walk.size - 1)]
        pts = a == b ? [world.node(*a)] : world.leg(a, b)
        pts[pts.size // 2]
      end
      targets = [] of Target
      case kind
      in .delivery?
        pick = Math.max(1, Math.min(3, walk.size - 1))
        targets << Target.new(spot.call(pick), 7_f32, true, "pickup")
        targets << Target.new(spot.call(walk.size - 1), 7_f32, true, "dropoff")
        # the timed part is from the pickup to the drop-off
        tail = 0_f32
        (pick...walk.size - 1).each { |i| tail += world.leg(walk[i], walk[i + 1]).each_cons_pair.sum { |p, q| p.distance(q) } }
        return Mission.new(kind, targets, Math.max(tail, 60_f32))
      in .race?
        (1...walk.size).each { |i| targets << Target.new(spot.call(i), 10_f32, false, "checkpoint") }
        return Mission.new(kind, targets, length, (length / 17_f32 + 12).round.to_f32)
      end
    end
  end

  # Wanted level: crimes raise it, police hunt you, hiding lets it cool down.
  class Wanted
    MAX = 5
    getter level = 0
    getter cooldown = 0_f32
    @crime_cooldown = 0_f32

    def active? : Bool
      @level > 0
    end

    # Records a crime. Minor ones (fender benders) only count after a few of them.
    def crime!(severity : Int32 = 1) : Bool
      return false if @crime_cooldown > 0
      @crime_cooldown = 1.5_f32
      before = @level
      @level = Math.min(MAX, @level + severity)
      @cooldown = 0_f32
      @level > before
    end

    # *seen* is true while any police car is close to the player.
    # Returns true when the level just dropped.
    def update(dt : Float32, seen : Bool) : Bool
      @crime_cooldown -= dt if @crime_cooldown > 0
      return false if @level == 0
      if seen
        @cooldown = 0_f32
        return false
      end
      @cooldown += dt
      if @cooldown >= 10
        @cooldown = 0_f32
        @level -= 1
        return true
      end
      false
    end

    def clear : Nil
      @level = 0; @cooldown = 0_f32
    end

    # How many police cars should be on the player's tail.
    def police_count : Int32
      Math.min(@level, 4)
    end
  end
end
