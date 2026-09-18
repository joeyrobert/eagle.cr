module Eagle
  # Playback settings shared by `AudioPlayer` and `AudioPlayer2D`.
  module AudioPlayback
    # The sound to play.
    property sound : Sound? = nil
    # Volume from 0 to 1.
    property volume : Float32 = 1_f32
    # Playback speed: 1 is normal.
    property pitch : Float32 = 1_f32
    # Stereo position from -1 to 1. `AudioPlayer2D` computes it from position instead.
    property pan : Float32 = 0_f32
    # Restart from the beginning when the sound ends.
    property? loop = false
    # Start playing when the node enters the tree.
    property? autoplay = false
    # The mixer bus, such as "music" or "sfx". See `Audio.bus`.
    property bus : String = "master"
    # Sets `volume` from any number.
    def volume=(v : Number); @volume = v.to_f32; end
    # Sets `pitch` from any number.
    def pitch=(v : Number); @pitch = v.to_f32; end
    # Sets `pan` from any number.
    def pan=(v : Number); @pan = v.to_f32; end
    # The voice currently playing, if any.
    getter voice : Voice? = nil

    signal finished

    # Plays *sound*, or the current `sound`. Stops what was playing first. Returns the voice.
    def play(sound : Sound? = nil) : Voice?
      @sound = sound if sound
      s = @sound
      return nil unless s
      stop
      v = s.play(effective_volume, @pitch, effective_pan, @loop, @bus)
      v.on_finished { emit_finished if @voice == v }
      @voice = v
    end

    # Stops playback.
    def stop : Nil
      @voice.try(&.stop)
      @voice = nil
    end

    # True while the sound is playing.
    def playing? : Bool
      @voice.try { |v| v.playing? && !v.finished? } || false
    end

    # Pushes volume, pitch and pan to the playing voice. Called every frame.
    def update_voice : Nil
      if v = @voice
        v.volume = effective_volume
        v.pitch = @pitch
        v.pan = effective_pan
      end
    end

    # The volume actually used.
    def effective_volume : Float32; @volume; end
    # The pan actually used.
    def effective_pan : Float32; @pan; end
  end

  # Plays a sound as part of the scene tree. It stops automatically when the node is removed,
  # so music tied to a level ends with the level.
  #
  # ```
  # music = AudioPlayer.load("res://music/level1.ogg", loop: true, autoplay: true)
  # music.bus = "music"
  # SceneTree.root.add(music)
  # ```
  class AudioPlayer < Node
    include AudioPlayback

    # Creates a player.
    def initialize(sound : Sound? = nil, name : String = "", volume : Number = 1, loop : Bool = false, autoplay : Bool = false)
      super(name)
      @sound = sound; @volume = volume.to_f32; @loop = loop; @autoplay = autoplay
    end

    # Creates a player for a sound file. Accepts the same named arguments as `new`.
    def self.load(path : String, **opts) : AudioPlayer
      new(Sound.load(path), **opts)
    end

    # Starts playing if `autoplay` is set.
    def ready : Nil; play if @autoplay; end
    # Keeps the voice in sync. Called by the engine.
    def process(dt : Float32) : Nil; update_voice; end
    # Stops playback when removed.
    def exit_tree : Nil; stop; end
  end

  # A sound with a position. It gets quieter with distance from the listener and pans left or
  # right, which suits footsteps, explosions and ambient loops placed in the level.
  #
  # The listener is the current `Camera2D`, or the origin when there is none.
  #
  # ```
  # waterfall = AudioPlayer2D.new(Sound.tone(200, 2, Sound::Wave::Noise), position: v2(900, 300), loop: true, autoplay: true)
  # waterfall.max_distance = 600
  # SceneTree.root.add(waterfall)
  # ```
  class AudioPlayer2D < Node2D
    include AudioPlayback
    # Distance at which the sound becomes silent.
    property max_distance : Float32 = 800_f32
    # Shape of the fall-off: 1 is linear, and higher values fade faster near the source.
    property attenuation : Float32 = 1_f32
    # Horizontal distance at which the sound is fully in one speaker.
    property pan_width : Float32 = 600_f32

    # Creates a positional player.
    def initialize(sound : Sound? = nil, position : Vec2 = Vec2::ZERO, name : String = "", volume : Number = 1, loop : Bool = false, autoplay : Bool = false, max_distance : Number = 800)
      super(name, position)
      @sound = sound; @volume = volume.to_f32; @loop = loop; @autoplay = autoplay
      @max_distance = max_distance.to_f32
    end

    # Where the listener is: the current camera's center or the origin.
    def listener_position : Vec2
      Camera2D.current.try(&.effective_position) || Vec2::ZERO
    end

    # Volume after distance fall-off.
    def effective_volume : Float32
      d = global_position.distance(listener_position)
      return @volume if d <= 0
      t = (1 - d / @max_distance).clamp(0_f32, 1_f32)
      @volume * (t ** @attenuation)
    end

    # Pan from the horizontal offset to the listener.
    def effective_pan : Float32
      dx = global_position.x - listener_position.x
      (dx / @pan_width).clamp(-1_f32, 1_f32)
    end

    # Starts playing if `autoplay` is set.
    def ready : Nil; play if @autoplay; end
    # Keeps the voice in sync. Called by the engine.
    def process(dt : Float32) : Nil; update_voice; end
    # Stops playback when removed.
    def exit_tree : Nil; stop; end
  end
end
