module Eagle
  # Platform backends provide a window, a GL-style proc loader, events, timing,
  # an audio output queue, and gamepads. Engine code only talks to this API.
  module Platform
    struct WindowConfig
      property title : String = "Eagle"
      property width : Int32 = 1280
      property height : Int32 = 720
      property resizable : Bool = true
      property fullscreen : Bool = false
      property vsync : Bool = true
      property msaa : Int32 = 0
      property hidden : Bool = false
      property highdpi : Bool = true
      def initialize; end
    end

    abstract class Base
      # Initialise subsystems and create the main window + graphics context.
      abstract def open(config : WindowConfig) : Nil
      abstract def close : Nil
      abstract def swap : Nil
      abstract def poll_events(& : Event ->) : Nil
      # Window size in logical points; drawable size in pixels (HiDPI).
      abstract def window_size : {Int32, Int32}
      abstract def drawable_size : {Int32, Int32}
      abstract def title=(t : String)
      abstract def fullscreen=(v : Bool)
      abstract def vsync=(v : Bool)
      abstract def gl_proc(name : String) : Void*
      abstract def now : Float64 # seconds, monotonic
      abstract def sleep(seconds : Float64) : Nil
      abstract def mouse_position : Vec2
      abstract def relative_mouse=(v : Bool)
      abstract def cursor_visible=(v : Bool)
      abstract def clipboard : String
      abstract def clipboard=(s : String)
      abstract def text_input=(enabled : Bool)
      abstract def base_path : String
      abstract def pref_path(org : String, app : String) : String
      # Audio: open a float32 stereo output. Returns actual sample rate.
      abstract def open_audio(sample_rate : Int32, buffer_frames : Int32) : Int32
      abstract def queue_audio(frames : Slice(Float32)) : Nil
      abstract def queued_audio_frames : Int32
      abstract def close_audio : Nil
      # Gamepads
      abstract def gamepad_name(id : Int32) : String?
      abstract def gamepad_rumble(id : Int32, low : Float32, high : Float32, ms : Int32) : Nil
      abstract def message_box(title : String, message : String) : Nil
    end
  end
end
