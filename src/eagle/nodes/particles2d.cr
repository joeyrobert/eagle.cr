module Eagle
  # CPU particle system. Configure the emitter, add to the tree, done.
  #
  #   p = Particles2D.new(amount: 200)
  #   p.lifetime = 1.5
  #   p.speed = 80..160
  #   p.spread = Math::PI / 4
  #   p.gravity = v2(0, 300)
  #   p.color_over_life = [Color::YELLOW, Color::RED, Color::TRANSPARENT]
  class Particles2D < Node2D
    struct Particle
      property position : Vec2 = Vec2::ZERO
      property velocity : Vec2 = Vec2::ZERO
      property life : Float32 = 0_f32
      property max_life : Float32 = 1_f32
      property rotation : Float32 = 0_f32
      property angular_velocity : Float32 = 0_f32
      property size : Float32 = 1_f32
      property seed : Float32 = 0_f32
      def alive? : Bool; @life > 0; end
      def t : Float32; 1 - @life / @max_life; end
    end

    enum EmissionShape
      Point
      Circle
      Rect
    end

    # Particles emitted per second while `emitting`.
    property amount : Int32
    property? emitting = true
    property? one_shot = false
    property lifetime : Float32 = 1_f32
    property lifetime_random : Float32 = 0_f32
    property direction : Float32 = -Math::PI.to_f32 / 2 # up
    property spread : Float32 = Math::PI.to_f32 / 6
    property speed : Range(Float32, Float32) = 50_f32..100_f32
    property gravity : Vec2 = Vec2::ZERO
    property damping : Float32 = 0_f32
    property scale_start : Float32 = 1_f32
    property scale_end : Float32 = 1_f32
    property scale_random : Float32 = 0_f32
    property angular_speed : Range(Float32, Float32) = 0_f32..0_f32
    property color_over_life : Array(Color) = [Color::WHITE, Color::WHITE]
    property texture : Drawable? = nil
    property blend : GPU::BlendMode = GPU::BlendMode::Alpha
    property emission_shape = EmissionShape::Point
    property emission_radius : Float32 = 0_f32
    property emission_rect : Vec2 = Vec2::ZERO
    # If true particle positions are in world space (they don't follow the node).
    property? world_space = true
    # Extra per-particle update: (particle, dt) → particle
    property custom_update : Proc(Particle, Float32, Particle)? = nil
    property seed : Int32? = nil
    getter particles : Array(Particle)
    @accumulator = 0_f32
    @rng : Random
    @alive_count = 0
    @default_texture : Texture? = nil

    signal finished

    # Hard cap on live particles (pool grows on demand up to this).
    property max_particles : Int32

    def initialize(name : String = "", @amount : Int32 = 100, position : Vec2 = Vec2::ZERO, max_particles : Int32? = nil, seed : Int32? = nil)
      super(name, position)
      @rng = seed ? Random.new(seed) : Random.new
      @max_particles = max_particles || Math.max(@amount * 4, 1000)
      @particles = Array(Particle).new(Math.min(@max_particles, Math.max(@amount * 2, 64))) { Particle.new }
    end

    def alive_count : Int32; @alive_count; end
    def speed=(r : Range(Number, Number)); @speed = r.begin.to_f32..r.end.to_f32; end
    def speed=(v : Number); @speed = v.to_f32..v.to_f32; end
    def angular_speed=(r : Range(Number, Number)); @angular_speed = r.begin.to_f32..r.end.to_f32; end
    def lifetime=(v : Number); @lifetime = v.to_f32; end
    def direction=(v : Number); @direction = v.to_f32; end
    def spread=(v : Number); @spread = v.to_f32; end
    def damping=(v : Number); @damping = v.to_f32; end
    def scale_start=(v : Number); @scale_start = v.to_f32; end
    def scale_end=(v : Number); @scale_end = v.to_f32; end

    # Emit `n` particles immediately (bursts/explosions).
    def emit(n : Int32) : Nil
      n.times { spawn_one }
    end

    # Emit a burst and stop (one-shot explosion helper).
    def explode(n : Int32) : Nil
      @emitting = false
      emit(n)
    end

    def restart : Nil
      @particles.size.times { |i| @particles[i] = Particle.new }
      @alive_count = 0
      @accumulator = 0_f32
      @emitting = true
    end

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

    def process(dt : Float32) : Nil
      update(dt)
    end

    # Advance the simulation (called by process; public for manual use/tests).
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
