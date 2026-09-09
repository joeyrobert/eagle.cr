module Eagle
  # Scripted interactions: schedule synthetic input over time. Used by demos
  # (`EAGLE_DEMO=1`), integration specs and replays.
  #
  #   Script.at(0.5) { Script.click(v2(100, 100)) }
  #   Script.at(1.0) { Script.type("hello"); Script.key(Key::Enter) }
  #   Script.drag(v2(10, 10), v2(200, 200), seconds: 0.5, start: 2.0)
  module Script
    record Step, time : Float64, action : Proc(Nil)

    @@steps = [] of Step
    @@time = 0.0
    @@running = false

    def self.at(seconds : Number, &block : ->) : Nil
      @@steps << Step.new(seconds.to_f64, block)
      @@steps.sort_by!(&.time)
      @@running = true
    end

    # Time since the script started (advances each frame).
    def self.time : Float64; @@time; end
    def self.pending : Int32; @@steps.size; end
    def self.running? : Bool; @@running && !@@steps.empty?; end

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
    def self.key(k : Key, mods : KeyMod = KeyMod::None) : Nil
      Eagle.inject(KeyEvent.new(k, true, false, mods), KeyEvent.new(k, false, false, mods))
    end

    def self.key_down(k : Key, mods : KeyMod = KeyMod::None) : Nil; Eagle.inject(KeyEvent.new(k, true, false, mods)); end
    def self.key_up(k : Key, mods : KeyMod = KeyMod::None) : Nil; Eagle.inject(KeyEvent.new(k, false, false, mods)); end
    def self.type(text : String) : Nil; Eagle.inject(TextEvent.new(text)); end
    def self.move(to : Vec2) : Nil
      Eagle.inject(MouseMotionEvent.new(to, to - Input.mouse))
    end

    def self.click(at : Vec2, button : MouseButton = MouseButton::Left, clicks : Int32 = 1) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, true, at, clicks), MouseButtonEvent.new(button, false, at, clicks))
    end

    def self.press(at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, true, at))
    end

    def self.release(at : Vec2, button : MouseButton = MouseButton::Left) : Nil
      Eagle.inject(MouseMotionEvent.new(at, at - Input.mouse), MouseButtonEvent.new(button, false, at))
    end

    def self.wheel(delta : Vec2, at : Vec2 = Input.mouse) : Nil
      Eagle.inject(MouseWheelEvent.new(delta, at))
    end

    # Press at `from`, move over `seconds` in `steps` increments, release at `to`.
    def self.drag(from : Vec2, to : Vec2, seconds : Number = 0.5, start : Number = 0, steps : Int32 = 10, button : MouseButton = MouseButton::Left) : Nil
      at(start) { press(from, button) }
      (1..steps).each do |i|
        t = i / steps.to_f
        at(start.to_f64 + seconds * t) { move(from.lerp(to, t)) }
      end
      at(start.to_f64 + seconds + 0.01) { release(to, button) }
    end

    # Hold a key for a duration.
    def self.hold(k : Key, seconds : Number, start : Number = 0) : Nil
      at(start) { key_down(k) }
      at(start.to_f64 + seconds) { key_up(k) }
    end

    def self.gamepad_button(id : Int32, b : GamepadButton) : Nil
      Eagle.inject(GamepadButtonEvent.new(id, b, true), GamepadButtonEvent.new(id, b, false))
    end

    def self.gamepad_axis(id : Int32, axis : GamepadAxis, value : Number) : Nil
      Eagle.inject(GamepadAxisEvent.new(id, axis, value.to_f32))
    end

    def self.connect_gamepad(id : Int32 = 0) : Nil
      Eagle.inject(GamepadConnectionEvent.new(id, true))
    end

    def self.drop_file(path : String) : Nil
      Eagle.inject(FileDropEvent.new(path))
    end
  end
end
