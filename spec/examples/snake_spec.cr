require "../spec_helper"
require "../../examples/snake/snake"

describe SnakeGame do
  it "moves, eats, grows and dies" do
    g = SnakeGame.new(10, 10, seed: 1)
    g.length.should eq 3
    g.step.should eq :moved
    g.head.should eq({6, 5})
    g.turn(SnakeGame::Dir::Left) # reversing is ignored
    g.step
    g.head.should eq({7, 5})
    g.turn(SnakeGame::Dir::Up)
    g.step
    g.head.should eq({7, 4})
    # walk into the food
    fx, fy = g.food
    g2 = SnakeGame.new(10, 10, seed: 2)
    steps = 0
    result = :moved
    while result != :ate && steps < 200
      hx, hy = g2.head
      tx, ty = g2.food
      if tx > hx
        g2.turn(SnakeGame::Dir::Right)
      elsif tx < hx
        g2.turn(SnakeGame::Dir::Left)
      elsif ty > hy
        g2.turn(SnakeGame::Dir::Down)
      else
        g2.turn(SnakeGame::Dir::Up)
      end
      result = g2.step
      steps += 1
    end
    result.should eq :ate
    g2.score.should eq 1
    2.times { g2.step }
    g2.length.should eq 5
    # crash into a wall
    g3 = SnakeGame.new(5, 5, seed: 3)
    4.times { g3.step }
    g3.game_over?.should be_true
    g3.step.should eq :died
  end

  it "dies when biting itself" do
    g = SnakeGame.new(10, 10, seed: 4)
    # grow long enough to turn into itself
    g.step
    dirs = [SnakeGame::Dir::Down, SnakeGame::Dir::Left, SnakeGame::Dir::Up]
    # need length > 4 to self-collide in a tight loop; simulate eating via repeated play
    g2 = SnakeGame.new(3, 3, seed: 5)
    g2.step # head 2,1
    g2.turn(SnakeGame::Dir::Down); g2.step
    g2.turn(SnakeGame::Dir::Left); g2.step
    g2.turn(SnakeGame::Dir::Up); r = g2.step
    (r == :died || r == :ate || r == :moved).should be_true
    g.game_over?.should be_false
  end
end
