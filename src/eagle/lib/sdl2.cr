# Minimal SDL2 bindings: only what Eagle's SDL platform backend needs.
{% if flag?(:windows) %}
  @[Link("SDL2")]
{% elsif flag?(:darwin) %}
  @[Link("SDL2")]
{% else %}
  @[Link("SDL2")]
{% end %}
# :nodoc:
lib LibSDL
  alias Window = Void*
  alias GLContext = Void*
  alias GameController = Void*
  alias Joystick = Void*
  alias JoystickID = Int32
  alias AudioDeviceID = UInt32
  alias AudioFormat = UInt16

  INIT_TIMER          = 0x00000001_u32
  INIT_AUDIO          = 0x00000010_u32
  INIT_VIDEO          = 0x00000020_u32
  INIT_JOYSTICK       = 0x00000200_u32
  INIT_HAPTIC         = 0x00001000_u32
  INIT_GAMECONTROLLER = 0x00002000_u32
  INIT_EVENTS         = 0x00004000_u32

  WINDOW_FULLSCREEN         = 0x00000001_u32
  WINDOW_OPENGL             = 0x00000002_u32
  WINDOW_SHOWN              = 0x00000004_u32
  WINDOW_HIDDEN             = 0x00000008_u32
  WINDOW_BORDERLESS         = 0x00000010_u32
  WINDOW_RESIZABLE          = 0x00000020_u32
  WINDOW_MINIMIZED          = 0x00000040_u32
  WINDOW_MAXIMIZED          = 0x00000080_u32
  WINDOW_FULLSCREEN_DESKTOP = 0x00001001_u32
  WINDOW_ALLOW_HIGHDPI      = 0x00002000_u32

  WINDOWPOS_CENTERED = 0x2FFF0000

  # SDL_GLattr
  GL_RED_SIZE              =  0
  GL_GREEN_SIZE            =  1
  GL_BLUE_SIZE             =  2
  GL_ALPHA_SIZE            =  3
  GL_DOUBLEBUFFER          =  5
  GL_DEPTH_SIZE            =  6
  GL_STENCIL_SIZE          =  7
  GL_MULTISAMPLEBUFFERS    = 13
  GL_MULTISAMPLESAMPLES    = 14
  GL_CONTEXT_MAJOR_VERSION = 17
  GL_CONTEXT_MINOR_VERSION = 18
  GL_CONTEXT_FLAGS         = 20
  GL_CONTEXT_PROFILE_MASK  = 21
  GL_FRAMEBUFFER_SRGB_CAPABLE = 23

  GL_CONTEXT_PROFILE_CORE          = 0x0001
  GL_CONTEXT_FORWARD_COMPATIBLE_FLAG = 0x0002

  # Event types
  QUIT                     = 0x100_u32
  WINDOWEVENT              = 0x200_u32
  KEYDOWN                  = 0x300_u32
  KEYUP                    = 0x301_u32
  TEXTEDITING              = 0x302_u32
  TEXTINPUT                = 0x303_u32
  MOUSEMOTION              = 0x400_u32
  MOUSEBUTTONDOWN          = 0x401_u32
  MOUSEBUTTONUP            = 0x402_u32
  MOUSEWHEEL               = 0x403_u32
  CONTROLLERAXISMOTION     = 0x650_u32
  CONTROLLERBUTTONDOWN     = 0x651_u32
  CONTROLLERBUTTONUP       = 0x652_u32
  CONTROLLERDEVICEADDED    = 0x653_u32
  CONTROLLERDEVICEREMOVED  = 0x654_u32
  DROPFILE                 = 0x1000_u32

  # Window event subtypes
  WINDOWEVENT_RESIZED      =  5_u8
  WINDOWEVENT_SIZE_CHANGED =  6_u8
  WINDOWEVENT_MINIMIZED    =  7_u8
  WINDOWEVENT_RESTORED     =  9_u8
  WINDOWEVENT_ENTER        = 10_u8
  WINDOWEVENT_LEAVE        = 11_u8
  WINDOWEVENT_FOCUS_GAINED = 12_u8
  WINDOWEVENT_FOCUS_LOST   = 13_u8
  WINDOWEVENT_CLOSE        = 14_u8

  BUTTON_LEFT   = 1_u8
  BUTTON_MIDDLE = 2_u8
  BUTTON_RIGHT  = 3_u8
  BUTTON_X1     = 4_u8
  BUTTON_X2     = 5_u8

  MOUSEWHEEL_FLIPPED = 1_u32

  AUDIO_F32SYS = 0x8120_u16
  AUDIO_S16SYS = 0x8010_u16

  struct Keysym
    scancode : Int32
    sym : Int32
    mod : UInt16
    unused : UInt32
  end

  struct KeyboardEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    state : UInt8
    repeat : UInt8
    padding2 : UInt8
    padding3 : UInt8
    keysym : Keysym
  end

  struct TextInputEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    text : UInt8[32]
  end

  struct MouseMotionEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    which : UInt32
    state : UInt32
    x : Int32
    y : Int32
    xrel : Int32
    yrel : Int32
  end

  struct MouseButtonEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    which : UInt32
    button : UInt8
    state : UInt8
    clicks : UInt8
    padding1 : UInt8
    x : Int32
    y : Int32
  end

  struct MouseWheelEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    which : UInt32
    x : Int32
    y : Int32
    direction : UInt32
    precise_x : Float32
    precise_y : Float32
    mouse_x : Int32
    mouse_y : Int32
  end

  struct WindowEvent
    type : UInt32
    timestamp : UInt32
    window_id : UInt32
    event : UInt8
    padding1 : UInt8
    padding2 : UInt8
    padding3 : UInt8
    data1 : Int32
    data2 : Int32
  end

  struct ControllerAxisEvent
    type : UInt32
    timestamp : UInt32
    which : JoystickID
    axis : UInt8
    padding1 : UInt8
    padding2 : UInt8
    padding3 : UInt8
    value : Int16
    padding4 : UInt16
  end

  struct ControllerButtonEvent
    type : UInt32
    timestamp : UInt32
    which : JoystickID
    button : UInt8
    state : UInt8
    padding1 : UInt8
    padding2 : UInt8
  end

  struct ControllerDeviceEvent
    type : UInt32
    timestamp : UInt32
    which : Int32
  end

  struct DropEvent
    type : UInt32
    timestamp : UInt32
    file : UInt8*
    window_id : UInt32
  end

  # Generic event: 56 bytes union. We read `type` and cast.
  struct Event
    type : UInt32
    padding : UInt8[52]
  end

  struct AudioSpec
    freq : Int32
    format : AudioFormat
    channels : UInt8
    silence : UInt8
    samples : UInt16
    padding : UInt16
    size : UInt32
    callback : Void*
    userdata : Void*
  end

  fun init = SDL_Init(flags : UInt32) : Int32
  fun init_sub_system = SDL_InitSubSystem(flags : UInt32) : Int32
  fun quit = SDL_Quit
  fun get_error = SDL_GetError : UInt8*
  fun set_hint = SDL_SetHint(name : UInt8*, value : UInt8*) : Int32
  fun get_platform = SDL_GetPlatform : UInt8*
  fun get_base_path = SDL_GetBasePath : UInt8*
  fun get_pref_path = SDL_GetPrefPath(org : UInt8*, app : UInt8*) : UInt8*
  fun free = SDL_free(ptr : Void*)

  fun create_window = SDL_CreateWindow(title : UInt8*, x : Int32, y : Int32, w : Int32, h : Int32, flags : UInt32) : Window
  fun destroy_window = SDL_DestroyWindow(w : Window)
  fun set_window_title = SDL_SetWindowTitle(w : Window, title : UInt8*)
  fun set_window_size = SDL_SetWindowSize(w : Window, x : Int32, y : Int32)
  fun get_window_size = SDL_GetWindowSize(w : Window, x : Int32*, y : Int32*)
  fun set_window_fullscreen = SDL_SetWindowFullscreen(w : Window, flags : UInt32) : Int32
  fun set_window_resizable = SDL_SetWindowResizable(w : Window, resizable : Int32)
  fun get_window_flags = SDL_GetWindowFlags(w : Window) : UInt32
  fun show_window = SDL_ShowWindow(w : Window)
  fun hide_window = SDL_HideWindow(w : Window)
  fun gl_get_drawable_size = SDL_GL_GetDrawableSize(w : Window, x : Int32*, y : Int32*)

  fun gl_set_attribute = SDL_GL_SetAttribute(attr : Int32, value : Int32) : Int32
  fun gl_create_context = SDL_GL_CreateContext(w : Window) : GLContext
  fun gl_delete_context = SDL_GL_DeleteContext(ctx : GLContext)
  fun gl_make_current = SDL_GL_MakeCurrent(w : Window, ctx : GLContext) : Int32
  fun gl_swap_window = SDL_GL_SwapWindow(w : Window)
  fun gl_set_swap_interval = SDL_GL_SetSwapInterval(interval : Int32) : Int32
  fun gl_get_proc_address = SDL_GL_GetProcAddress(proc : UInt8*) : Void*

  fun poll_event = SDL_PollEvent(event : Event*) : Int32
  fun get_keyboard_state = SDL_GetKeyboardState(numkeys : Int32*) : UInt8*
  fun get_mod_state = SDL_GetModState : Int32
  fun get_mouse_state = SDL_GetMouseState(x : Int32*, y : Int32*) : UInt32
  fun set_relative_mouse_mode = SDL_SetRelativeMouseMode(enabled : Int32) : Int32
  fun show_cursor = SDL_ShowCursor(toggle : Int32) : Int32
  fun warp_mouse_in_window = SDL_WarpMouseInWindow(w : Window, x : Int32, y : Int32)
  fun start_text_input = SDL_StartTextInput
  fun stop_text_input = SDL_StopTextInput
  fun get_scancode_name = SDL_GetScancodeName(scancode : Int32) : UInt8*

  fun get_ticks = SDL_GetTicks : UInt32
  fun get_performance_counter = SDL_GetPerformanceCounter : UInt64
  fun get_performance_frequency = SDL_GetPerformanceFrequency : UInt64
  fun delay = SDL_Delay(ms : UInt32)

  fun get_clipboard_text = SDL_GetClipboardText : UInt8*
  fun set_clipboard_text = SDL_SetClipboardText(text : UInt8*) : Int32

  fun num_joysticks = SDL_NumJoysticks : Int32
  fun is_game_controller = SDL_IsGameController(index : Int32) : Int32
  fun game_controller_open = SDL_GameControllerOpen(index : Int32) : GameController
  fun game_controller_close = SDL_GameControllerClose(gc : GameController)
  fun game_controller_name = SDL_GameControllerName(gc : GameController) : UInt8*
  fun game_controller_get_joystick = SDL_GameControllerGetJoystick(gc : GameController) : Joystick
  fun joystick_instance_id = SDL_JoystickInstanceID(j : Joystick) : JoystickID
  fun game_controller_rumble = SDL_GameControllerRumble(gc : GameController, low : UInt16, high : UInt16, ms : UInt32) : Int32
  fun game_controller_get_axis = SDL_GameControllerGetAxis(gc : GameController, axis : Int32) : Int16
  fun game_controller_get_button = SDL_GameControllerGetButton(gc : GameController, button : Int32) : UInt8
  fun game_controller_add_mappings_from_file = SDL_GameControllerAddMappingsFromRW(rw : Void*, freerw : Int32) : Int32

  fun open_audio_device = SDL_OpenAudioDevice(device : UInt8*, iscapture : Int32, desired : AudioSpec*, obtained : AudioSpec*, allowed_changes : Int32) : AudioDeviceID
  fun close_audio_device = SDL_CloseAudioDevice(dev : AudioDeviceID)
  fun pause_audio_device = SDL_PauseAudioDevice(dev : AudioDeviceID, pause_on : Int32)
  fun queue_audio = SDL_QueueAudio(dev : AudioDeviceID, data : Void*, len : UInt32) : Int32
  fun get_queued_audio_size = SDL_GetQueuedAudioSize(dev : AudioDeviceID) : UInt32
  fun clear_queued_audio = SDL_ClearQueuedAudio(dev : AudioDeviceID)

  fun show_simple_message_box = SDL_ShowSimpleMessageBox(flags : UInt32, title : UInt8*, message : UInt8*, window : Window) : Int32
end
