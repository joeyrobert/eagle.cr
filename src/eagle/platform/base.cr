module Eagle
  # The operating-system layer: window, input events, timing, audio output and gamepads.
  # Eagle ships an SDL2 backend for desktop and a browser backend for WebAssembly.
  #
  # Games use `Window`, `Input` and `Audio` instead. Read this module only when porting
  # Eagle to a new platform.
  module Platform
    # Window settings passed to a backend when it opens. `Config` fills this in.
    struct WindowConfig
      # Window title.
      property title : String = "Eagle"
      # Width in logical points.
      property width : Int32 = 1280
      # Height in logical points.
      property height : Int32 = 720
      # Whether the window can be resized.
      property resizable : Bool = true
      # Start fullscreen.
      property fullscreen : Bool = false
      # Sync to the display refresh.
      property vsync : Bool = true
      # Multisample count.
      property msaa : Int32 = 0
      # Start hidden.
      property hidden : Bool = false
      # Use full resolution on high-DPI screens.
      property highdpi : Bool = true
      # Creates the default config.
      def initialize; end
    end

    # The interface a platform backend implements. `Eagle.platform` returns the active one.
    abstract class Base
      # Creates the window and graphics context.
      abstract def open(config : WindowConfig) : Nil
      # Destroys the window and shuts the backend down.
      abstract def close : Nil
      # Presents the frame.
      abstract def swap : Nil
      # Yields each pending event.
      abstract def poll_events(& : Event ->) : Nil
      # Window size in logical points.
      abstract def window_size : {Int32, Int32}
      # Framebuffer size in pixels.
      abstract def drawable_size : {Int32, Int32}
      # Sets the window title.
      abstract def title=(t : String)
      # Enters or leaves fullscreen.
      abstract def fullscreen=(v : Bool)
      # Turns vsync on or off.
      abstract def vsync=(v : Bool)
      # Looks up an OpenGL function pointer.
      abstract def gl_proc(name : String) : Void*
      # Monotonic time in seconds.
      abstract def now : Float64 # seconds, monotonic
      # Sleeps for *seconds*.
      abstract def sleep(seconds : Float64) : Nil
      # Current mouse position.
      abstract def mouse_position : Vec2
      # Captures or releases the mouse.
      abstract def relative_mouse=(v : Bool)
      # Shows or hides the cursor.
      abstract def cursor_visible=(v : Bool)
      # Clipboard text.
      abstract def clipboard : String
      # Sets the clipboard text.
      abstract def clipboard=(s : String)
      # Starts or stops OS text input.
      abstract def text_input=(enabled : Bool)
      # Folder containing the executable.
      abstract def base_path : String
      # A writable folder for saves and settings, per organization and app.
      abstract def pref_path(org : String, app : String) : String
      # Opens a stereo float output. Returns the actual sample rate, or 0 on failure.
      abstract def open_audio(sample_rate : Int32, buffer_frames : Int32) : Int32
      # Queues interleaved stereo samples for playback.
      abstract def queue_audio(frames : Slice(Float32)) : Nil
      # Frames queued and not yet played.
      abstract def queued_audio_frames : Int32
      # Closes the audio output.
      abstract def close_audio : Nil
      # The product name of a controller.
      abstract def gamepad_name(id : Int32) : String?
      # Vibrates a controller.
      abstract def gamepad_rumble(id : Int32, low : Float32, high : Float32, ms : Int32) : Nil
      # Shows a native message box, for fatal errors.
      abstract def message_box(title : String, message : String) : Nil
    end
  end
end
