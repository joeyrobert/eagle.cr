module Eagle
  # A 2D camera: world-space view with position (center), zoom, rotation.
  class Camera2D
    property position : Vec2 = Vec2::ZERO
    property zoom : Float32 = 1_f32
    property rotation : Float32 = 0_f32
    # Size of the area the camera renders into (defaults to the window).
    property viewport : Vec2? = nil
    # Optional world-space limits; the view is clamped inside.
    property limits : Rect? = nil
    @shake_amount = 0_f32
    @shake_time = 0_f32
    @shake_offset = Vec2::ZERO
    @rng = Random.new

    def initialize(@position = Vec2::ZERO, @zoom = 1_f32, @rotation = 0_f32); end

    def viewport_size : Vec2; @viewport || Window.size; end

    # Effective center after limits and shake.
    def effective_position : Vec2
      p = @position
      if lim = @limits
        half = viewport_size / (2 * @zoom)
        p = Vec2.new(
          lim.w <= half.x * 2 ? lim.center.x : p.x.clamp(lim.x + half.x, lim.right - half.x),
          lim.h <= half.y * 2 ? lim.center.y : p.y.clamp(lim.y + half.y, lim.bottom - half.y))
      end
      p + @shake_offset
    end

    # World → screen transform.
    def view : Transform2D
      vs = viewport_size
      Transform2D.translation(vs / 2) * Transform2D.rotation(-@rotation) * Transform2D.scale(Vec2.new(@zoom)) * Transform2D.translation(-effective_position)
    end

    def screen_to_world(p : Vec2) : Vec2; view.inverse * p; end
    def world_to_screen(p : Vec2) : Vec2; view * p; end
    def mouse_world : Vec2; screen_to_world(Input.mouse); end

    # Visible world rectangle (axis-aligned bounds when rotated).
    def bounds : Rect
      inv = view.inverse
      vs = viewport_size
      pts = [inv * Vec2::ZERO, inv * Vec2.new(vs.x, 0), inv * vs, inv * Vec2.new(0, vs.y)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    # Smoothly move toward `target` (framerate independent). Call each frame.
    def follow(target : Vec2, dt : Float32, smoothing : Number = 8) : Nil
      @position = Mathf.damp(@position, target, smoothing, dt)
    end

    def shake(amount : Number, duration : Number = 0.3) : Nil
      @shake_amount = amount.to_f32
      @shake_time = duration.to_f32
    end

    # Advance shake; called automatically by Graphics when the camera is active.
    def update(dt : Float32) : Nil
      if @shake_time > 0
        @shake_time -= dt
        t = Math.max(@shake_time, 0_f32)
        @shake_offset = Vec2.new(@rng.rand(-1.0..1.0), @rng.rand(-1.0..1.0)) * @shake_amount * (t > 0 ? 1 : 0)
      else
        @shake_offset = Vec2::ZERO
      end
    end
  end
end
