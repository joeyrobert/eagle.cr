require "./keys"

module Eagle
  # Polling input state plus a Godot-style action map.
  #
  #   Input.map "jump", Key::Space, GamepadButton::A
  #   Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
  #   if Input.pressed?("jump") ...
  #   move = Input.vector("left", "right", "up", "down")
  module Input
    # A gamepad axis with a direction, usable as an action binding.
    record AxisBinding, axis : GamepadAxis, sign : Int32, threshold : Float32 = 0.5_f32

    alias Binding = Key | MouseButton | GamepadButton | AxisBinding

    class Gamepad
      getter id : Int32
      getter name : String
      @axes = Array(Float32).new(GamepadAxis::Count.value, 0_f32)
      @down = Array(Bool).new(GamepadButton::Count.value, false)
      @pressed = Array(Bool).new(GamepadButton::Count.value, false)
      @released = Array(Bool).new(GamepadButton::Count.value, false)
      property deadzone : Float32 = 0.15_f32

      def initialize(@id, @name); end

      def axis(a : GamepadAxis) : Float32
        v = @axes[a.value]
        v.abs < @deadzone ? 0_f32 : ((v.abs - @deadzone) / (1 - @deadzone) * Mathf.sign(v)).to_f32
      end

      def raw_axis(a : GamepadAxis) : Float32; @axes[a.value]; end
      def left_stick : Vec2; Vec2.new(axis(GamepadAxis::LeftX), axis(GamepadAxis::LeftY)); end
      def right_stick : Vec2; Vec2.new(axis(GamepadAxis::RightX), axis(GamepadAxis::RightY)); end
      def down?(b : GamepadButton) : Bool; @down[b.value]; end
      def pressed?(b : GamepadButton) : Bool; @pressed[b.value]; end
      def released?(b : GamepadButton) : Bool; @released[b.value]; end

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

    # --- keyboard ---
    def self.down?(k : Key) : Bool; @@down[k.value]; end
    def self.pressed?(k : Key) : Bool; @@pressed[k.value]; end
    def self.released?(k : Key) : Bool; @@released[k.value]; end
    def self.mods : KeyMod; @@mods; end
    def self.shift? : Bool; @@mods.shift?; end
    def self.ctrl? : Bool; @@mods.ctrl?; end
    def self.alt? : Bool; @@mods.alt?; end
    # Text typed this frame (respects layout/IME). Enable with `Input.text_input = true`.
    def self.text : String; @@text; end
    def self.text_input=(v : Bool); Eagle.platform?.try(&.text_input=(v)); end
    def self.any_pressed? : Bool; @@any_pressed; end

    # --- mouse ---
    def self.mouse : Vec2; @@mouse; end
    def self.mouse_delta : Vec2; @@mouse_delta; end
    def self.wheel : Vec2; @@wheel; end
    def self.mouse_down?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_down[b.value]; end
    def self.mouse_pressed?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_pressed[b.value]; end
    def self.mouse_released?(b : MouseButton = MouseButton::Left) : Bool; @@mouse_released[b.value]; end

    # --- gamepads ---
    def self.gamepads : Array(Gamepad); @@gamepads.values; end
    def self.gamepad(index : Int32 = 0) : Gamepad?; @@gamepads.values[index]?; end

    # --- actions ---
    def self.axis(a : GamepadAxis, sign : Int32 = 1, threshold : Number = 0.5) : AxisBinding
      AxisBinding.new(a, sign, threshold.to_f32)
    end

    def self.map(action : String, *bindings : Binding) : Nil
      list = @@actions[action] ||= [] of Binding
      bindings.each { |b| list << b unless list.includes?(b) }
    end

    def self.unmap(action : String) : Nil; @@actions.delete(action); end
    def self.actions : Hash(String, Array(Binding)); @@actions; end
    def self.bindings(action : String) : Array(Binding); @@actions[action]? || [] of Binding; end

    def self.down?(action : String) : Bool
      bindings(action).any? { |b| binding_down?(b) }
    end

    def self.pressed?(action : String) : Bool
      bindings(action).any? { |b| binding_pressed?(b) }
    end

    def self.released?(action : String) : Bool
      bindings(action).any? { |b| binding_released?(b) }
    end

    # Analog strength 0..1 (1 for digital inputs).
    def self.strength(action : String) : Float32
      best = 0_f32
      bindings(action).each do |b|
        s = binding_strength(b)
        best = s if s > best
      end
      best
    end

    def self.axis(negative : String, positive : String) : Float32
      strength(positive) - strength(negative)
    end

    def self.vector(left : String, right : String, up : String, down : String, normalize : Bool = true) : Vec2
      v = Vec2.new(axis(left, right), axis(up, down))
      normalize ? v.limit(1) : v
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

    # :nodoc: Clear per-frame state. Call at the *start* of a frame before polling.
    def self.begin_frame : Nil
      @@pressed.fill(false); @@released.fill(false)
      @@mouse_pressed.fill(false); @@mouse_released.fill(false)
      @@mouse_delta = Vec2::ZERO
      @@wheel = Vec2::ZERO
      @@text = ""
      @@any_pressed = false
      @@gamepads.each_value(&.end_frame)
      @@axis_pressed.clear; @@axis_released.clear
    end

    # :nodoc: After polling, compute virtual axis presses.
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

    # :nodoc: For tests and simulated input.
    def self.reset : Nil
      begin_frame
      @@down.fill(false); @@mouse_down.fill(false)
      @@actions.clear; @@gamepads.clear; @@axis_state.clear
      @@mouse = Vec2::ZERO
    end
  end
end
