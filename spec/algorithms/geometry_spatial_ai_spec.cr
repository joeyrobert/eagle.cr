require "../spec_helper"

describe Eagle::Geometry do
  it "computes convex hulls and polygon containment" do
    hull = Geometry.convex_hull([v2(0, 0), v2(2, 0), v2(1, 1), v2(1, 0.25), v2(0, 0)])
    hull.size.should eq 3
    Geometry.point_in_polygon?(v2(1, 0.25), hull).should be_true
    Geometry.point_in_polygon?(v2(3, 3), hull).should be_false
  end

  it "intersects segments including shared collinear endpoints" do
    Geometry.segment_intersection(v2(0, 0), v2(2, 2), v2(0, 2), v2(2, 0)).not_nil!.approx?(v2(1, 1)).should be_true
    Geometry.segment_intersection(v2(0, 0), v2(1, 0), v2(1, 0), v2(2, 0)).should eq v2(1, 0)
    Geometry.segment_intersection(v2(0, 0), v2(1, 0), v2(2, 0), v2(3, 0)).should be_nil
  end

  it "evaluates curves by parameter and arc length" do
    Geometry.bezier_quadratic(v2(0, 0), v2(1, 2), v2(2, 0), 0.5).approx?(v2(1, 1)).should be_true
    Geometry.bezier_cubic(v2(0, 0), v2(1, 0), v2(2, 0), v2(3, 0), 0.5).approx?(v2(1.5, 0)).should be_true
    Geometry.catmull_rom(v2(-1, 0), v2(0, 0), v2(1, 0), v2(2, 0), 0.5).approx?(v2(0.5, 0)).should be_true
    path = ArcLengthPath.new(20) { |t| v2(t * 10, 0) }
    path.length.should be_close(10, 0.001)
    path.at(7).approx?(v2(7, 0), 0.001).should be_true
  end

  it "smooths scalar and vector values without overshoot" do
    spring = Spring.new
    spring2 = Spring2.new
    60.times { spring.update(10, 0.2, 1.0 / 60); spring2.update(v2(10, -5), 0.2, 1.0 / 60) }
    spring.value.in?(8..10.1).should be_true
    spring2.value.x.in?(8..10.1).should be_true
    spring2.value.y.in?(-5.1..-4).should be_true
  end
end

describe "spatial indexes" do
  it "queries a subdivided quadtree" do
    tree = Quadtree(Int32).new(Rect.new(0, 0, 100, 100), capacity: 1)
    10.times { |i| tree.insert(i, v2(i * 9 + 1, i * 9 + 1)) }
    tree.size.should eq 10
    tree.query(Rect.new(0, 0, 20, 20)).sort.should eq [0, 1, 2]
    tree.query_circle(v2(1, 1), 1).should eq [0]
  end

  it "moves and queries values in 2D and 3D spatial hashes" do
    hash = SpatialHash(String).new(10)
    hash.insert("a", v2(1, 1)); hash.insert("b", v2(30, 30))
    hash.query(v2(0, 0), 5).should eq ["a"]
    hash.move("a", v2(31, 30)); hash.query(v2(30, 30), 3).sort.should eq ["a", "b"]
    hash3 = SpatialHash3D(Int32).new(5)
    hash3.insert(1, v3(0, 0, 0)); hash3.insert(2, v3(20, 0, 0))
    hash3.query(v3(0, 0, 0), 2).should eq [1]
  end
end

describe "game AI helpers" do
  it "computes steering and flocking vectors" do
    Steering.seek(v2(0, 0), v2(4, 0), 2).should eq v2(2, 0)
    Steering.arrive(v2(0, 0), v2(1, 0), 10, 5).should eq v2(2, 0)
    Steering.separation(v2(0, 0), [v2(1, 0)], 2).x.should be < 0
    Steering.cohesion(v2(0, 0), [v2(2, 0), v2(4, 0)]).should eq v2(3, 0)
  end

  it "runs state machines and behavior trees" do
    context = [] of String
    machine = StateMachine(Array(String), Symbol).new(:idle)
      .on_enter(:run) { |log| log << "enter" }
      .on_update(:run) { |log, _| log << "tick" }
    machine.transition(:run, context); machine.update(context, 0.1)
    context.should eq ["enter", "tick"]

    condition = BehaviorCondition(Int32).new { |value| value > 0 }
    action = BehaviorAction(Int32).new { |_| BehaviorStatus::Success }
    BehaviorSequence(Int32).new([condition.as(Behavior(Int32)), action.as(Behavior(Int32))]).tick(1).success?.should be_true
    BehaviorSelector(Int32).new([condition.as(Behavior(Int32))]).tick(-1).failure?.should be_true
    BehaviorInverter(Int32).new(condition.as(Behavior(Int32))).tick(-1).success?.should be_true
  end

  it "finds a best minimax move with alpha-beta pruning" do
    moves = ->(value : Int32) { value.abs >= 3 ? [] of Int32 : [1, 2] }
    apply = ->(value : Int32, move : Int32) { value + move }
    evaluate = ->(value : Int32) { value.to_f64 }
    result = Minimax.search(0, 2, true, moves, apply, evaluate)
    result.move.should eq 2
    result.visited.should be > 1
  end
end
