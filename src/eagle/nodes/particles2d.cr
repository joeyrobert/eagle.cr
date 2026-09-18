module Eagle
  # A particle emitter for fire, smoke, sparks, explosions, rain and magic effects.
  #
  # Configure how particles spawn, move and change over their life, add the node to the
  # tree, and it runs by itself. Particles are simulated on the CPU and drawn in one batch,
  # so thousands are fine.
  #
  # ```
  # fire = Particles2D.new(amount: 120, position: v2(200, 300))
  # fire.lifetime = 0.8
  # fire.speed = 40..90
  # fire.direction = -Math::PI / 2         # up
  # fire.spread = 0.4
  # fire.gravity = v2(0, -60)              # rises
  # fire.scale_start, fire.scale_end = 1.2, 0.2
  # fire.color_over_life = [Color::YELLOW, Color::ORANGE, Color::RED.alpha(0)]
  # fire.blend = GPU::BlendMode::Additive
  # SceneTree.root.add(fire)
  #
  # boom = Particles2D.new(amount: 0, position: v2(400, 300))
  # boom.speed = 100..300
  # boom.spread = Mathf::TAU               # every direction
  # boom.on_finished { boom.queue_free }
  # SceneTree.root.add(boom)
  # boom.explode(80)                       # one burst, then remove itself
  # ```
  #
  # By default particles live in world space, so a moving emitter leaves a trail. Set
  # `world_space = false` to make them follow the node.
  class Particles2D < Node2D
    # One live particle. Only needed with `custom_update`.
    struct Particle
      # Position of the particle.
      property position : Vec2 = Vec2::ZERO
      # Velocity in points per second.
      property velocity : Vec2 = Vec2::ZERO
      # Seconds left to live.
      property life : Float32 = 0_f32
      # Total lifetime in seconds.
      property max_life : Float32 = 1_f32
      # Rotation in radians.
      property rotation : Float32 = 0_f32
      # Spin in radians per second.
      property angular_velocity : Float32 = 0_f32
      # Current size multiplier.
      property size : Float32 = 1_f32
      # A random value from 0 to 1, fixed per particle, for per-particle variation.
      property seed : Float32 = 0_f32
      # True while the particle has life left.
      def alive? : Bool; @life > 0; end
      # How far through its life the particle is, from 0 to 1.
      def t : Float32; 1 - @life / @max_life; end
    end

    # Where new particles appear: at the node's position, inside a circle of `emission_radius`,
    # or inside a rectangle of `emission_rect`.
    enum EmissionShape
      # Spawn at the node's position.
      Point
      # Spawn anywhere inside a circle of `emission_radius`.
      Circle
      # Spawn anywhere inside a rectangle of `emission_rect`, centered on the node.
      Rect
    end

    # Particles emitted per second while `emitting`.
    property amount : Int32
    # Whether new particles are spawned. Existing ones finish their lives either way.
    property? emitting = true
    # Emit `amount` particles at once, then stop.
    property? one_shot = false
    # How long each particle lives, in seconds.
    property lifetime : Float32 = 1_f32
    # Random variation of lifetime, as a fraction: 0.2 means up to 20% longer or shorter.
    property lifetime_random : Float32 = 0_f32
    # Launch direction in radians. The default points up.
    property direction : Float32 = -Math::PI.to_f32 / 2 # up
    # Random spread around `direction`, in radians on each side. `Mathf::TAU` fires in every direction.
    property spread : Float32 = Math::PI.to_f32 / 6
    # Launch speed range in points per second. Each particle picks a random value.
    property speed : Range(Float32, Float32) = 50_f32..100_f32
    # Constant acceleration, such as `v2(0, 400)` for sparks that fall.
    property gravity : Vec2 = Vec2::ZERO
    # Drag that slows particles down over time.
    property damping : Float32 = 0_f32
    # Size multiplier when a particle is born.
    property scale_start : Float32 = 1_f32
    # Size multiplier when it dies. Size eases between the two.
    property scale_end : Float32 = 1_f32
    # Random size variation, as a fraction.
    property scale_random : Float32 = 0_f32
    # Spin range in radians per second.
    property angular_speed : Range(Float32, Float32) = 0_f32..0_f32
    # Colors a particle passes through from birth to death, evenly spaced. Fade to a transparent
    # color for a soft end.
    property color_over_life : Array(Color) = [Color::WHITE, Color::WHITE]
    # Texture for each particle. `nil` uses a soft white circle.
    property texture : Drawable? = nil
    # Blend mode. `Additive` makes overlapping particles glow.
    property blend : GPU::BlendMode = GPU::BlendMode::Alpha
    # Where particles spawn; see `EmissionShape`.
    property emission_shape = EmissionShape::Point
    # Radius for `EmissionShape::Circle`.
    property emission_radius : Float32 = 0_f32
    # Size for `EmissionShape::Rect`.
    property emission_rect : Vec2 = Vec2::ZERO
    # When true (the default), particles stay where they were emitted as the node moves.
    property? world_space = true
    # A block run for every particle each frame to apply custom behavior, such as swirling.
    # It receives the particle and *dt* and returns the updated particle.
    property custom_update : Proc(Particle, Float32, Particle)? = nil
    # Seed for the random generator, for repeatable effects.
    property seed : Int32? = nil
    # The particle pool, including dead particles.
    getter particles : Array(Particle)
    @accumulator = 0_f32
    @rng : Random
    @alive_count = 0
    @default_texture : Texture? = nil

    # Emitted when emission has stopped and the last particle has died. Connect with
    # `on_finished { ... }`, for example to remove a one-shot explosion.
    signal finished

    # Hard cap on live particles.
    property max_particles : Int32

    # Creates an emitter.
    def initialize(name : String = "", @amount : Int32 = 100, position : Vec2 = Vec2::ZERO, max_particles : Int32? = nil, seed : Int32? = nil)
      super(name, position)
      @rng = seed ? Random.new(seed) : Random.new
      @max_particles = max_particles || Math.max(@amount * 4, 1000)
      @particles = Array(Particle).new(Math.min(@max_particles, Math.max(@amount * 2, 64))) { Particle.new }
    end

    # Number of live particles.
    def alive_count : Int32; @alive_count; end
    # Sets the speed range.
    def speed=(r : Range(Number, Number)); @speed = r.begin.to_f32..r.end.to_f32; end
    # Sets a fixed speed.
    def speed=(v : Number); @speed = v.to_f32..v.to_f32; end
    # Sets the spin range.
    def angular_speed=(r : Range(Number, Number)); @angular_speed = r.begin.to_f32..r.end.to_f32; end
    # Sets the lifetime.
    def lifetime=(v : Number); @lifetime = v.to_f32; end
    # Sets the launch direction in radians.
    def direction=(v : Number); @direction = v.to_f32; end
    # Sets the spread in radians.
    def spread=(v : Number); @spread = v.to_f32; end
    # Sets the damping.
    def damping=(v : Number); @damping = v.to_f32; end
    # Sets the starting size.
    def scale_start=(v : Number); @scale_start = v.to_f32; end
    # Sets the ending size.
    def scale_end=(v : Number); @scale_end = v.to_f32; end

    # Spawns *n* particles right away, for bursts.
    def emit(n : Int32) : Nil
      n.times { spawn_one }
    end

    # Spawns *n* particles and stops emitting. `finished` fires when the last one dies.
    def explode(n : Int32) : Nil
      @emitting = false
      emit(n)
    end

    # Kills every particle and starts emitting again.
    def restart : Nil
      @particles.size.times { |i| @particles[i] = Particle.new }
      @alive_count = 0
      @accumulator = 0_f32
      @emitting = true
    end

    # Kills every particle.
    def clear : Nil
      @particles.size.times { |i| @particles[i] = Particle.new }
      @alive_count = 0
    end

    private def spawn_one
      idx = @particles.index { |p| !p.alive? }
      if idx.nil?
        return if @particles.size >= @max_particles
        @particles << Particle.new
        idx = @particles.size - 1
      end
      p = Particle.new
      origin = case @emission_shape
               in EmissionShape::Point then Vec2::ZERO
               in EmissionShape::Circle
                 Vec2.from_angle(@rng.rand * Math::PI * 2, Math.sqrt(@rng.rand) * @emission_radius)
               in EmissionShape::Rect
                 Vec2.new((@rng.rand - 0.5) * @emission_rect.x, (@rng.rand - 0.5) * @emission_rect.y)
               end
      p.position = @world_space ? to_global(origin) : origin
      angle = (@direction + (@rng.rand - 0.5) * 2 * @spread).to_f32
      angle += global_rotation if @world_space
      spd = (@speed.begin + (@speed.end - @speed.begin) * @rng.rand).to_f32
      p.velocity = Vec2.from_angle(angle, spd)
      p.max_life = Math.max(0.01_f32, (@lifetime * (1 + (@rng.rand - 0.5) * 2 * @lifetime_random)).to_f32)
      p.life = p.max_life
      p.rotation = (@rng.rand * Math::PI * 2).to_f32
      p.angular_velocity = (@angular_speed.begin + (@angular_speed.end - @angular_speed.begin) * @rng.rand).to_f32
      p.size = (1 + (@rng.rand - 0.5) * 2 * @scale_random).to_f32
      p.seed = @rng.rand.to_f32
      @particles[idx] = p
      @alive_count += 1
    end

    # Updates the simulation. Called by the engine.
    def process(dt : Float32) : Nil
      update(dt)
    end

    # Advances the simulation by *dt*. Public so tests and tools can step it manually.
    def update(dt : Float32) : Nil
      if @emitting && @amount > 0
        if @one_shot
          # one_shot: emit everything in the first update, then stop
          @emitting = false
          @amount.times { spawn_one }
        else
          @accumulator += dt * @amount
          while @accumulator >= 1
            spawn_one
            @accumulator -= 1
          end
        end
      end
      alive = 0
      cu = @custom_update
      @particles.size.times do |i|
        p = @particles[i]
        next unless p.alive?
        p.life -= dt
        if p.life <= 0
          p.life = 0_f32
          @particles[i] = p
          next
        end
        p.velocity += @gravity * dt
        p.velocity *= (1 / (1 + dt * @damping)) if @damping > 0
        p.position += p.velocity * dt
        p.rotation += p.angular_velocity * dt
        p = cu.call(p, dt) if cu
        @particles[i] = p
        alive += 1
      end
      was = @alive_count
      @alive_count = alive
      emit_finished if was > 0 && alive == 0 && !@emitting
    end

    # The color at life fraction *t*.
    def color_at(t : Float32) : Color
      cols = @color_over_life
      return Color::WHITE if cols.empty?
      return cols[0] if cols.size == 1
      f = t.clamp(0_f32, 1_f32) * (cols.size - 1)
      i = f.floor.to_i
      return cols.last if i >= cols.size - 1
      cols[i].lerp(cols[i + 1], f - i)
    end

    private def default_texture : Texture
      @default_texture ||= Texture.new(Image.circle(16, Color::WHITE))
    end

    # Draws every live particle.
    def draw_tree(g : Graphics) : Nil
      return unless @visible
      tex = @texture || default_texture
      w, h = case tex
             in Texture then {tex.width.to_f32, tex.height.to_f32}
             in TextureRegion then {tex.width, tex.height}
             end
      base = g.color * @modulate
      g.push
      g.apply(transform) unless @world_space
      g.with_blend(@blend) do
        @particles.each do |p|
          next unless p.alive?
          t = p.t
          s = (@scale_start + (@scale_end - @scale_start) * t) * p.size
          g.draw(tex, p.position.x, p.position.y, p.rotation, s, s, w / 2, h / 2, base * color_at(t))
        end
      end
      g.pop
      draw_children(g)
    end
  end
end
