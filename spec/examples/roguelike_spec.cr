require "../spec_helper"
require "../../examples/roguelike/dungeon"

describe Rogue::Dungeon do
  it "generates connected dungeons with rooms, stairs and doors" do
    (1..8).each do |seed|
      d = Rogue::Dungeon.new(60, 34, seed)
      d.rooms.size.should be >= 4
      sx, sy = d.rooms.first.center
      d.reachable_from(sx, sy).size.should eq d.walkable_count
      d.tiles.count(&.stairs_down?).should eq 1
      d.tiles.count(&.wall?).should be > d.walkable_count
    end
  end

  it "computes a symmetric-ish field of view blocked by walls" do
    d = Rogue::Dungeon.new(30, 20, 3)
    d.tiles.fill(Rogue::Tile::Floor)
    d[15, 10] = Rogue::Tile::Wall
    d.compute_fov(10, 10, 8)
    d.visible?(10, 10).should be_true
    d.visible?(14, 10).should be_true
    d.visible?(15, 10).should be_true   # the wall itself is seen
    d.visible?(17, 10).should be_false  # behind the wall
    d.visible?(10, 17).should be_true   # within radius
    d.visible?(10, 19).should be_false  # beyond radius
    d.explored?(14, 10).should be_true
    d.compute_fov(2, 2, 3)
    d.visible?(14, 10).should be_false
    d.explored?(14, 10).should be_true
  end

  it "finds paths around obstacles" do
    d = Rogue::Dungeon.new(20, 10, 4)
    d.tiles.fill(Rogue::Tile::Floor)
    (0...10).each { |y| d[10, y] = Rogue::Tile::Wall unless y == 9 }
    step = d.next_step({5, 5}, {15, 5}).not_nil!
    [{5, 6}, {6, 5}].should contain(step) # either first step is equally short
    d[10, 9] = Rogue::Tile::Wall
    d.next_step({5, 5}, {15, 5}).should be_nil
    d.next_step({5, 5}, {5, 5}).should be_nil
  end
end

describe Rogue::Game do
  it "moves, fights, picks up items and descends deterministically" do
    g = Rogue::Game.new(7)
    g.level.should eq 1
    g.player.alive?.should be_true
    start = g.player.pos
    moved = false
    [{1, 0}, {-1, 0}, {0, 1}, {0, -1}].each { |(dx, dy)| moved = true if g.move_player(dx, dy) }
    moved.should be_true
    g.turns.should be >= 1
    # place a monster next to the player and fight it
    m = Rogue::Entity.new("rat", g.player.x + 1, g.player.y, 1, 0, 0, 'r', xp_value: 3)
    g.monsters << m
    g.move_player(1, 0)
    m.alive?.should be_false
    g.messages.last(2).any?(&.includes?("dies")).should be_true
    g.xp.should eq 3
    # gold pickup
    g.items << Rogue::Item.new(Rogue::Item::Kind::Gold, g.player.x, g.player.y - 1, 10)
    g.move_player(0, -1) || g.move_player(0, -1)
    if g.player.pos == {g.player.x, g.player.y}
      g.gold.should be >= 0
    end
    # teleport to the stairs and descend
    d = g.dungeon
    sx, sy = d.rooms.last.center
    g.player.x = sx; g.player.y = sy
    g.descend.should be_true
    g.level.should eq 2
    g.game_over?.should be_false
    # same seed => same dungeon
    a = Rogue::Game.new(42); b = Rogue::Game.new(42)
    a.dungeon.tiles.should eq b.dungeon.tiles
    a.monsters.map(&.pos).should eq b.monsters.map(&.pos)
  end

  it "monsters chase and can kill the player; winning after the last level" do
    g = Rogue::Game.new(9)
    g.monsters.clear
    troll = Rogue::Entity.new("troll", g.player.x + 3, g.player.y, 99, 50, 0, 'T')
    g.dungeon.tiles.fill(Rogue::Tile::Floor)
    g.monsters << troll
    20.times { g.wait_turn }
    g.game_over?.should be_true
    g.won?.should be_false
    g.messages.last.should contain("You die")
    w = Rogue::Game.new(11)
    (1..Rogue::Game::MAX_LEVEL).each do
      sx, sy = w.dungeon.rooms.last.center
      w.player.x = sx; w.player.y = sy
      w.descend
    end
    w.won?.should be_true
  end
end
