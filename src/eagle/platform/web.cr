require "../lib/js"

module Eagle
  module Platform
    # Browser backend: a <canvas> with WebGL2, WebAudio and DOM input, driven by
    # requestAnimationFrame calling the exported `eagle_frame` each frame.
    {% if flag?(:wasm32) %}
      class Web < Base
        EV_KEY = 1; EV_TEXT = 2; EV_MOTION = 3; EV_BUTTON = 4; EV_WHEEL = 5; EV_RESIZE = 6; EV_FOCUS = 7
        EV_GP_CONNECT = 8; EV_GP_BUTTON = 9; EV_GP_AXIS = 10; EV_QUIT = 12

        @buf = Slice(Float32).new(8)
        @size = Slice(Int32).new(4)

        def open(config : WindowConfig) : Nil
          LibJS.js_init(config.width, config.height, config.title.to_unsafe, config.title.bytesize)
        end

        def close : Nil; end
        def swap : Nil; end

        def window_size : {Int32, Int32}
          LibJS.js_window_size(@size.to_unsafe)
          {@size[0], @size[1]}
        end

        def drawable_size : {Int32, Int32}
          LibJS.js_window_size(@size.to_unsafe)
          {@size[2], @size[3]}
        end

        def title=(t : String); LibJS.js_set_title(t.to_unsafe, t.bytesize); end
        def fullscreen=(v : Bool); end
        def vsync=(v : Bool); end
        def gl_proc(name : String) : Void*; Pointer(Void).null; end
        def now : Float64; LibJS.js_now; end
        def sleep(seconds : Float64) : Nil; end
        def mouse_position : Vec2; Input.mouse; end
        def relative_mouse=(v : Bool); LibJS.js_relative_mouse(v ? 1 : 0); end
        def cursor_visible=(v : Bool); LibJS.js_cursor(v ? 1 : 0); end
        def clipboard : String; ""; end
        def clipboard=(s : String); end
        def text_input=(enabled : Bool); LibJS.js_text_input(enabled ? 1 : 0); end
        def base_path : String; "/"; end
        def pref_path(org : String, app : String) : String; "/"; end
        def message_box(title : String, message : String) : Nil
          msg = "#{title}: #{message}"
          LibJS.js_log(1, msg.to_unsafe, msg.bytesize)
        end

        def open_audio(sample_rate : Int32, buffer_frames : Int32) : Int32
          LibJS.js_audio_open(sample_rate, buffer_frames)
        end

        def queue_audio(frames : Slice(Float32)) : Nil
          LibJS.js_audio_queue(frames.to_unsafe, frames.size)
        end

        def queued_audio_frames : Int32; LibJS.js_audio_queued; end
        def close_audio : Nil; end
        def gamepad_name(id : Int32) : String?; "Gamepad #{id}"; end
        def gamepad_rumble(id : Int32, low : Float32, high : Float32, ms : Int32) : Nil
          LibJS.js_gamepad_rumble(id, low, high, ms)
        end

        def poll_events(& : Event ->) : Nil
          while LibJS.js_poll_event(@buf.to_unsafe) == 1
            ev = translate
            yield ev if ev
          end
        end

        private def translate : Event?
          b = @buf
          case b[0].to_i
          when EV_KEY
            KeyEvent.new(Key.from_value?(b[1].to_i) || Key::Unknown, b[2] == 1, b[3] == 1, KeyMod.new(b[4].to_i))
          when EV_TEXT
            text = String.build { |io| (1..6).each { |i| cp = b[i].to_i; io << cp.chr if cp > 0 } }
            text.empty? ? nil : TextEvent.new(text)
          when EV_MOTION then MouseMotionEvent.new(Vec2.new(b[1], b[2]), Vec2.new(b[3], b[4]))
          when EV_BUTTON then MouseButtonEvent.new(MouseButton.from_value?(b[1].to_i) || MouseButton::Left, b[2] == 1, Vec2.new(b[3], b[4]), b[5].to_i)
          when EV_WHEEL then MouseWheelEvent.new(Vec2.new(b[1], b[2]), Vec2.new(b[3], b[4]))
          when EV_RESIZE then WindowEvent.new(WindowEventKind::Resized, Vec2.new(b[1], b[2]))
          when EV_FOCUS then WindowEvent.new(b[1] == 1 ? WindowEventKind::FocusGained : WindowEventKind::FocusLost)
          when EV_GP_CONNECT then GamepadConnectionEvent.new(b[1].to_i, b[2] == 1)
          when EV_GP_BUTTON then GamepadButtonEvent.new(b[1].to_i, GamepadButton.from_value?(b[2].to_i) || GamepadButton::A, b[3] == 1)
          when EV_GP_AXIS then GamepadAxisEvent.new(b[1].to_i, GamepadAxis.from_value?(b[2].to_i) || GamepadAxis::LeftX, b[3])
          when EV_QUIT then QuitEvent.new
          else nil
          end
        end
      end
    {% end %}
  end
end

{% if flag?(:wasm32) %}
  # Called by eagle.js once per animation frame.
  fun eagle_frame : Void
    Eagle.step if Eagle.running?
  end
{% end %}
