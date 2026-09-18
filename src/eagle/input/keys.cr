module Eagle
  # A physical key, named after its position on a US keyboard.
  #
  # Keys are layout-independent: `Key::W` is the key above `S` whether the player uses
  # QWERTY, AZERTY or Dvorak, which is what you want for movement. For typed text, use
  # `TextEvent` or `TextInput` instead.
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
    Shift
    Ctrl
    Alt
    Gui
  end

  # A mouse button.
  enum MouseButton
    Left   = 1
    Middle = 2
    Right  = 3
    X1     = 4
    X2     = 5
  end

  # A controller button, named after the Xbox layout. `A` is the bottom face button on every
  # controller, including PlayStation's cross.
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
  enum GamepadAxis
    LeftX = 0; LeftY; RightX; RightY; TriggerLeft; TriggerRight
    Count
  end
end
