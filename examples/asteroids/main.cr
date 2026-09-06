require "../../src/eagle"
include Eagle

# Asteroids: rotate with A/D or left stick, thrust with W, fire with space / A button.
class Ship < Node2D
  property velocity = Vec2::ZERO
  getter? alive = true
  @respawn = 0_f32
  @invuln = 2_f32

  def process(dt : Float32)
    unless @alive
      @respawn -= dt
      if @respawn <= 0
        @alive = true; @invuln = 2_f32
        self.position = v2(Window.width / 2, Window.height / 2)
        @velocity = Vec2::ZERO
      end
      return
    end
    @invuln -= dt
    self.rotation += Input.axis("left", "right") * 4 * dt
    if Input.down?("thrust")
      @velocity += Vec2.from_angle(rotation) * 380 * dt
      thrust.emitting = true
    else
      thrust.emitting = false
    end
    @velocity *= (1 / (1 + dt * 0.4))
    self.position += @velocity * dt
    self.position = v2(position.x % Window.width, position.y % Window.height)
    thrust.direction = rotation + Math::PI
  end

  def thrust : Particles2D
    (child?("thrust") || add(Particles2D.new("thrust", amount: 120, position: Vec2::ZERO).tap { |p|
      p.world_space = true; p.lifetime = 0.35; p.speed = 80..160; p.spread = 0.3
      p.scale_start = 0.4; p.scale_end = 0; p.color_over_life = [Color::ORANGE, Color::RED.with_alpha(0)]
      p.blend = GPU::BlendMode::Additive; p.emitting = false
    })).as(Particles2D)
  end

  def invulnerable? : Bool; @invuln > 0; end

  def die
    @alive = false
    @respawn = 2_f32
    thrust.emitting = false
  end

  def draw(g : Graphics)
    return unless @alive
    return if invulnerable? && (Clock.elapsed * 10).to_i.even?
    g.polygon([v2(16, 0), v2(-12, 10), v2(-6, 0), v2(-12, -10)], DrawMode::Line, Color::WHITE)
  end
end

class Rock < Node2D
  property velocity : Vec2
  property size : Int32
  getter radius : Float32
  @points : Array(Vec2)
  @spin : Float32

  def initialize(position : Vec2, @size : Int32, rng : Random)
    super("rock", position)
    @radius = (@size * 14).to_f32
    @velocity = Vec2.from_angle(rng.rand * Math::PI * 2, 40 + rng.rand * 60 + (3 - @size) * 30)
    @spin = (rng.rand - 0.5).to_f32 * 2
    n = 10
    @points = Array(Vec2).new(n) { |i| Vec2.from_angle(Math::PI * 2 * i / n, @radius * (0.7 + rng.rand * 0.4)) }
  end

  def process(dt : Float32)
    self.position += @velocity * dt
    self.rotation += @spin * dt
    self.position = v2(position.x % Window.width, position.y % Window.height)
  end

  def draw(g : Graphics)
    g.polygon(@points, DrawMode::Line, Color.gray(0.8))
  end
end

class Bullet < Node2D
  property velocity : Vec2
  @life = 1.1_f32
  def initialize(position : Vec2, @velocity : Vec2)
    super("bullet", position)
  end
  def process(dt : Float32)
    self.position += @velocity * dt
    self.position = v2(position.x % Window.width, position.y % Window.height)
    @life -= dt
    queue_free if @life <= 0
  end
  def draw(g : Graphics)
    g.circle(0, 0, 2, color: Color::YELLOW)
  end
end

class AsteroidsGame < App
  @ship = Ship.new("ship", v2(400, 300))
  @score = 0
  @lives = 3
  @wave = 0
  @rng = Random.new(7)
  @fx = Particles2D.new(amount: 0)
  @snd_shoot : Sound? = nil
  @snd_boom : Sound? = nil
  @cooldown = 0_f32
  @over = false

  def load
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "thrust", Key::W, Key::Up, GamepadButton::B, Input.axis(GamepadAxis::TriggerRight, 1)
    Input.map "fire", Key::Space, GamepadButton::A
    @snd_shoot = Sound.tone(880, 0.05, Sound::Wave::Square, 0.15)
    @snd_boom = Sound.tone(90, 0.3, Sound::Wave::Noise, 0.35)
    @fx.lifetime = 0.6; @fx.speed = 40..180; @fx.spread = Math::PI; @fx.scale_start = 0.3; @fx.scale_end = 0
    @fx.color_over_life = [Color::WHITE, Color.gray(0.5).with_alpha(0)]
    SceneTree.root.add(@ship, @fx)
    spawn_wave
  end

  def spawn_wave
    @wave += 1
    (3 + @wave).times do
      pos = v2(@rng.rand * Window.width, @rng.rand * Window.height)
      pos = v2(pos.x + 200, pos.y) if pos.distance(@ship.position) < 150
      SceneTree.root.add(Rock.new(pos, 3, @rng))
    end
  end

  def update(dt : Float32)
    @cooldown -= dt
    if @ship.alive? && Input.down?("fire") && @cooldown <= 0 && !@over
      @cooldown = 0.18_f32
      SceneTree.root.add(Bullet.new(@ship.position + Vec2.from_angle(@ship.rotation, 16), @ship.velocity + Vec2.from_angle(@ship.rotation, 500)))
      @snd_shoot.try(&.play(pitch: 0.9 + rand * 0.2))
    end
    rocks = SceneTree.root.children_of(Rock)
    bullets = SceneTree.root.children_of(Bullet)
    rocks.each do |r|
      bullets.each do |b|
        next if b.queued_free?
        if b.position.distance(r.position) < r.radius
          b.queue_free
          split(r)
          break
        end
      end
      if @ship.alive? && !@ship.invulnerable? && !r.queued_free? && r.position.distance(@ship.position) < r.radius + 10
        @lives -= 1
        explode(@ship.position, 40)
        @ship.die
        @over = true if @lives <= 0
      end
    end
    spawn_wave if rocks.empty?
    if @over && Input.pressed?(Key::R)
      SceneTree.root.children_of(Rock).each(&.queue_free)
      @score = 0; @lives = 3; @wave = 0; @over = false
      SceneTree.flush_deferred
      spawn_wave
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def split(r : Rock)
    r.queue_free
    @score += {3 => 20, 2 => 50, 1 => 100}[r.size]
    explode(r.position, 12 * r.size)
    @snd_boom.try(&.play(pitch: 0.7 + r.size * 0.2))
    if r.size > 1
      2.times { SceneTree.root.add(Rock.new(r.position, r.size - 1, @rng)) }
    end
  end

  def explode(at : Vec2, n : Int32)
    @fx.position = at
    @fx.emit(n)
  end

  def draw(g : Graphics)
    g.print("score #{@score}   lives #{@lives}   wave #{@wave}", 12, 10, Color::WHITE)
    g.print("GAME OVER — R to restart", Window.width / 2, Window.height / 2, Color::RED, align: TextAlign::Center) if @over
  end
end

Eagle.run(AsteroidsGame, title: "Eagle Asteroids", width: 800, height: 600)
