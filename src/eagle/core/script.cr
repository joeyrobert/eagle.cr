module Eagle
  # Schedules synthetic input over time: key presses, clicks, drags, touches and gamepad events.
  #
  # Scripts drive integration tests, attract-mode demos and replays. Events go through
  # exactly the same path as real input, so `Input`, `App#input` and every node see them.
  # Times are seconds since the first step was scheduled.
  #
  # ```
  # Script.at(0.5) { Script.click(v2(100, 100)) }
  # Script.at(1.0) { Script.type("hello"); Script.key(Key::Enter) }
  # Script.drag(v2(10, 10), v2(200, 200), seconds: 0.5, start: 2.0)
  # Script.hold(Key::Right, 1.5, start: 3.0) # walk right for a moment
  # Script.pinch(v2(480, 270), 100, 250, start: 4.0) # two fingers spread apart
  # ```
  module Script
    # One scheduled action.
    record Step, time : Float64, action : Proc(Nil)

    @@steps = [] of Step
    @@time = 0.0
    @@running = false

    # Runs the block when the script clock reaches *seconds*.
    def self.at(seconds : Number, &block : ->) : Nil
      @@steps << Step.new(seconds.to_f64, block)
      @@steps.sort_by!(&.time)
      @@running = true
    end

    # Seconds since the script started.
    def self.time : Float64; @@time; end
    # Number of steps still waiting to run.
    def self.pending : Int32; @@steps.size; end
    # True while steps remain.
    def self.running? : Bool; @@running && !@@steps.empty?; end

    # Cancels every pending step and resets the clock.
    def self.clear : Nil
      @@steps.clear
      @@time = 0.0
      @@running = false
    end

    # :nodoc: advance and fire due steps (called by the engine every frame)
    def self.tick(dt : Float64 = Clock.raw_delta.to_f64) : Nil
      return unless @@running
      @@time += dt
      while (st = @@steps.first?) && st.time <= @@time
        @@steps.shift
        st.action.call
      end
    end

    # --- convenience emitters (queue events for the next frame) ---
    # Presses and releases a key on the next frame.
    def self.key(k : Key, mods : KeyMod = KeyMod::None) : Nil
      Eagle.inject(KeyEvent.new(k, true, false, mods), KeyEvent.new(k, false, false, mods))
    end

    # Presses a key and keeps it held until `key_up`.
    def self.key_down(k : Key, mods : KeyMod = KeyMod::None) : Nil; Eagle.inject(KeyEvent.new(k, true, false, mods)); end
    # Releases a key.
    def self.key_up(k : Key, mods : KeyMod = KeyMod::None) : Nil; Eagle.inject(KeyEvent.new(k, false, false, mods)); end
    # Types text, as if entered on the keyboard.
    def self.type(text : String) : Nil; Eagle.inject(TextEvent.new(text)); end
    # Moves the mouse to *to*.
    def self.move(to : Vec2) : Nil
      Eagle.inject(MouseMotionEvent.new(to, to - Input.mouse))
    end

    # Moves the mouse to *at* and clicks. Pass `clicks: 2` for a double-click.
    def self.click(at : Vec2, button : MouseButton = MouseButton::Left, clicks : Int32 = 1) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, true, at, clicks), MouseButtonEvent.new(button, false, at, clicks))
    end

    # Moves to *at* and presses a mouse button without releasing it.
    def self.press(at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, true, at))
    end

    # Moves to *at* and releases a mouse button.
    def self.release(at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, false, at))
    end

    # Scrolls the wheel by *delta*.
    def self.wheel(delta : Vec2, at : Vec2 = Input.mouse) : Nil
      Eagle.inject(MouseWheelEvent.new(delta, at))
    end

    # Schedules a full drag: press at *from*, move in *steps* increments over *seconds*,
    # then release at *to*. Starts at script time *start*.
    def self.drag(from : Vec2, to : Vec2, seconds : Number = 0.5, start : Number = 0, steps : Int32 = 10, button : MouseButton = MouseButton::Left) : Nil
      at(start) { press(from, button) }
      (1..steps).each do |i|
        t = i / steps.to_f
        at(start.to_f64 + seconds * t) { move(from.lerp(to, t)) }
      end
      at(start.to_f64 + seconds + 0.01) { release(to, button) }
    end

    # Puts finger *id* down at *at*. Follow with `touch_move` and `touch_up`.
    def self.touch_down(id : Int32, at : Vec2) : Nil; Eagle.inject(TouchEvent.new(id, TouchPhase::Began, at)); end
    # Moves finger *id* to *to*.
    def self.touch_move(id : Int32, to : Vec2) : Nil; Eagle.inject(TouchEvent.new(id, TouchPhase::Moved, to)); end
    # Lifts finger *id* at *at*.
    def self.touch_up(id : Int32, at : Vec2) : Nil; Eagle.inject(TouchEvent.new(id, TouchPhase::Ended, at)); end
    # Cancels finger *id*, as when the system takes the touch away.
    def self.touch_cancel(id : Int32, at : Vec2) : Nil; Eagle.inject(TouchEvent.new(id, TouchPhase::Cancelled, at)); end

    # Taps once with a finger: down and up on the next frame.
    def self.touch_tap(at : Vec2, id : Int32 = 0) : Nil
      Eagle.inject(TouchEvent.new(id, TouchPhase::Began, at), TouchEvent.new(id, TouchPhase::Ended, at))
    end

    # Schedules a one-finger drag: down at *from*, move to *to* in *steps* over *seconds*, then up.
    def self.touch_drag(from : Vec2, to : Vec2, seconds : Number = 0.5, start : Number = 0, steps : Int32 = 10, id : Int32 = 0) : Nil
      at(start) { touch_down(id, from) }
      (1..steps).each do |i|
        t = i / steps.to_f
        at(start.to_f64 + seconds * t) { touch_move(id, from.lerp(to, t)) }
      end
      at(start.to_f64 + seconds + 0.01) { touch_up(id, to) }
    end

    # Schedules a two-finger pinch around *center*: the fingers start *from* pixels apart and end *to* apart.
    def self.pinch(center : Vec2, from : Number, to : Number, seconds : Number = 0.5, start : Number = 0, steps : Int32 = 10) : Nil
      two_fingers(center, from, to, 0.0, 0.0, seconds, start, steps)
    end

    # Schedules a two-finger twist around *center* with the fingers *radius* pixels out, turning by *radians*.
    def self.twist(center : Vec2, radius : Number, radians : Number, seconds : Number = 0.5, start : Number = 0, steps : Int32 = 10) : Nil
      two_fingers(center, radius * 2, radius * 2, 0.0, radians.to_f64, seconds, start, steps)
    end

    private def self.two_fingers(center : Vec2, from : Number, to : Number, angle0 : Float64, turn : Float64, seconds : Number, start : Number, steps : Int32) : Nil
      spots = ->(t : Float64) do
        half = (from + (to - from) * t) / 2
        off = Vec2.new(half, 0).rotated(angle0 + turn * t)
        {center + off, center - off}
      end
      first = spots.call(0.0)
      at(start) { touch_down(0, first[0]); touch_down(1, first[1]) }
      (1..steps).each do |i|
        t = i / steps.to_f
        at(start.to_f64 + seconds * t) { pa, pb = spots.call(t); touch_move(0, pa); touch_move(1, pb) }
      end
      last = spots.call(1.0)
      at(start.to_f64 + seconds + 0.01) { touch_up(0, last[0]); touch_up(1, last[1]) }
    end

    # Holds a key down for *seconds*, starting at script time *start*.
    def self.hold(k : Key, seconds : Number, start : Number = 0) : Nil
      at(start) { key_down(k) }
      at(start.to_f64 + seconds) { key_up(k) }
    end

    # Presses and releases a gamepad button.
    def self.gamepad_button(id : Int32, b : GamepadButton) : Nil
      Eagle.inject(GamepadButtonEvent.new(id, b, true), GamepadButtonEvent.new(id, b, false))
    end

    # Moves a gamepad axis to *value* (-1 to 1).
    def self.gamepad_axis(id : Int32, axis : GamepadAxis, value : Number) : Nil
      Eagle.inject(GamepadAxisEvent.new(id, axis, value.to_f32))
    end

    # Simulates plugging in a gamepad.
    def self.connect_gamepad(id : Int32 = 0) : Nil
      Eagle.inject(GamepadConnectionEvent.new(id, true))
    end

    # Simulates dropping a file onto the window.
    def self.drop_file(path : String) : Nil
      Eagle.inject(FileDropEvent.new(path))
    end
  end
end
