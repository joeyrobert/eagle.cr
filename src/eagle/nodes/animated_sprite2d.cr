module Eagle
  # Frame animation from sprite-sheet regions.
  #
  #   s = AnimatedSprite2D.new
  #   s.add_animation("run", tex.frames(32, 32)[0..5], fps: 12)
  #   s.add_animation("idle", [tex.region(0, 0, 32, 32)], loop: false)
  #   s.play("run")
  class AnimatedSprite2D < Sprite2D
    class Animation
      getter name : String
      getter frames : Array(TextureRegion)
      property fps : Float32
      property? loop : Bool
      def initialize(@name, @frames, @fps = 10_f32, @loop = true); end
      def duration : Float32; @frames.size / @fps; end
    end

    getter animations = {} of String => Animation
    getter animation : String? = nil
    getter? playing = false
    property speed_scale : Float32 = 1_f32
    @time = 0_f32
    @frame_index = 0

    signal animation_finished(name : String)
    signal frame_changed(frame : Int32)

    def add_animation(name : String, frames : Array(TextureRegion), fps : Number = 10, loop : Bool = true) : Animation
      a = Animation.new(name, frames, fps.to_f32, loop)
      @animations[name] = a
      if @animation.nil?
        @animation = name
        @texture = frames.first?
      end
      a
    end

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

    def stop : Nil
      @playing = false
    end

    def pause : Nil; @playing = false; end

    def frame_index : Int32; @frame_index; end

    def frame_index=(i : Int32)
      set_frame(i)
      if anim = current_animation
        @time = @frame_index / anim.fps
      end
    end

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
