require "./wav"
require "./vorbis"

module Eagle
  # Decoded audio in memory: interleaved `Float32` samples from -1 to 1.
  #
  # A `Sound` wraps one. You deal with buffers directly only when generating or analyzing
  # audio sample by sample.
  class AudioBuffer
    # Samples per second per channel, such as 44100 or 48000.
    getter sample_rate : Int32
    # 1 for mono, 2 for stereo.
    getter channels : Int32
    # The interleaved samples: left, right, left, right for stereo.
    getter samples : Slice(Float32)

    # Wraps existing samples.
    def initialize(@sample_rate : Int32, @channels : Int32, @samples : Slice(Float32))
    end

    # Number of frames, where one frame holds one sample per channel.
    def frames : Int32; @samples.size // @channels; end
    # Length in seconds.
    def duration : Float32; frames / @sample_rate.to_f32; end

    # Sample for a channel at a frame index (clamped).
    @[AlwaysInline]
    # The sample for *channel* at *frame*, with *frame* clamped to the buffer.
    def at(frame : Int32, channel : Int32) : Float32
      return 0_f32 if frame < 0 || frame >= frames
      @samples[frame * @channels + (channel < @channels ? channel : @channels - 1)]
    end
  end

  # A sound effect or music track loaded into memory. Play it as often as you like; each
  # `play` returns a `Voice` that you can adjust or stop independently.
  #
  # Eagle decodes WAV and Ogg Vorbis in pure Crystal, and can synthesize simple sounds,
  # which is great for prototypes and jams.
  #
  # ```
  # jump = Sound.load("res://sfx/jump.wav")
  # jump.play(volume: 0.8, pitch: 0.9 + rand * 0.2) # small pitch variation sounds natural
  #
  # music = Sound.load("res://music/theme.ogg")
  # voice = music.play(loop: true, bus: "music")
  # voice.fade(0, 2.0) # fade out over two seconds
  #
  # beep = Sound.tone(880, 0.15, Sound::Wave::Square, volume: 0.3)
  # laser = Sound.generate(0.3) { |t| Math.sin(t * 2000 * (1 - t * 2)).to_f32 * (1 - t / 0.3) }
  # ```
  #
  # Sounds are fully decoded into memory. That is fine for effects and short loops; long
  # tracks cost a few tens of megabytes each.
  class Sound
    # The decoded samples.
    getter buffer : AudioBuffer
    # A label for debugging: the file path for loaded sounds.
    getter name : String

    # Wraps an `AudioBuffer`.
    def initialize(@buffer : AudioBuffer, @name : String = "sound")
    end

    # Loads a WAV or Ogg Vorbis file through the asset cache.
    def self.load(path : String) : Sound
      Assets.sound(path)
    end

    # Decodes WAV or Ogg Vorbis bytes, detecting the format from the data.
    def self.decode(data : Bytes, hint : String = "") : Sound
      if Codecs::WAV.wav?(data)
        Sound.new(Codecs::WAV.decode(data), hint)
      elsif Codecs::Vorbis.ogg?(data)
        Sound.new(Codecs::Vorbis.decode(data), hint)
      else
        raise AssetError.new("Unknown audio format#{hint.empty? ? "" : " for #{hint}"} (WAV and Ogg Vorbis supported)")
      end
    end

    # Writes the sound as a 16-bit WAV file.
    def save(path : String) : Nil
      File.write(path, Codecs::WAV.encode(@buffer))
    end

    # Synthesizes a mono sound sample by sample. The block receives the time in seconds and
    # returns a sample from -1 to 1.
    def self.generate(duration : Number, sample_rate : Int32 = Audio::SAMPLE_RATE, name : String = "generated", &block : Float32 -> Float32) : Sound
      n = (duration * sample_rate).to_i
      samples = Slice(Float32).new(n) { |i| block.call(i / sample_rate.to_f32).clamp(-1_f32, 1_f32) }
      Sound.new(AudioBuffer.new(sample_rate, 1, samples), name)
    end

    # Waveforms for `Sound.tone`. `Square` and `Saw` sound retro, `Sine` is pure, and `Noise`
    # suits explosions and hi-hats.
    enum Wave
      Sine
      Square
      Saw
      Triangle
      Noise
    end

    # A single note of *frequency* Hz with a short fade in and out, so it doesn't click.
    # Handy for UI beeps and chiptune effects.
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

    # Length in seconds.
    def duration : Float32; @buffer.duration; end

    # Starts playing the sound and returns its `Voice`. *pitch* 2 is an octave up and 0.5 an
    # octave down. *pan* runs from -1 (left) to 1 (right). *bus* groups voices for volume control.
    def play(volume : Number = 1, pitch : Number = 1, pan : Number = 0, loop : Bool = false, bus : String = "master") : Voice
      Audio.play(self, volume, pitch, pan, loop, bus)
    end
  end

  # One playing instance of a `Sound`. Keep it to change volume, pitch or pan while it
  # plays, to fade it, or to stop it.
  #
  # ```
  # engine = Sound.tone(110, 1.0, Sound::Wave::Saw).play(loop: true, volume: 0.2)
  # speed = 0.5
  # engine.pitch = 0.8 + speed * 0.8 # rev up with speed
  # engine.fade(0, 0.5)
  # ```
  class Voice
    # The sound being played.
    getter sound : Sound
    # Volume from 0 to 1. Values above 1 amplify.
    property volume : Float32
    # Playback speed: 1 is normal, 2 is an octave up.
    property pitch : Float32
    # Stereo position from -1 (left) to 1 (right).
    property pan : Float32

    # Sets `volume` from any number.
    def volume=(v : Number); @volume = v.to_f32; end
    # Sets `pitch` from any number.
    def pitch=(v : Number); @pitch = v.to_f32; end
    # Sets `pan` from any number.
    def pan=(v : Number); @pan = v.to_f32; end
    # Whether playback restarts at the end.
    property? loop : Bool
    # The bus this voice mixes into. See `Audio.bus`.
    property bus : String
    @playing = true
    @finished = false
    @position = 0_f64
    # Optional fade target (volume, seconds remaining).
    @fade_to : Float32? = nil
    @fade_rate = 0_f32

    signal finished

    # True while the voice is producing sound. False when paused or finished.
    def playing? : Bool; @playing; end
    # True once the voice reached the end or was stopped. A finished voice can't be resumed.
    def finished? : Bool; @finished; end

    # Creates a voice. Use `Sound#play` or `Audio.play` instead, which also start it.
    def initialize(@sound, volume : Number, pitch : Number, pan : Number, @loop, @bus = "master")
      @volume = volume.to_f32; @pitch = pitch.to_f32; @pan = pan.to_f32
    end

    # Playback position in seconds.
    def position : Float32; (@position / @sound.buffer.sample_rate).to_f32; end
    # Seeks to *seconds*.
    def position=(seconds : Number); @position = (seconds * @sound.buffer.sample_rate).to_f64; end
    # Stops playback for good.
    def stop : Nil; @playing = false; @finished = true; end
    # Pauses playback. Call `resume` to continue from the same spot.
    def pause : Nil; @playing = false; end
    # Continues after `pause`.
    def resume : Nil; @playing = true unless @finished; end

    # Ramps the volume to *to* over *seconds*. A fade to 0 is the smooth way to stop music.
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

  # Audio you generate on the fly, a block of samples at a time: synthesizers, engine hum,
  # procedural music.
  #
  # Subclass it, implement `fill`, and register it with `Audio.add_stream`.
  #
  # ```
  # class Hum < AudioStream
  #   @phase = 0.0
  #
  #   def fill(buf : Slice(Float32), frames : Int32, sample_rate : Int32) : Nil
  #     frames.times do |i|
  #       s = (Math.sin(@phase) * 0.2).to_f32
  #       buf[i * 2] = s     # left
  #       buf[i * 2 + 1] = s # right
  #       @phase += Math::TAU * 60 / sample_rate
  #     end
  #   end
  # end
  #
  # Audio.add_stream(Hum.new)
  # ```
  abstract class AudioStream
    # Volume applied to what `fill` writes.
    property volume : Float32 = 1_f32
    # False after `stop`. The mixer then drops the stream.
    getter? playing = true
    # Stops the stream.
    def stop : Nil; @playing = false; end
    # Writes *frames* stereo frames of interleaved samples into *buf*. It runs on the main thread
    # once per frame, so keep it fast.
    abstract def fill(buf : Slice(Float32), frames : Int32, sample_rate : Int32) : Nil
  end

  # The mixer: global volume, named buses, and the list of playing voices.
  #
  # Eagle mixes audio in Crystal and sends it to the device, SDL on desktop and WebAudio
  # in the browser. Browsers only allow sound after the first click or key press.
  #
  # Buses group voices so players can set music and effects volume separately:
  #
  # ```
  # Audio.bus("music").volume = 0.5
  # Audio.bus("sfx").muted = true
  # Audio.volume = 0.8 # master volume, applies to everything
  # Audio.stop_all
  # ```
  module Audio
    # Output sample rate requested from the device.
    SAMPLE_RATE = 48000
    # Seconds of audio kept queued ahead of the device. Lower means more responsive
    # sound but a higher risk of crackles.
    TARGET_LATENCY = 0.06 # seconds queued ahead of the device

    # A named group of voices with a shared volume and mute switch. Get one with `Audio.bus`.
    class Bus
      # Volume for every voice on this bus.
      property volume : Float32 = 1_f32
      # Silences the bus without losing its volume setting.
      property? muted = false
      # Sets `volume` from any number.
      def volume=(v : Number); @volume = v.to_f32; end
      # The effective volume: 0 when muted, otherwise `volume`.
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

    # Opens the audio device. `Eagle.run` calls this unless `Config#audio` is false.
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

    # True when an audio device is open.
    def self.enabled? : Bool; @@enabled; end
    # The actual output sample rate.
    def self.sample_rate : Int32; @@sample_rate; end
    # Every voice currently playing.
    def self.voices : Array(Voice); @@voices; end
    # Number of voices currently playing.
    def self.voice_count : Int32; @@voices.size; end
    # Caps simultaneous voices (64 by default). When full, the oldest non-looping voice is cut
    # off, so rapid-fire effects can't drown out music.
    def self.max_voices=(n : Int32); @@max_voices = n; end

    # The bus called *name*, created on first use. The default bus is "master".
    def self.bus(name : String) : Bus
      @@buses[name] ||= Bus.new
    end

    # The master bus.
    def self.master : Bus; @@buses["master"]; end
    # Master volume.
    def self.volume : Float32; master.volume; end
    # Sets the master volume.
    def self.volume=(v : Number); master.volume = v.to_f32; end

    # Plays a sound and returns its voice. Same as `Sound#play`.
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

    # Starts mixing a stream. Returns it.
    def self.add_stream(s : AudioStream) : AudioStream
      @@streams << s
      s
    end

    # Stops mixing a stream.
    def self.remove_stream(s : AudioStream) : Nil
      @@streams.delete(s)
    end

    # Stops every voice and stream.
    def self.stop_all : Nil
      @@voices.each(&.stop)
      @@voices.clear
    end

    # Mixes *frames* stereo frames and returns them, without touching the device. Used by tests.
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

    # Closes the audio device.
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
