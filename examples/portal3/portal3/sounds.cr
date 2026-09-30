module Portal3
  # Every sound is synthesised at load, so the game has a full soundscape with no
  # audio files. They are built lazily, since creating a sound needs the audio device.
  module Sounds
    extend self

    # Every sound the game can play, so the self test can check them all.
    NAMES = [
      :portal_open, :portal_close, :portal_enter, :portal_deny,
      :step, :button, :button_up, :door, :death, :pickup, :drop,
      :chime, :fizz, :laser,
    ]

    @@cache = {} of Symbol => Sound

    def [](key : Symbol) : Sound
      @@cache[key] ||= build(key)
    end

    # Every sound is scaled to this peak, so a quiet generator does not need a bigger
    # volume passed at every call site and the mix stays even as sounds are added.
    PEAK = 0.82_f32

    # Wraps a generator so the maths can be written in Float64 and the engine still
    # gets the Float32 samples it expects. The result is normalised to a common peak,
    # which is what keeps the mix from drifting as generators are tuned.
    private def wave(duration : Float64, &block : Float64 -> Float64) : Sound
      sound = Sound.generate(duration) { |t| block.call(t.to_f64).to_f32 }
      normalise(sound)
    end

    # Scales a sound so its loudest sample sits at PEAK, leaving anything already
    # quieter alone rather than amplifying noise.
    private def normalise(sound : Sound) : Sound
      samples = sound.buffer.samples
      peak = 0_f32
      samples.each { |sample| peak = sample.abs if sample.abs > peak }
      return sound if peak <= 0.001 || peak >= PEAK
      scale = PEAK / peak
      samples.each_with_index { |sample, i| samples[i] = sample * scale }
      sound
    end

    private def build(key : Symbol) : Sound
      case key
      when :portal_open  then portal_open
      when :portal_close then portal_close
      when :portal_enter then portal_enter
      when :portal_deny  then portal_deny
      when :step         then step
      when :button       then button
      when :button_up    then button_up
      when :door         then door
      when :death        then death
      when :pickup       then pickup
      when :drop         then drop
      when :chime        then chime
      when :fizz         then fizz
      when :laser        then laser
      else                    chime
      end
    end

    # The device firing: a bright rising sweep with a shimmer on top.
    def portal_open : Sound
      wave(0.5) do |t|
        f = 220.0 + 900.0 * (1.0 - Math.exp(-t * 7.0))
        env = Math.exp(-t * 4.2) * Math.min(1.0, t * 60.0)
        (Math.sin(t * f * Math::TAU) * 0.5 + Math.sin(t * f * 2.02 * Math::TAU) * 0.2) * env * 0.5
      end
    end

    def portal_close : Sound
      wave(0.28) do |t|
        f = 900.0 * Math.exp(-t * 6.0) + 120.0
        Math.sin(t * f * Math::TAU) * Math.exp(-t * 9.0) * 0.4
      end
    end

    # Passing through: a short doppler whoosh.
    def portal_enter : Sound
      wave(0.42) do |t|
        f = 140.0 + 700.0 * Math.sin(Math::PI * t * 1.6)
        env = Math.sin(Math::PI * (t / 0.42)).clamp(0.0, 1.0)
        (Math.sin(t * f * Math::TAU) * 0.4 + Math.sin(t * f * 1.5 * Math::TAU) * 0.2) * env * 0.55
      end
    end

    # Firing at a surface that cannot hold a portal.
    def portal_deny : Sound
      wave(0.12) do |t|
        Math.sin(t * 180.0 * Math::TAU) * Math.exp(-t * 22.0) * 0.3
      end
    end

    def step : Sound
      rng = Random.new(11)
      wave(0.1) do |t|
        (rng.rand(-1.0..1.0) * 0.5 + Math.sin(t * 90.0 * Math::TAU) * 0.3) * Math.exp(-t * 40.0) * 0.5
      end
    end

    def button : Sound
      wave(0.22) do |t|
        (Math.sin(t * 320.0 * Math::TAU) * 0.5 + Math.sin(t * 520.0 * Math::TAU) * 0.25) * Math.exp(-t * 18.0) * 0.55
      end
    end

    def button_up : Sound
      wave(0.18) do |t|
        Math.sin(t * 260.0 * Math::TAU) * Math.exp(-t * 22.0) * 0.4
      end
    end

    # The mechanical grind of a door panel.
    def door : Sound
      rng = Random.new(29)
      wave(0.6) do |t|
        (rng.rand(-1.0..1.0) * 0.25 + Math.sin(t * 70.0 * Math::TAU) * 0.35) * Math.min(1.0, t * 20.0) * Math.exp(-t * 2.4) * 0.4
      end
    end

    def death : Sound
      wave(0.75) do |t|
        f = 380.0 * Math.exp(-t * 3.2)
        (Math.sin(t * f * Math::TAU) * 0.5 + Math.sin(t * f * 0.5 * Math::TAU) * 0.3) * Math.exp(-t * 3.5) * 0.6
      end
    end

    def pickup : Sound
      wave(0.16) do |t|
        Math.sin(t * 480.0 * Math::TAU) * Math.exp(-t * 20.0) * 0.35
      end
    end

    def drop : Sound
      wave(0.18) do |t|
        (Math.sin(t * 200.0 * Math::TAU) * 0.4 + Math.sin(t * 340.0 * Math::TAU) * 0.2) * Math.exp(-t * 16.0) * 0.4
      end
    end

    # A short two-note sting, used before each of the announcer's lines.
    def chime : Sound
      wave(0.9) do |t|
        a = Math.sin(t * 587.33 * Math::TAU) * Math.exp(-t * 3.0)
        b = t > 0.16 ? Math.sin((t - 0.16) * 880.0 * Math::TAU) * Math.exp(-(t - 0.16) * 3.0) : 0.0
        (a * 0.3 + b * 0.25) * Math.min(1.0, t * 40.0)
      end
    end

    # The fizz of something being destroyed.
    def fizz : Sound
      rng = Random.new(53)
      wave(0.7) do |t|
        (rng.rand(-1.0..1.0) * 0.6 + Math.sin(t * 60.0 * Math::TAU) * 0.3) * Math.exp(-t * 3.0) * 0.4
      end
    end

    # A continuous hum for a laser emitter.
    def laser : Sound
      wave(1.0) do |t|
        (Math.sin(t * 165.0 * Math::TAU) * 0.2 + Math.sin(t * 330.0 * Math::TAU) * 0.08) * 0.5
      end
    end
  end
end
