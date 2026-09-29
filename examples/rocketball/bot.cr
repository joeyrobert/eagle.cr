require "./physics"

module EagleRocketBall
  enum Difficulty
    Rookie
    Pro
    AllStar
  end

  # A computer driver. It picks a role (attack, support or defend), a point to drive to, and presses the same controls a person would.
  class Bot
    getter car : Car
    getter role = :attack
    @think_timer = 0_f32
    @target = Vec3::ZERO
    @want_boost = false
    @noise = 0_f32
    @stuck = 0_f32
    @reverse_left = 0_f32
    @reverse_steer = 1_f32
    @jump_step = 0
    @jump_timer = 0_f32

    def initialize(@car : Car, @difficulty : Difficulty, @rng : Random)
      @think_timer = @rng.rand.to_f32 * 0.3_f32
    end

    def target : Vec3
      @target
    end

    def think(m : Match, dt : Float32) : Nil
      c = @car.controls
      c.clear
      return if @car.demolished? || !m.phase.playing?
      @think_timer -= dt
      if @think_timer <= 0
        decide(m)
        interval = case @difficulty
                   in .rookie?   then 0.35_f32
                   in .pro?      then 0.2_f32
                   in .all_star? then 0.1_f32
                   end
        @think_timer = interval * (0.8_f32 + @rng.rand.to_f32 * 0.4_f32)
      end
      act(m, dt)
    end

    private def skill : Float32
      case @difficulty
      in .rookie?   then 0.35_f32
      in .pro?      then 0.75_f32
      in .all_star? then 1_f32
      end
    end

    private def decide(m : Match) : Nil
      car = @car
      ball = m.ball
      dir = car.team == 0 ? -1_f32 : 1_f32
      own_z = -dir * HALF_L
      mates = m.cars.select { |o| o.team == car.team && !o.demolished? }
      ranked = mates.sort_by { |o| o.pos.distance(ball.pos) + o.slot * 0.01_f32 }
      rank = ranked.index(car) || 0
      danger = m.will_enter_goal?(car.team, 2_f32)
      @role = if rank == 0 || (danger && rank < 2)
                :attack
              elsif rank == 1 && mates.size >= 3
                :support
              else
                :defend
              end
      @noise = (@rng.rand.to_f32 - 0.5_f32) * 2 * (1 - skill) * 0.4_f32
      dist = car.pos.distance(ball.pos)
      lead = @difficulty.rookie? ? 0_f32 : (dist / Math.max(car.speed, 14_f32)).clamp(0_f32, 1.4_f32)
      ball_f = lead > 0.05 ? ball.predict(lead)[0] : ball.pos
      goal = Vec3.new(0, 0, dir * HALF_L)
      @want_boost = true
      case @role
      when :attack
        to_goal = Vec3.new(goal.x - ball_f.x, 0, goal.z - ball_f.z).normalized
        ahead = (car.pos.x - ball_f.x) * to_goal.x + (car.pos.z - ball_f.z) * to_goal.z
        if ahead > -1 && dist > 7
          # On the wrong side of the ball: swing around behind it, wide of the goal line.
          side = car.pos.x >= ball_f.x ? 1_f32 : -1_f32
          @target = Vec3.new(ball_f.x - to_goal.x * 12 + side * 9, 0, ball_f.z - to_goal.z * 12)
          @target = Vec3.new(@target.x.clamp(-HALF_W + 3, HALF_W - 3), 0, @target.z.clamp(-HALF_L + 3, HALF_L - 3))
        elsif dist > 9
          @target = Vec3.new(ball_f.x - to_goal.x * (BALL_RADIUS + 2.2_f32), 0, ball_f.z - to_goal.z * (BALL_RADIUS + 2.2_f32))
        else
          @target = Vec3.new(ball_f.x, 0, ball_f.z)
        end
      when :support
        @target = Vec3.new(ball_f.x * 0.5_f32, 0, (ball_f.z - dir * 15).clamp(-HALF_L + 6, HALF_L - 6))
        @want_boost = dist > 25
      else
        depth = 7_f32 + Math.min(20_f32, (ball.pos.z - own_z).abs * 0.25_f32)
        @target = Vec3.new((ball.pos.x * 0.35_f32).clamp(-GOAL_HALF_W + 1, GOAL_HALF_W - 1), 0, own_z + dir * depth)
        @want_boost = false
      end
      if @role != :attack && car.boost < 30 || (@role == :attack && car.boost < 12 && dist > 25)
        if pad = m.nearest_pad(car.pos, 32_f32)
          @target = Vec3.new(pad.pos.x, 0, pad.pos.z)
        end
      end
    end

    private def act(m : Match, dt : Float32) : Nil
      car = @car
      c = car.controls
      ball = m.ball
      to_ball = ball.pos - car.pos
      flat_dist = Math.sqrt(to_ball.x * to_ball.x + to_ball.z * to_ball.z).to_f32
      if car.grounded?
        if @reverse_left > 0
          @reverse_left -= dt
          c.throttle = -1
          c.steer = @reverse_steer
          return
        end
        @stuck = car.speed < 1.5 && flat_dist > 6 ? @stuck + dt : 0_f32
        if @stuck > 1.0
          @stuck = 0
          @reverse_left = 0.8_f32
          @reverse_steer = @rng.rand < 0.5 ? -1_f32 : 1_f32
        end
        drive_to(car, @target)
        jump_logic(m, car, flat_dist, to_ball, dt)
      else
        air_control(m, car, to_ball, flat_dist, dt)
      end
    end

    private def drive_to(car : Car, target : Vec3) : Nil
      c = car.controls
      to = Vec3.new(target.x - car.pos.x, 0, target.z - car.pos.z)
      dist = to.length
      f = car.forward
      fx = f.x
      fz = f.z
      fl = Math.sqrt(fx * fx + fz * fz).to_f32
      if fl > 0.01
        fx /= fl
        fz /= fl
      end
      ang = Math.atan2(fx * to.z - fz * to.x, fx * to.x + fz * to.z).to_f32
      c.steer = (ang * 2.2_f32 + @noise).clamp(-1_f32, 1_f32)
      c.throttle = skill.clamp(0.7_f32, 1_f32)
      c.throttle = 0 if dist < 3 && car.speed > 9
      c.handbrake = ang.abs > 1.3 && car.speed > 8 && dist > 4
      c.boost = @want_boost && ang.abs < (0.12_f32 + 0.08_f32 * skill) && dist > 14 && car.boost > 8 && car.speed < MAX_BOOST_SPEED - 1 && skill > 0.5
      c.boost = true if @difficulty.rookie? && ang.abs < 0.1 && dist > 30 && car.boost > 40
    end

    private def jump_logic(m : Match, car : Car, flat_dist : Float32, to_ball : Vec3, dt : Float32) : Nil
      c = car.controls
      ball = m.ball
      if @jump_step > 0
        run_jump(c, car, dt, to_ball)
        return
      end
      return unless @role == :attack || flat_dist < 8
      f = car.forward
      facing = (f.x * to_ball.x + f.z * to_ball.z) / Math.max(flat_dist, 0.01_f32)
      if flat_dist < 8 && ball.pos.y > 2.6 && ball.pos.y < (@difficulty.all_star? ? 10_f32 : 7_f32) && facing > 0.5 && skill > 0.3
        @jump_step = 1
        @jump_timer = 0
      elsif flat_dist < 7.5 && ball.pos.y < 3.4 && car.speed > 14 && facing > 0.85 && skill > 0.6 && m.ball.vel.length < 30
        @jump_step = 1
        @jump_timer = 0
      end
    end

    private def run_jump(c : Controls, car : Car, dt : Float32, to_ball : Vec3) : Nil
      @jump_timer += dt
      case @jump_step
      when 1
        c.jump = true
        if @jump_timer > 0.1
          @jump_step = 2
          @jump_timer = 0
        end
      when 2
        c.jump = false
        if @jump_timer > 0.07
          @jump_step = 3
          @jump_timer = 0
        end
      else
        c.jump = true
        c.throttle = 1
        @jump_step = 0 if @jump_timer > 0.1
      end
    end

    private def air_control(m : Match, car : Car, to_ball : Vec3, flat_dist : Float32, dt : Float32) : Nil
      c = car.controls
      ball = m.ball
      if @jump_step > 0
        run_jump(c, car, dt, to_ball)
        c.boost = false
        return if @jump_step == 3
      end
      if to_ball.length < 14 && !@difficulty.rookie?
        local = car.orient.conjugate * to_ball.normalized
        c.throttle = -(local.y * 3).clamp(-1_f32, 1_f32)
        c.steer = (local.x * 3).clamp(-1_f32, 1_f32)
        c.boost = local.z < -0.6 && ball.pos.y > car.pos.y + 1 && car.boost > 5
      else
        c.throttle = (car.forward.y * 2).clamp(-1_f32, 1_f32)
      end
      c.roll = -(car.right.y * 3).clamp(-1_f32, 1_f32)
    end
  end
end
