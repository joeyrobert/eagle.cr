module Eagle
  # Playback settings shared by `AudioPlayer`, `AudioPlayer2D` and `AudioPlayer3D`.
  module AudioPlayback
    # The sound to play.
    property sound : Sound? = nil
    # Volume from 0 to 1.
    property volume : Float32 = 1_f32
    # Playback speed: 1 is normal.
    property pitch : Float32 = 1_f32
    # Stereo position from -1 to 1. `AudioPlayer2D` computes it from position instead, and `AudioPlayer3D` ignores it.
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

    # Emitted when a non-looping sound reaches its end. Connect with `on_finished { ... }`.
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

module Eagle
  # A sound placed in a 3D scene, heard from `Audio.listener` (the current `Camera3D` unless
  # an `AudioListener3D` takes over). It fades with distance, pans toward the ear it is
  # closer to, reaches the far ear slightly later and duller, and sounds muffled from behind,
  # so players can locate it on headphones.
  #
  # Use it for sounds attached to things in the level: an enemy's footsteps, a humming
  # generator, a radio. Add it as a child of the object and it follows along. For one-off
  # sounds that don't need a node, such as gunshots and explosions, use `Audio.play_at`.
  #
  # ```
  # generator = AudioPlayer3D.new(Sound.tone(55, 2, Sound::Wave::Saw, volume: 0.3), position: v3(4, 1, -6), loop: true, autoplay: true)
  # generator.max_distance = 30
  # generator.attenuation = Attenuation::Linear
  # SceneTree.root.add(generator)
  #
  # drone = Node3D.new(position: v3(0, 3, 0))
  # buzz = AudioPlayer3D.new(Sound.tone(180, 1, Sound::Wave::Square, volume: 0.2), loop: true, autoplay: true)
  # buzz.doppler = true # pitch rises as it flies toward the listener
  # drone.add(buzz)
  # SceneTree.root.add(drone)
  # ```
  class AudioPlayer3D < Node3D
    include AudioPlayback
    # The distance model. See `Attenuation`.
    property attenuation : Attenuation = Attenuation::Inverse
    # Distance inside which the sound plays at full volume.
    property min_distance : Float32 = 1_f32
    # Distance past which the sound stops getting quieter (silent there with `Attenuation::Linear`).
    property max_distance : Float32 = 100_f32
    # How fast the volume falls between `min_distance` and `max_distance`. 1 is natural.
    property rolloff : Float32 = 1_f32
    # Shifts pitch as the source moves toward or away from the listener. Off by default.
    property? doppler = false
    # Exaggerates (above 1) or tames (below 1) the doppler effect.
    property doppler_scale : Float32 = 1_f32
    # World-space velocity, measured from how the node moved since the last frame.
    getter velocity : Vec3 = Vec3::ZERO
    @last_global : Vec3? = nil

    # Sets `min_distance` from any number.
    def min_distance=(v : Number); @min_distance = v.to_f32; end
    # Sets `max_distance` from any number.
    def max_distance=(v : Number); @max_distance = v.to_f32; end
    # Sets `rolloff` from any number.
    def rolloff=(v : Number); @rolloff = v.to_f32; end
    # Sets `doppler_scale` from any number.
    def doppler_scale=(v : Number); @doppler_scale = v.to_f32; end

    # Creates a 3D player.
    def initialize(sound : Sound? = nil, position : Vec3 = Vec3::ZERO, name : String = "", volume : Number = 1, loop : Bool = false, autoplay : Bool = false,
                   attenuation : Attenuation = Attenuation::Inverse, min_distance : Number = 1, max_distance : Number = 100)
      super(name, position)
      @sound = sound; @volume = volume.to_f32; @loop = loop; @autoplay = autoplay
      @attenuation = attenuation; @min_distance = min_distance.to_f32; @max_distance = max_distance.to_f32
    end

    # Plays *sound*, or the current `sound`, positioned at this node. Returns the voice.
    def play(sound : Sound? = nil) : Voice?
      v = super
      if v
        v.spatial = Spatial3D.new(global_position)
        update_voice
      end
      v
    end

    # Pushes volume, pitch, position and distance settings to the playing voice. Called every frame.
    def update_voice : Nil
      super
      return unless (v = @voice) && (sp = v.spatial)
      sp.position = global_position
      sp.velocity = @velocity
      sp.attenuation = @attenuation
      sp.min_distance = @min_distance; sp.max_distance = @max_distance; sp.rolloff = @rolloff
      sp.doppler = @doppler; sp.doppler_scale = @doppler_scale
    end

    # Starts measuring velocity from here.
    def enter_tree : Nil; @last_global = global_position; end
    # Starts playing if `autoplay` is set.
    def ready : Nil; play if @autoplay; end

    # Measures velocity and keeps the voice in sync. Called by the engine.
    def process(dt : Float32) : Nil
      gp = global_position
      if (last = @last_global) && dt > 0
        @velocity = (gp - last) / dt
      end
      @last_global = gp
      update_voice
    end

    # Stops playback when removed.
    def exit_tree : Nil; stop; @last_global = nil; end
  end

  # The ears for 3D audio, when they shouldn't be at the camera. While one is current,
  # `Audio.listener` uses its position and orientation instead of the current `Camera3D`'s.
  #
  # Most first-person games need none: the camera already sits at the player's head. Add
  # one for a third-person camera (put it on the character), a cutscene, or a split view.
  # The first listener added to the tree becomes current.
  #
  # ```
  # player = Node3D.new(position: v3(0, 0, 0))
  # ears = AudioListener3D.new(position: v3(0, 1.7, 0))
  # player.add(ears)
  # SceneTree.root.add(player)
  # ears.current? # => true
  # ```
  class AudioListener3D < Node3D
    # True when this listener is the one 3D audio is heard from.
    getter? current = false
    @@current : AudioListener3D? = nil

    # Creates a listener.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, current : Bool = false)
      super(name, position)
      make_current if current
    end

    # The active listener, if any.
    def self.current : AudioListener3D?; @@current; end
    # Switches the active listener. `nil` falls back to the current `Camera3D`.
    def self.current=(l : AudioListener3D?)
      @@current.try(&.clear_current)
      @@current = l
      l.try(&.set_current)
    end
    # :nodoc:
    def self.reset; @@current = nil; end

    # Makes this the active listener. Returns self.
    def make_current : self; AudioListener3D.current = self; self; end
    protected def set_current; @current = true; end
    protected def clear_current; @current = false; end

    # Becomes current if no other listener is.
    def enter_tree : Nil
      make_current if AudioListener3D.current.nil?
    end

    # Stops being current when removed.
    def exit_tree : Nil
      AudioListener3D.current = nil if AudioListener3D.current == self
    end
  end
end
