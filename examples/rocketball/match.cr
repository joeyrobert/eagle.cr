require "./physics"
require "./bot"

module EagleRocketBall
  enum BoostMode
    Normal
    Unlimited
    Off
  end

  enum Phase
    Countdown
    Playing
    Goal
    Replay
    Finished
  end

  enum EventKind
    Countdown
    Kickoff
    Touch
    Bounce
    Goal
    Pad
    Jump
    Dodge
    Demo
    Save
    Overtime
    Whistle
  end

  record MatchEvent, kind : EventKind, pos : Vec3 = Vec3::ZERO, value : Float32 = 0_f32, team : Int32 = -1, car : Car? = nil

  # What a match is made of. The title screen's background match uses `human = false`.
  class MatchConfig
    property team_size : Int32 = 2
    property difficulty : Difficulty = Difficulty::Pro
    property minutes : Int32 = 3
    property boost_mode : BoostMode = BoostMode::Normal
    property ball_scale : Float32 = 1_f32
    property gravity_scale : Float32 = 1_f32
    property? human = true
    property? training = false
    property seed : Int32 = 1
  end

  class Pad
    getter pos : Vec3
    getter? big : Bool
    property timer : Float32 = 0_f32

    def initialize(@pos : Vec3, @big : Bool); end

    def active? : Bool
      @timer <= 0
    end

    def radius : Float32
      big? ? 3_f32 : 1.8_f32
    end

    def amount : Float32
      big? ? 100_f32 : 12_f32
    end

    def cooldown : Float32
      big? ? 10_f32 : 4_f32
    end
  end

  record CarSnap, pos : Vec3, orient : Quat, boosting : Bool, visible : Bool
  record Snapshot, ball : Vec3, roll : Quat, cars : Array(CarSnap)

  BLUE_NAMES   = ["You", "Nova", "Comet", "Vega"]
  ORANGE_NAMES = ["Blaze", "Ember", "Cinder", "Flare"]

  class Match
    TICK      = 1_f32 / 120
    GOAL_TIME = 2.6_f32
    HISTORY   =     150
    COUNTDOWN =   3_f32

    getter config : MatchConfig
    getter ball : Ball
    getter cars = [] of Car
    getter pads = [] of Pad
    getter bots = [] of Bot
    getter events = [] of MatchEvent
    getter phase = Phase::Countdown
    getter clock : Float32
    getter scores = [0, 0]
    getter countdown : Float32 = COUNTDOWN
    getter phase_time : Float32 = 0_f32
    getter? overtime = false
    getter last_goal_team : Int32 = -1
    getter last_scorer : Car? = nil
    getter last_assist : Car? = nil
    getter winner : Int32 = -1
    getter replay_index : Float32 = 0_f32
    getter elapsed : Float32 = 0_f32
    getter replay : Array(Snapshot) = [] of Snapshot
    @history = [] of Snapshot
    @accum = 0_f32
    @ticks = 0
    @time_up = false
    @last_count = 4
    @touch_log = [] of {Car, Float32}
    @rng : Random

    def initialize(@config : MatchConfig = MatchConfig.new)
      @rng = Random.new(@config.seed.to_u64)
      @ball = Ball.new(BALL_RADIUS * @config.ball_scale)
      @clock = @config.minutes * 60_f32
      build_cars
      build_pads
      kickoff
    end

    def human : Car?
      @cars.find(&.human?)
    end

    def gravity : Float32
      GRAVITY * @config.gravity_scale
    end

    def time_scale : Float32
      @phase.goal? || @phase.finished? ? 0.35_f32 : 1_f32
    end

    def training? : Bool
      @config.training?
    end

    def finished? : Bool
      @phase.finished?
    end

    def drain_events : Array(MatchEvent)
      out = @events.dup
      @events.clear
      out
    end

    # Advances the match by *dt* seconds of real time, in fixed physics ticks.
    def update(dt : Float32) : Nil
      @accum = Math.min(@accum + dt, 0.1_f32)
      while @accum >= TICK
        @accum -= TICK
        tick(TICK)
      end
    end

    # Lets a person skip the goal replay.
    def skip_replay : Nil
      finish_goal if @phase.replay?
    end

    def nearest_pad(from : Vec3, max_distance : Float32 = 40_f32) : Pad?
      return nil if @config.boost_mode != BoostMode::Normal
      best = nil
      best_score = max_distance
      @pads.each do |p|
        next unless p.active?
        d = Math.sqrt((p.pos.x - from.x) ** 2 + (p.pos.z - from.z) ** 2).to_f32 - (p.big? ? 8_f32 : 0_f32)
        if d < best_score
          best_score = d
          best = p
        end
      end
      best
    end

    # True when the ball, left alone, crosses the goal line of *team*'s own goal within *seconds*.
    def will_enter_goal?(team : Int32, seconds : Float32) : Bool
      own_z = team == 0 ? HALF_L : -HALF_L
      return false if (@ball.pos.z - own_z).abs > 38 && (@ball.vel.z * (team == 0 ? 1 : -1)) < 8
      return false if (@ball.vel.z * (team == 0 ? 1 : -1)) < -2
      ghost = Ball.new(@ball.radius)
      ghost.pos = @ball.pos
      ghost.vel = @ball.vel
      t = 0_f32
      step = 1_f32 / 30
      while t < seconds
        ghost.step(step, gravity)
        t += step
        return true if team == 0 ? ghost.pos.z > HALF_L + ghost.radius : ghost.pos.z < -HALF_L - ghost.radius
      end
      false
    end

    def kickoff_spot(team : Int32, index : Int32, size : Int32) : Vec3
      zk = HALF_L * 0.6_f32
      offsets = case size
                when 1 then [{0_f32, 0_f32}]
                when 2 then [{-9_f32, 0_f32}, {9_f32, 0_f32}]
                else        [{-10_f32, 1_f32}, {10_f32, 1_f32}, {0_f32, 9_f32}]
                end
      ox, oz = offsets[index % offsets.size]
      team == 0 ? Vec3.new(ox, 0, zk + oz) : Vec3.new(-ox, 0, -(zk + oz))
    end

    # Puts everything back for a kickoff, with the countdown running.
    def kickoff : Nil
      @ball.pos = Vec3.new(0, @ball.radius, 0)
      @ball.vel = Vec3::ZERO
      @ball.last_touch = nil
      @touch_log.clear
      @history.clear
      size = @config.training? ? 1 : @config.team_size
      {0, 1}.each do |team|
        @cars.select { |c| c.team == team }.each do |car|
          car.spawn(kickoff_spot(team, car.slot, size), team == 0 ? 0_f32 : Math::PI.to_f32, start_boost)
          car.touching_ball = false
        end
      end
      @pads.each { |p| p.timer = 0 }
      @phase = Phase::Countdown
      @countdown = @config.training? ? 1.2_f32 : COUNTDOWN
      @last_count = @countdown.ceil.to_i + 1
      @phase_time = 0
    end

    private def start_boost : Float32
      @config.boost_mode.off? ? 0_f32 : 33_f32
    end

    private def build_cars : Nil
      size = @config.training? ? 1 : @config.team_size
      teams = @config.training? ? {0} : {0, 1}
      teams.each do |team|
        size.times do |i|
          names = team == 0 ? BLUE_NAMES : ORANGE_NAMES
          human = team == 0 && i == 0 && @config.human?
          car = Car.new(team, i, human ? "You" : names[i % names.size], human)
          @cars << car
          @bots << Bot.new(car, @config.difficulty, Random.new((@config.seed + team * 31 + i * 7).to_u64)) unless human || @config.training?
        end
      end
    end

    private def build_pads : Nil
      big = [{25, 0}, {24, 36}]
      small = [{0, 36}, {9, 33}, {19, 27}, {7, 22}, {21, 13}, {10, 9}, {0, 0}, {13, 0}, {0, 14}]
      seen = Set({Int32, Int32}).new
      add = ->(x : Int32, z : Int32, is_big : Bool) do
        {-1, 1}.each do |sx|
          {-1, 1}.each do |sz|
            key = {x * sx, z * sz}
            next if seen.includes?(key)
            seen << key
            @pads << Pad.new(Vec3.new(x * sx, 0.05, z * sz), is_big)
          end
        end
      end
      big.each { |(x, z)| add.call(x.to_i, z.to_i, true) }
      small.each { |(x, z)| add.call(x, z, false) }
    end

    private def tick(dt : Float32) : Nil
      @elapsed += dt
      case @phase
      when .countdown?
        @phase_time += dt
        @countdown -= dt
        n = @countdown.ceil.to_i
        if n < @last_count && n >= 1
          @last_count = n
          @events << MatchEvent.new(EventKind::Countdown, value: n.to_f32)
        end
        if @countdown <= 0
          @phase = Phase::Playing
          @events << MatchEvent.new(EventKind::Kickoff)
        end
      when .playing?
        play(dt)
      when .goal?
        @phase_time += dt
        physics(dt * time_scale, freeze_controls: true)
        record if @phase_time < 0.9
        if @phase_time >= GOAL_TIME
          if @history.size >= 45 && !@config.training?
            start_replay
          else
            finish_goal
          end
        end
      when .replay?
        @replay_index += dt * 24
        finish_goal if @replay_index >= @replay.size - 1
      when .finished?
        @phase_time += dt
        physics(dt * time_scale, freeze_controls: true)
      end
    end

    private def play(dt : Float32) : Nil
      unless @config.training? || @overtime
        @clock = Math.max(0_f32, @clock - dt)
        @time_up = true if @clock <= 0
      end
      @bots.each(&.think(self, dt))
      physics(dt)
      @ticks += 1
      record if @ticks % 4 == 0
      check_goal
      if @time_up && @phase.playing? && @ball.pos.y <= @ball.radius + 0.4
        if @scores[0] != @scores[1]
          end_match
        else
          @overtime = true
          @time_up = false
          @events << MatchEvent.new(EventKind::Overtime)
        end
      end
    end

    private def physics(dt : Float32, freeze_controls : Bool = false) : Nil
      @cars.each do |car|
        car.controls.clear if freeze_controls
        car.controls.boost = false if @config.boost_mode.off?
        was_down = car.demolished?
        flips = car.flip_events
        car.step(dt, gravity, @config.boost_mode.unlimited?)
        if was_down && !car.demolished?
          side = car.team == 0 ? 1 : -1
          car.spawn(Vec3.new((@rng.rand.to_f32 - 0.5_f32) * 12, 0, side * (HALF_L - 6)), car.team == 0 ? 0_f32 : Math::PI.to_f32, start_boost)
        end
        if car.flip_events != flips
          @events << MatchEvent.new(car.dodging? ? EventKind::Dodge : EventKind::Jump, car.pos, car: car)
        end
      end
      collide_cars(dt)
      @ball.step(dt, gravity)
      if @ball.impact > 3 && @ball.pos.z.abs < HALF_L + 1
        @events << MatchEvent.new(EventKind::Bounce, @ball.pos, @ball.impact, car: nil)
      end
      @cars.each { |car| car_ball(car) }
      pickups(dt)
    end

    private def pickups(dt : Float32) : Nil
      @pads.each { |p| p.timer = Math.max(0_f32, p.timer - dt) if p.timer > 0 }
      return unless @config.boost_mode.normal?
      @cars.each do |car|
        next if car.demolished? || !car.grounded? && car.pos.y > 3
        @pads.each do |pad|
          next unless pad.active?
          dx = car.pos.x - pad.pos.x
          dz = car.pos.z - pad.pos.z
          next if dx * dx + dz * dz > pad.radius * pad.radius
          next if car.boost >= 100 && !pad.big?
          car.add_boost(pad.amount)
          pad.timer = pad.cooldown
          @events << MatchEvent.new(EventKind::Pad, pad.pos, pad.amount, car.team, car)
        end
      end
    end

    private def collide_cars(dt : Float32) : Nil
      @cars.each_with_index do |a, i|
        next if a.demolished?
        (i + 1...@cars.size).each do |j|
          b = @cars[j]
          next if b.demolished?
          d = b.pos - a.pos
          flat = Vec3.new(d.x, 0, d.z)
          dist = flat.length
          reach = CAR_RADIUS * 2
          next if dist >= reach || (d.y).abs > 1.8
          n = dist > 0.01 ? flat / dist : Vec3.new(1, 0, 0)
          # A supersonic hit on an opponent demolishes them.
          if a.team != b.team
            if a.supersonic? && (a.vel - b.vel).dot(n) > 14 && a.speed > b.speed
              demolish(a, b)
              next
            elsif b.supersonic? && (b.vel - a.vel).dot(-n) > 14 && b.speed > a.speed
              demolish(b, a)
              next
            end
          end
          overlap = reach - dist
          a.pos -= n * (overlap / 2)
          b.pos += n * (overlap / 2)
          rel = (b.vel - a.vel).dot(n)
          if rel < 0
            push = n * (rel * 0.7_f32)
            a.vel += push
            b.vel -= push
          end
        end
      end
    end

    private def demolish(attacker : Car, victim : Car) : Nil
      victim.demolish
      attacker.demos += 1
      @events << MatchEvent.new(EventKind::Demo, victim.pos, team: attacker.team, car: attacker)
    end

    private def car_ball(car : Car) : Nil
      if car.demolished?
        car.touching_ball = false
        return
      end
      hit = car.hit_sphere(@ball.pos, @ball.radius)
      unless hit
        car.touching_ball = false
        return
      end
      n, depth = hit
      @ball.pos += n * depth
      rel = @ball.vel - car.vel
      vn = rel.dot(n)
      first = !car.touching_ball?
      car.touching_ball = true
      return unless vn < 0
      before = first && defended_threat?(car)
      shot_before = first && attack_threat?(car)
      hn = Vec3.new(n.x, n.y * 0.5_f32, n.z).normalized
      @ball.vel += hn * (-vn * 1.55_f32)
      extra = Math.max(0_f32, car.vel.dot(hn)) * 0.3_f32
      extra += 10_f32 if car.dodge_hit_left > 0
      @ball.vel += hn * extra
      speed = @ball.vel.length
      @ball.vel = @ball.vel * (MAX_BALL_SPEED / speed) if speed > MAX_BALL_SPEED
      return unless first
      car.touches += 1
      car.dodge_hit_left = 0
      @touch_log << {car, @elapsed}
      @touch_log.shift if @touch_log.size > 8
      @ball.last_touch = car
      if before && !defended_threat?(car)
        car.saves += 1
        @events << MatchEvent.new(EventKind::Save, @ball.pos, team: car.team, car: car)
      end
      car.shots += 1 if !shot_before && attack_threat?(car)
      @events << MatchEvent.new(EventKind::Touch, @ball.pos, Math.min(1_f32, (-vn + extra) / 40), car.team, car)
    end

    private def defended_threat?(car : Car) : Bool
      will_enter_goal?(car.team, 1.6_f32)
    end

    private def attack_threat?(car : Car) : Bool
      will_enter_goal?(1 - car.team, 1.6_f32)
    end

    private def check_goal : Nil
      return unless @phase.playing?
      if @ball.pos.z < -(HALF_L + @ball.radius)
        score(0)
      elsif @ball.pos.z > HALF_L + @ball.radius
        score(1)
      end
    end

    private def score(team : Int32) : Nil
      @scores[team] += 1
      @last_goal_team = team
      scorer = @ball.last_touch
      scorer = nil if scorer && scorer.team != team
      @last_scorer = scorer
      @last_assist = nil
      if scorer
        scorer.goals += 1
        scorer.shots += 1
        if prior = @touch_log.reverse.find { |(c, t)| c.team == team && !c.same?(scorer) && @elapsed - t < 5 }
          prior[0].assists += 1
          @last_assist = prior[0]
        end
      end
      @events << MatchEvent.new(EventKind::Goal, @ball.pos, team: team, car: scorer)
      @phase = Phase::Goal
      @phase_time = 0
      @replay = @history.dup
    end

    private def start_replay : Nil
      @phase = Phase::Replay
      @replay_index = 0
    end

    private def finish_goal : Nil
      if @overtime && !@config.training?
        end_match
      else
        kickoff
      end
    end

    private def end_match : Nil
      @phase = Phase::Finished
      @phase_time = 0
      @winner = @scores[0] > @scores[1] ? 0 : (@scores[1] > @scores[0] ? 1 : -1)
      @events << MatchEvent.new(EventKind::Whistle, team: @winner)
    end

    private def record : Nil
      snap = Snapshot.new(@ball.pos, @ball.roll, @cars.map { |c| CarSnap.new(c.pos, c.orient, c.boosting?, !c.demolished?) })
      @history << snap
      @history.shift if @history.size > HISTORY
    end

    # The replay frame to show, blending two neighbouring snapshots.
    def replay_frame : Snapshot?
      return nil unless @phase.replay? && !@replay.empty?
      i = @replay_index.floor.to_i.clamp(0, @replay.size - 1)
      j = Math.min(i + 1, @replay.size - 1)
      t = (@replay_index - i).clamp(0_f32, 1_f32)
      a = @replay[i]
      b = @replay[j]
      cars = a.cars.each_with_index.map do |c, k|
        d = b.cars[k]
        CarSnap.new(c.pos.lerp(d.pos, t), c.orient.slerp(d.orient, t), c.boosting, c.visible)
      end.to_a
      Snapshot.new(a.ball.lerp(b.ball, t), a.roll.slerp(b.roll, t), cars)
    end
  end
end
