require "../../src/eagle"
include Eagle

# Platformer: tile map from ASCII, KinematicBody2D player with coyote time and
# jump buffering, patrolling enemies, coins (Area2D), a goal, camera with limits.
LEVEL = <<-MAP
  ####################################################################
  #                                                                  #
  #                                     c c c                        #
  #            c                       #######                       #
  #    P      ###          c c                        c              #
  #  #####            e   ####                  ###  ####            #
  #                 #####            ####               ##   c   G   #
  #        c c                  e             c   e         ####  ###
  #       #####        ^^^    ######    ^^^  ####### ^^^^ ^^        #
  ####################################################################
  MAP

class Player < KinematicBody2D
  SPEED = 220
  JUMP = 520
  GRAVITY = 1400
  @coyote = 0_f32
  @buffer = 0_f32
  @sprite = Polygon2D.rect(22, 30, Color.hex("#ffd166"))
  @face = 1

  signal died

  def initialize(position : Vec2)
    super("Player", position)
    box(22, 30)
    add(@sprite)
    eye = Polygon2D.rect(4, 4, Color::BLACK)
    eye.position = v2(5, -8)
    add(eye)
  end

  def physics_process(dt : Float32)
    @coyote = on_floor? ? 0.1_f32 : @coyote - dt
    @buffer = Input.pressed?("jump") ? 0.12_f32 : @buffer - dt
    x = Input.axis("left", "right")
    @face = x > 0 ? 1 : (x < 0 ? -1 : @face)
    vx = Mathf.damp(velocity.x, x * SPEED, 12, dt)
    vy = velocity.y + GRAVITY * dt
    if @buffer > 0 && @coyote > 0
      vy = -JUMP
      @buffer = 0_f32; @coyote = 0_f32
      Sounds.jump
    end
    vy = Math.max(vy, -JUMP * 0.5) if Input.released?("jump") && vy < 0
    self.velocity = v2(vx, vy)
    move_and_slide(dt)
    self.velocity = v2(velocity.x, 0) if on_ceiling? && velocity.y < 0
    @sprite.scale = v2(@face, 1)
    emit_died if position.y > 800
  end
end

class Enemy < KinematicBody2D
  @dir = 1
  def initialize(position : Vec2)
    super("Enemy", position)
    box(24, 20)
    add(Polygon2D.rect(24, 20, Color.hex("#ef476f")))
    add_to_group("enemies")
  end

  def physics_process(dt : Float32)
    # turn at walls or ledges
    ahead = global_position + v2(@dir * 16, 14)
    floor_ahead = Physics2D.world.raycast(ahead, v2(0, 1), 12, exclude: body)
    self.velocity = v2(@dir * 60, 300)
    move_and_slide(dt)
    @dir = -@dir if on_wall? || floor_ahead.nil?
  end
end

module Sounds
  @@jump : Sound? = nil
  @@coin : Sound? = nil
  @@hurt : Sound? = nil
  def self.init
    @@jump = Sound.tone(500, 0.1, Sound::Wave::Square, 0.2)
    @@coin = Sound.tone(1200, 0.08, Sound::Wave::Sine, 0.3)
    @@hurt = Sound.tone(150, 0.3, Sound::Wave::Saw, 0.3)
  end
  def self.jump; @@jump.try(&.play(pitch: 0.9 + rand * 0.2)); end
  def self.coin; @@coin.try(&.play(pitch: 1 + rand * 0.3)); end
  def self.hurt; @@hurt.try(&.play); end
end

class Platformer < App
  TILE = 32
  @player : Player? = nil
  @cam = Camera2D.new(zoom: 1.5)
  @coins = 0
  @total = 0
  @deaths = 0
  @won = false
  @world = Node2D.new("World")
  @hud = Label.new("")

  def load
    Sounds.init
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "jump", Key::Space, Key::W, Key::Up, GamepadButton::A
    root = SceneTree.root
    root.add(@world)
    build
    hud = CanvasLayer.new
    @hud.position = v2(10, 10)
    hud.add(@hud)
    root.add(hud)
    root.add(@cam)
  end

  def build
    @world.clear_children
    @coins = 0; @total = 0; @won = false
    lines = LEVEL.lines.map(&.rstrip)
    ts = Image.new(TILE * 2, TILE)
    ts.fill_rect(0, 0, TILE, TILE, Color.hex("#3d5a80"))
    ts.fill_rect(0, 0, TILE, 4, Color.hex("#98c1d9"))
    ts.fill_rect(TILE, 0, TILE, TILE, Color::TRANSPARENT)
    TILE.times { |x| (0..(x % 8 == 0 ? 6 : 2)).each { |y| ts[TILE + x, TILE - 1 - y] = Color.hex("#ee6c4d") } } # spikes
    map = TileMap.new(Texture.new(ts, GPU::Filter::Nearest), TILE, TILE)
    @world.add(map)
    solids = StaticBody2D.new("Solids")
    hazards = Area2D.new("Hazards")
    lines.each_with_index do |line, y|
      x = 0
      while x < line.size
        c = line[x]
        case c
        when '#'
          # merge horizontal runs into one collider
          x2 = x
          while x2 < line.size && line[x2] == '#'
            x2 += 1
          end
          (x...x2).each { |xx| map[xx, y] = 0 }
          w = (x2 - x) * TILE
          solids.add_shape(Physics2D::Polygon.box(w, TILE, v2(x * TILE + w / 2, y * TILE + TILE / 2)))
          x = x2
          next
        when '^'
          map[x, y] = 1
          hazards.add_shape(Physics2D::Polygon.box(TILE - 8, 10, v2(x * TILE + TILE / 2, y * TILE + TILE - 5)))
        when 'c'
          coin = Area2D.new("Coin", v2(x * TILE + TILE / 2, y * TILE + TILE / 2)).circle(8)
          coin.add(Polygon2D.circle(8, Color.hex("#ffd60a")))
          coin.add_to_group("coins")
          @world.add(coin)
          @total += 1
        when 'e' then @world.add(Enemy.new(v2(x * TILE + TILE / 2, y * TILE + TILE / 2)))
        when 'G'
          goal = Area2D.new("Goal", v2(x * TILE + TILE / 2, y * TILE + TILE / 2)).box(24, 40)
          goal.add(Polygon2D.rect(24, 40, Color.hex("#06d6a0")))
          @world.add(goal)
        when 'P' then spawn(v2(x * TILE + TILE / 2, y * TILE + TILE / 2))
        end
        x += 1
      end
    end
    @world.add(solids, hazards)
    hazards.on_body_entered { |b| hurt if b.is_a?(Player) }
    @cam.limits = Rect.new(0, 0, lines.map(&.size).max * TILE, lines.size * TILE)
  end

  def spawn(at : Vec2)
    p = Player.new(at)
    p.on_died { hurt }
    p.on_body_entered do |o|
      if o.name == "Coin" && !o.queued_free?
        o.queue_free; @coins += 1; Sounds.coin
      elsif o.name == "Goal"
        @won = true
      elsif o.is_a?(Enemy)
        if p.velocity.y > 0 && p.position.y < o.position.y - 10
          o.queue_free; p.velocity = v2(p.velocity.x, -300); Sounds.coin
        else
          hurt
        end
      end
    end
    @world.add(p)
    @player = p
    @cam.follow(p, v2(0, -40))
    @cam.smoothing = 6
  end

  def hurt
    return unless (p = @player) && p.in_tree?
    @deaths += 1
    Sounds.hurt
    @cam.shake(6, 0.3)
    start = p.position
    p.queue_free
    SceneTree.defer { spawn(v2(2.5 * TILE, 4.5 * TILE)) }
  end

  def update(dt : Float32)
    @hud.text = "coins #{@coins}/#{@total}   deaths #{@deaths}   #{@won ? "YOU WIN! R to restart" : "arrows/WASD move, space jump"}"
    build if Input.pressed?(Key::R)
    Eagle.quit if Input.pressed?(Key::Escape)
  end
end

Eagle.run(Platformer, title: "Eagle Platformer", width: 960, height: 540, clear_color: Color.hex("#1b1f2a"))
