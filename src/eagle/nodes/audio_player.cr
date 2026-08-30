module Eagle
  # Shared playback logic for AudioPlayer / AudioPlayer2D.
  module AudioPlayback
    property sound : Sound? = nil
    property volume : Float32 = 1_f32
    property pitch : Float32 = 1_f32
    property pan : Float32 = 0_f32
    property? loop = false
    property? autoplay = false
    property bus : String = "master"
    getter voice : Voice? = nil

    signal finished

    def play(sound : Sound? = nil) : Voice?
      @sound = sound if sound
      s = @sound
      return nil unless s
      stop
      v = s.play(effective_volume, @pitch, effective_pan, @loop, @bus)
      v.on_finished { emit_finished if @voice == v }
      @voice = v
    end

    def stop : Nil
      @voice.try(&.stop)
      @voice = nil
    end

    def playing? : Bool
      @voice.try { |v| v.playing? && !v.finished? } || false
    end

    def update_voice : Nil
      if v = @voice
        v.volume = effective_volume
        v.pitch = @pitch
        v.pan = effective_pan
      end
    end

    def effective_volume : Float32; @volume; end
    def effective_pan : Float32; @pan; end
  end

  # Plays a Sound from the scene tree.
  #
  #   root.add(AudioPlayer.new(Sound.load("jump.wav")))
  class AudioPlayer < Node
    include AudioPlayback

    def initialize(sound : Sound? = nil, name : String = "", volume : Number = 1, loop : Bool = false, autoplay : Bool = false)
      super(name)
      @sound = sound; @volume = volume.to_f32; @loop = loop; @autoplay = autoplay
    end

    def self.load(path : String, **opts) : AudioPlayer
      new(Sound.load(path), **opts)
    end

    def ready : Nil; play if @autoplay; end
    def process(dt : Float32) : Nil; update_voice; end
    def exit_tree : Nil; stop; end
  end

  # Positional 2D audio: volume falls off with distance from the listener
  # (the current Camera2D, or the origin) and pans by horizontal offset.
  class AudioPlayer2D < Node2D
    include AudioPlayback
    property max_distance : Float32 = 800_f32
    property attenuation : Float32 = 1_f32
    property pan_width : Float32 = 600_f32

    def initialize(sound : Sound? = nil, position : Vec2 = Vec2::ZERO, name : String = "", volume : Number = 1, loop : Bool = false, autoplay : Bool = false, max_distance : Number = 800)
      super(name, position)
      @sound = sound; @volume = volume.to_f32; @loop = loop; @autoplay = autoplay
      @max_distance = max_distance.to_f32
    end

    def listener_position : Vec2
      Camera2D.current.try(&.effective_position) || Vec2::ZERO
    end

    def effective_volume : Float32
      d = global_position.distance(listener_position)
      return @volume if d <= 0
      t = (1 - d / @max_distance).clamp(0_f32, 1_f32)
      @volume * (t ** @attenuation)
    end

    def effective_pan : Float32
      dx = global_position.x - listener_position.x
      (dx / @pan_width).clamp(-1_f32, 1_f32)
    end

    def ready : Nil; play if @autoplay; end
    def process(dt : Float32) : Nil; update_voice; end
    def exit_tree : Nil; stop; end
  end
end
