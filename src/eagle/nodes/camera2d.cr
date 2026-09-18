module Eagle
  # A 2D camera: it decides which part of the world is on screen. Its global position is the
  # center of the view.
  #
  # The first camera added to the tree becomes current automatically. The scene tree draws
  # through the current camera, while `CanvasLayer` children stay fixed on screen.
  #
  # ```
  # player = Node2D.new("Player", position: v2(400, 300))
  # cam = Camera2D.new(zoom: 2)
  # cam.follow(player)                            # smooth follow
  # cam.limits = Rect.new(0, 0, 4000, 2000)       # never show outside the level
  # cam.drag_margin = v2(40, 20)                  # small dead zone before scrolling
  # SceneTree.root.add(player, cam)
  #
  # cam.shake(6, 0.25)                            # on explosions
  # clicked = cam.mouse_world                     # mouse position in world space
  # ```
  class Camera2D < Node2D
    # Magnification: 2 shows everything twice as large, 0.5 shows twice as much of the world.
    property zoom : Float32 = 1_f32
    # Size of the screen area the camera renders into. `nil` means the window.
    property viewport : Vec2? = nil
    # World-space rectangle the view is kept inside.
    property limits : Rect? = nil
    # How quickly the camera catches up with its target. Higher is snappier, and 0 snaps instantly.
    property smoothing : Float32 = 8_f32
    # The node being followed.
    property target : Node2D? = nil
    # Offset added to the target's position, for example to look ahead of the player.
    property target_offset : Vec2 = Vec2::ZERO
    # How far, in world units, the target can move from the center before the camera follows.
    property drag_margin : Vec2 = Vec2::ZERO
    # True when this is the camera the scene is drawn through.
    getter? current = false
    @shake_amount = 0_f32
    @shake_time = 0_f32
    @shake_duration = 0_f32
    @shake_offset = Vec2::ZERO
    @rng = Random.new

    @@current : Camera2D? = nil

    # Creates a camera. Pass `current: true` to make it current right away.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, zoom : Number = 1, @viewport = nil, current : Bool = false)
      super(name, position)
      @zoom = zoom.to_f32
      make_current if current
    end

    # The camera the scene tree is drawn through, if any.
    def self.current : Camera2D?; @@current; end
    # Switches the active camera.
    def self.current=(c : Camera2D?); @@current.try(&.clear_current); @@current = c; c.try(&.set_current); end
    # :nodoc:
    def self.reset; @@current = nil; end

    # Makes this the active camera. Returns self.
    def make_current : self
      Camera2D.current = self
      self
    end

    protected def set_current; @current = true; end
    protected def clear_current; @current = false; end

    # Becomes current if no other camera is.
    def enter_tree : Nil
      make_current if Camera2D.current.nil?
    end

    # Stops being current when removed.
    def exit_tree : Nil
      Camera2D.current = nil if Camera2D.current == self
    end

    # The size of the area the camera renders into.
    def viewport_size : Vec2; @viewport || Window.size; end

    # Follows *node* every frame, smoothed by `smoothing`. Pass `nil` to stop.
    def follow(node : Node2D?, offset : Vec2 = Vec2::ZERO) : Nil
      @target = node
      @target_offset = offset
    end

    # The actual view center after limits and shake.
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

    # The world-to-screen transform.
    def view : Transform2D
      vs = viewport_size
      Transform2D.translation(vs / 2) * Transform2D.rotation(-global_rotation) * Transform2D.scale(Vec2.new(@zoom)) * Transform2D.translation(-effective_position)
    end

    # Converts a screen point, such as the mouse, to world space.
    def screen_to_world(p : Vec2) : Vec2; view.inverse * p; end
    # Converts a world point to screen space, for drawing HUD markers over objects.
    def world_to_screen(p : Vec2) : Vec2; view * p; end
    # The mouse position in world space.
    def mouse_world : Vec2; screen_to_world(Input.mouse); end

    # The visible part of the world. Use it to skip work for things off screen.
    def bounds : Rect
      inv = view.inverse
      vs = viewport_size
      pts = [inv * Vec2::ZERO, inv * Vec2.new(vs.x, 0), inv * vs, inv * Vec2.new(0, vs.y)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    # Shakes the view by up to *amount* points, fading out over *duration* seconds.
    def shake(amount : Number, duration : Number = 0.3) : Nil
      @shake_amount = amount.to_f32
      @shake_time = @shake_duration = duration.to_f32
    end

    # Updates following and shake. Called by the engine.
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

    # Cameras draw nothing and don't move their children.
    def draw_tree(g : Graphics) : Nil
      draw_children(g)
    end
  end
end
