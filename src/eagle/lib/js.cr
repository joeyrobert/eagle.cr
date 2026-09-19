# JavaScript imports for the web backend (implemented in web/eagle.js).
{% if flag?(:wasm32) %}
  @[Link(wasm_import_module: "eagle")]
  # :nodoc:
  lib LibJS
    fun js_init(width : Int32, height : Int32, title : Pointer(UInt8), title_len : Int32)
    fun js_log(level : Int32, ptr : Pointer(UInt8), len : Int32)
    fun js_now : Float64
    fun js_window_size(ptr : Pointer(Int32))
    fun js_set_title(ptr : Pointer(UInt8), len : Int32)
    fun js_poll_event(ptr : Pointer(Float32)) : Int32
    fun js_text_input(enabled : Int32)
    fun js_text_area(x : Float32, y : Float32, w : Float32, h : Float32, text : Pointer(UInt8), len : Int32, caret : Int32)
    fun js_clipboard_read(ptr : Pointer(UInt8), cap : Int32) : Int32
    fun js_clipboard_write(ptr : Pointer(UInt8), len : Int32)
    fun js_take_string(ptr : Pointer(UInt8), cap : Int32) : Int32
    fun js_relative_mouse(enabled : Int32)
    fun js_cursor(visible : Int32)
    fun js_audio_open(rate : Int32, frames : Int32) : Int32
    fun js_audio_queue(ptr : Pointer(Float32), count : Int32)
    fun js_audio_queued : Int32
    fun js_gamepad_rumble(id : Int32, low : Float32, high : Float32, ms : Int32)
    fun gl_get_string(name : UInt32, buf : Pointer(UInt8), len : Int32) : Int32
  end
{% end %}
