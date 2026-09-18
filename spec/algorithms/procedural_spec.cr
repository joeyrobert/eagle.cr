require "../spec_helper"

describe Eagle::Procedural do
  it "creates deterministic Poisson-disk points with the requested spacing" do
    a = Procedural.poisson_disk(80, 50, 6, Rng.new(42))
    b = Procedural.poisson(80, 50, 6, Rng.new(42))
    a.should eq b
    a.size.should be > 40
    a.each do |point|
      point.x.should be >= 0
      point.x.should be < 80
      point.y.should be >= 0
      point.y.should be < 50
    end
    a.each_with_index do |point, i|
      (i + 1...a.size).each { |j| point.distance(a[j]).should be >= 5.999 }
    end
  end

  it "partitions bounded, non-overlapping BSP rooms deterministically" do
    rooms = Procedural.bsp_rooms(64, 48, Rng.new(8), minimum_size: 7, depth: 5)
    rooms.should eq Procedural.bsp_rooms(64, 48, Rng.new(8), minimum_size: 7, depth: 5)
    rooms.size.should be > 4
    rooms.each do |room|
      room.x.should be >= 1
      room.y.should be >= 1
      room.right.should be <= 63
      room.bottom.should be <= 47
      room.w.should be > 0
      room.h.should be > 0
    end
    rooms.each_with_index do |room, i|
      (i + 1...rooms.size).each { |j| room.intersects?(rooms[j]).should be_false }
    end
  end

  it "smooths deterministic cellular caves while keeping solid borders" do
    width = 31; height = 19
    cave = Procedural.cellular_cave(width, height, Rng.new(99), fill: 0.43, iterations: 4)
    cave.should eq Procedural.cave(width, height, Rng.new(99), fill: 0.43, iterations: 4)
    cave.size.should eq width * height
    width.times { |x| cave[x].should be_true; cave[(height - 1) * width + x].should be_true }
    height.times { |y| cave[y * width].should be_true; cave[y * width + width - 1].should be_true }
    cave.count(true).should be >= width * 2
    cave.count(true).should be < width * height
  end

  it "carves a connected maze without changing even dimensions" do
    width = 20; height = 14
    maze = Procedural.maze(width, height, Rng.new(123))
    maze.size.should eq width * height
    open = maze.each_index.select { |i| maze[i] }.to_a
    open.should_not be_empty
    reached = Set(Int32).new
    queue = Deque{open.first}
    reached << open.first
    until queue.empty?
      i = queue.shift
      x = i % width; y = i // width
      [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}].each do |(nx, ny)|
        next unless nx.in?(0...width) && ny.in?(0...height)
        ni = ny * width + nx
        next unless maze[ni] && reached.add?(ni)
        queue << ni
      end
    end
    reached.size.should eq open.size
  end

  it "expands and interprets branching L-systems" do
    program = Procedural.lsystem("F", {'F' => "F[+F]F[-F]F"}, 2)
    program.count('F').should eq 25
    segments = Procedural.lsystem_segments(program, Math::PI / 5, step: 2)
    segments.size.should eq 25
    segments.first[0].should eq Vec2::ZERO
    segments.all? { |(a, b)| Mathf.approx?(a.distance(b), 2, 0.001) }.should be_true
    expect_raises(ArgumentError) { Procedural.lsystem_segments("F[+F", 1) }
    expect_raises(ArgumentError) { Procedural.lsystem_segments("F]", 1) }
  end

  it "validates generator dimensions and settings" do
    expect_raises(ArgumentError) { Procedural.poisson_disk(10, 10, 0) }
    expect_raises(ArgumentError) { Procedural.poisson_disk(10, 10, 2, attempts: 0) }
    expect_raises(ArgumentError) { Procedural.bsp_rooms(2, 10) }
    expect_raises(ArgumentError) { Procedural.cellular_cave(10, 10, fill: 1.1) }
    expect_raises(ArgumentError) { Procedural.maze(2, 2) }
  end
end
