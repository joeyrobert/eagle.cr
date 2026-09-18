require "../spec_helper"
require "../../examples/fps/game"

describe EagleFPS::Arena do
  it "generates a stable, symmetric arena with usable spawns" do
    a = EagleFPS::Arena.new(2401)
    b = EagleFPS::Arena.new(2401)
    a.obstacles.should eq b.obstacles
    a.obstacles.size.should eq 14
    a.spawn_points.all? { |p| a.free?(p) }.should be_true
    a.obstacles[4].center.should eq -a.obstacles[5].center
  end

  it "slides movement along cover and blocks sight" do
    arena = EagleFPS::Arena.new
    box = arena.obstacles[4]
    start = box.center - v2(box.half.x + 1, 0)
    stopped = arena.move(start, v2(2, 0))
    stopped.should eq start
    arena.visible?(start, box.center + v2(box.half.x + 2, 0)).should be_false
    arena.visible?(v2(-2, 0), v2(2, 0)).should be_true
  end

  it "reports slab entry distance and misses" do
    box = EagleFPS::Obstacle.new(v2(0, 0), v2(1, 1))
    t = box.ray_distance(v2(-3, 0), v2(1, 0), 10_f32)
    t.should_not be_nil
    t.not_nil!.should be_close(2, 0.001)
    box.ray_distance(v2(-3, 5), v2(1, 0), 10_f32).should be_nil
    box.ray_distance(v2(0, -3), v2(0, 1), 10_f32).not_nil!.should be_close(2, 0.001)
  end
end

describe EagleFPS::Game do
  it "supports two distinct weapons and deterministic shooting" do
    a = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 9)
    b = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 9)
    EagleFPS::WEAPONS.size.should eq 2
    EagleFPS::RIFLE.pellets.should eq 1
    EagleFPS::SCATTERGUN.pellets.should be > 1
    target = a.enemies.first
    direction = (target.position - a.player).normalized
    a.shoot(direction).should eq b.shoot(direction)
    a.enemies.map(&.health).should eq b.enemies.map(&.health)
  end

  it "occludes bullets with arena cover" do
    game = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 3)
    enemy = game.enemies.first
    obstacle = game.arena.obstacles[4]
    enemy.position = obstacle.center + v2(obstacle.half.x + 2, 0)
    game.move_player(obstacle.center - v2(obstacle.half.x + 2, 0) - game.player)
    before = enemy.health
    game.shoot((enemy.position - game.player).normalized)
    enemy.health.should eq before
  end

  it "advances waves after every enemy is defeated" do
    game = EagleFPS::Game.new(EagleFPS::Mode::Waves, 5)
    game.enemies.each { |e| e.health = 0 }
    game.update(0.016_f32)
    game.wave.should eq 2
    game.enemies.count(&.alive?).should eq 6
  end

  it "refills a deathmatch and ends at the frag limit" do
    game = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 5)
    game.enemies.each { |e| e.health = 0 }
    game.update(0.016_f32)
    game.enemies.size.should eq 6
    game.mode.deathmatch?.should be_true

    game.switch_weapon(0)
    400.times do
      break if game.finished?
      if game.health <= 0
        game.update(0.25_f32)
        next
      end
      target = game.enemies.find(&.alive?)
      break unless target
      game.enemies.each do |enemy|
        next unless enemy.alive?
        enemy.position = enemy == target ? (game.player + v2(2, 0)) : (game.player + v2(0, 20))
      end
      game.shoot(v2(1, 0))
      game.update(0.17_f32)
    end
    game.finished?.should be_true
    game.score.should be >= 15
    game.message.should eq "Frag limit reached"
  end

  it "switches weapons and clamps the index" do
    game = EagleFPS::Game.new
    game.weapon.should eq EagleFPS::RIFLE
    game.switch_weapon(1)
    game.weapon.should eq EagleFPS::SCATTERGUN
    game.switch_weapon(-3)
    game.weapon.should eq EagleFPS::RIFLE
    game.switch_weapon(9)
    game.weapon.should eq EagleFPS::SCATTERGUN
  end

  it "respawns the player after a delay" do
    game = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 12)
    charger = game.enemies.find(&.kind.charger?).not_nil!
    200.times do
      break if game.deaths > 0
      charger.position = game.player + v2(0.4, 0)
      charger.cooldown = 0
      game.update(0.05_f32)
    end
    game.deaths.should eq 1
    game.health.should eq 0
    game.message.should eq "Respawning..."
    game.update(2.1_f32)
    game.health.should eq 100
    game.player.should eq Vec2::ZERO
    game.message.should eq "Back in the fight"
  end

  it "moves both enemy types with different tactics" do
    game = EagleFPS::Game.new(EagleFPS::Mode::Deathmatch, 12)
    grunt = game.enemies.find(&.kind.grunt?).not_nil!
    charger = game.enemies.find(&.kind.charger?).not_nil!
    grunt.position = v2(0, -15)
    charger.position = v2(0, 8)
    g0 = grunt.position
    c0 = charger.position
    game.update(0.25_f32)
    grunt.position.distance(game.player).should be < g0.distance(game.player)
    charger.position.distance(game.player).should be < c0.distance(game.player)
  end
end
