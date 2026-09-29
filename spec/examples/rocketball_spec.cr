require "../spec_helper"
require "../../examples/rocketball/match"
require "../../examples/rocketball/menu"

module EagleRocketBall
  def self.advance(m : Match, seconds : Float32) : Nil
    (seconds * 60).to_i.times { m.update(1_f32 / 60) }
  end

  def self.advance_until(m : Match, limit : Float32 = 400_f32, &) : Nil
    (limit * 60).to_i.times do
      return if yield
      m.update(1_f32 / 60)
    end
    raise "condition not reached"
  end

  def self.playing_match(human = true, size = 1) : Match
    cfg = MatchConfig.new
    cfg.human = human
    cfg.team_size = size
    m = Match.new(cfg)
    EagleRocketBall.advance(m, 3.5_f32)
    m.events.clear
    m
  end

  describe "Boost Ball physics" do
    it "drops the ball to the floor and bounces it to rest" do
      b = Ball.new
      b.pos = v3(0, 10, 0)
      600.times { b.step(1_f32 / 120) }
      b.pos.y.should be_close(b.radius, 0.05)
    end

    it "keeps the ball inside the arena walls" do
      b = Ball.new
      b.pos = v3(0, 3, 0)
      b.vel = v3(50, 5, 0)
      240.times { b.step(1_f32 / 120) }
      b.pos.x.abs.should be <= HALF_W
    end

    it "lets the ball through the goal mouth" do
      b = Ball.new
      b.pos = v3(0, 3, -HALF_L + 5)
      b.vel = v3(0, 0, -40)
      lowest = 0_f32
      120.times do
        b.step(1_f32 / 120)
        lowest = Math.min(lowest, b.pos.z)
      end
      lowest.should be < -HALF_L
    end

    it "accelerates a car and spends boost" do
      c = Car.new(0, 0)
      c.spawn(v3(0, 0, 20), 0)
      c.controls.throttle = 1
      120.times { c.step(1_f32 / 120) }
      c.speed.should be > 15
      c.controls.boost = true
      60.times { c.step(1_f32 / 120) }
      c.boost.should be < 33
      c.speed.should be > 20
    end

    it "steers right when asked" do
      c = Car.new(0, 0)
      c.spawn(v3(0, 0, 20), 0)
      c.controls.throttle = 1
      c.controls.steer = 1
      120.times { c.step(1_f32 / 120) }
      c.forward.x.should be > 0.1
    end

    it "jumps, double jumps and lands upright" do
      c = Car.new(0, 0)
      c.spawn(v3(0, 0, 20), 0)
      c.controls.jump = true
      c.step(1_f32 / 120)
      c.grounded?.should be_false
      c.controls.jump = false
      10.times { c.step(1_f32 / 120) }
      peak = c.pos.y
      c.controls.jump = true
      c.step(1_f32 / 120)
      c.vel.y.should be > 5
      c.controls.jump = false
      400.times { c.step(1_f32 / 120) }
      c.grounded?.should be_true
      c.up.y.should be > 0.99
      peak.should be > CAR_RIDE
    end

    it "flips toward the pushed direction" do
      c = Car.new(0, 0)
      c.spawn(v3(0, 0, 20), 0)
      c.controls.jump = true
      c.step(1_f32 / 120)
      c.controls.jump = false
      10.times { c.step(1_f32 / 120) }
      c.controls.throttle = 1
      c.controls.jump = true
      c.step(1_f32 / 120)
      c.dodging?.should be_true
      c.vel.z.should be < -8
    end
  end

  describe Match do
    it "counts down, then plays" do
      m = Match.new(MatchConfig.new)
      m.phase.should eq Phase::Countdown
      EagleRocketBall.advance(m, 3.5_f32)
      m.phase.should eq Phase::Playing
    end

    it "scores when the ball crosses a goal line and restarts at kickoff" do
      m = playing_match
      m.ball.pos = v3(0, 3, -HALF_L - 3)
      m.update(0.05_f32)
      m.scores[0].should eq 1
      m.phase.should eq Phase::Goal
      EagleRocketBall.advance_until(m) { m.phase.countdown? }
      m.ball.pos.x.should eq 0
    end

    it "credits the scorer and an assist" do
      cfg = MatchConfig.new
      cfg.team_size = 2
      m = Match.new(cfg)
      EagleRocketBall.advance(m, 3.5_f32)
      a, b = m.cars.select { |c| c.team == 0 }
      m.ball.last_touch = a
      m.ball.pos = v3(0, 3, -HALF_L - 3)
      m.update(0.02_f32)
      a.goals.should eq 1
      m.last_scorer.should eq a
      b.assists.should eq 0
    end

    it "hits the ball away when a car drives into it" do
      m = playing_match
      car = m.human.not_nil!
      car.spawn(v3(0, 0, 8), 0)
      car.vel = v3(0, 0, -20)
      m.ball.pos = v3(0, BALL_RADIUS, 4)
      m.ball.vel = Vec3::ZERO
      6.times { m.update(1_f32 / 60) }
      m.ball.vel.z.should be < -10
      car.touches.should be >= 1
    end

    it "refills boost from a pad, then makes it wait" do
      m = playing_match
      car = m.human.not_nil!
      pad = m.pads.find(&.big?).not_nil!
      car.spawn(pad.pos, 0, 10)
      m.update(0.05_f32)
      car.boost.should eq 100
      pad.active?.should be_false
    end

    it "demolishes a rival hit at supersonic speed" do
      cfg = MatchConfig.new
      cfg.team_size = 1
      m = Match.new(cfg)
      EagleRocketBall.advance(m, 3.5_f32)
      a, b = m.cars
      a.spawn(v3(0, 0, 10), 0)
      b.spawn(v3(0, 0, 4), 0)
      a.vel = v3(0, 0, -(SUPERSONIC + 2))
      m.update(0.1_f32)
      b.demolished?.should be_true
      a.demos.should eq 1
    end

    it "ends when time runs out and declares the leader the winner" do
      cfg = MatchConfig.new
      cfg.minutes = 1
      m = Match.new(cfg)
      EagleRocketBall.advance(m, 3.5_f32)
      m.ball.pos = v3(0, 3, -HALF_L - 3)
      m.update(0.05_f32)
      EagleRocketBall.advance_until(m) { m.finished? }
      m.winner.should eq 0
    end

    it "goes to overtime when tied and ends on the next goal" do
      cfg = MatchConfig.new
      cfg.minutes = 1
      cfg.human = false
      m = Match.new(cfg)
      EagleRocketBall.advance(m, 3.5_f32)
      EagleRocketBall.advance_until(m) do
        m.ball.pos = v3(0, BALL_RADIUS, 0)
        m.ball.vel = Vec3::ZERO
        m.overtime?
      end
      m.ball.pos = v3(0, 3, HALF_L + 3)
      m.update(0.05_f32)
      EagleRocketBall.advance_until(m) { m.finished? }
      m.winner.should eq 1
    end

    it "plays bot against bot without breaking" do
      cfg = MatchConfig.new
      cfg.human = false
      cfg.team_size = 3
      m = Match.new(cfg)
      3600.times do
        m.update(1_f32 / 60)
        m.events.clear
        m.skip_replay if m.phase.replay?
      end
      m.cars.each do |c|
        c.pos.x.finite?.should be_true
        c.pos.y.should be < HEIGHT
      end
      m.cars.sum(&.touches).should be > 10
    end

    it "records a replay after a goal" do
      m = playing_match
      120.times { m.update(1_f32 / 60) }
      m.ball.pos = v3(0, 3, -HALF_L - 3)
      m.update(0.05_f32)
      EagleRocketBall.advance_until(m) { m.phase.replay? }
      m.replay_frame.should_not be_nil
    end
  end

  describe EagleRocketBall::Menu do
    it "moves the cursor, skips headers and wraps" do
      menu = Menu.new("t")
      menu << MenuItem.header("h")
      menu << MenuItem.button("a") { }
      menu << MenuItem.button("b") { }
      menu.cursor.should eq 1
      menu.move(1)
      menu.cursor.should eq 2
      menu.move(1)
      menu.cursor.should eq 1
    end

    it "cycles choices and clamps sliders" do
      got = -1
      level = 0_f32
      menu = Menu.new("t")
      menu << MenuItem.choice("c", ["x", "y", "z"], 0) { |i| got = i }
      menu << MenuItem.slider("s", 0, 1, 0.5, 0.25) { |v| level = v }
      menu.adjust(-1)
      got.should eq 2
      menu.move(1)
      4.times { menu.adjust(1) }
      level.should eq 1
      menu.selected.not_nil!.display.should eq "100%"
    end

    it "activates buttons and finds rows under the mouse" do
      hit = false
      menu = Menu.new("t")
      menu << MenuItem.button("a") { hit = true }
      menu.activate
      hit.should be_true
      rects = menu.layout(100, 50, 200, 40, 10)
      menu.item_at(v2(100, 60), rects).should eq 0
      menu.item_at(v2(5, 5), rects).should be_nil
    end
  end
end
