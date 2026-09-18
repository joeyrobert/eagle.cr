module Eagle
  # Base class for input and window events, delivered to `App#input` and `Node#input`.
  #
  # Use events when you care that something happened: a key went down, a button was
  # clicked, the window resized. For "is this key held right now?", ask `Input` instead.
  #
  # Nodes receive events deepest-first, in reverse order of addition, so the thing
  # drawn on top gets the first chance. Set `handled = true` to stop the event from
  # reaching anything else.
  #
  # ```
  # class Menu < Node2D
  #   def input(event : Event) : Nil
  #     case event
  #     when KeyEvent
  #       if event.pressed? && event.key.escape?
  #         visible = !visible?
  #         event.handled = true
  #       end
  #     when MouseButtonEvent
  #       puts "click at #{event.position}" if event.pressed?
  #     end
  #   end
  # end
  # ```
  abstract class Event
    # Set to true in a handler to stop the event from reaching later nodes.
    property? handled = false
  end

  # A keyboard key went down or up. Key repeat sends more presses with `repeat?` set.
  # For typed text, use `TextEvent`, which handles keyboard layouts and dead keys.
  class KeyEvent < Event
    getter key : Key
    getter? pressed : Bool
    getter? repeat : Bool
    getter mods : KeyMod
    def initialize(@key, @pressed, @repeat = false, @mods = KeyMod::None); end
    # True when the key was released.
    def released? : Bool; !@pressed; end
  end

  # Text the player typed, already composed by the OS (accents, CJK input and so on).
  # Enable it with `Input.text_input = true`; `TextInput` controls do this for you.
  class TextEvent < Event
    getter text : String
    def initialize(@text); end
  end

  # A mouse button went down or up. `position` is in window coordinates, and `clicks` is
  # 2 for a double-click.
  class MouseButtonEvent < Event
    getter button : MouseButton
    getter? pressed : Bool
    getter position : Vec2
    getter clicks : Int32
    def initialize(@button, @pressed, @position, @clicks = 1); end
    # True when the button was released.
    def released? : Bool; !@pressed; end
  end

  # The mouse moved. `delta` is the movement since the last event, which still works
  # when `Window.relative_mouse=` has locked the cursor.
  class MouseMotionEvent < Event
    getter position : Vec2
    getter delta : Vec2
    def initialize(@position, @delta); end
  end

  # The wheel or trackpad scrolled. `delta.y` is positive when scrolling up.
  class MouseWheelEvent < Event
    getter delta : Vec2
    getter position : Vec2
    def initialize(@delta, @position); end
  end

  # What happened to the window in a `WindowEvent`.
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

  # The window was resized, gained or lost focus, was minimized or restored, or the mouse
  # entered or left it. `App#resize` and `Node#resized` already cover resizing.
  class WindowEvent < Event
    getter kind : WindowEventKind
    getter size : Vec2
    def initialize(@kind, @size = Vec2::ZERO); end
  end

  # A gamepad button went down or up. `gamepad` is the controller's id.
  class GamepadButtonEvent < Event
    getter gamepad : Int32
    getter button : GamepadButton
    getter? pressed : Bool
    def initialize(@gamepad, @button, @pressed); end
  end

  # A gamepad stick or trigger moved, with `value` from -1 to 1 (0 to 1 for triggers).
  class GamepadAxisEvent < Event
    getter gamepad : Int32
    getter axis : GamepadAxis
    getter value : Float32
    def initialize(@gamepad, @axis, @value); end
  end

  # A gamepad was plugged in or unplugged.
  class GamepadConnectionEvent < Event
    getter gamepad : Int32
    getter? connected : Bool
    def initialize(@gamepad, @connected); end
  end

  # A file was dragged onto the window. `path` is its full path, for level editors and viewers.
  class FileDropEvent < Event
    getter path : String
    def initialize(@path); end
  end

  # The player asked to close the window. `App#quit?` decides whether to actually quit.
  class QuitEvent < Event
    def initialize; end
  end
end
