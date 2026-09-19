module Eagle
  # An on-screen thumb stick for touch screens. It gives games written for keyboard or gamepad
  # a way to move on a phone: bind it to the same actions and existing `Input` code just works.
  #
  # The stick claims the finger that lands inside it and follows that finger until it lifts, even
  # if it slides outside. Other fingers are free for `VirtualButton`s and gestures. Put it on a
  # `CanvasLayer` so it stays fixed on screen.
  #
  # ```
  # Input.map "left", Key::A
  # Input.map "right", Key::D
  # Input.map "up", Key::W
  # Input.map "down", Key::S
  #
  # hud = CanvasLayer.new
  # stick = VirtualJoystick.new(v2(40, Window.height - 190))
  # stick.bind("left", "right", "up", "down")
  # stick.on_changed { |v| puts v } # or read stick.value directly
  # hud.add(stick)
  # SceneTree.root.add(hud)
  #
  # # in the player: Input.vector("left", "right", "up", "down") now follows the thumb
  # ```
  class VirtualJoystick < Control
    # Fraction of the radius the stick must move before it registers, from 0 to 1.
    property dead_zone : Float32 = 0.15_f32
    # The stick direction from -1 to 1 on each axis. Up is negative y, like `Input.vector`.
    getter value : Vec2 = Vec2::ZERO
    # Emitted when the stick value changes.
    signal changed(value : Vec2)

    @finger : Int32? = nil
    @actions : {String, String, String, String}? = nil

    # Creates a joystick whose top-left corner is at *position*; it is a square of 2 * *radius* pixels.
    def initialize(position : Vec2 = Vec2::ZERO, radius : Number = 75, name : String = "")
      super(name, position, Vec2.new(radius.to_f32 * 2, radius.to_f32 * 2))
      @mouse_enabled = false
    end

    # How far the knob can travel from the center, in pixels.
    def radius : Float32; Math.min(@size.x, @size.y) / 2; end

    # True while a finger is holding the stick.
    def held? : Bool; !@finger.nil?; end

    # Drives four actions from the stick, so `Input.down?("left")` and `Input.vector` see it.
    def bind(left : String, right : String, up : String, down : String) : self
      @actions = {left, right, up, down}
      self
    end

    # Handles the finger that controls the stick.
    def input(event : Event) : Nil
      return if @disabled || !@visible || !event.is_a?(TouchEvent)
      case event.phase
      in .began?
        if @finger.nil? && contains_global?(event.position)
          @finger = event.id
          follow(event.position)
          event.handled = true
        end
      in .moved?
        if @finger == event.id
          follow(event.position)
          event.handled = true
        end
      in .ended?, .cancelled?
        if @finger == event.id
          release
          event.handled = true
        end
      end
    end

    # Lets go of the stick and releases its actions.
    def exit_tree : Nil
      release
      super
    end

    # Draws the base ring and knob.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      c = @size / 2
      r = radius
      g.circle(c, r, color: g.color * t.panel.with_alpha(0.45))
      g.circle(c, r, DrawMode::Line, g.color * t.button_border.with_alpha(0.8))
      knob = c + @value * (r - r * 0.35)
      g.circle(knob, r * 0.35, color: g.color * (held? ? t.accent : t.button_hover).with_alpha(0.85))
    end

    private def follow(p : Vec2)
      r = radius
      off = (to_local(p) - @size / 2) / (r - r * 0.35)
      off = off.limit(1)
      len = off.length
      off = len < @dead_zone ? Vec2::ZERO : off * ((len - @dead_zone) / (1 - @dead_zone) / len)
      set_value(off)
    end

    private def release
      @finger = nil
      set_value(Vec2::ZERO)
    end

    private def set_value(v : Vec2)
      return if v == @value
      @value = v
      if a = @actions
        Input.set_virtual(a[0], Math.max(-v.x, 0_f32))
        Input.set_virtual(a[1], Math.max(v.x, 0_f32))
        Input.set_virtual(a[2], Math.max(-v.y, 0_f32))
        Input.set_virtual(a[3], Math.max(v.y, 0_f32))
      end
      emit_changed(v)
    end
  end

  # An on-screen round button for touch screens. While a finger holds it, its action reads as
  # pressed through `Input.down?`, `Input.pressed?` and `Input.released?`, so game code written
  # for a key or gamepad button needs no changes. Several buttons work at once with a
  # `VirtualJoystick`, because each one follows its own finger.
  #
  # ```
  # Input.map "jump", Key::Space, GamepadButton::A
  #
  # hud = CanvasLayer.new
  # jump = VirtualButton.new("jump", "A", v2(Window.width - 110, Window.height - 110))
  # jump.on_button_down { puts "jump!" }
  # hud.add(jump)
  # SceneTree.root.add(hud)
  # ```
  class VirtualButton < Control
    # The action driven by this button.
    property action : String
    # Label drawn in the middle.
    property text : String
    # Emitted when a finger lands on the button.
    signal button_down
    # Emitted when the finger lifts or the touch is cancelled.
    signal button_up

    @finger : Int32? = nil

    # Creates a button of *diameter* pixels with its top-left corner at *position*.
    def initialize(@action : String, @text : String = "", position : Vec2 = Vec2::ZERO, diameter : Number = 84, name : String = "")
      super(name, position, Vec2.new(diameter.to_f32, diameter.to_f32))
      @mouse_enabled = false
    end

    # True while a finger holds the button.
    def held? : Bool; !@finger.nil?; end

    # Handles the finger that presses the button.
    def input(event : Event) : Nil
      return if @disabled || !@visible || !event.is_a?(TouchEvent)
      case event.phase
      in .began?
        if @finger.nil? && (to_local(event.position) - @size / 2).length <= @size.x / 2
          @finger = event.id
          Input.set_virtual(@action, 1)
          emit_button_down
          event.handled = true
        end
      in .moved?
        event.handled = true if @finger == event.id
      in .ended?, .cancelled?
        if @finger == event.id
          release
          event.handled = true
        end
      end
    end

    # Releases the action when removed.
    def exit_tree : Nil
      release
      super
    end

    # Draws the button.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      c = @size / 2
      r = @size.x / 2
      g.circle(c, r, color: g.color * (held? ? t.accent : t.panel).with_alpha(held? ? 0.85 : 0.55))
      g.circle(c, r, DrawMode::Line, g.color * t.button_border.with_alpha(0.8))
      unless @text.empty?
        ts = font.measure(@text)
        g.print(@text, c.x - ts.x / 2, c.y - ts.y / 2, g.color * t.text, font)
      end
    end

    private def release
      return unless @finger
      @finger = nil
      Input.set_virtual(@action, 0)
      emit_button_up
    end
  end
end
