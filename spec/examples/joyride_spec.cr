require "../spec_helper"
require "../../examples/joyride/sim"

private def joy_world(seed = 77_i64)
  Joyride::World.new(seed)
end

describe Joyride::World do
  it "generates deterministic chunks and matching roads across chunk edges" do
    a = joy_world
    b = joy_world
    (-3..3).each do |cx|
      (-3..3).each do |cz|
        la = a.layout(cx, cz)
        lb = b.layout(cx, cz)
        la.zone.should eq lb.zone
        la.density.should eq lb.density
        la.buildings.should eq lb.buildings
        la.props.should eq lb.props
        Joyride::Dir.values.each do |dir|
          a.road?(cx, cz, dir).should eq a.road?(cx + dir.dx, cz + dir.dz, dir.opposite)
          if a.road?(cx, cz, dir)
            a.crossing(cx, cz, dir).should eq a.crossing(cx + dir.dx, cz + dir.dz, dir.opposite)
          end
        end
      end
    end
  end

  it "streams city, town and countryside layouts with bounded caches" do
    w = joy_world
    zones = Set(Joyride::Zone).new
    (-12..12).step(3) { |cx| (-12..12).step(3) { |cz| zones << w.layout(cx, cz).zone } }
    zones.should contain Joyride::Zone::City
    zones.should contain Joyride::Zone::Country
    w.cached_layouts.should be > 20
    w.evict(0, 0, 2)
    w.cached_layouts.should be <= 25
  end

  it "finds connected routes and nearest road points" do
    w = joy_world
    route = w.route({0, 0}, {4, 4}).not_nil!
    route.first.should eq({0, 0})
    route.last.should eq({4, 4})
    route.each_cons_pair do |a, b|
      ((a[0] - b[0]).abs + (a[1] - b[1]).abs).should eq 1
      w.leg(a, b).size.should be >= 3
    end
    point, direction = w.nearest_road_point(v2(48, 48)).not_nil!
    direction.length.should be_close(1, 0.001)
    w.layout(*Joyride::World.chunk_of(point)).road_distance(point).should be <= 0.1
  end
end

describe Joyride::Car do
  it "accelerates, steers and handbrake-drifts deterministically" do
    car = Joyride::Car.new(v2(0, 0))
    120.times do
      car.throttle = 1_f32
      car.steer_input = 0.65_f32
      car.handbrake = car.speed > 10
      car.step(1_f32 / 60, nil)
    end
    car.speed.should be > 10
    car.heading.abs.should be > 0.1
    car.slip.should be > 0.01
    car.pos.length.should be > 10
  end

  it "does not tunnel through generated static colliders" do
    w = joy_world
    collider = w.layout(0, 0).colliders.first
    car = Joyride::Car.new(collider.center - v2(15, 0), -Math::PI.to_f32 / 2)
    car.vel = v2(80, 0)
    impact = car.step(0.3_f32, w)
    impact.should be > 0
    collider.penetration(car.pos, car.spec.radius).should be_nil
  end

  it "resolves car-to-car impacts" do
    a = Joyride::Car.new(v2(0, 0)); b = Joyride::Car.new(v2(1, 0))
    a.vel = v2(8, 0); b.vel = v2(-2, 0)
    Joyride::Car.collide(a, b).should be > 0
    a.pos.distance(b.pos).should be > 1
  end
end

describe "Joyride actors and missions" do
  it "drives traffic along an endless route" do
    w = joy_world
    player = Joyride::Car.new(v2(-1000, -1000))
    t = Joyride::TrafficCar.new(w, {0, 0}, nil, 9_u64)
    start = t.position
    180.times { t.update(1_f32 / 60, w, player, [t]) }
    t.position.distance(start).should be > 5
    t.wanderer.path.empty?.should be_false
  end

  it "makes pedestrians dodge and records a direct hit" do
    p = Joyride::Pedestrian.new(v2(-5, 0), v2(5, 0), 0.5_f32, Color::RED, Color::BLUE)
    car = Joyride::Car.new(v2(0, 0), -Math::PI.to_f32 / 2)
    car.vel = v2(12, 0)
    p.update(1_f32 / 60, [car]).should be_true
    p.down?.should be_true
  end

  it "completes delivery stops and awards a reward" do
    targets = [
      Joyride::Mission::Target.new(v2(0, 0), 3_f32, true, "pickup"),
      Joyride::Mission::Target.new(v2(20, 0), 3_f32, true, "dropoff"),
    ]
    m = Joyride::Mission.new(Joyride::Mission::Kind::Delivery, targets, 20_f32)
    20.times { m.update(0.02_f32, v2(0, 0), 0) }
    m.index.should eq 1
    m.time_left.should_not be_nil
    20.times { m.update(0.02_f32, v2(20, 0), 0) }
    m.state.complete?.should be_true
    m.reward.should be > 0
  end

  it "raises and cools the wanted level" do
    wanted = Joyride::Wanted.new
    wanted.crime!(2).should be_true
    wanted.level.should eq 2
    wanted.police_count.should eq 2
    wanted.update(9, false).should be_false
    wanted.update(1.1, false).should be_true
    wanted.level.should eq 1
    wanted.update(20, true).should be_false
    wanted.level.should eq 1
  end
end
