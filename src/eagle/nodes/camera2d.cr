module Eagle
  # A 2D camera node. Its global position is the centre of the view.
  # Add one to the tree and call `make_current` (or set `current: true`).
  #
  #   cam = Camera2D.new(zoom: 2)
  #   cam.follow(player)          # smooth follow another node
  #   cam.limits = Rect.new(0, 0, 4000, 2000)
  class Camera2D < Node2D
    property zoom : Float32 = 1_f32
    # Size of the area the camera renders into (defaults to the window).
    property viewport : Vec2? = nil
    # World-space limits; the view is clamped inside.
    property limits : Rect? = nil
    # Smoothing speed for `follow` (higher = snappier). 0 = instant.
    property smoothing : Float32 = 8_f32
    # Node to follow each frame (uses its global position).
    property target : Node2D? = nil
    property target_offset : Vec2 = Vec2::ZERO
    # Optional dead-zone (in world units) around the target before the camera moves.
    property drag_margin : Vec2 = Vec2::ZERO
    getter? current = false
    @shake_amount = 0_f32
    @shake_time = 0_f32
    @shake_duration = 0_f32
    @shake_offset = Vec2::ZERO
    @rng = Random.new

    @@current : Camera2D? = nil

    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, zoom : Number = 1, @viewport = nil, current : Bool = false)
      super(name, position)
      @zoom = zoom.to_f32
      make_current if current
    end

    def self.current : Camera2D?; @@current; end
    def self.current=(c : Camera2D?); @@current.try(&.clear_current); @@current = c; c.try(&.set_current); end
    # :nodoc:
    def self.reset; @@current = nil; end

    def make_current : self
      Camera2D.current = self
      self
    end

    protected def set_current; @current = true; end
    protected def clear_current; @current = false; end

    def enter_tree : Nil
      make_current if Camera2D.current.nil?
    end

    def exit_tree : Nil
      Camera2D.current = nil if Camera2D.current == self
    end

    def viewport_size : Vec2; @viewport || Window.size; end

    def follow(node : Node2D?, offset : Vec2 = Vec2::ZERO) : Nil
      @target = node
      @target_offset = offset
    end

    # Camera centre after limits and shake.
    def effective_position : Vec2
      p = global_position
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
      Transform2D.translation(vs / 2) * Transform2D.rotation(-global_rotation) * Transform2D.scale(Vec2.new(@zoom)) * Transform2D.translation(-effective_position)
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

    def shake(amount : Number, duration : Number = 0.3) : Nil
      @shake_amount = amount.to_f32
      @shake_time = @shake_duration = duration.to_f32
    end

    def process(dt : Float32) : Nil
      if t = @target
        goal = t.global_position + @target_offset
        if !@drag_margin.zero?
          cur = global_position
          dx = goal.x - cur.x; dy = goal.y - cur.y
          gx = dx.abs > @drag_margin.x ? cur.x + dx - Mathf.sign(dx) * @drag_margin.x : cur.x
          gy = dy.abs > @drag_margin.y ? cur.y + dy - Mathf.sign(dy) * @drag_margin.y : cur.y
          goal = Vec2.new(gx, gy)
        end
        self.global_position = @smoothing > 0 ? Mathf.damp(global_position, goal, @smoothing, dt) : goal
      end
      update_shake(dt)
    end

    # :nodoc: called by Graphics when the camera is not in the tree (manual use)
    def update(dt : Float32) : Nil
      update_shake(dt) unless in_tree?
    end

    private def update_shake(dt : Float32)
      if @shake_time > 0
        @shake_time -= dt
        falloff = @shake_duration > 0 ? (@shake_time / @shake_duration).clamp(0_f32, 1_f32) : 0_f32
        @shake_offset = Vec2.new(@rng.rand(-1.0..1.0), @rng.rand(-1.0..1.0)) * @shake_amount * falloff
      else
        @shake_offset = Vec2::ZERO
      end
    end

    # Cameras draw nothing and don't transform their children.
    def draw_tree(g : Graphics) : Nil
      draw_children(g)
    end
  end
end
