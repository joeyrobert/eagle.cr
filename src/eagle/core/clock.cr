module Eagle
  # Frame timing. Read anywhere: `Clock.delta`, `Clock.elapsed`, `Clock.fps`.
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

    # Seconds since last frame, scaled by `scale`.
    def self.delta : Float32; @@delta; end
    # Unscaled seconds since last frame.
    def self.raw_delta : Float32; @@raw_delta; end
    # Seconds since the engine started.
    def self.elapsed : Float64; @@elapsed; end
    def self.frame : Int64; @@frame; end
    def self.fps : Float32; @@fps; end
    # Time scale (1 = normal, 0 = paused, 0.5 = slow motion).
    def self.scale : Float32; @@scale; end
    def self.scale=(v : Number); @@scale = v.to_f32; end
    # Fixed timestep used for `physics_process`.
    def self.fixed_delta : Float32; @@fixed_delta; end
    def self.fixed_delta=(v : Number); @@fixed_delta = v.to_f32; end
    # Clamp for huge frame times (e.g. after a breakpoint) to avoid spiral of death.
    def self.max_delta=(v : Number); @@max_delta = v.to_f32; end

    # Interpolation alpha between the last two fixed steps (for smooth rendering).
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
