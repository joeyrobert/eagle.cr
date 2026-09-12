require "./wav"
require "./vorbis"

module Eagle
  # PCM audio in memory: interleaved Float32 samples, -1..1.
  class AudioBuffer
    getter sample_rate : Int32
    getter channels : Int32
    getter samples : Slice(Float32)

    def initialize(@sample_rate : Int32, @channels : Int32, @samples : Slice(Float32))
    end

    def frames : Int32; @samples.size // @channels; end
    def duration : Float32; frames / @sample_rate.to_f32; end

    # Sample for a channel at a frame index (clamped).
    @[AlwaysInline]
    def at(frame : Int32, channel : Int32) : Float32
      return 0_f32 if frame < 0 || frame >= frames
      @samples[frame * @channels + (channel < @channels ? channel : @channels - 1)]
    end
  end

  # A loaded/generated sound. Play it with `play`, which returns a `Voice`.
  class Sound
    getter buffer : AudioBuffer
    getter name : String

    def initialize(@buffer : AudioBuffer, @name : String = "sound")
    end

    def self.load(path : String) : Sound
      Assets.sound(path)
    end

    def self.decode(data : Bytes, hint : String = "") : Sound
      if Codecs::WAV.wav?(data)
        Sound.new(Codecs::WAV.decode(data), hint)
      elsif Codecs::Vorbis.ogg?(data)
        Sound.new(Codecs::Vorbis.decode(data), hint)
      else
        raise AssetError.new("Unknown audio format#{hint.empty? ? "" : " for #{hint}"} (WAV and Ogg Vorbis supported)")
      end
    end

    def save(path : String) : Nil
      File.write(path, Codecs::WAV.encode(@buffer))
    end

    # Generate a mono sound; the block receives time in seconds and returns -1..1.
    def self.generate(duration : Number, sample_rate : Int32 = Audio::SAMPLE_RATE, name : String = "generated", &block : Float32 -> Float32) : Sound
      n = (duration * sample_rate).to_i
      samples = Slice(Float32).new(n) { |i| block.call(i / sample_rate.to_f32).clamp(-1_f32, 1_f32) }
      Sound.new(AudioBuffer.new(sample_rate, 1, samples), name)
    end

    enum Wave
      Sine
      Square
      Saw
      Triangle
      Noise
    end

    # A simple tone with an attack/release envelope to avoid clicks.
    def self.tone(frequency : Number, duration : Number, wave : Wave = Wave::Sine, volume : Number = 0.5, attack : Number = 0.005, release : Number = 0.02, sample_rate : Int32 = Audio::SAMPLE_RATE) : Sound
      rng = Random.new(1)
      f = frequency.to_f32; d = duration.to_f32; v = volume.to_f32
      generate(d, sample_rate, "tone#{f}") do |t|
        phase = (t * f) % 1
        s = case wave
            in Wave::Sine then Math.sin(phase * Math::PI * 2)
            in Wave::Square then phase < 0.5 ? 1.0 : -1.0
            in Wave::Saw then phase * 2 - 1
            in Wave::Triangle then phase < 0.5 ? phase * 4 - 1 : 3 - phase * 4
            in Wave::Noise then rng.rand(-1.0..1.0)
            end
        env = 1_f32
        env = Math.min(env, t / attack) if attack > 0
        env = Math.min(env, (d - t) / release) if release > 0
        (s * v * env.clamp(0_f32, 1_f32)).to_f32
      end
    end

    def duration : Float32; @buffer.duration; end

    def play(volume : Number = 1, pitch : Number = 1, pan : Number = 0, loop : Bool = false, bus : String = "master") : Voice
      Audio.play(self, volume, pitch, pan, loop, bus)
    end
  end

  # A playing instance of a sound.
  class Voice
    getter sound : Sound
    property volume : Float32
    property pitch : Float32
    # -1 (left) .. 1 (right)
    property pan : Float32
    property? loop : Bool
    property bus : String
    @playing = true
    @finished = false
    @position = 0_f64
    # Optional fade target (volume, seconds remaining).
    @fade_to : Float32? = nil
    @fade_rate = 0_f32

    signal finished

    def playing? : Bool; @playing; end
    def finished? : Bool; @finished; end

    def initialize(@sound, volume : Number, pitch : Number, pan : Number, @loop, @bus = "master")
      @volume = volume.to_f32; @pitch = pitch.to_f32; @pan = pan.to_f32
    end

    # Playback position in seconds.
    def position : Float32; (@position / @sound.buffer.sample_rate).to_f32; end
    def position=(seconds : Number); @position = (seconds * @sound.buffer.sample_rate).to_f64; end
    def stop : Nil; @playing = false; @finished = true; end
    def pause : Nil; @playing = false; end
    def resume : Nil; @playing = true unless @finished; end

    def fade(to : Number, seconds : Number) : Nil
      @fade_to = to.to_f32
      @fade_rate = ((to - @volume) / Math.max(seconds, 0.001)).to_f32
    end

    # :nodoc: Mix `frames` stereo frames into `out` (additive). Returns false when done.
    def mix(mix_buf : Slice(Float32), frames : Int32, out_rate : Int32, bus_gain : Float32) : Bool
      return false if @finished
      return true unless @playing
      buf = @sound.buffer
      step = @pitch.to_f64 * buf.sample_rate / out_rate
      total = buf.frames
      left_gain = Math.sqrt(0.5 * (1 - @pan)).to_f32
      right_gain = Math.sqrt(0.5 * (1 + @pan)).to_f32
      fade_per_frame = @fade_rate / out_rate
      frames.times do |i|
        if @position >= total
          if @loop && total > 0
            @position -= total
          else
            @finished = true
            @playing = false
            return false
          end
        end
        if (ft = @fade_to)
          @volume += fade_per_frame
          if (fade_per_frame >= 0 && @volume >= ft) || (fade_per_frame < 0 && @volume <= ft)
            @volume = ft
            @fade_to = nil
            if ft <= 0
              @finished = true; @playing = false
              return false
            end
          end
        end
        f0 = @position.to_i
        frac = (@position - f0).to_f32
        f1 = f0 + 1
        f1 = @loop ? f1 % total : Math.min(f1, total - 1)
        gain = @volume * bus_gain
        if buf.channels == 1
          s = buf.at(f0, 0) * (1 - frac) + buf.at(f1, 0) * frac
          mix_buf[i * 2] += s * gain * left_gain
          mix_buf[i * 2 + 1] += s * gain * right_gain
        else
          l = buf.at(f0, 0) * (1 - frac) + buf.at(f1, 0) * frac
          r = buf.at(f0, 1) * (1 - frac) + buf.at(f1, 1) * frac
          mix_buf[i * 2] += l * gain * left_gain * 1.4142_f32
          mix_buf[i * 2 + 1] += r * gain * right_gain * 1.4142_f32
        end
        @position += step
      end
      true
    end
  end

  # A procedural stream: implement `fill(buf, frames, rate)` writing interleaved stereo.
  abstract class AudioStream
    property volume : Float32 = 1_f32
    getter? playing = true
    def stop : Nil; @playing = false; end
    abstract def fill(buf : Slice(Float32), frames : Int32, sample_rate : Int32) : Nil
  end

  # The mixer. Audio is mixed in Crystal on the main thread each frame and
  # pushed to the platform's output queue, keeping ~`TARGET_LATENCY` buffered.
  module Audio
    SAMPLE_RATE = 48000
    TARGET_LATENCY = 0.06 # seconds queued ahead of the device

    class Bus
      property volume : Float32 = 1_f32
      property? muted = false
      def gain : Float32; @muted ? 0_f32 : @volume; end
    end

    @@platform : Platform::Base? = nil
    @@sample_rate = SAMPLE_RATE
    @@voices = [] of Voice
    @@streams = [] of AudioStream
    @@buses = {"master" => Bus.new}
    @@mix = Slice(Float32).new(0)
    @@enabled = false
    @@max_voices = 64
    @@last_finished = [] of Voice

    def self.init(platform : Platform::Base) : Nil
      @@platform = platform
      rate = platform.open_audio(SAMPLE_RATE, 1024)
      if rate > 0
        @@sample_rate = rate
        @@enabled = true
        Eagle.log.info { "Audio: #{rate} Hz stereo float" }
      else
        @@enabled = false
      end
    end

    def self.enabled? : Bool; @@enabled; end
    def self.sample_rate : Int32; @@sample_rate; end
    def self.voices : Array(Voice); @@voices; end
    def self.voice_count : Int32; @@voices.size; end
    def self.max_voices=(n : Int32); @@max_voices = n; end

    def self.bus(name : String) : Bus
      @@buses[name] ||= Bus.new
    end

    def self.master : Bus; @@buses["master"]; end
    def self.volume : Float32; master.volume; end
    def self.volume=(v : Number); master.volume = v.to_f32; end

    def self.play(sound : Sound, volume : Number = 1, pitch : Number = 1, pan : Number = 0, loop : Bool = false, bus : String = "master") : Voice
      v = Voice.new(sound, volume, pitch, pan, loop, bus)
      if @@voices.size >= @@max_voices
        # steal the oldest non-looping voice
        idx = @@voices.index { |x| !x.loop? } || 0
        @@voices[idx].stop
        @@voices.delete_at(idx)
      end
      @@voices << v
      v
    end

    def self.add_stream(s : AudioStream) : AudioStream
      @@streams << s
      s
    end

    def self.remove_stream(s : AudioStream) : Nil
      @@streams.delete(s)
    end

    def self.stop_all : Nil
      @@voices.each(&.stop)
      @@voices.clear
    end

    # Mix `frames` stereo frames and return them (used by update and by tests).
    def self.render(frames : Int32) : Slice(Float32)
      needed = frames * 2
      @@mix = Slice(Float32).new(needed) if @@mix.size < needed
      buf = @@mix[0, needed]
      buf.fill(0_f32)
      master_gain = master.gain
      @@voices.reject! do |v|
        gain = (v.bus == "master" ? 1_f32 : bus(v.bus).gain) * master_gain
        alive = v.mix(buf, frames, @@sample_rate, gain)
        if v.finished?
          v.emit_finished
          true
        else
          !alive
        end
      end
      @@streams.reject! do |s|
        next true unless s.playing?
        s.fill(buf, frames, @@sample_rate)
        false
      end
      # soft clip
      needed.times do |i|
        x = buf[i]
        buf[i] = x > 1 ? 1_f32 : (x < -1 ? -1_f32 : x)
      end
      buf
    end

    # :nodoc: Called once per frame by the engine.
    def self.update : Nil
      return unless @@enabled
      pf = @@platform
      return unless pf
      target = (TARGET_LATENCY * @@sample_rate).to_i
      queued = pf.queued_audio_frames
      return if queued >= target
      frames = target - queued
      frames = Math.min(frames, @@sample_rate) # never more than 1s at once
      pf.queue_audio(render(frames))
    end

    def self.shutdown : Nil
      stop_all
      @@streams.clear
      @@platform.try(&.close_audio)
      @@platform = nil
      @@enabled = false
    end

    # :nodoc: for tests without a device
    def self.reset : Nil
      stop_all
      @@streams.clear
      @@buses = {"master" => Bus.new}
      @@sample_rate = SAMPLE_RATE
    end
  end
end
