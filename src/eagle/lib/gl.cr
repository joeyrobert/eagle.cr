# OpenGL 3.3 core / GLES 3.0 / WebGL2 common-subset loader.
# Functions are loaded through a proc-address getter (SDL_GL_GetProcAddress on
# desktop) so no platform GL headers or loader libraries are needed.
module Eagle
  module GL
    alias Enum = UInt32
    alias Bitfield = UInt32
    alias Sizei = Int32
    alias Int = Int32
    alias Uint = UInt32
    alias Float = Float32
    alias Boolean = UInt8
    alias Sizeiptr = Int64
    alias Intptr = Int64

    # --- constants ---------------------------------------------------------
    DEPTH_BUFFER_BIT   = 0x00000100_u32
    STENCIL_BUFFER_BIT = 0x00000400_u32
    COLOR_BUFFER_BIT   = 0x00004000_u32

    FALSE_ = 0_u8
    TRUE_  = 1_u8

    POINTS         = 0x0000_u32
    LINES          = 0x0001_u32
    LINE_LOOP      = 0x0002_u32
    LINE_STRIP     = 0x0003_u32
    TRIANGLES      = 0x0004_u32
    TRIANGLE_STRIP = 0x0005_u32
    TRIANGLE_FAN   = 0x0006_u32

    NEVER    = 0x0200_u32
    LESS     = 0x0201_u32
    EQUAL    = 0x0202_u32
    LEQUAL   = 0x0203_u32
    GREATER  = 0x0204_u32
    NOTEQUAL = 0x0205_u32
    GEQUAL   = 0x0206_u32
    ALWAYS   = 0x0207_u32

    ZERO                = 0_u32
    ONE                 = 1_u32
    SRC_COLOR           = 0x0300_u32
    ONE_MINUS_SRC_COLOR = 0x0301_u32
    SRC_ALPHA           = 0x0302_u32
    ONE_MINUS_SRC_ALPHA = 0x0303_u32
    DST_ALPHA           = 0x0304_u32
    ONE_MINUS_DST_ALPHA = 0x0305_u32
    DST_COLOR           = 0x0306_u32
    ONE_MINUS_DST_COLOR = 0x0307_u32

    FUNC_ADD              = 0x8006_u32
    FUNC_SUBTRACT         = 0x800A_u32
    FUNC_REVERSE_SUBTRACT = 0x800B_u32
    MIN                   = 0x8007_u32
    MAX                   = 0x8008_u32

    FRONT          = 0x0404_u32
    BACK           = 0x0405_u32
    FRONT_AND_BACK = 0x0408_u32
    CW             = 0x0900_u32
    CCW            = 0x0901_u32

    CULL_FACE    = 0x0B44_u32
    DEPTH_TEST   = 0x0B71_u32
    STENCIL_TEST = 0x0B90_u32
    BLEND        = 0x0BE2_u32
    SCISSOR_TEST = 0x0C11_u32
    MULTISAMPLE  = 0x809D_u32
    FRAMEBUFFER_SRGB = 0x8DB9_u32
    PROGRAM_POINT_SIZE = 0x8642_u32
    LINE_SMOOTH  = 0x0B20_u32

    NO_ERROR          = 0_u32
    INVALID_ENUM      = 0x0500_u32
    INVALID_VALUE     = 0x0501_u32
    INVALID_OPERATION = 0x0502_u32
    OUT_OF_MEMORY     = 0x0505_u32
    INVALID_FRAMEBUFFER_OPERATION = 0x0506_u32

    VENDOR                   = 0x1F00_u32
    RENDERER                 = 0x1F01_u32
    VERSION                  = 0x1F02_u32
    SHADING_LANGUAGE_VERSION = 0x8B8C_u32
    MAX_TEXTURE_SIZE         = 0x0D33_u32
    MAX_TEXTURE_IMAGE_UNITS  = 0x8872_u32
    VIEWPORT                 = 0x0BA2_u32

    UNSIGNED_BYTE  = 0x1401_u32
    BYTE           = 0x1400_u32
    UNSIGNED_SHORT = 0x1403_u32
    SHORT          = 0x1402_u32
    UNSIGNED_INT   = 0x1405_u32
    INT            = 0x1404_u32
    FLOAT          = 0x1406_u32
    UNSIGNED_INT_24_8 = 0x84FA_u32

    RED             = 0x1903_u32
    RG              = 0x8227_u32
    RGB             = 0x1907_u32
    RGBA            = 0x1908_u32
    R8              = 0x8229_u32
    RG8             = 0x822B_u32
    RGB8            = 0x8051_u32
    RGBA8           = 0x8058_u32
    SRGB8_ALPHA8    = 0x8C43_u32
    RGBA16F         = 0x881A_u32
    RGBA32F         = 0x8814_u32
    DEPTH_COMPONENT = 0x1902_u32
    DEPTH_COMPONENT16 = 0x81A5_u32
    DEPTH_COMPONENT24 = 0x81A6_u32
    DEPTH24_STENCIL8  = 0x88F0_u32
    DEPTH_STENCIL     = 0x84F9_u32

    TEXTURE_2D       = 0x0DE1_u32
    TEXTURE_CUBE_MAP = 0x8513_u32
    TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515_u32
    TEXTURE0         = 0x84C0_u32
    TEXTURE_MAG_FILTER = 0x2800_u32
    TEXTURE_MIN_FILTER = 0x2801_u32
    TEXTURE_WRAP_S     = 0x2802_u32
    TEXTURE_WRAP_T     = 0x2803_u32
    TEXTURE_WRAP_R     = 0x8072_u32
    TEXTURE_COMPARE_MODE = 0x884C_u32
    TEXTURE_COMPARE_FUNC = 0x884D_u32
    COMPARE_REF_TO_TEXTURE = 0x884E_u32
    NEAREST = 0x2600_u32
    LINEAR  = 0x2601_u32
    NEAREST_MIPMAP_NEAREST = 0x2700_u32
    LINEAR_MIPMAP_NEAREST  = 0x2701_u32
    NEAREST_MIPMAP_LINEAR  = 0x2702_u32
    LINEAR_MIPMAP_LINEAR   = 0x2703_u32
    REPEAT          = 0x2901_u32
    CLAMP_TO_EDGE   = 0x812F_u32
    MIRRORED_REPEAT = 0x8370_u32
    UNPACK_ALIGNMENT = 0x0CF5_u32
    PACK_ALIGNMENT   = 0x0D05_u32

    ARRAY_BUFFER         = 0x8892_u32
    ELEMENT_ARRAY_BUFFER = 0x8893_u32
    STREAM_DRAW  = 0x88E0_u32
    STATIC_DRAW  = 0x88E4_u32
    DYNAMIC_DRAW = 0x88E8_u32

    FRAGMENT_SHADER = 0x8B30_u32
    VERTEX_SHADER   = 0x8B31_u32
    COMPILE_STATUS  = 0x8B81_u32
    LINK_STATUS     = 0x8B82_u32
    INFO_LOG_LENGTH = 0x8B84_u32

    FRAMEBUFFER          = 0x8D40_u32
    READ_FRAMEBUFFER     = 0x8CA8_u32
    DRAW_FRAMEBUFFER     = 0x8CA9_u32
    RENDERBUFFER         = 0x8D41_u32
    COLOR_ATTACHMENT0    = 0x8CE0_u32
    DEPTH_ATTACHMENT     = 0x8D00_u32
    STENCIL_ATTACHMENT   = 0x8D20_u32
    DEPTH_STENCIL_ATTACHMENT = 0x821A_u32
    FRAMEBUFFER_COMPLETE = 0x8CD5_u32
    NONE                 = 0_u32

    # Desktop-only (not in WebGL2): wireframe mode
    LINE = 0x1B01_u32
    FILL = 0x1B02_u32

    # --- function table ----------------------------------------------------
    {% begin %}
      {%
        funcs = {
          get_error:                  {"glGetError", [] of Nil, UInt32},
          get_string:                 {"glGetString", [UInt32], Pointer(UInt8)},
          get_integerv:               {"glGetIntegerv", [UInt32, Pointer(Int32)], Nil},
          enable:                     {"glEnable", [UInt32], Nil},
          disable:                    {"glDisable", [UInt32], Nil},
          clear:                      {"glClear", [UInt32], Nil},
          clear_color:                {"glClearColor", [Float32, Float32, Float32, Float32], Nil},
          clear_depth:                {"glClearDepth", [Float64], Nil},
          clear_stencil:              {"glClearStencil", [Int32], Nil},
          viewport:                   {"glViewport", [Int32, Int32, Int32, Int32], Nil},
          scissor:                    {"glScissor", [Int32, Int32, Int32, Int32], Nil},
          blend_func:                 {"glBlendFunc", [UInt32, UInt32], Nil},
          blend_func_separate:        {"glBlendFuncSeparate", [UInt32, UInt32, UInt32, UInt32], Nil},
          blend_equation:             {"glBlendEquation", [UInt32], Nil},
          depth_func:                 {"glDepthFunc", [UInt32], Nil},
          depth_mask:                 {"glDepthMask", [UInt8], Nil},
          color_mask:                 {"glColorMask", [UInt8, UInt8, UInt8, UInt8], Nil},
          cull_face:                  {"glCullFace", [UInt32], Nil},
          front_face:                 {"glFrontFace", [UInt32], Nil},
          line_width:                 {"glLineWidth", [Float32], Nil},
          polygon_mode:               {"glPolygonMode", [UInt32, UInt32], Nil},
          stencil_func:               {"glStencilFunc", [UInt32, Int32, UInt32], Nil},
          stencil_op:                 {"glStencilOp", [UInt32, UInt32, UInt32], Nil},
          stencil_mask:               {"glStencilMask", [UInt32], Nil},
          flush:                      {"glFlush", [] of Nil, Nil},
          finish:                     {"glFinish", [] of Nil, Nil},
          pixel_storei:               {"glPixelStorei", [UInt32, Int32], Nil},
          read_pixels:                {"glReadPixels", [Int32, Int32, Int32, Int32, UInt32, UInt32, Pointer(Void)], Nil},

          gen_buffers:                {"glGenBuffers", [Int32, Pointer(UInt32)], Nil},
          delete_buffers:             {"glDeleteBuffers", [Int32, Pointer(UInt32)], Nil},
          bind_buffer:                {"glBindBuffer", [UInt32, UInt32], Nil},
          buffer_data:                {"glBufferData", [UInt32, Int64, Pointer(Void), UInt32], Nil},
          buffer_sub_data:            {"glBufferSubData", [UInt32, Int64, Int64, Pointer(Void)], Nil},

          gen_vertex_arrays:          {"glGenVertexArrays", [Int32, Pointer(UInt32)], Nil},
          delete_vertex_arrays:       {"glDeleteVertexArrays", [Int32, Pointer(UInt32)], Nil},
          bind_vertex_array:          {"glBindVertexArray", [UInt32], Nil},
          enable_vertex_attrib_array: {"glEnableVertexAttribArray", [UInt32], Nil},
          disable_vertex_attrib_array: {"glDisableVertexAttribArray", [UInt32], Nil},
          vertex_attrib_pointer:      {"glVertexAttribPointer", [UInt32, Int32, UInt32, UInt8, Int32, Pointer(Void)], Nil},
          vertex_attrib_divisor:      {"glVertexAttribDivisor", [UInt32, UInt32], Nil},

          create_shader:              {"glCreateShader", [UInt32], UInt32},
          shader_source:              {"glShaderSource", [UInt32, Int32, Pointer(Pointer(UInt8)), Pointer(Int32)], Nil},
          compile_shader:             {"glCompileShader", [UInt32], Nil},
          get_shaderiv:               {"glGetShaderiv", [UInt32, UInt32, Pointer(Int32)], Nil},
          get_shader_info_log:        {"glGetShaderInfoLog", [UInt32, Int32, Pointer(Int32), Pointer(UInt8)], Nil},
          delete_shader:              {"glDeleteShader", [UInt32], Nil},
          create_program:             {"glCreateProgram", [] of Nil, UInt32},
          attach_shader:              {"glAttachShader", [UInt32, UInt32], Nil},
          link_program:               {"glLinkProgram", [UInt32], Nil},
          get_programiv:              {"glGetProgramiv", [UInt32, UInt32, Pointer(Int32)], Nil},
          get_program_info_log:       {"glGetProgramInfoLog", [UInt32, Int32, Pointer(Int32), Pointer(UInt8)], Nil},
          use_program:                {"glUseProgram", [UInt32], Nil},
          delete_program:             {"glDeleteProgram", [UInt32], Nil},
          get_uniform_location:       {"glGetUniformLocation", [UInt32, Pointer(UInt8)], Int32},
          get_attrib_location:        {"glGetAttribLocation", [UInt32, Pointer(UInt8)], Int32},
          bind_attrib_location:       {"glBindAttribLocation", [UInt32, UInt32, Pointer(UInt8)], Nil},
          uniform1i:                  {"glUniform1i", [Int32, Int32], Nil},
          uniform1f:                  {"glUniform1f", [Int32, Float32], Nil},
          uniform2f:                  {"glUniform2f", [Int32, Float32, Float32], Nil},
          uniform3f:                  {"glUniform3f", [Int32, Float32, Float32, Float32], Nil},
          uniform4f:                  {"glUniform4f", [Int32, Float32, Float32, Float32, Float32], Nil},
          uniform1iv:                 {"glUniform1iv", [Int32, Int32, Pointer(Int32)], Nil},
          uniform1fv:                 {"glUniform1fv", [Int32, Int32, Pointer(Float32)], Nil},
          uniform2fv:                 {"glUniform2fv", [Int32, Int32, Pointer(Float32)], Nil},
          uniform3fv:                 {"glUniform3fv", [Int32, Int32, Pointer(Float32)], Nil},
          uniform4fv:                 {"glUniform4fv", [Int32, Int32, Pointer(Float32)], Nil},
          uniform_matrix3fv:          {"glUniformMatrix3fv", [Int32, Int32, UInt8, Pointer(Float32)], Nil},
          uniform_matrix4fv:          {"glUniformMatrix4fv", [Int32, Int32, UInt8, Pointer(Float32)], Nil},

          gen_textures:               {"glGenTextures", [Int32, Pointer(UInt32)], Nil},
          delete_textures:            {"glDeleteTextures", [Int32, Pointer(UInt32)], Nil},
          bind_texture:               {"glBindTexture", [UInt32, UInt32], Nil},
          active_texture:             {"glActiveTexture", [UInt32], Nil},
          tex_image2d:                {"glTexImage2D", [UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, Pointer(Void)], Nil},
          tex_sub_image2d:            {"glTexSubImage2D", [UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, Pointer(Void)], Nil},
          tex_parameteri:             {"glTexParameteri", [UInt32, UInt32, Int32], Nil},
          generate_mipmap:            {"glGenerateMipmap", [UInt32], Nil},

          gen_framebuffers:           {"glGenFramebuffers", [Int32, Pointer(UInt32)], Nil},
          delete_framebuffers:        {"glDeleteFramebuffers", [Int32, Pointer(UInt32)], Nil},
          bind_framebuffer:           {"glBindFramebuffer", [UInt32, UInt32], Nil},
          framebuffer_texture2d:      {"glFramebufferTexture2D", [UInt32, UInt32, UInt32, UInt32, Int32], Nil},
          check_framebuffer_status:   {"glCheckFramebufferStatus", [UInt32], UInt32},
          gen_renderbuffers:          {"glGenRenderbuffers", [Int32, Pointer(UInt32)], Nil},
          delete_renderbuffers:       {"glDeleteRenderbuffers", [Int32, Pointer(UInt32)], Nil},
          bind_renderbuffer:          {"glBindRenderbuffer", [UInt32, UInt32], Nil},
          renderbuffer_storage:       {"glRenderbufferStorage", [UInt32, UInt32, Int32, Int32], Nil},
          framebuffer_renderbuffer:   {"glFramebufferRenderbuffer", [UInt32, UInt32, UInt32, UInt32], Nil},
          blit_framebuffer:           {"glBlitFramebuffer", [Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32], Nil},
          draw_buffers:               {"glDrawBuffers", [Int32, Pointer(UInt32)], Nil},
          read_buffer:                {"glReadBuffer", [UInt32], Nil},

          draw_arrays:                {"glDrawArrays", [UInt32, Int32, Int32], Nil},
          draw_elements:              {"glDrawElements", [UInt32, Int32, UInt32, Pointer(Void)], Nil},
          draw_arrays_instanced:      {"glDrawArraysInstanced", [UInt32, Int32, Int32, Int32], Nil},
          draw_elements_instanced:    {"glDrawElementsInstanced", [UInt32, Int32, UInt32, Pointer(Void), Int32], Nil},
        }
      %}

      {% if flag?(:wasm32) %}
        # Web: every GL entry point is a JavaScript import (see web/eagle.js).
        @[Link(wasm_import_module: "eagle")]
        lib LibJSGL
          {% for name, spec in funcs %}
            {% if name != :get_string %}
              fun gl_{{name}}({{ spec[1].map_with_index { |t, i| "a#{i} : #{t == Int64 ? Int32 : t}".id }.splat }}) : {{ spec[2] == Nil ? Void : spec[2] }}
            {% end %}
          {% end %}
        end

        {% for name, spec in funcs %}
          {% if name != :get_string %}
            @[AlwaysInline]
            def self.{{name}}({{ spec[1].map_with_index { |t, i| "a#{i} : #{t}".id }.splat }})
              LibJSGL.gl_{{name}}({{ spec[1].map_with_index { |t, i| (t == Int64 ? "a#{i}.to_i32" : "a#{i}").id }.splat }})
            end
          {% end %}
        {% end %}

        def self.load_all(&getter : String -> Void*) : Array(String)
          [] of String
        end

        def self.loaded? : Bool
          true
        end
      {% else %}
      {% for name, spec in funcs %}
        {% proc_type = "Proc(#{(spec[1] + [spec[2]]).join(", ").id})".id %}
        @@{{name}} : {{proc_type}}? = nil

        @[AlwaysInline]
        def self.{{name}}(*args)
          fn = @@{{name}}
          raise "OpenGL function {{spec[0].id}} is not loaded (no GL context?)" unless fn
          fn.call(*args)
        end
      {% end %}

      # Loads every entry point via the given getter; returns names that failed.
      def self.load_all(&getter : String -> Pointer(Void)) : Array(String)
        missing = [] of String
        {% for name, spec in funcs %}
          {% proc_type = "Proc(#{(spec[1] + [spec[2]]).join(", ").id})".id %}
          ptr = yield {{spec[0]}}
          if ptr.null?
            missing << {{spec[0]}}
          else
            @@{{name}} = {{proc_type}}.new(ptr, Pointer(Void).null)
          end
        {% end %}
        missing
      end

      def self.loaded? : Bool
        !@@clear.nil?
      end
      {% end %}
    {% end %}

    def self.check!(where = "") : Nil
      err = get_error
      return if err == NO_ERROR
      name = case err
             when INVALID_ENUM then "INVALID_ENUM"
             when INVALID_VALUE then "INVALID_VALUE"
             when INVALID_OPERATION then "INVALID_OPERATION"
             when OUT_OF_MEMORY then "OUT_OF_MEMORY"
             when INVALID_FRAMEBUFFER_OPERATION then "INVALID_FRAMEBUFFER_OPERATION"
             else "0x#{err.to_s(16)}"
             end
      raise Eagle::Error.new("OpenGL error #{name} #{where}")
    end

    def self.string(name : UInt32) : String
      {% if flag?(:wasm32) %}
        buf = Bytes.new(256)
        n = LibJS.gl_get_string(name, buf, buf.size)
        String.new(buf[0, Math.max(n, 0)])
      {% else %}
        p = get_string(name)
        p.null? ? "" : String.new(p)
      {% end %}
    end
  end
end
