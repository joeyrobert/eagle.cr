module Eagle
  # How a 3D sound gets quieter with distance, used by `Spatial3D#attenuation`.
  #
  # Every model plays at full volume inside `min_distance` and stops changing past
  # `max_distance`. `rolloff` controls how fast the volume falls in between.
  #
  # ```
  # gun = AudioPlayer3D.new(Sound.tone(220, 0.2, Sound::Wave::Noise))
  # gun.attenuation = Attenuation::Linear # silent at max_distance
  # gun.max_distance = 60
  # ```
  enum Attenuation
    # Natural fall-off: half the volume at twice `min_distance` (with `rolloff` 1). Never quite silent.
    Inverse
    # Straight line from full volume at `min_distance` to silence at `max_distance` (with `rolloff` 1).
    Linear
    # Falls off by `(distance / min_distance) ** -rolloff`, steeper than inverse for `rolloff` above 1.
    Exponential
  end

  # 3D positioning for a `Voice`: where the sound is, how it fades with distance, and the
  # state the mixer needs to place it between the ears.
  #
  # You rarely create one yourself. `AudioPlayer3D` and `Audio.play_at` attach one to their
  # voice, and the mixer updates it against `Audio.listener` every time it renders. Reach for
  # it to move a one-shot voice without a node, or to read the gains for a debug overlay.
  #
  # Per voice the mixer applies distance attenuation, equal-power stereo panning from the
  # direction in listener space, a small interaural time difference (the far ear hears the
  # sound up to `MAX_ITD` seconds later) and a head-shadow low-pass on the far ear and on
  # sounds behind the listener, so left, right, front and back are distinguishable on
  # headphones. Doppler is optional. Every parameter glides across one mixed buffer, so moving
  # sources don't click.
  #
  # ```
  # rocket = Audio.play_at(Sound.tone(90, 3, Sound::Wave::Saw, volume: 0.3), v3(0, 1, -20), loop: true)
  # if sp = rocket.spatial
  #   sp.position = v3(0, 1, -15) # move it each frame as the rocket flies
  #   sp.velocity = v3(0, 0, 30)  # used for doppler
  #   sp.doppler = true
  # end
  # ```
  class Spatial3D
    # Largest delay between the ears, in seconds (roughly a human head).
    MAX_ITD = 0.00066_f32
    # Frequency the far ear is low-passed to when fully shadowed.
    SHADOW_CUTOFF = 900_f32
    # How much of the head shadow comes from facing away: 1 muffles sounds straight behind fully.
    BACK_SHADOW = 0.55_f32
    # Volume kept for a sound straight behind the listener.
    BACK_GAIN = 0.8_f32
    # How far toward one ear panning goes for a source straight to the side. Below 1 the far
    # ear still hears it, as with a real head; the delay and low-pass carry the rest.
    PAN_WIDTH = 0.8_f32
    # Distance over which a very close sound blends back to the center, in world units.
    NEAR_FIELD = 0.25_f32
    # delay line length, a power of two above MAX_ITD at 48 kHz
    private RING = 64
    # indices into the parameter arrays
    private GAIN_L  = 0
    private GAIN_R  = 1
    private DELAY_L = 2
    private DELAY_R = 3
    private COEF_L  = 4
    private COEF_R  = 5
    private PITCH   = 6

    # Source position in world space.
    property position : Vec3
    # Source velocity in world units per second, used for doppler.
    property velocity : Vec3 = Vec3::ZERO
    # The distance model.
    property attenuation : Attenuation = Attenuation::Inverse
    # Distance inside which the sound plays at full volume.
    property min_distance : Float32 = 1_f32
    # Distance past which the sound stops getting quieter (silent there with `Attenuation::Linear`).
    property max_distance : Float32 = 100_f32
    # How fast the volume falls between `min_distance` and `max_distance`. 1 is natural.
    property rolloff : Float32 = 1_f32
    # Shifts pitch with the speed of the source toward or away from the listener. Off by default.
    property? doppler = false
    # Exaggerates (above 1) or tames (below 1) the doppler effect.
    property doppler_scale : Float32 = 1_f32

    # Sets `min_distance` from any number.
    def min_distance=(v : Number); @min_distance = v.to_f32; end
    # Sets `max_distance` from any number.
    def max_distance=(v : Number); @max_distance = v.to_f32; end
    # Sets `rolloff` from any number.
    def rolloff=(v : Number); @rolloff = v.to_f32; end
    # Sets `doppler_scale` from any number.
    def doppler_scale=(v : Number); @doppler_scale = v.to_f32; end

    @cur = StaticArray(Float32, 7).new(0_f32)
    @tgt = StaticArray(Float32, 7).new(0_f32)
    @primed = false
    @ring = Slice(Float32).new(RING, 0_f32)
    @write = 0
    @lp_l = 0_f32
    @lp_r = 0_f32

    # Creates settings for a source at *position*.
    def initialize(@position : Vec3 = Vec3::ZERO, attenuation : Attenuation = Attenuation::Inverse, min_distance : Number = 1, max_distance : Number = 100, rolloff : Number = 1, doppler : Bool = false)
      @attenuation = attenuation
      @min_distance = min_distance.to_f32; @max_distance = max_distance.to_f32; @rolloff = rolloff.to_f32
      @doppler = doppler
    end

    # Volume multiplier from 0 to 1 for a source *distance* away, using this source's model.
    def distance_gain(distance : Number) : Float32
      Spatial3D.distance_gain(@attenuation, distance, @min_distance, @max_distance, @rolloff)
    end

    # Volume multiplier from 0 to 1 for a distance under a model, as OpenAL and WebAudio define it.
    def self.distance_gain(model : Attenuation, distance : Number, min_distance : Number, max_distance : Number, rolloff : Number) : Float32
      lo = Math.max(min_distance.to_f32, 1e-4_f32)
      hi = Math.max(max_distance.to_f32, lo)
      r = rolloff.to_f32
      d = distance.to_f32.clamp(lo, hi)
      g = case model
          in Attenuation::Inverse     then lo / (lo + r * (d - lo))
          in Attenuation::Linear      then hi > lo ? 1 - r * (d - lo) / (hi - lo) : 1_f32
          in Attenuation::Exponential then (d / lo) ** -r
          end
      g.to_f32.clamp(0_f32, 1_f32)
    end

    # Left ear gain the mixer is heading to, including distance and direction.
    def gain_left : Float32; @tgt[GAIN_L]; end
    # Right ear gain the mixer is heading to.
    def gain_right : Float32; @tgt[GAIN_R]; end
    # Left ear delay in seconds at *sample_rate*.
    def delay_left(sample_rate : Int32 = Audio.sample_rate) : Float32; @tgt[DELAY_L] / sample_rate; end
    # Right ear delay in seconds at *sample_rate*.
    def delay_right(sample_rate : Int32 = Audio.sample_rate) : Float32; @tgt[DELAY_R] / sample_rate; end
    # Pitch multiplier from doppler (1 when off or still).
    def doppler_pitch : Float32; @tgt[PITCH]; end

    # Recomputes the targets for *listener*. The mixer calls this before each buffer.
    def update(listener : Audio::Listener, sample_rate : Int32) : Nil
      rel = @position - listener.position
      local = listener.rotation.conjugate * rel
      dist = local.length
      gain = distance_gain(dist)
      near = Math.sqrt(dist * dist + NEAR_FIELD * NEAR_FIELD)
      side = (local.x / near).clamp(-1_f32, 1_f32)
      behind = (local.z / near).clamp(0_f32, 1_f32)
      gain *= 1 - (1 - BACK_GAIN) * behind
      theta = (side * PAN_WIDTH + 1) * Math::PI / 4
      @tgt[GAIN_L] = (Math.cos(theta) * gain).to_f32
      @tgt[GAIN_R] = (Math.sin(theta) * gain).to_f32
      itd = MAX_ITD * sample_rate * side.abs
      @tgt[DELAY_L] = side > 0 ? itd : 0_f32
      @tgt[DELAY_R] = side < 0 ? itd : 0_f32
      coef_min = (1 - Math.exp(-Math::TAU * SHADOW_CUTOFF / sample_rate)).to_f32
      shadow_l = Math.min(Math.max(side, 0_f32) + BACK_SHADOW * behind, 1_f32)
      shadow_r = Math.min(Math.max(-side, 0_f32) + BACK_SHADOW * behind, 1_f32)
      @tgt[COEF_L] = 1 - (1 - coef_min) * shadow_l
      @tgt[COEF_R] = 1 - (1 - coef_min) * shadow_r
      @tgt[PITCH] = @doppler ? doppler_factor(rel, dist, listener.velocity) : 1_f32
      unless @primed
        @cur = @tgt
        @primed = true
      end
    end

    private def doppler_factor(rel : Vec3, dist : Float32, listener_velocity : Vec3) : Float32
      return 1_f32 if dist < 1e-4
      dir = rel / dist
      c = Audio.speed_of_sound
      limit = c * 0.9_f32
      vl = (listener_velocity.dot(dir) * @doppler_scale).clamp(-limit, limit)
      vs = (@velocity.dot(dir) * @doppler_scale).clamp(-limit, limit)
      ((c + vl) / (c + vs)).clamp(0.25_f32, 4_f32)
    end

    # :nodoc: Mixes *frames* frames of *voice* into *dest* as stereo.
    # Parameters glide linearly from their last values to the targets over the buffer.
    def mix(voice : Voice, dest : Slice(Float32), frames : Int32, out_rate : Int32, gain : Float32) : Bool
      inv = 1_f32 / Math.max(frames, 1)
      d = StaticArray(Float32, 7).new { |k| (@tgt[k] - @cur[k]) * inv }
      c = @cur
      mask = RING - 1
      ring = @ring
      w = @write
      alive = true
      frames.times do |i|
        7.times { |k| c[k] += d[k] }
        x = voice.next_sample(out_rate, c[PITCH])
        unless x
          alive = false
          break
        end
        w = (w + 1) & mask
        ring[w] = x * gain
        @lp_l += c[COEF_L] * (tap(ring, w, c[DELAY_L], mask) - @lp_l)
        @lp_r += c[COEF_R] * (tap(ring, w, c[DELAY_R], mask) - @lp_r)
        dest[i * 2] += @lp_l * c[GAIN_L]
        dest[i * 2 + 1] += @lp_r * c[GAIN_R]
      end
      @write = w
      @cur = @tgt
      alive
    end

    @[AlwaysInline]
    private def tap(ring : Slice(Float32), w : Int32, delay : Float32, mask : Int32) : Float32
      i = delay.to_i
      f = delay - i
      a = ring[(w - i) & mask]
      b = ring[(w - i - 1) & mask]
      a + (b - a) * f
    end
  end

  module Audio
    # Where the ears are: a position, an orientation (`Vec3::FORWARD` is straight ahead and
    # `Vec3::RIGHT` is the right ear) and a velocity for doppler. Get the current one with
    # `Audio.listener`.
    #
    # ```
    # ears = Audio.listener
    # ahead = ears.position + ears.rotation * Vec3::FORWARD * 10
    # ```
    record Listener, position : Vec3 = Vec3::ZERO, rotation : Quat = Quat::IDENTITY, velocity : Vec3 = Vec3::ZERO

    @@speed_of_sound = 343_f32
    @@listener_last : Vec3? = nil
    @@listener_velocity = Vec3::ZERO

    # Speed of sound in world units per second for doppler. 343 suits a world measured in meters.
    def self.speed_of_sound : Float32; @@speed_of_sound; end
    # Sets `speed_of_sound`. Lower values exaggerate doppler.
    def self.speed_of_sound=(v : Number); @@speed_of_sound = v.to_f32; end

    # The listener 3D sounds are heard from: the current `AudioListener3D` if there is one,
    # otherwise the current `Camera3D`, otherwise the origin facing `Vec3::FORWARD`.
    def self.listener : Listener
      node = AudioListener3D.current || Camera3D.current
      return Listener.new(velocity: @@listener_velocity) unless node
      Listener.new(node.global_position, node.global_rotation, @@listener_velocity)
    end

    # :nodoc: Tracks the listener's velocity from its motion. `Audio.update` calls it every frame.
    def self.track_listener(dt : Float32) : Nil
      pos = listener.position
      if (last = @@listener_last) && dt > 0
        @@listener_velocity = (pos - last) / dt
      end
      @@listener_last = pos
    end

    # Plays *sound* at a world position, heard from `Audio.listener`. Suits gunshots, impacts
    # and explosions that don't need a node. Move it later through `Voice#spatial`.
    #
    # ```
    # boom = Sound.tone(60, 0.6, Sound::Wave::Noise, volume: 0.8)
    # Audio.play_at(boom, v3(12, 0, -30), max_distance: 200)
    # Audio.play_at(boom, v3(-4, 0, 2), pitch: 0.9 + rand * 0.2, attenuation: Attenuation::Linear, max_distance: 40)
    # ```
    def self.play_at(sound : Sound, position : Vec3, volume : Number = 1, pitch : Number = 1, loop : Bool = false, bus : String = "master",
                     velocity : Vec3 = Vec3::ZERO, attenuation : Attenuation = Attenuation::Inverse, min_distance : Number = 1,
                     max_distance : Number = 100, rolloff : Number = 1, doppler : Bool = false) : Voice
      v = play(sound, volume, pitch, 0, loop, bus)
      sp = Spatial3D.new(position, attenuation, min_distance, max_distance, rolloff, doppler)
      sp.velocity = velocity
      v.spatial = sp
      v
    end
  end
end
