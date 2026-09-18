require "../../src/eagle/math/math"

# Renderer-independent game rules for the FPS example. Keeping simulation here makes the
# arena, weapons, enemy decisions and game modes deterministic and cheap to spec.
module EagleFPS
  include Eagle

  enum Mode
    Waves
    Deathmatch
  end

  enum EnemyKind
    Grunt
    Charger
  end

  record Weapon, name : String, damage : Int32, pellets : Int32, spread : Float32,
    cooldown : Float32, range : Float32

  RIFLE      = Weapon.new("Pulse rifle", 34, 1, 0.006_f32, 0.16_f32, 42_f32)
  SCATTERGUN = Weapon.new("Scattergun", 15, 7, 0.12_f32, 0.72_f32, 20_f32)
  WEAPONS    = [RIFLE, SCATTERGUN]

  record Obstacle, center : Vec2, half : Vec2 do
    def contains?(p : Vec2, radius : Number = 0) : Bool
      r = radius.to_f32
      (p.x - center.x).abs <= half.x + r && (p.y - center.y).abs <= half.y + r
    end

    # Distance along a normalized ray, or nil. Slab intersection also makes walls occlude shots.
    def ray_distance(origin : Vec2, direction : Vec2, max_distance : Float32) : Float32?
      lo = center - half
      hi = center + half
      t0 = 0_f32
      t1 = max_distance
      o = origin.x
      d = direction.x
      a = lo.x
      b = hi.x
      if d.abs < 1e-6
        return nil unless o >= a && o <= b
      else
        x0 = (a - o) / d
        x1 = (b - o) / d
        x0, x1 = x1, x0 if x0 > x1
        t0 = Math.max(t0, x0)
        t1 = Math.min(t1, x1)
        return nil if t0 > t1
      end
      o = origin.y
      d = direction.y
      a = lo.y
      b = hi.y
      if d.abs < 1e-6
        return nil unless o >= a && o <= b
      else
        x0 = (a - o) / d
        x1 = (b - o) / d
        x0, x1 = x1, x0 if x0 > x1
        t0 = Math.max(t0, x0)
        t1 = Math.min(t1, x1)
        return nil if t0 > t1
      end
      t0
    end
  end

  # Tiny stable generator so layouts and combat spread stay identical across platforms.
  class RNG
    @state : UInt32
    def initialize(seed : Int32)
      @state = seed.to_u32
      @state = 1_u32 if @state == 0
    end
    def next_u32 : UInt32
      x = @state
      x ^= x << 13; x ^= x >> 17; x ^= x << 5
      @state = x
    end
    def float : Float32; ((next_u32 & 0xffffff).to_f32 / 0x1000000).to_f32; end
    def range(lo : Number, hi : Number) : Float32; lo.to_f32 + float * (hi.to_f32 - lo.to_f32); end
  end

  class Arena
    HALF = 24_f32
    getter obstacles = [] of Obstacle
    getter spawn_points = [] of Vec2

    def initialize(seed : Int32 = 2401)
      rng = RNG.new(seed)
      @obstacles.concat([
        Obstacle.new(v2(0, -HALF), v2(HALF, 0.6)),
        Obstacle.new(v2(0, HALF), v2(HALF, 0.6)),
        Obstacle.new(v2(-HALF, 0), v2(0.6, HALF)),
        Obstacle.new(v2(HALF, 0), v2(0.6, HALF)),
      ])
      # Mirrored cover keeps the arena fair while its sizes and offsets are procedural.
      5.times do |i|
        x = rng.range(5, 18) * (i.even? ? 1 : -1)
        z = rng.range(-17, 17)
        half = v2(rng.range(1.2, 2.8), rng.range(1.0, 3.2))
        @obstacles << Obstacle.new(v2(x, z), half)
        @obstacles << Obstacle.new(v2(-x, -z), half)
      end
      @spawn_points.concat([v2(-19, -19), v2(19, 19), v2(-19, 19), v2(19, -19), v2(0, -19), v2(0, 19)])
    end

    def free?(p : Vec2, radius : Number = 0.55) : Bool
      p.x.abs < HALF - radius && p.y.abs < HALF - radius && @obstacles.none?(&.contains?(p, radius))
    end

    def move(from : Vec2, delta : Vec2, radius : Number = 0.55) : Vec2
      p = from
      px = v2(from.x + delta.x, from.y)
      p = px if free?(px, radius)
      py = v2(p.x, p.y + delta.y)
      p = py if free?(py, radius)
      p
    end

    def visible?(a : Vec2, b : Vec2) : Bool
      delta = b - a
      distance = delta.length
      return true if distance < 1e-5
      @obstacles.none? { |o| (t = o.ray_distance(a, delta / distance, distance)) && t > 0.01 }
    end
  end

  class Enemy
    getter id : Int32
    getter kind : EnemyKind
    property position : Vec2
    property health : Int32
    property cooldown = 0_f32

    def initialize(@id, @kind, @position)
      @health = kind.grunt? ? 70 : 105
    end

    def radius : Float32; @kind.grunt? ? 0.6_f32 : 0.78_f32; end
    def alive? : Bool; @health > 0; end
  end

  record ShotResult, fired : Bool, hits : Int32 = 0, kills : Int32 = 0, endpoint : Vec2 = Vec2::ZERO

  class Game
    getter arena : Arena
    getter enemies = [] of Enemy
    getter mode : Mode
    getter player : Vec2 = Vec2::ZERO
    getter health = 100
    getter score = 0
    getter deaths = 0
    getter wave = 1
    getter weapon_index = 0
    getter cooldown = 0_f32
    getter elapsed = 0_f32
    getter message = ""
    getter? finished = false
    @next_id = 1
    @rng : RNG
    @spawn_cursor = 0
    @respawn = 0_f32

    def initialize(@mode = Mode::Waves, seed : Int32 = 2401)
      @arena = Arena.new(seed)
      @rng = RNG.new(seed ^ 0x5eed)
      spawn_wave
    end

    def weapon : Weapon; WEAPONS[@weapon_index]; end
    def switch_weapon(index : Int32) : Nil; @weapon_index = index.clamp(0, WEAPONS.size - 1); end

    def move_player(delta : Vec2) : Vec2
      return @player if @health <= 0 || @finished
      @player = @arena.move(@player, delta)
    end

    def update(dt : Float32) : Nil
      return if @finished
      @elapsed += dt
      @cooldown = Math.max(0_f32, @cooldown - dt)
      if @health <= 0
        @respawn -= dt
        respawn_player if @respawn <= 0
      else
        @enemies.each do |enemy|
          next unless enemy.alive?
          enemy.cooldown = Math.max(0_f32, enemy.cooldown - dt)
          to_player = @player - enemy.position
          distance = to_player.length
          next if distance < 1e-4
          if enemy.kind.charger?
            enemy.position = @arena.move(enemy.position, to_player / distance * (5.0_f32 * dt), enemy.radius)
            if distance < 1.25 && enemy.cooldown <= 0
              damage_player(18)
              enemy.cooldown = 0.8_f32
            end
          else
            desired = distance > 9 ? 1_f32 : (distance < 6 ? -1_f32 : 0_f32)
            enemy.position = @arena.move(enemy.position, to_player / distance * (2.4_f32 * dt * desired), enemy.radius)
            if distance < 20 && enemy.cooldown <= 0 && @arena.visible?(enemy.position, @player)
              damage_player(7)
              enemy.cooldown = 1.0_f32 + @rng.float * 0.5_f32
            end
          end
        end
      end

      if @mode.waves? && @health > 0 && @enemies.none?(&.alive?)
        @wave += 1
        @health = Math.min(100, @health + 25)
        @message = "Wave #{@wave}"
        spawn_wave
      elsif @mode.deathmatch?
        @enemies.reject! { |e| !e.alive? }
        while @enemies.size < 6
          spawn_enemy(@next_id.even? ? EnemyKind::Grunt : EnemyKind::Charger)
        end
        if @score >= 15
          @finished = true
          @message = "Frag limit reached"
        end
      end
    end

    def shoot(direction : Vec2) : ShotResult
      return ShotResult.new(false, endpoint: @player) if @finished || @health <= 0 || @cooldown > 0
      dir = direction.normalized
      return ShotResult.new(false, endpoint: @player) if dir.zero?
      w = weapon
      @cooldown = w.cooldown
      hits = 0
      kills = 0
      endpoint = @player + dir * w.range
      w.pellets.times do
        shot_dir = dir.rotated(@rng.range(-w.spread, w.spread))
        wall_distance = w.range
        @arena.obstacles.each do |obstacle|
          if t = obstacle.ray_distance(@player, shot_dir, w.range)
            wall_distance = Math.min(wall_distance, t)
          end
        end
        endpoint = @player + shot_dir * wall_distance if w.pellets == 1
        target : Enemy? = nil
        target_t = wall_distance
        @enemies.each do |enemy|
          next unless enemy.alive?
          rel = enemy.position - @player
          t = rel.dot(shot_dir)
          next unless t > 0 && t < target_t
          miss = (rel - shot_dir * t).length
          if miss <= enemy.radius
            target = enemy
            target_t = t
          end
        end
        if enemy = target
          was_alive = enemy.alive?
          enemy.health -= w.damage
          hits += 1
          if was_alive && !enemy.alive?
            kills += 1
            @score += 1
          end
        end
      end
      ShotResult.new(true, hits, kills, endpoint)
    end

    private def damage_player(amount : Int32) : Nil
      return if @health <= 0
      @health = Math.max(0, @health - amount)
      if @health == 0
        @deaths += 1
        @respawn = 2_f32
        @message = "Respawning..."
      end
    end

    private def respawn_player : Nil
      @health = 100
      @player = Vec2::ZERO
      @message = "Back in the fight"
    end

    private def spawn_wave : Nil
      count = @mode.waves? ? 2 + @wave * 2 : 6
      count.times { |i| spawn_enemy((i + @wave) % 3 == 0 ? EnemyKind::Charger : EnemyKind::Grunt) }
    end

    private def spawn_enemy(kind : EnemyKind) : Nil
      points = @arena.spawn_points
      point = points[@spawn_cursor % points.size]
      @spawn_cursor += 1
      point += v2(@rng.range(-1.2, 1.2), @rng.range(-1.2, 1.2))
      @enemies << Enemy.new(@next_id, kind, point)
      @next_id += 1
    end
  end
end
