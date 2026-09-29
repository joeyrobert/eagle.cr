require "../../src/eagle/math/math"

# Renderer-independent rules for Boost Ball, a rocket-powered car soccer game: the arena, the ball and
# the cars. Specs drive these files without opening a window.
module EagleRocketBall
  include Eagle

  HALF_W      = 28_f32
  HALF_L      = 42_f32
  HEIGHT      = 18_f32
  GOAL_HALF_W =  7_f32
  GOAL_HEIGHT =  6_f32
  GOAL_DEPTH  =  6_f32
  CORNER      =  8_f32
  WALL_T      =  8_f32

  BALL_RADIUS     = 1.8_f32
  MAX_BALL_SPEED  =  60_f32
  GRAVITY         =  22_f32
  CAR_HALF        = Vec3.new(1.05, 0.55, 2.2)
  CAR_RIDE        = 0.62_f32
  CAR_RADIUS      =  1.5_f32
  MAX_GROUND      =   26_f32
  MAX_BOOST_SPEED =   40_f32
  SUPERSONIC      =   37_f32
  BOOST_USE       = 33.3_f32
  JUMP_SPEED      =   10_f32
  DODGE_WINDOW    =  1.4_f32
  DODGE_TIME      = 0.55_f32

  # An axis-aligned solid the ball and cars bounce off.
  record Box, min : Vec3, max : Vec3

  # Something that moves and bounces: shared by the ball and the cars.
  abstract class Body
    property pos : Vec3 = Vec3::ZERO
    property vel : Vec3 = Vec3::ZERO
    # The hardest hit against the arena during the last collision pass, and what it hit (1 floor, 2 wall or ceiling).
    property impact : Float32 = 0_f32
    property impact_kind : Int32 = 0
  end

  module Arena
    @@boxes = [] of Box

    # The solid boxes around the pitch: side walls, end walls with the goal mouth cut out, goal nets and crossbars.
    def self.boxes : Array(Box)
      return @@boxes unless @@boxes.empty?
      t = WALL_T
      h = HEIGHT + t
      @@boxes << Box.new(Vec3.new(HALF_W, -t, -HALF_L), Vec3.new(HALF_W + t, h, HALF_L))
      @@boxes << Box.new(Vec3.new(-HALF_W - t, -t, -HALF_L), Vec3.new(-HALF_W, h, HALF_L))
      {-1, 1}.each do |s|
        far = HALF_L + GOAL_DEPTH + t
        lo, hi = s > 0 ? {HALF_L, far} : {-far, -HALF_L}
        @@boxes << Box.new(Vec3.new(-HALF_W - t, -t, lo), Vec3.new(-GOAL_HALF_W, h, hi))
        @@boxes << Box.new(Vec3.new(GOAL_HALF_W, -t, lo), Vec3.new(HALF_W + t, h, hi))
        @@boxes << Box.new(Vec3.new(-GOAL_HALF_W, GOAL_HEIGHT, lo), Vec3.new(GOAL_HALF_W, h, hi))
        back_lo, back_hi = s > 0 ? {HALF_L + GOAL_DEPTH, far} : {-far, -(HALF_L + GOAL_DEPTH)}
        @@boxes << Box.new(Vec3.new(-GOAL_HALF_W, -t, back_lo), Vec3.new(GOAL_HALF_W, h, back_hi))
      end
      @@boxes
    end

    # Pushes a sphere of *r* out of the floor, ceiling, walls and corner bevels, bouncing it with *e* and keeping *keep* of its sliding speed.
    def self.collide(b : Body, r : Float32, e : Float32, keep : Float32, floor : Bool = true) : Nil
      b.impact = 0
      b.impact_kind = 0
      contact(b, Vec3::UP, r - b.pos.y, e, keep, 1) if floor && b.pos.y < r
      contact(b, -Vec3::UP, b.pos.y - (HEIGHT - r), e, keep, 2) if b.pos.y > HEIGHT - r
      boxes.each do |box|
        c = Vec3.new(b.pos.x.clamp(box.min.x, box.max.x), b.pos.y.clamp(box.min.y, box.max.y), b.pos.z.clamp(box.min.z, box.max.z))
        d = b.pos - c
        d2 = d.length_squared
        next if d2 >= r * r
        if d2 > 1e-6
          dist = Math.sqrt(d2).to_f32
          contact(b, d / dist, r - dist, e, keep, 2)
        else
          # The center is inside the box: leave through the nearest face.
          faces = [{b.pos.x - box.min.x, Vec3.new(-1, 0, 0)}, {box.max.x - b.pos.x, Vec3.new(1, 0, 0)}, {b.pos.z - box.min.z, Vec3.new(0, 0, -1)}, {box.max.z - b.pos.z, Vec3.new(0, 0, 1)}]
          nearest = faces.min_by { |f| f[0] }
          contact(b, nearest[1], nearest[0] + r, e, keep, 2)
        end
      end
      {-1, 1}.each do |sx|
        {-1, 1}.each do |sz|
          n = Vec3.new(-sx, 0, -sz) * 0.70710677_f32
          dist = n.dot(b.pos - Vec3.new(sx * (HALF_W - CORNER), 0, sz * HALF_L))
          contact(b, n, r - dist, e, keep, 2) if dist < r && corner_zone?(b.pos, sx, sz)
        end
      end
    end

    # True when a point is on the pitch side of a corner bevel's own quadrant, so bevels never touch the goal mouths.
    def self.corner_zone?(p : Vec3, sx : Int32, sz : Int32) : Bool
      p.x * sx > HALF_W - CORNER - 4 && p.z * sz > HALF_L - CORNER - 4 && p.z.abs <= HALF_L + 2
    end

    private def self.contact(b : Body, n : Vec3, depth : Float32, e : Float32, keep : Float32, kind : Int32) : Nil
      b.pos += n * depth
      vn = b.vel.dot(n)
      return unless vn < 0
      speed = -vn
      if speed > b.impact
        b.impact = speed
        b.impact_kind = kind
      end
      rebound = speed * e
      rebound = 0_f32 if rebound < 1.2
      b.vel = (b.vel - n * vn) * keep + n * rebound
    end
  end

  class Ball < Body
    property radius : Float32 = BALL_RADIUS
    property last_touch : Car? = nil
    # Visual rolling, as an orientation the renderer can apply.
    property roll : Quat = Quat::IDENTITY

    def initialize(@radius : Float32 = BALL_RADIUS); end

    def step(dt : Float32, gravity : Float32 = GRAVITY) : Nil
      @vel = Vec3.new(@vel.x, @vel.y - gravity * dt, @vel.z)
      speed = @vel.length
      @vel = @vel * (MAX_BALL_SPEED / speed) if speed > MAX_BALL_SPEED
      @pos += @vel * dt
      Arena.collide(self, @radius, 0.62_f32, 0.985_f32)
      if @pos.y <= @radius + 0.01
        @vel = Vec3.new(@vel.x, 0, @vel.z) if @vel.y.abs < 0.6
        @vel = Vec3.new(@vel.x * (1 - 0.3_f32 * dt), @vel.y, @vel.z * (1 - 0.3_f32 * dt))
      end
      horizontal = Vec3.new(@vel.x, 0, @vel.z)
      if horizontal.length > 0.05
        axis = Vec3::UP.cross(horizontal).normalized
        @roll = (Quat.from_axis_angle(axis, horizontal.length * dt / @radius) * @roll).normalized
      end
    end

    # Where the ball will be, and how fast it moves, *seconds* from now if nothing touches it.
    def predict(seconds : Float32, gravity : Float32 = GRAVITY, step : Float32 = 1_f32 / 30) : {Vec3, Vec3}
      ghost = Ball.new(@radius)
      ghost.pos = @pos
      ghost.vel = @vel
      t = 0_f32
      while t < seconds
        ghost.step(step, gravity)
        t += step
      end
      {ghost.pos, ghost.vel}
    end
  end

  # What a driver asks of a car this instant: the keyboard, a gamepad or a bot fills this in.
  class Controls
    property throttle : Float32 = 0_f32
    property steer : Float32 = 0_f32
    property roll : Float32 = 0_f32
    property? jump = false
    property? boost = false
    property? handbrake = false

    def clear : Nil
      @throttle = 0
      @steer = 0
      @roll = 0
      @jump = false
      @boost = false
      @handbrake = false
    end
  end

  class Car < Body
    getter team : Int32
    getter slot : Int32
    property name : String
    property? human = false
    property orient : Quat = Quat::IDENTITY
    property boost : Float32 = 33_f32
    property? grounded = true
    property controls = Controls.new
    property demolished_for : Float32 = 0_f32
    property? boosting = false
    property dodge_left : Float32 = 0_f32
    property dodge_hit_left : Float32 = 0_f32
    property air_time : Float32 = 0_f32
    property? touching_ball = false
    property flip_events : Int32 = 0
    # Scoreboard.
    property goals : Int32 = 0
    property assists : Int32 = 0
    property saves : Int32 = 0
    property shots : Int32 = 0
    property demos : Int32 = 0
    property touches : Int32 = 0

    @heading = 0_f32
    @spin = Vec3::ZERO
    @jump_prev = false
    @jump_age = 0_f32
    @air_jumps = 0
    @jump_hold = 0_f32
    @dodge_axis = Vec3::ZERO

    def initialize(@team : Int32, @slot : Int32, @name : String = "Car", @human = false); end

    def score : Int32
      @goals * 100 + @assists * 50 + @saves * 50 + @shots * 20 + @demos * 25 + @touches * 2
    end

    def forward : Vec3
      @orient * Vec3::FORWARD
    end

    def up : Vec3
      @orient * Vec3::UP
    end

    def right : Vec3
      @orient * Vec3::RIGHT
    end

    def speed : Float32
      @vel.length
    end

    def supersonic? : Bool
      speed >= SUPERSONIC
    end

    def demolished? : Bool
      @demolished_for > 0
    end

    def can_dodge? : Bool
      !@grounded && @air_jumps > 0 && @jump_age < DODGE_WINDOW
    end

    def dodging? : Bool
      @dodge_left > 0
    end

    # Faces a heading (radians about the vertical axis, 0 looks down -Z) and stands the car on its wheels.
    def face(heading : Float32) : Nil
      @heading = heading
      @orient = Quat.from_axis_angle(Vec3::UP, heading)
      @spin = Vec3::ZERO
    end

    def heading : Float32
      @heading
    end

    def spawn(at : Vec3, heading : Float32, boost : Float32 = 33_f32) : Nil
      @pos = Vec3.new(at.x, CAR_RIDE, at.z)
      @vel = Vec3::ZERO
      @grounded = true
      @boost = boost
      @demolished_for = 0
      @dodge_left = 0
      @air_jumps = 0
      @boosting = false
      face(heading)
    end

    def demolish(seconds : Float32 = 3_f32) : Nil
      @demolished_for = seconds
      @boosting = false
      @vel = Vec3::ZERO
    end

    def add_boost(amount : Number) : Nil
      @boost = Math.min(100_f32, @boost + amount.to_f32)
    end

    def step(dt : Float32, gravity : Float32 = GRAVITY, unlimited_boost : Bool = false) : Nil
      if @demolished_for > 0
        @demolished_for = Math.max(0_f32, @demolished_for - dt)
        return
      end
      c = @controls
      edge = c.jump? && !@jump_prev
      @jump_prev = c.jump?
      can_boost = c.boost? && (@boost > 0 || unlimited_boost)
      @boosting = can_boost
      @boost = Math.max(0_f32, @boost - BOOST_USE * dt) if can_boost && !unlimited_boost
      @dodge_hit_left = Math.max(0_f32, @dodge_hit_left - dt)
      if @grounded
        drive(dt, edge, can_boost)
      else
        fly(dt, gravity, edge, can_boost)
      end
      Arena.collide(self, CAR_RADIUS, 0.25_f32, 0.98_f32, floor: false)
      if @grounded
        @pos = Vec3.new(@pos.x, CAR_RIDE, @pos.z)
      end
    end

    private def flat_forward : Vec3
      f = forward
      flat = Vec3.new(f.x, 0, f.z)
      flat.length > 0.3 ? flat.normalized : Vec3.new(-Math.sin(@heading), 0, -Math.cos(@heading))
    end

    private def drive(dt : Float32, jump_edge : Bool, can_boost : Bool) : Nil
      c = @controls
      fwd = Vec3.new(-Math.sin(@heading), 0, -Math.cos(@heading))
      rgt = Vec3.new(Math.cos(@heading), 0, -Math.sin(@heading))
      fs = @vel.dot(fwd)
      ls = @vel.dot(rgt)
      if can_boost
        fs += 42_f32 * dt
        fs = Math.min(fs, MAX_BOOST_SPEED)
      elsif c.throttle.abs > 0.01
        if c.throttle * fs >= -0.1
          fs += c.throttle * 26_f32 * (1 - (fs.abs / MAX_GROUND).clamp(0_f32, 1_f32)) * dt
        else
          fs += c.throttle * 55_f32 * dt
        end
      else
        fs -= fs.sign * Math.min(fs.abs, 7_f32 * dt)
      end
      fs -= fs.sign * Math.min(fs.abs - MAX_GROUND, 9_f32 * dt) if fs.abs > MAX_GROUND && !can_boost
      ls *= Math.exp(-(c.handbrake? ? 1.3_f32 : 14_f32) * dt).to_f32
      fs *= Math.exp(-0.5_f32 * dt).to_f32 if c.handbrake?
      authority = (fs.abs / 4).clamp(0_f32, 1_f32)
      rate = 2.9_f32 * (1 - 0.5_f32 * (fs.abs / MAX_BOOST_SPEED).clamp(0_f32, 1_f32)) * (c.handbrake? ? 1.7_f32 : 1_f32)
      @heading += -c.steer * rate * authority * (fs >= 0 ? 1_f32 : -1_f32) * dt
      @vel = fwd * fs + rgt * ls
      @pos += @vel * dt
      @orient = Quat.from_axis_angle(Vec3::UP, @heading)
      @spin = Vec3::ZERO
      @air_time = 0
      @dodge_left = 0
      if jump_edge
        @vel = Vec3.new(@vel.x, JUMP_SPEED, @vel.z)
        @grounded = false
        @jump_age = 0
        @jump_hold = 0.2_f32
        @air_jumps = 1
        @flip_events += 1
      end
    end

    private def fly(dt : Float32, gravity : Float32, jump_edge : Bool, can_boost : Bool) : Nil
      c = @controls
      @air_time += dt
      @jump_age += dt
      if @dodge_left > 0
        @dodge_left = Math.max(0_f32, @dodge_left - dt)
        @orient = (@orient * Quat.from_axis_angle(@dodge_axis, Math::TAU.to_f32 / DODGE_TIME * dt)).normalized
      else
        target = Vec3.new(-c.throttle * 5_f32, -c.steer * 4_f32, c.roll * 5.5_f32)
        @spin = @spin.lerp(target, 1 - Math.exp(-12_f32 * dt).to_f32)
        turn = @spin * dt
        angle = turn.length
        @orient = (@orient * Quat.from_axis_angle(turn / angle, angle)).normalized if angle > 1e-5
      end
      if @jump_hold > 0
        @jump_hold -= dt
        @vel += up * (c.jump? ? 16_f32 : 0_f32) * dt
      end
      @vel += forward * 40_f32 * dt if can_boost
      speed = @vel.length
      @vel = @vel * (MAX_BOOST_SPEED / speed) if speed > MAX_BOOST_SPEED + 6
      @vel = Vec3.new(@vel.x, @vel.y - gravity * dt, @vel.z)
      if jump_edge && can_dodge?
        @air_jumps = 0
        @jump_hold = 0
        input = Vec2.new(c.steer, c.throttle)
        if input.length > 0.5
          d = input.normalized
          flat = flat_forward
          side = Vec3.new(-flat.z, 0, flat.x)
          @vel += (flat * d.y + side * d.x) * 12_f32
          @vel = Vec3.new(@vel.x, @vel.y * 0.3_f32 + 1.5_f32, @vel.z)
          @dodge_axis = Vec3.new(-d.y, 0, -d.x).normalized
          @dodge_left = DODGE_TIME
          @dodge_hit_left = 0.32_f32
        else
          @vel = Vec3.new(@vel.x, Math.max(@vel.y, 0_f32) + 9_f32, @vel.z)
        end
        @flip_events += 1
      end
      @pos += @vel * dt
      if @pos.y > HEIGHT - 1
        @pos = Vec3.new(@pos.x, HEIGHT - 1, @pos.z)
        @vel = Vec3.new(@vel.x, Math.min(@vel.y, 0_f32), @vel.z)
      end
      if @pos.y <= CAR_RIDE && @vel.y <= 0
        land
      end
    end

    # Touching down always ends up on the wheels, facing wherever the nose pointed.
    private def land : Nil
      f = forward
      flat = Vec3.new(f.x, 0, f.z)
      @heading = Math.atan2(-flat.x, -flat.z).to_f32 if flat.length > 0.3
      @orient = Quat.from_axis_angle(Vec3::UP, @heading)
      @pos = Vec3.new(@pos.x, CAR_RIDE, @pos.z)
      @vel = Vec3.new(@vel.x, 0, @vel.z)
      @grounded = true
      @dodge_left = 0
      @spin = Vec3::ZERO
      @air_jumps = 0
    end

    # True when a sphere at *center* with *radius* overlaps the car's hitbox, with the push-out normal and depth.
    def hit_sphere(center : Vec3, radius : Float32) : {Vec3, Float32}?
      local = @orient.conjugate * (center - @pos)
      closest = Vec3.new(local.x.clamp(-CAR_HALF.x, CAR_HALF.x), local.y.clamp(-CAR_HALF.y, CAR_HALF.y), local.z.clamp(-CAR_HALF.z, CAR_HALF.z))
      d = local - closest
      d2 = d.length_squared
      return nil if d2 >= radius * radius
      if d2 < 1e-6
        return {@orient * Vec3::UP, radius}
      end
      dist = Math.sqrt(d2).to_f32
      {(@orient * (d / dist)).normalized, radius - dist}
    end
  end
end
