module Eagle
  # Input & window events, delivered to `App#input` and `Node#input`.
  abstract class Event
    # Set to true by a handler to stop propagation to later nodes.
    property? handled = false
  end

  class KeyEvent < Event
    getter key : Key
    getter? pressed : Bool
    getter? repeat : Bool
    getter mods : KeyMod
    def initialize(@key, @pressed, @repeat = false, @mods = KeyMod::None); end
    def released? : Bool; !@pressed; end
  end

  class TextEvent < Event
    getter text : String
    def initialize(@text); end
  end

  class MouseButtonEvent < Event
    getter button : MouseButton
    getter? pressed : Bool
    getter position : Vec2
    getter clicks : Int32
    def initialize(@button, @pressed, @position, @clicks = 1); end
    def released? : Bool; !@pressed; end
  end

  class MouseMotionEvent < Event
    getter position : Vec2
    getter delta : Vec2
    def initialize(@position, @delta); end
  end

  class MouseWheelEvent < Event
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

  class WindowEvent < Event
    getter kind : WindowEventKind
    getter size : Vec2
    def initialize(@kind, @size = Vec2::ZERO); end
  end

  class GamepadButtonEvent < Event
    getter gamepad : Int32
    getter button : GamepadButton
    getter? pressed : Bool
    def initialize(@gamepad, @button, @pressed); end
  end

  class GamepadAxisEvent < Event
    getter gamepad : Int32
    getter axis : GamepadAxis
    getter value : Float32
    def initialize(@gamepad, @axis, @value); end
  end

  class GamepadConnectionEvent < Event
    getter gamepad : Int32
    getter? connected : Bool
    def initialize(@gamepad, @connected); end
  end

  class FileDropEvent < Event
    getter path : String
    def initialize(@path); end
  end

  class QuitEvent < Event
    def initialize; end
  end
end
