require "../lib/sdl2"

# Crystal hands the scheduler to a new thread when the main fiber sits in a blocking syscall (a long file read)
# for over 10ms. The GL context and the Cocoa event loop belong to the original thread, so the next GL or event call
# crashes. Run those calls in place so the main fiber never changes threads.
class Fiber
  # :nodoc:
  def self.syscall(&)
    yield
  end
end

module Eagle
  module Platform
    # :nodoc:
    class SDL < Base
      @window : LibSDL::Window = Pointer(Void).null
      @context : LibSDL::GLContext = Pointer(Void).null
      @audio_device : LibSDL::AudioDeviceID = 0_u32
      @audio_channels = 2
      @gamepads = {} of Int32 => LibSDL::GameController
      @perf_freq : Float64 = 1.0
      @event = LibSDL::Event.new

      def initialize
      end

      def open(config : WindowConfig) : Nil
        flags = LibSDL::INIT_VIDEO | LibSDL::INIT_EVENTS | LibSDL::INIT_TIMER | LibSDL::INIT_GAMECONTROLLER | LibSDL::INIT_AUDIO
        if LibSDL.init(flags) != 0
          # Audio may be unavailable (CI); retry without it.
          raise Error.new("SDL_Init failed: #{error}") if LibSDL.init(flags & ~LibSDL::INIT_AUDIO) != 0
          Eagle.log.warn { "SDL audio subsystem unavailable: #{error}" }
        end
        @perf_freq = LibSDL.get_performance_frequency.to_f64

        LibSDL.set_hint("SDL_VIDEO_HIGHDPI_DISABLED", config.highdpi ? "0" : "1")
        LibSDL.gl_set_attribute(LibSDL::GL_CONTEXT_MAJOR_VERSION, 3)
        LibSDL.gl_set_attribute(LibSDL::GL_CONTEXT_MINOR_VERSION, 3)
        LibSDL.gl_set_attribute(LibSDL::GL_CONTEXT_PROFILE_MASK, LibSDL::GL_CONTEXT_PROFILE_CORE)
        LibSDL.gl_set_attribute(LibSDL::GL_CONTEXT_FLAGS, LibSDL::GL_CONTEXT_FORWARD_COMPATIBLE_FLAG)
        LibSDL.gl_set_attribute(LibSDL::GL_DOUBLEBUFFER, 1)
        LibSDL.gl_set_attribute(LibSDL::GL_DEPTH_SIZE, 24)
        LibSDL.gl_set_attribute(LibSDL::GL_STENCIL_SIZE, 8)
        if config.msaa > 0
          LibSDL.gl_set_attribute(LibSDL::GL_MULTISAMPLEBUFFERS, 1)
          LibSDL.gl_set_attribute(LibSDL::GL_MULTISAMPLESAMPLES, config.msaa)
        end

        wflags = LibSDL::WINDOW_OPENGL
        wflags |= LibSDL::WINDOW_RESIZABLE if config.resizable
        wflags |= LibSDL::WINDOW_FULLSCREEN_DESKTOP if config.fullscreen
        wflags |= LibSDL::WINDOW_ALLOW_HIGHDPI if config.highdpi
        wflags |= config.hidden ? LibSDL::WINDOW_HIDDEN : LibSDL::WINDOW_SHOWN

        @window = LibSDL.create_window(config.title, LibSDL::WINDOWPOS_CENTERED, LibSDL::WINDOWPOS_CENTERED, config.width, config.height, wflags)
        raise Error.new("SDL_CreateWindow failed: #{error}") if @window.null?

        @context = LibSDL.gl_create_context(@window)
        if @context.null? && config.msaa > 0
          # Retry without multisampling.
          LibSDL.gl_set_attribute(LibSDL::GL_MULTISAMPLEBUFFERS, 0)
          LibSDL.gl_set_attribute(LibSDL::GL_MULTISAMPLESAMPLES, 0)
          @context = LibSDL.gl_create_context(@window)
        end
        raise Error.new("SDL_GL_CreateContext failed: #{error}") if @context.null?
        LibSDL.gl_make_current(@window, @context)
        self.vsync = config.vsync
      end

      def close : Nil
        close_audio
        @gamepads.each_value { |gc| LibSDL.game_controller_close(gc) }
        @gamepads.clear
        LibSDL.gl_delete_context(@context) unless @context.null?
        LibSDL.destroy_window(@window) unless @window.null?
        @context = Pointer(Void).null
        @window = Pointer(Void).null
        LibSDL.quit
      end

      def error : String
        String.new(LibSDL.get_error)
      end

      def swap : Nil
        LibSDL.gl_swap_window(@window)
      end

      def window_size : {Int32, Int32}
        LibSDL.get_window_size(@window, out w, out h)
        {w, h}
      end

      def drawable_size : {Int32, Int32}
        LibSDL.gl_get_drawable_size(@window, out w, out h)
        {w, h}
      end

      def title=(t : String); LibSDL.set_window_title(@window, t); end

      def fullscreen=(v : Bool)
        LibSDL.set_window_fullscreen(@window, v ? LibSDL::WINDOW_FULLSCREEN_DESKTOP : 0_u32)
      end

      def vsync=(v : Bool)
        if v
          LibSDL.gl_set_swap_interval(-1) != 0 && LibSDL.gl_set_swap_interval(1)
        else
          LibSDL.gl_set_swap_interval(0)
        end
      end

      def gl_proc(name : String) : Void*
        LibSDL.gl_get_proc_address(name)
      end

      def now : Float64
        LibSDL.get_performance_counter.to_f64 / @perf_freq
      end

      def sleep(seconds : Float64) : Nil
        LibSDL.delay((seconds * 1000).to_u32) if seconds > 0
      end

      def mouse_position : Vec2
        LibSDL.get_mouse_state(out x, out y)
        Vec2.new(x, y)
      end

      def relative_mouse=(v : Bool); LibSDL.set_relative_mouse_mode(v ? 1 : 0); end
      def cursor_visible=(v : Bool); LibSDL.show_cursor(v ? 1 : 0); end

      def clipboard : String
        p = LibSDL.get_clipboard_text
        s = String.new(p)
        LibSDL.free(p)
        s
      end

      def clipboard=(s : String); LibSDL.set_clipboard_text(s); end

      def text_input=(enabled : Bool)
        enabled ? LibSDL.start_text_input : LibSDL.stop_text_input
      end

      def set_text_input_area(rect : Rect, text : String, caret : Int32) : Nil
        r = LibSDL::Rect.new(x: rect.x.to_i, y: rect.y.to_i, w: rect.w.to_i, h: rect.h.to_i)
        LibSDL.set_text_input_rect(pointerof(r))
      end

      def base_path : String
        p = LibSDL.get_base_path
        return Dir.current if p.null?
        s = String.new(p); LibSDL.free(p); s
      end

      def pref_path(org : String, app : String) : String
        p = LibSDL.get_pref_path(org, app)
        return Dir.current if p.null?
        s = String.new(p); LibSDL.free(p); s
      end

      def message_box(title : String, message : String) : Nil
        LibSDL.show_simple_message_box(0x10_u32, title, message, @window)
      end

      # --- audio ---------------------------------------------------------
      def open_audio(sample_rate : Int32, buffer_frames : Int32) : Int32
        desired = LibSDL::AudioSpec.new
        desired.freq = sample_rate
        desired.format = LibSDL::AUDIO_F32SYS
        desired.channels = 2_u8
        desired.samples = buffer_frames.to_u16
        obtained = LibSDL::AudioSpec.new
        @audio_device = LibSDL.open_audio_device(Pointer(UInt8).null, 0, pointerof(desired), pointerof(obtained), 0)
        if @audio_device == 0
          Eagle.log.warn { "Could not open audio device: #{error}" }
          return 0
        end
        LibSDL.pause_audio_device(@audio_device, 0)
        obtained.freq
      end

      def queue_audio(frames : Slice(Float32)) : Nil
        return if @audio_device == 0
        LibSDL.queue_audio(@audio_device, frames.to_unsafe.as(Void*), (frames.size * 4).to_u32)
      end

      def queued_audio_frames : Int32
        return 0 if @audio_device == 0
        (LibSDL.get_queued_audio_size(@audio_device) // (4 * @audio_channels)).to_i
      end

      def close_audio : Nil
        return if @audio_device == 0
        LibSDL.close_audio_device(@audio_device)
        @audio_device = 0_u32
      end

      # --- gamepads ------------------------------------------------------
      def gamepad_name(id : Int32) : String?
        gc = @gamepads[id]?
        return nil unless gc
        p = LibSDL.game_controller_name(gc)
        p.null? ? "Gamepad" : String.new(p)
      end

      def gamepad_rumble(id : Int32, low : Float32, high : Float32, ms : Int32) : Nil
        gc = @gamepads[id]?
        return unless gc
        LibSDL.game_controller_rumble(gc, (low.clamp(0, 1) * 65535).to_u16, (high.clamp(0, 1) * 65535).to_u16, ms.to_u32)
      end

      # --- events --------------------------------------------------------
      def poll_events(& : Event ->) : Nil
        while LibSDL.poll_event(pointerof(@event)) != 0
          ev = translate(pointerof(@event))
          yield ev if ev
        end
      end

      private def translate(raw : LibSDL::Event*) : Event?
        case raw.value.type
        when LibSDL::QUIT
          QuitEvent.new
        when LibSDL::KEYDOWN, LibSDL::KEYUP
          e = raw.as(LibSDL::KeyboardEvent*).value
          code = e.keysym.scancode
          key = (code >= 0 && code < Key::Count.value) ? Key.from_value?(code) || Key::Unknown : Key::Unknown
          KeyEvent.new(key, e.type == LibSDL::KEYDOWN, e.repeat != 0, translate_mods(e.keysym.mod))
        when LibSDL::TEXTEDITING
          e = raw.as(LibSDL::TextEditingEvent*).value
          CompositionEvent.new(String.new(e.text.to_unsafe))
        when LibSDL::TEXTINPUT
          e = raw.as(LibSDL::TextInputEvent*).value
          TextEvent.new(String.new(e.text.to_unsafe))
        when LibSDL::MOUSEMOTION
          e = raw.as(LibSDL::MouseMotionEvent*).value
          MouseMotionEvent.new(Vec2.new(e.x, e.y), Vec2.new(e.xrel, e.yrel))
        when LibSDL::MOUSEBUTTONDOWN, LibSDL::MOUSEBUTTONUP
          e = raw.as(LibSDL::MouseButtonEvent*).value
          MouseButtonEvent.new(MouseButton.from_value?(e.button.to_i) || MouseButton::Left, e.type == LibSDL::MOUSEBUTTONDOWN, Vec2.new(e.x, e.y), e.clicks.to_i)
        when LibSDL::MOUSEWHEEL
          e = raw.as(LibSDL::MouseWheelEvent*).value
          sign = e.direction == LibSDL::MOUSEWHEEL_FLIPPED ? -1 : 1
          MouseWheelEvent.new(Vec2.new(e.precise_x * sign, e.precise_y * sign), Vec2.new(e.mouse_x, e.mouse_y))
        when LibSDL::WINDOWEVENT
          e = raw.as(LibSDL::WindowEvent*).value
          case e.event
          when LibSDL::WINDOWEVENT_SIZE_CHANGED then WindowEvent.new(WindowEventKind::Resized, Vec2.new(e.data1, e.data2))
          when LibSDL::WINDOWEVENT_FOCUS_GAINED then WindowEvent.new(WindowEventKind::FocusGained)
          when LibSDL::WINDOWEVENT_FOCUS_LOST   then WindowEvent.new(WindowEventKind::FocusLost)
          when LibSDL::WINDOWEVENT_ENTER        then WindowEvent.new(WindowEventKind::MouseEnter)
          when LibSDL::WINDOWEVENT_LEAVE        then WindowEvent.new(WindowEventKind::MouseLeave)
          when LibSDL::WINDOWEVENT_MINIMIZED    then WindowEvent.new(WindowEventKind::Minimized)
          when LibSDL::WINDOWEVENT_RESTORED     then WindowEvent.new(WindowEventKind::Restored)
          when LibSDL::WINDOWEVENT_CLOSE        then WindowEvent.new(WindowEventKind::Close)
          else nil
          end
        when LibSDL::CONTROLLERDEVICEADDED
          e = raw.as(LibSDL::ControllerDeviceEvent*).value
          gc = LibSDL.game_controller_open(e.which)
          return nil if gc.null?
          id = LibSDL.joystick_instance_id(LibSDL.game_controller_get_joystick(gc))
          @gamepads[id] = gc
          GamepadConnectionEvent.new(id, true)
        when LibSDL::CONTROLLERDEVICEREMOVED
          e = raw.as(LibSDL::ControllerDeviceEvent*).value
          if gc = @gamepads.delete(e.which)
            LibSDL.game_controller_close(gc)
          end
          GamepadConnectionEvent.new(e.which, false)
        when LibSDL::CONTROLLERBUTTONDOWN, LibSDL::CONTROLLERBUTTONUP
          e = raw.as(LibSDL::ControllerButtonEvent*).value
          GamepadButtonEvent.new(e.which, GamepadButton.from_value?(e.button.to_i) || GamepadButton::A, e.type == LibSDL::CONTROLLERBUTTONDOWN)
        when LibSDL::CONTROLLERAXISMOTION
          e = raw.as(LibSDL::ControllerAxisEvent*).value
          v = e.value < 0 ? e.value / 32768_f32 : e.value / 32767_f32
          GamepadAxisEvent.new(e.which, GamepadAxis.from_value?(e.axis.to_i) || GamepadAxis::LeftX, v)
        when LibSDL::DROPFILE
          e = raw.as(LibSDL::DropEvent*).value
          path = String.new(e.file)
          LibSDL.free(e.file.as(Void*))
          FileDropEvent.new(path)
        else
          nil
        end
      end

      private def translate_mods(m : UInt16) : KeyMod
        r = KeyMod::None
        r |= KeyMod::Shift if m & 0x0003 != 0
        r |= KeyMod::Ctrl if m & 0x00C0 != 0
        r |= KeyMod::Alt if m & 0x0300 != 0
        r |= KeyMod::Gui if m & 0x0C00 != 0
        r
      end
    end
  end
end
