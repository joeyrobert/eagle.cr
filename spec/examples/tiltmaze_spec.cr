require "../spec_helper"
require "../../examples/tiltmaze/board"

describe EagleTiltMaze::Board do
  it "rolls the marble the way the player pushes" do
    board = EagleTiltMaze::Board.new
    board.place(v2(-6.3, 3.0))
    start = board.marble
    20.times { board.step(v2(1, 0), 1 / 60_f32) }
    board.marble.x.should be > start.x
    (board.rotation * v3(1, 0, 0)).y.should be < 0
  end

  it "tilts the far edge down when pushing up" do
    board = EagleTiltMaze::Board.new
    20.times { board.step(v2(0, -1), 1 / 60_f32) }
    (board.rotation * v3(0, 0, -1)).y.should be < 0
  end

  it "stops the marble at a wall" do
    board = EagleTiltMaze::Board.new
    wall = board.walls[4]
    board.place(v2(wall.center.x, wall.center.y + 1.2), v2(0, -8))
    60.times { board.step(v2(0, -1), 1 / 60_f32) }
    board.marble.y.should be >= wall.center.y + wall.half.y + EagleTiltMaze::BALL_RADIUS - 0.01
  end

  it "resets the marble after falling into a hole" do
    board = EagleTiltMaze::Board.new
    board.place(board.holes.first)
    board.step(Vec2::ZERO, 1 / 60_f32).should be_true
    board.falls.should eq 1
    board.marble.should eq EagleTiltMaze::START
  end

  it "wins at the goal and loses when time runs out" do
    board = EagleTiltMaze::Board.new
    board.place(board.goal)
    board.step(Vec2::ZERO, 1 / 60_f32)
    board.state.won?.should be_true

    board = EagleTiltMaze::Board.new
    (EagleTiltMaze::TIME_LIMIT * 60 + 2).to_i.times { board.step(Vec2::ZERO, 1 / 60_f32) }
    board.state.lost?.should be_true
  end
end
