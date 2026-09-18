require "../spec_helper"

describe Eagle::Rng do
  it "repeats PCG streams and stays inside requested bounds" do
    a = Rng.new(1234)
    b = Rng.new(1234)
    20.times { a.next_u.should eq b.next_u }
    values = Array.new(500) { a.int(-3, 7) }
    values.all? { |value| value.in?(-3..7) }.should be_true
    values.uniq.size.should be > 8
  end

  it "supports weighted picks, shuffles and geometric helpers" do
    rng = Rng.new(42)
    20.times { rng.weighted([:only, :never], [1, 0]).should eq :only }
    rng.shuffle([1, 2, 3, 4]).sort.should eq [1, 2, 3, 4]
    50.times { rng.in_circle(3).length.should be <= 3 }
    rng.fork.next_u.should_not eq rng.next_u
    20.times { rng.int(1..6).in?(1..6).should be_true }
    20.times { rng.weighted({:only => 1, :never => 0}).should eq :only }
    rng.roll("2d6").in?(2..12).should be_true
  end

  it "parses and rolls dice expressions" do
    dice = Dice.parse("4d6kh3+2")
    dice.to_s.should eq "4d6kh3+2"
    dice.min.should eq 5
    dice.max.should eq 20
    30.times { dice.roll(Rng.new(99)).in?(5..20).should be_true }
    expect_raises(ArgumentError) { Dice.parse("2dd6") }
  end
end

describe Eagle::Grid do
  it "rasterizes lines and tests visibility" do
    Grid.line({0, 0}, {4, 2}).should eq [{0, 0}, {1, 1}, {2, 1}, {3, 2}, {4, 2}]
    Grid.line_of_sight?({0, 0}, {4, 0}) { |x, _| x == 2 }.should be_false
    Grid.line_of_sight?({0, 0}, {1, 0}) { |_, _| false }.should be_true
  end

  it "flood fills bounded areas and computes shadowcasting FOV" do
    fill = Grid.flood_fill({1, 1}) { |x, y| x.in?(0..2) && y.in?(0..2) && {x, y} != {1, 0} }
    fill.size.should eq 8
    visible = Grid.field_of_view({2, 2}, 4) { |x, y| x < 0 || y < 0 || x > 4 || y > 4 || {x, y} == {3, 2} }
    visible.should contain({3, 2})
    visible.should_not contain({4, 2})
  end

  it "supports axial hex coordinates" do
    origin = Hex.new(0, 0)
    origin.neighbors.uniq.size.should eq 6
    origin.distance(Hex.new(3, -2)).should eq 3
    Hex.round(0.8, -0.2).should eq Hex.new(1, 0)
  end
end

describe Eagle::Pathfinding do
  it "finds weighted grid paths without cutting corners" do
    grid = CostGrid.new(5, 5)
    grid.block(2, 0); grid.block(2, 1); grid.block(2, 2); grid.block(2, 3)
    result = Pathfinding.a_star(grid, {0, 0}, {4, 0}, diagonal: true)
    result.found?.should be_true
    result.path.first.should eq({0, 0})
    result.path.last.should eq({4, 0})
    result.path.should contain({2, 4})
    Pathfinding.dijkstra(grid, {0, 0}, {4, 0}).found?.should be_true
  end

  it "searches arbitrary weighted graphs with A* and Dijkstra" do
    graph = {
      :a => [{:b, 2.0}, {:c, 1.0}],
      :b => [{:d, 1.0}],
      :c => [{:d, 5.0}],
      :d => [] of {Symbol, Float64},
    }
    result = Pathfinding.dijkstra(graph, :a, :d)
    result.path.should eq [:a, :b, :d]
    result.cost.should eq 3.0
  end

  it "builds flow fields and smooths visible path segments" do
    grid = CostGrid.new(4, 3)
    field = Pathfinding.flow_field(grid, {3, 1})
    field.next_step({0, 1}).should eq({1, 1})
    path = [{0, 0}, {1, 0}, {2, 0}, {2, 1}]
    Pathfinding.smooth(path) { |a, b| a[1] == b[1] }.should eq [{0, 0}, {2, 0}, {2, 1}]
  end

  it "blocks cells and reports them impassable" do
    grid = CostGrid.new(3, 3)
    grid.passable?(1, 1).should be_true
    grid.block(1, 1)
    grid.passable?(1, 1).should be_false
    grid[1, 1].should eq Float64::INFINITY
    expect_raises(ArgumentError) { grid[0, 0] = 0 }
  end
end
