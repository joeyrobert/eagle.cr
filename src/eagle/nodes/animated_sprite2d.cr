module Eagle
  # A sprite that plays named frame animations such as "idle", "run" and "jump".
  #
  # Add animations from texture regions (`Texture#frames` cuts a sheet into them), then call
  # `play` whenever the state changes. Calling `play` with the animation that is already
  # running does nothing, so it's safe to call every frame.
  #
  # ```
  # sheet = Texture.new(Image.checkerboard(256, 64, 32))
  # hero = AnimatedSprite2D.new
  # hero.add_animation("idle", sheet.frames(32, 32)[0..1], fps: 4)
  # hero.add_animation("run", sheet.frames(32, 32)[2..7], fps: 12)
  # hero.add_animation("die", sheet.frames(32, 32)[8..11], fps: 8, loop: false)
  # hero.on_animation_finished { |name| hero.queue_free if name == "die" }
  #
  # moving = true
  # hero.play(moving ? "run" : "idle")
  # ```
  class AnimatedSprite2D < Sprite2D
    # One named animation: its frames, speed and whether it loops.
    class Animation
      # The animation's name.
      getter name : String
      # The regions shown, in order.
      getter frames : Array(TextureRegion)
      # Frames per second.
      property fps : Float32
      # Whether to start over at the end. Non-looping animations stop on the last frame and emit
      # `animation_finished`.
      property? loop : Bool
      # Creates an animation.
      def initialize(@name, @frames, @fps = 10_f32, @loop = true); end
      # Length of one pass in seconds.
      def duration : Float32; @frames.size / @fps; end
    end

    # Every animation by name.
    getter animations = {} of String => Animation
    # Name of the current animation.
    getter animation : String? = nil
    # True while frames are advancing.
    getter? playing = false
    # Multiplies every animation's fps. Use it to match run speed to movement speed.
    property speed_scale : Float32 = 1_f32
    @time = 0_f32
    @frame_index = 0

    signal animation_finished(name : String)
    signal frame_changed(frame : Int32)

    # Adds an animation and returns it. Replaces any animation with the same name.
    def add_animation(name : String, frames : Array(TextureRegion), fps : Number = 10, loop : Bool = true) : Animation
      a = Animation.new(name, frames, fps.to_f32, loop)
      @animations[name] = a
      if @animation.nil?
        @animation = name
        @texture = frames.first?
      end
      a
    end

    # Plays *name*, or resumes the current animation when *name* is `nil`. Restarts only when
    # the animation changes or *restart* is true. Raises for an unknown name.
    def play(name : String? = nil, restart : Bool = false) : Nil
      name ||= @animation
      raise Error.new("Unknown animation #{name}") if name && !@animations[name]?
      if name != @animation || restart || !@playing
        @animation = name
        @time = 0_f32
        set_frame(0)
      end
      @playing = true
    end

    # Stops advancing frames.
    def stop : Nil
      @playing = false
    end

    # Stops advancing frames. Call `play` to continue.
    def pause : Nil; @playing = false; end

    # Index of the current frame within the animation.
    def frame_index : Int32; @frame_index; end

    # Jumps to a frame within the current animation.
    def frame_index=(i : Int32)
      set_frame(i)
      if anim = current_animation
        @time = @frame_index / anim.fps
      end
    end

    # The current `Animation`, or `nil`.
    def current_animation : Animation?
      @animation.try { |n| @animations[n]? }
    end

    private def set_frame(i : Int32)
      anim = current_animation
      return unless anim
      i = i.clamp(0, anim.frames.size - 1)
      changed = i != @frame_index
      @frame_index = i
      @texture = anim.frames[i]
      emit_frame_changed(i) if changed
    end

    # Advances frames. Called by the engine.
    def process(dt : Float32) : Nil
      return unless @playing
      anim = current_animation
      return unless anim
      @time += dt * @speed_scale
      idx = (@time * anim.fps).to_i
      if idx >= anim.frames.size
        if anim.loop?
          @time -= anim.duration * (idx // anim.frames.size)
          idx = idx % anim.frames.size
        else
          set_frame(anim.frames.size - 1)
          @playing = false
          emit_animation_finished(anim.name)
          return
        end
      end
      set_frame(idx)
    end
  end
end
