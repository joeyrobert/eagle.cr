module Eagle
  # A physical key, named after its position on a US keyboard.
  #
  # Keys are layout-independent: `Key::W` is the key above `S` whether the player uses
  # QWERTY, AZERTY or Dvorak, which is what you want for movement. For typed text, use
  # `TextEvent` or `TextInput` instead.
  #
  # Naming: `Num1` to `Num0` are the digits above the letters, `Kp0` to `KpEnter` are
  # the numeric keypad, `Grave` is the backtick key, and `LGui`/`RGui` are the Command
  # or Windows keys. `Count` is not a key; it sizes internal tables.
  #
  # ```
  # Input.pressed?(Key::Space)
  # Input.down?(Key::LShift)
  # Key.named?("escape") # => Key::Escape, for loading bindings from a config file
  # ```
  enum Key
    Unknown = 0
    A = 4; B; C; D; E; F; G; H; I; J; K; L; M; N; O; P; Q; R; S; T; U; V; W; X; Y; Z
    Num1 = 30; Num2; Num3; Num4; Num5; Num6; Num7; Num8; Num9; Num0
    Enter = 40; Escape; Backspace; Tab; Space; Minus; Equals; LeftBracket; RightBracket; Backslash
    Semicolon = 51; Apostrophe; Grave; Comma; Period; Slash; CapsLock
    F1 = 58; F2; F3; F4; F5; F6; F7; F8; F9; F10; F11; F12
    PrintScreen = 70; ScrollLock; Pause; Insert; Home; PageUp; Delete; End; PageDown
    Right = 79; Left; Down; Up
    NumLock = 83; KpDivide; KpMultiply; KpMinus; KpPlus; KpEnter; Kp1; Kp2; Kp3; Kp4; Kp5; Kp6; Kp7; Kp8; Kp9; Kp0; KpPeriod
    LCtrl = 224; LShift; LAlt; LGui; RCtrl; RShift; RAlt; RGui

    Count = 512

    # Looks up a key by name, ignoring case. Returns `nil` for unknown names.
    def self.named?(name : String) : Key?
      n = name.downcase
      each { |k| return k if k.to_s.downcase == n }
      nil
    end
  end

  @[Flags]
  # Modifier keys held during a key event. It is a flags enum, so several can be set at once:
  # `event.mods.ctrl?`.
  enum KeyMod
    # Either shift key.
    Shift
    # Either control key.
    Ctrl
    # Either alt/option key.
    Alt
    # Either Command (macOS) or Windows key.
    Gui
  end

  # A mouse button.
  enum MouseButton
    # The primary (usually left) button.
    Left   = 1
    # The wheel button.
    Middle = 2
    # The secondary (usually right) button.
    Right  = 3
    # The "back" side button.
    X1     = 4
    # The "forward" side button.
    X2     = 5
  end

  # A controller button, named after the Xbox layout. `A` is the bottom face button on every
  # controller, including PlayStation's cross, and `B`, `X` and `Y` follow clockwise from it.
  # `Back`, `Guide` and `Start` are the middle buttons, `LeftStick` and `RightStick` are stick
  # clicks, and `Misc1`, the paddles and `Touchpad` exist only on some controllers.
  # `Count` is not a button.
  enum GamepadButton
    A = 0; B; X; Y
    Back; Guide; Start
    LeftStick; RightStick
    LeftShoulder; RightShoulder
    DpadUp; DpadDown; DpadLeft; DpadRight
    Misc1; Paddle1; Paddle2; Paddle3; Paddle4; Touchpad
    Count
  end

  # A controller stick or trigger axis. Sticks range from -1 to 1 and triggers from 0 to 1.
  # `LeftY` and `RightY` are negative when pushed up. `Count` is not an axis.
  enum GamepadAxis
    LeftX = 0; LeftY; RightX; RightY; TriggerLeft; TriggerRight
    Count
  end
end
