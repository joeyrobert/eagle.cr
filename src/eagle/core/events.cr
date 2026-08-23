module Eagle
  # Input & window events, delivered to `App#input` and `Node#input`.
  abstract struct Event
    # Set to true by a handler to stop propagation to later nodes.
    property? handled = false
  end

  struct KeyEvent < Event
    getter key : Key
    getter? pressed : Bool
    getter? repeat : Bool
    getter mods : KeyMod
    def initialize(@key, @pressed, @repeat = false, @mods = KeyMod::None); end
    def released? : Bool; !@pressed; end
  end

  struct TextEvent < Event
    getter text : String
    def initialize(@text); end
  end

  struct MouseButtonEvent < Event
    getter button : MouseButton
    getter? pressed : Bool
    getter position : Vec2
    getter clicks : Int32
    def initialize(@button, @pressed, @position, @clicks = 1); end
    def released? : Bool; !@pressed; end
  end

  struct MouseMotionEvent < Event
    getter position : Vec2
    getter delta : Vec2
    def initialize(@position, @delta); end
  end

  struct MouseWheelEvent < Event
    getter delta : Vec2
    getter position : Vec2
    def initialize(@delta, @position); end
  end

  enum WindowEventKind
    Resized
    FocusGained
    FocusLost
    MouseEnter
    MouseLeave
    Minimized
    Restored
    Close
  end

  struct WindowEvent < Event
    getter kind : WindowEventKind
    getter size : Vec2
    def initialize(@kind, @size = Vec2::ZERO); end
  end

  struct GamepadButtonEvent < Event
    getter gamepad : Int32
    getter button : GamepadButton
    getter? pressed : Bool
    def initialize(@gamepad, @button, @pressed); end
  end

  struct GamepadAxisEvent < Event
    getter gamepad : Int32
    getter axis : GamepadAxis
    getter value : Float32
    def initialize(@gamepad, @axis, @value); end
  end

  struct GamepadConnectionEvent < Event
    getter gamepad : Int32
    getter? connected : Bool
    def initialize(@gamepad, @connected); end
  end

  struct FileDropEvent < Event
    getter path : String
    def initialize(@path); end
  end

  struct QuitEvent < Event
    def initialize; end
  end
end
