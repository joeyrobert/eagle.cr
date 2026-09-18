module Eagle
  # Frame timing you can read from anywhere: how long the last frame took, how long the
  # game has been running, the frame rate, and a global time scale.
  #
  # The `dt` passed to `App#update` and `Node#process` is the same as `Clock.delta`.
  # Multiply speeds by it so movement is the same at any frame rate.
  #
  # `scale` slows down or speeds up everything that uses `delta`: set it to 0.3 for
  # slow motion or 0 to freeze gameplay while menus keep working through `raw_delta`.
  #
  # ```
  # class Hud < Node2D
  #   def draw(g : Graphics) : Nil
  #     g.print("fps #{Clock.fps.round}  t=#{Clock.elapsed.round(1)}s", 10, 10)
  #   end
  # end
  #
  # Clock.scale = 0.25 # bullet time
  # pulse = Math.sin(Clock.elapsed * 4) # a value that oscillates over time
  # ```
  module Clock
    @@delta = 0_f32
    @@raw_delta = 0_f32
    @@elapsed = 0_f64
    @@frame = 0_i64
    @@fps = 0_f32
    @@scale = 1_f32
    @@fps_accum = 0_f64
    @@fps_count = 0
    @@fixed_delta = 1_f32 / 60
    @@fixed_accumulator = 0_f64
    @@max_delta = 0.25_f32

    # Seconds since the last frame, multiplied by `scale`. Clamped so a long hitch
    # (for example after a breakpoint) doesn't teleport everything.
    def self.delta : Float32; @@delta; end
    # Seconds since the last frame, ignoring `scale`. Use it for UI and menus that must keep
    # moving while the game is paused or slowed down.
    def self.raw_delta : Float32; @@raw_delta; end
    # Real seconds since the engine started. Handy for animations driven by `Math.sin`.
    def self.elapsed : Float64; @@elapsed; end
    # Number of frames since start.
    def self.frame : Int64; @@frame; end
    # Measured frames per second, updated twice a second.
    def self.fps : Float32; @@fps; end
    # Time scale applied to `delta`: 1 is normal, 0.5 is half speed and 0 pauses gameplay.
    def self.scale : Float32; @@scale; end
    # Sets the time scale. Tweens and fixed steps follow it too.
    def self.scale=(v : Number); @@scale = v.to_f32; end
    # Length of one fixed step in seconds, which is `1 / Config#fixed_fps`.
    def self.fixed_delta : Float32; @@fixed_delta; end
    # Changes the fixed step length.
    def self.fixed_delta=(v : Number); @@fixed_delta = v.to_f32; end
    # Largest `delta` a single frame can report, 0.25 s by default. This stops a long
    # stall from causing a burst of physics steps.
    def self.max_delta=(v : Number); @@max_delta = v.to_f32; end

    # How far the current frame sits between the last fixed step and the next, from 0 to 1.
    # Use it to interpolate positions of physics objects for smooth rendering at high refresh rates.
    def self.fixed_alpha : Float32
      (@@fixed_accumulator / @@fixed_delta).to_f32.clamp(0_f32, 1_f32)
    end

    # :nodoc:
    def self.advance(raw_dt : Float64) : Nil
      raw_dt = @@max_delta.to_f64 if raw_dt > @@max_delta
      raw_dt = 0.0 if raw_dt < 0
      @@raw_delta = raw_dt.to_f32
      @@delta = (raw_dt * @@scale).to_f32
      @@elapsed += raw_dt
      @@frame += 1
      @@fps_accum += raw_dt
      @@fps_count += 1
      if @@fps_accum >= 0.5
        @@fps = (@@fps_count / @@fps_accum).to_f32
        @@fps_accum = 0.0
        @@fps_count = 0
      end
      @@fixed_accumulator += @@delta
    end

    # :nodoc: Yields once per pending fixed step.
    def self.each_fixed_step(max_steps = 8, &) : Nil
      steps = 0
      while @@fixed_accumulator >= @@fixed_delta && steps < max_steps
        @@fixed_accumulator -= @@fixed_delta
        steps += 1
        yield @@fixed_delta
      end
      # Drop excess time if we can't keep up.
      @@fixed_accumulator = 0.0 if steps >= max_steps
    end

    # :nodoc:
    def self.reset : Nil
      @@delta = @@raw_delta = 0_f32
      @@elapsed = 0.0
      @@frame = 0_i64
      @@fps = 0_f32
      @@fixed_accumulator = 0.0
      @@fps_accum = 0.0
      @@fps_count = 0
    end
  end
end
