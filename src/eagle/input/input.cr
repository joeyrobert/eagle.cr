require "./keys"
require "./touch"

module Eagle
  # Keyboard, mouse, touch and gamepad state you can check from anywhere, plus an action map
  # so game code talks about "jump" instead of specific keys.
  #
  # There are two ways to read input:
  #
  # * **Polling** with `Input`: "is this key held?", "was it pressed this frame?". This is what
  #   movement and most gameplay wants.
  # * **Events** through `App#input` and `Node#input`, which suit menus and text entry.
  #
  # `down?` is true every frame the input is held. `pressed?` and `released?` are true only
  # on the frame it changed, so use them for one-shot actions like jumping or firing.
  #
  # Actions bind any mix of keys, mouse buttons, gamepad buttons and stick directions to
  # a name. Map them once in `App#load`, then ask about the action:
  #
  # ```
  # Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
  # Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
  # Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
  # Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
  # Input.map "jump", Key::Space, GamepadButton::A
  # Input.map "fire", MouseButton::Left, GamepadButton::RightShoulder
  #
  # class Player < Node2D
  #   def process(dt : Float32) : Nil
  #     move = Input.vector("left", "right", "up", "down") # analog on sticks, digital on keys
  #     self.position += move * 200 * dt
  #     puts "jump!" if Input.pressed?("jump")
  #     look_at(Input.mouse) if Input.down?("fire")
  #   end
  # end
  # ```
  module Input
    # A gamepad stick direction used as an action binding. It counts as pressed once the axis,
    # multiplied by *sign*, passes *threshold*. Create one with `Input.axis(axis, sign)`.
    record AxisBinding, axis : GamepadAxis, sign : Int32, threshold : Float32 = 0.5_f32

    # Anything that can trigger an action: a key, a mouse button, a gamepad button or a stick direction.
    alias Binding = Key | MouseButton | GamepadButton | AxisBinding

    # A connected game controller. Get one with `Input.gamepad` or iterate `Input.gamepads`.
    #
    # Stick values have a deadzone applied, so a resting stick reads exactly 0.
    # Most games use actions instead, but direct access is handy for twin-stick controls.
    #
    # ```
    # if pad = Input.gamepad
    #   aim = pad.right_stick
    #   pad.rumble(0.3, 0.6, 150) if pad.pressed?(GamepadButton::RightShoulder)
    # end
    # ```
    class Gamepad
      # The controller's id, as reported in gamepad events.
      getter id : Int32
      # The controller's product name, such as "Xbox Wireless Controller".
      getter name : String
      @axes = Array(Float32).new(GamepadAxis::Count.value, 0_f32)
      @down = Array(Bool).new(GamepadButton::Count.value, false)
      @pressed = Array(Bool).new(GamepadButton::Count.value, false)
      @released = Array(Bool).new(GamepadButton::Count.value, false)
      # Stick values smaller than this read as 0. Raise it for worn sticks that drift.
      property deadzone : Float32 = 0.15_f32

      # :nodoc:
      def initialize(@id, @name); end

      # An axis value after the deadzone: -1 to 1 for sticks, 0 to 1 for triggers.
      def axis(a : GamepadAxis) : Float32
        v = @axes[a.value]
        v.abs < @deadzone ? 0_f32 : ((v.abs - @deadzone) / (1 - @deadzone) * Mathf.sign(v)).to_f32
      end

      # An axis value without the deadzone.
      def raw_axis(a : GamepadAxis) : Float32; @axes[a.value]; end
      # The left stick as a vector. Up is negative y, matching screen space.
      def left_stick : Vec2; Vec2.new(axis(GamepadAxis::LeftX), axis(GamepadAxis::LeftY)); end
      # The right stick as a vector.
      def right_stick : Vec2; Vec2.new(axis(GamepadAxis::RightX), axis(GamepadAxis::RightY)); end
      # True while *b* is held.
      def down?(b : GamepadButton) : Bool; @down[b.value]; end
      # True on the frame *b* went down.
      def pressed?(b : GamepadButton) : Bool; @pressed[b.value]; end
      # True on the frame *b* went up.
      def released?(b : GamepadButton) : Bool; @released[b.value]; end

      # Vibrates the controller. *low* and *high* are motor strengths from 0 to 1.
      def rumble(low : Number = 0.5, high : Number = 0.5, ms : Int = 200) : Nil
        Eagle.platform?.try(&.gamepad_rumble(@id, low.to_f32, high.to_f32, ms.to_i))
      end

      # :nodoc:
      def set_axis(a : GamepadAxis, v : Float32); @axes[a.value] = v; end
      # :nodoc:
      def set_button(b : GamepadButton, v : Bool)
        i = b.value
        if v && !@down[i]
          @pressed[i] = true
        elsif !v && @down[i]
          @released[i] = true
        end
        @down[i] = v
      end
      # :nodoc:
      def end_frame; @pressed.fill(false); @released.fill(false); end
    end

    @@down = Array(Bool).new(Key::Count.value, false)
    @@pressed = Array(Bool).new(Key::Count.value, false)
    @@released = Array(Bool).new(Key::Count.value, false)
    @@mouse_down = Array(Bool).new(6, false)
    @@mouse_pressed = Array(Bool).new(6, false)
    @@mouse_released = Array(Bool).new(6, false)
    @@mouse = Vec2::ZERO
    @@mouse_delta = Vec2::ZERO
    @@wheel = Vec2::ZERO
    @@text = ""
    @@mods = KeyMod::None
    @@actions = {} of String => Array(Binding)
    @@gamepads = {} of Int32 => Gamepad
    @@any_pressed = false
    @@virtual = {} of String => Float32
    @@virtual_pressed = [] of String
    @@virtual_released = [] of String

    # --- keyboard ---
    # True every frame while the key is held.
    def self.down?(k : Key) : Bool; @@down[k.value]; end
    # True only on the frame the key went down.
    def self.pressed?(k : Key) : Bool; @@pressed[k.value]; end
    # True only on the frame the key went up.
    def self.released?(k : Key) : Bool; @@released[k.value]; end
    # Modifier keys currently held (shift, ctrl, alt, gui).
    def self.mods : KeyMod; @@mods; end
    # True while either shift key is held.
    def self.shift? : Bool; @@mods.shift?; end
    # True while either control key is held.
    def self.ctrl? : Bool; @@mods.ctrl?; end
    # True while either alt/option key is held.
    def self.alt? : Bool; @@mods.alt?; end
    # Text typed this frame, when text input is enabled.
    def self.text : String; @@text; end
    # Turns OS text input on or off. While on, typing produces `TextEvent`s and fills `text`.
    # `TextInput` controls handle this for you.
    def self.text_input=(v : Bool); Eagle.platform?.try(&.text_input=(v)); end
    # True if any key, mouse button or gamepad button went down this frame. Handy for "press any key".
    def self.any_pressed? : Bool; @@any_pressed; end

    # --- mouse ---
    # Mouse position in window coordinates. With a `Camera2D`, convert it with `Camera2D#screen_to_world`.
    def self.mouse : Vec2; @@mouse; end
    # How far the mouse moved this frame. Works with `Window.relative_mouse=` for mouse-look.
    def self.mouse_delta : Vec2; @@mouse_delta; end
    # Scroll amount this frame. `wheel.y` is positive when scrolling up.
    def self.wheel : Vec2; @@wheel; end
    # True while the mouse button is held.
    def self.mouse_down?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_down[b.value]; end
    # True on the frame the mouse button went down.
    def self.mouse_pressed?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_pressed[b.value]; end
    # True on the frame the mouse button went up.
    def self.mouse_released?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_released[b.value]; end

    # --- touch ---
    # Fingers currently on the screen. Shorthand for `Touch.fingers`.
    def self.touches : Array(Finger); Touch.fingers; end

    # --- gamepads ---
    # Every connected controller.
    def self.gamepads : Array(Gamepad); @@gamepads.values; end
    # The controller at *index* in connection order, or `nil`. Index 0 is the first player.
    def self.gamepad(index : Int32 = 0) : Gamepad?; @@gamepads.values[index]?; end

    # --- actions ---
    # Builds a stick-direction binding for `map`. `Input.axis(GamepadAxis::LeftX, -1)` means
    # "left stick pushed left".
    def self.axis(a : GamepadAxis, sign : Int32 = 1, threshold : Number = 0.5) : AxisBinding
      AxisBinding.new(a, sign, threshold.to_f32)
    end

    # Binds one or more inputs to an action name. Calling it again adds more bindings.
    #
    # ```
    # Input.map "pause", Key::Escape, Key::P, GamepadButton::Start
    # ```
    def self.map(action : String, *bindings : Binding) : Nil
      list = @@actions[action] ||= [] of Binding
      bindings.each { |b| list << b unless list.includes?(b) }
    end

    # Removes an action and all its bindings, for example before rebinding controls.
    def self.unmap(action : String) : Nil; @@actions.delete(action); end
    # Every action and its bindings, for building a controls menu.
    def self.actions : Hash(String, Array(Binding)); @@actions; end
    # The bindings for one action.
    def self.bindings(action : String) : Array(Binding); @@actions[action]? || [] of Binding; end

    # True while any binding of the action is held.
    def self.down?(action : String) : Bool
      bindings(action).any? { |b| binding_down?(b) } || virtual_strength(action) >= 0.5
    end

    # True on the frame any binding of the action went down.
    def self.pressed?(action : String) : Bool
      bindings(action).any? { |b| binding_pressed?(b) } || @@virtual_pressed.includes?(action)
    end

    # True on the frame any binding of the action went up.
    def self.released?(action : String) : Bool
      bindings(action).any? { |b| binding_released?(b) } || @@virtual_released.includes?(action)
    end

    # How strongly the action is held, from 0 to 1. Keys and buttons are 0 or 1, and sticks and
    # triggers give values in between.
    def self.strength(action : String) : Float32
      best = virtual_strength(action)
      bindings(action).each do |b|
        s = binding_strength(b)
        best = s if s > best
      end
      best
    end

    # Combines two actions into one value from -1 to 1: `positive` minus `negative`.
    #
    # ```
    # steer = Input.axis("left", "right") # -1 for left, 1 for right
    # ```
    def self.axis(negative : String, positive : String) : Float32
      strength(positive) - strength(negative)
    end

    # Combines four actions into a direction vector. With *normalize*, diagonals aren't
    # faster than straight lines.
    def self.vector(left : String, right : String, up : String, down : String, normalize : Bool = true) : Vec2
      v = Vec2.new(axis(left, right), axis(up, down))
      normalize ? v.limit(1) : v
    end

    # Sets how strongly an action is held from code, 0 to 1. On-screen controls (`VirtualJoystick`,
    # `VirtualButton`) use it, so game code that asks about "jump" or "left" works with touch
    # without changes. Set it back to 0 to release.
    #
    # ```
    # Input.set_virtual("jump", 1) # a touch button went down
    # Input.pressed?("jump")       # true this frame
    # Input.set_virtual("jump", 0)
    # ```
    def self.set_virtual(action : String, strength : Number) : Nil
      v = strength.to_f32.clamp(0_f32, 1_f32)
      was = (@@virtual[action]? || 0_f32) >= 0.5
      @@virtual[action] = v
      now = v >= 0.5
      @@virtual_pressed << action if now && !was
      @@virtual_released << action if was && !now
    end

    private def self.virtual_strength(action : String) : Float32
      @@virtual[action]? || 0_f32
    end

    private def self.binding_down?(b : Binding) : Bool
      case b
      in Key then down?(b)
      in MouseButton then mouse_down?(b)
      in GamepadButton then @@gamepads.each_value.any?(&.down?(b))
      in AxisBinding then @@gamepads.each_value.any? { |g| g.axis(b.axis) * b.sign >= b.threshold }
      end
    end

    private def self.binding_pressed?(b : Binding) : Bool
      case b
      in Key then pressed?(b)
      in MouseButton then mouse_pressed?(b)
      in GamepadButton then @@gamepads.each_value.any?(&.pressed?(b))
      in AxisBinding then @@axis_pressed.includes?(b)
      end
    end

    private def self.binding_released?(b : Binding) : Bool
      case b
      in Key then released?(b)
      in MouseButton then mouse_released?(b)
      in GamepadButton then @@gamepads.each_value.any?(&.released?(b))
      in AxisBinding then @@axis_released.includes?(b)
      end
    end

    private def self.binding_strength(b : Binding) : Float32
      case b
      in AxisBinding
        best = 0_f32
        @@gamepads.each_value do |g|
          v = g.axis(b.axis) * b.sign
          best = v if v > best
        end
        best.clamp(0_f32, 1_f32)
      in Key, MouseButton, GamepadButton then binding_down?(b) ? 1_f32 : 0_f32
      end
    end

    @@axis_pressed = [] of AxisBinding
    @@axis_released = [] of AxisBinding
    @@axis_state = {} of AxisBinding => Bool

    # :nodoc: Feed an event from the platform.
    def self.handle(e : Event) : Nil
      case e
      when KeyEvent
        i = e.key.value
        @@mods = e.mods
        if e.pressed?
          @@pressed[i] = true unless @@down[i]
          @@down[i] = true
          @@any_pressed = true
        else
          @@released[i] = true if @@down[i]
          @@down[i] = false
        end
      when TextEvent then @@text += e.text
      when MouseMotionEvent
        @@mouse = e.position
        @@mouse_delta += e.delta
      when MouseButtonEvent
        i = e.button.value
        @@mouse = e.position
        if e.pressed?
          @@mouse_pressed[i] = true; @@mouse_down[i] = true; @@any_pressed = true
        else
          @@mouse_released[i] = true; @@mouse_down[i] = false
        end
      when MouseWheelEvent then @@wheel += e.delta
      when TouchEvent
        Touch.handle(e)
        @@any_pressed = true if e.began?
      when GamepadConnectionEvent
        if e.connected?
          name = Eagle.platform?.try(&.gamepad_name(e.gamepad)) || "Gamepad"
          @@gamepads[e.gamepad] = Gamepad.new(e.gamepad, name)
          Eagle.log.info { "Gamepad connected: #{name} (#{e.gamepad})" }
        else
          @@gamepads.delete(e.gamepad)
        end
      when GamepadButtonEvent
        @@gamepads[e.gamepad]?.try(&.set_button(e.button, e.pressed?))
        @@any_pressed ||= e.pressed?
      when GamepadAxisEvent
        @@gamepads[e.gamepad]?.try(&.set_axis(e.axis, e.value))
      end
    end

    # :nodoc:
    def self.begin_frame : Nil
      @@pressed.fill(false); @@released.fill(false)
      @@mouse_pressed.fill(false); @@mouse_released.fill(false)
      @@mouse_delta = Vec2::ZERO
      @@wheel = Vec2::ZERO
      @@text = ""
      @@any_pressed = false
      @@gamepads.each_value(&.end_frame)
      @@axis_pressed.clear; @@axis_released.clear
      @@virtual_pressed.clear; @@virtual_released.clear
      Touch.begin_frame
    end

    # :nodoc:
    def self.end_poll : Nil
      @@actions.each_value do |list|
        list.each do |b|
          next unless b.is_a?(AxisBinding)
          now = binding_down?(b)
          was = @@axis_state[b]? || false
          @@axis_pressed << b if now && !was
          @@axis_released << b if !now && was
          @@axis_state[b] = now
        end
      end
    end

    # Clears everything: held keys and buttons, the mouse, known gamepads and all action mappings.
    # Mainly for tests; call `map` again afterwards.
    def self.reset : Nil
      begin_frame
      @@down.fill(false); @@mouse_down.fill(false)
      @@actions.clear; @@gamepads.clear; @@axis_state.clear; @@virtual.clear
      Touch.reset
      @@mouse = Vec2::ZERO
    end
  end
end
