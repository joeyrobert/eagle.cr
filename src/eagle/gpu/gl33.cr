require "../lib/gl"

module Eagle
  module GPU
    # OpenGL 3.3 core backend. Uses the WebGL2-compatible subset only.
    class GL33 < Device
      private record Geom, vao : UInt32, vbo : UInt32, ebo : UInt32, layout : VertexLayout
      @geoms = {} of UInt32 => Geom
      @next_geom = 1_u32
      @current_program = 0_u32
      @bound_geom = 0_u32
      @max_texture_size = 0
      @info = ""
      @default_fbo_size = {0, 0}
      @bound_target : RenderTargetHandle? = nil

      def initialize(&loader : String -> Void*)
        missing = GL.load_all { |name| loader.call(name) }
        unless missing.empty?
          Eagle.log.warn { "GL functions not available: #{missing.join(", ")}" }
        end
        raise Error.new("Could not load core OpenGL functions") unless GL.loaded?
        mts = 0_i32
        GL.get_integerv(GL::MAX_TEXTURE_SIZE, pointerof(mts))
        @max_texture_size = mts
        @info = "#{GL.string(GL::RENDERER)} / OpenGL #{GL.string(GL::VERSION)} / GLSL #{GL.string(GL::SHADING_LANGUAGE_VERSION)}"
        Eagle.log.info { "GPU: #{@info}" }
        GL.enable(GL::BLEND)
        GL.blend_func_separate(GL::SRC_ALPHA, GL::ONE_MINUS_SRC_ALPHA, GL::ONE, GL::ONE_MINUS_SRC_ALPHA)
        GL.pixel_storei(GL::UNPACK_ALIGNMENT, 1)
        GL.pixel_storei(GL::PACK_ALIGNMENT, 1)
        GL.enable(GL::PROGRAM_POINT_SIZE)
        {% if flag?(:darwin) %}
          # macOS core profile requires a VAO to be bound for any draw.
        {% end %}
      end

      def name : String; @info; end
      def max_texture_size : Int32; @max_texture_size; end

      def shader_prelude(stage : Symbol) : String
        "#version 330 core\n#define EAGLE_GL33 1\n"
      end

      def default_framebuffer_size=(size : {Int32, Int32})
        @default_fbo_size = size
      end

      # --- state -------------------------------------------------------------
      def clear(color : Color? = nil, depth : Bool = false, stencil : Bool = false) : Nil
        mask = 0_u32
        if c = color
          GL.clear_color(c.r, c.g, c.b, c.a)
          mask |= GL::COLOR_BUFFER_BIT
        end
        if depth
          GL.depth_mask(GL::TRUE_)
          mask |= GL::DEPTH_BUFFER_BIT
        end
        mask |= GL::STENCIL_BUFFER_BIT if stencil
        GL.clear(mask) if mask != 0
      end

      def viewport(x : Int32, y : Int32, w : Int32, h : Int32) : Nil
        GL.viewport(x, y, w, h)
      end

      def scissor(rect : Rect?, framebuffer_height : Int32) : Nil
        if r = rect
          GL.enable(GL::SCISSOR_TEST)
          # GL scissor origin is bottom-left.
          GL.scissor(r.x.to_i, framebuffer_height - (r.y + r.h).to_i, r.w.to_i, r.h.to_i)
        else
          GL.disable(GL::SCISSOR_TEST)
        end
      end

      def blend_mode(mode : BlendMode) : Nil
        case mode
        in BlendMode::None
          GL.disable(GL::BLEND)
        in BlendMode::Alpha
          GL.enable(GL::BLEND)
          GL.blend_equation(GL::FUNC_ADD)
          GL.blend_func_separate(GL::SRC_ALPHA, GL::ONE_MINUS_SRC_ALPHA, GL::ONE, GL::ONE_MINUS_SRC_ALPHA)
        in BlendMode::Additive
          GL.enable(GL::BLEND)
          GL.blend_equation(GL::FUNC_ADD)
          GL.blend_func_separate(GL::SRC_ALPHA, GL::ONE, GL::ZERO, GL::ONE)
        in BlendMode::Multiply
          GL.enable(GL::BLEND)
          GL.blend_equation(GL::FUNC_ADD)
          GL.blend_func_separate(GL::DST_COLOR, GL::ONE_MINUS_SRC_ALPHA, GL::ZERO, GL::ONE)
        in BlendMode::Screen
          GL.enable(GL::BLEND)
          GL.blend_equation(GL::FUNC_ADD)
          GL.blend_func_separate(GL::ONE, GL::ONE_MINUS_SRC_COLOR, GL::ZERO, GL::ONE)
        end
      end

      def depth_test(enabled : Bool, write : Bool = true, func : DepthFunc = DepthFunc::Less) : Nil
        if enabled
          GL.enable(GL::DEPTH_TEST)
          GL.depth_mask(write ? GL::TRUE_ : GL::FALSE_)
          GL.depth_func(case func
            in DepthFunc::Less then GL::LESS
            in DepthFunc::LessEqual then GL::LEQUAL
            in DepthFunc::Always then GL::ALWAYS
            in DepthFunc::Equal then GL::EQUAL
            in DepthFunc::Greater then GL::GREATER
            in DepthFunc::GreaterEqual then GL::GEQUAL
            in DepthFunc::Never then GL::NEVER
            in DepthFunc::NotEqual then GL::NOTEQUAL
            end)
        else
          GL.disable(GL::DEPTH_TEST)
          GL.depth_mask(GL::TRUE_)
        end
      end

      def cull(mode : CullMode) : Nil
        case mode
        in CullMode::None then GL.disable(GL::CULL_FACE)
        in CullMode::Back
          GL.enable(GL::CULL_FACE); GL.cull_face(GL::BACK)
        in CullMode::Front
          GL.enable(GL::CULL_FACE); GL.cull_face(GL::FRONT)
        end
      end

      def wireframe(enabled : Bool) : Nil
        GL.polygon_mode(GL::FRONT_AND_BACK, enabled ? GL::LINE : GL::FILL)
      end

      def front_face_ccw(ccw : Bool) : Nil
        GL.front_face(ccw ? GL::CCW : GL::CW)
      end

      def check_errors(where : String = "") : Nil
        GL.check!(where)
      end

      # --- programs ----------------------------------------------------------
      def create_program(vertex : String, fragment : String, attribs : Array(String)) : UInt32
        vs = compile(GL::VERTEX_SHADER, shader_prelude(:vertex) + vertex, "vertex")
        fs = compile(GL::FRAGMENT_SHADER, shader_prelude(:fragment) + fragment, "fragment")
        prog = GL.create_program
        GL.attach_shader(prog, vs)
        GL.attach_shader(prog, fs)
        attribs.each_with_index { |name, i| GL.bind_attrib_location(prog, i.to_u32, name.to_unsafe) }
        GL.link_program(prog)
        ok = 0_i32
        GL.get_programiv(prog, GL::LINK_STATUS, pointerof(ok))
        GL.delete_shader(vs)
        GL.delete_shader(fs)
        if ok == 0
          log = program_log(prog)
          GL.delete_program(prog)
          raise ShaderError.new("Program link failed:\n#{log}")
        end
        prog
      end

      private def compile(kind : UInt32, src : String, label : String) : UInt32
        sh = GL.create_shader(kind)
        ptr = src.to_unsafe
        len = src.bytesize
        GL.shader_source(sh, 1, pointerof(ptr), pointerof(len))
        GL.compile_shader(sh)
        ok = 0_i32
        GL.get_shaderiv(sh, GL::COMPILE_STATUS, pointerof(ok))
        if ok == 0
          loglen = 0_i32
          GL.get_shaderiv(sh, GL::INFO_LOG_LENGTH, pointerof(loglen))
          buf = Bytes.new(Math.max(loglen, 1))
          written = 0_i32
          GL.get_shader_info_log(sh, buf.size, pointerof(written), buf.to_unsafe)
          msg = String.new(buf[0, Math.max(written, 0)])
          GL.delete_shader(sh)
          raise ShaderError.new("#{label} shader compile failed:\n#{msg}\n--- source ---\n#{numbered(src)}")
        end
        sh
      end

      private def numbered(src : String) : String
        String.build { |io| src.each_line.with_index(1) { |l, i| io << i.to_s.rjust(3) << ": " << l << "\n" } }
      end

      private def program_log(prog : UInt32) : String
        loglen = 0_i32
        GL.get_programiv(prog, GL::INFO_LOG_LENGTH, pointerof(loglen))
        buf = Bytes.new(Math.max(loglen, 1))
        written = 0_i32
        GL.get_program_info_log(prog, buf.size, pointerof(written), buf.to_unsafe)
        String.new(buf[0, Math.max(written, 0)])
      end

      def delete_program(id : UInt32) : Nil
        GL.delete_program(id)
        @current_program = 0_u32 if @current_program == id
      end

      def use_program(id : UInt32) : Nil
        return if @current_program == id
        GL.use_program(id)
        @current_program = id
      end

      def uniform_location(program : UInt32, name : String) : Int32
        GL.get_uniform_location(program, name.to_unsafe)
      end

      def set_uniform(location : Int32, value : UniformValue) : Nil
        return if location < 0
        case value
        in Int32 then GL.uniform1i(location, value)
        in Bool then GL.uniform1i(location, value ? 1 : 0)
        in Float32 then GL.uniform1f(location, value)
        in Vec2 then GL.uniform2f(location, value.x, value.y)
        in Vec3 then GL.uniform3f(location, value.x, value.y, value.z)
        in Vec4 then GL.uniform4f(location, value.x, value.y, value.z, value.w)
        in Color then GL.uniform4f(location, value.r, value.g, value.b, value.a)
        in Mat3 then GL.uniform_matrix3fv(location, 1, GL::FALSE_, value.to_unsafe)
        in Mat4 then GL.uniform_matrix4fv(location, 1, GL::FALSE_, value.to_unsafe)
        in Array(Float32) then GL.uniform1fv(location, value.size, value.to_unsafe)
        in Array(Int32) then GL.uniform1iv(location, value.size, value.to_unsafe)
        in Array(Vec2) then GL.uniform2fv(location, value.size, value.to_unsafe.as(Float32*))
        in Array(Vec3) then GL.uniform3fv(location, value.size, value.to_unsafe.as(Float32*))
        in Array(Vec4) then GL.uniform4fv(location, value.size, value.to_unsafe.as(Float32*))
        in Array(Mat4) then GL.uniform_matrix4fv(location, value.size, GL::FALSE_, value.to_unsafe.as(Float32*))
        end
      end

      # --- textures ----------------------------------------------------------
      private def gl_format(f : PixelFormat) : {UInt32, UInt32, UInt32}
        case f
        in PixelFormat::RGBA8 then {GL::RGBA8, GL::RGBA, GL::UNSIGNED_BYTE}
        in PixelFormat::RGB8 then {GL::RGB8, GL::RGB, GL::UNSIGNED_BYTE}
        in PixelFormat::R8 then {GL::R8, GL::RED, GL::UNSIGNED_BYTE}
        in PixelFormat::RG8 then {GL::RG8, GL::RG, GL::UNSIGNED_BYTE}
        in PixelFormat::RGBA16F then {GL::RGBA16F, GL::RGBA, GL::FLOAT}
        in PixelFormat::Depth24 then {GL::DEPTH_COMPONENT24, GL::DEPTH_COMPONENT, GL::UNSIGNED_INT}
        in PixelFormat::Depth24Stencil8 then {GL::DEPTH24_STENCIL8, GL::DEPTH_STENCIL, GL::UNSIGNED_INT_24_8}
        end
      end

      def create_texture(w : Int32, h : Int32, format : PixelFormat, data : Bytes?, filter : Filter, wrap : Wrap, mipmaps : Bool) : UInt32
        id = 0_u32
        GL.gen_textures(1, pointerof(id))
        GL.bind_texture(GL::TEXTURE_2D, id)
        internal, fmt, type = gl_format(format)
        ptr = data ? data.to_unsafe.as(Void*) : Pointer(Void).null
        GL.tex_image2d(GL::TEXTURE_2D, 0, internal.to_i, w, h, 0, fmt, type, ptr)
        apply_params(filter, wrap, mipmaps && !data.nil?)
        id
      end

      private def apply_params(filter : Filter, wrap : Wrap, mipmaps : Bool)
        mag = filter == Filter::Nearest ? GL::NEAREST : GL::LINEAR
        min = if mipmaps
                filter == Filter::Nearest ? GL::NEAREST_MIPMAP_LINEAR : GL::LINEAR_MIPMAP_LINEAR
              else
                mag
              end
        GL.tex_parameteri(GL::TEXTURE_2D, GL::TEXTURE_MAG_FILTER, mag.to_i)
        GL.tex_parameteri(GL::TEXTURE_2D, GL::TEXTURE_MIN_FILTER, min.to_i)
        w = case wrap
            in Wrap::Clamp then GL::CLAMP_TO_EDGE
            in Wrap::Repeat then GL::REPEAT
            in Wrap::Mirror then GL::MIRRORED_REPEAT
            end
        GL.tex_parameteri(GL::TEXTURE_2D, GL::TEXTURE_WRAP_S, w.to_i)
        GL.tex_parameteri(GL::TEXTURE_2D, GL::TEXTURE_WRAP_T, w.to_i)
        GL.generate_mipmap(GL::TEXTURE_2D) if mipmaps
      end

      def update_texture(id : UInt32, x : Int32, y : Int32, w : Int32, h : Int32, format : PixelFormat, data : Bytes) : Nil
        GL.bind_texture(GL::TEXTURE_2D, id)
        _, fmt, type = gl_format(format)
        GL.tex_sub_image2d(GL::TEXTURE_2D, 0, x, y, w, h, fmt, type, data.to_unsafe.as(Void*))
      end

      def texture_params(id : UInt32, filter : Filter, wrap : Wrap, mipmaps : Bool) : Nil
        GL.bind_texture(GL::TEXTURE_2D, id)
        apply_params(filter, wrap, mipmaps)
      end

      def delete_texture(id : UInt32) : Nil
        GL.delete_textures(1, pointerof(id))
      end

      def bind_texture(unit : Int32, id : UInt32) : Nil
        GL.active_texture(GL::TEXTURE0 + unit)
        GL.bind_texture(GL::TEXTURE_2D, id)
      end

      # --- geometry ----------------------------------------------------------
      def create_geometry(layout : VertexLayout) : UInt32
        vao = 0_u32
        GL.gen_vertex_arrays(1, pointerof(vao))
        vbo = 0_u32
        GL.gen_buffers(1, pointerof(vbo))
        ebo = 0_u32
        GL.gen_buffers(1, pointerof(ebo))
        GL.bind_vertex_array(vao)
        GL.bind_buffer(GL::ARRAY_BUFFER, vbo)
        GL.bind_buffer(GL::ELEMENT_ARRAY_BUFFER, ebo)
        layout.attribs.each_with_index do |a, i|
          GL.enable_vertex_attrib_array(i.to_u32)
          case a.type
          in AttribType::Float32
            GL.vertex_attrib_pointer(i.to_u32, a.components, GL::FLOAT, GL::FALSE_, layout.stride, Pointer(Void).new(a.offset.to_u64))
          in AttribType::UInt8Normalized
            GL.vertex_attrib_pointer(i.to_u32, a.components, GL::UNSIGNED_BYTE, GL::TRUE_, layout.stride, Pointer(Void).new(a.offset.to_u64))
          end
        end
        GL.bind_vertex_array(0_u32)
        id = @next_geom
        @next_geom += 1
        @geoms[id] = Geom.new(vao, vbo, ebo, layout)
        id
      end

      private def gl_usage(u : Usage) : UInt32
        case u
        in Usage::Static then GL::STATIC_DRAW
        in Usage::Dynamic then GL::DYNAMIC_DRAW
        in Usage::Stream then GL::STREAM_DRAW
        end
      end

      def upload_vertices(geom : UInt32, data : Slice(Float32), usage : Usage) : Nil
        g = @geoms[geom]
        GL.bind_vertex_array(g.vao)
        GL.bind_buffer(GL::ARRAY_BUFFER, g.vbo)
        GL.buffer_data(GL::ARRAY_BUFFER, (data.size * 4).to_i64, data.to_unsafe.as(Void*), gl_usage(usage))
        @bound_geom = geom
      end

      def upload_vertices(geom : UInt32, data : Bytes, usage : Usage) : Nil
        g = @geoms[geom]
        GL.bind_vertex_array(g.vao)
        GL.bind_buffer(GL::ARRAY_BUFFER, g.vbo)
        GL.buffer_data(GL::ARRAY_BUFFER, data.size.to_i64, data.to_unsafe.as(Void*), gl_usage(usage))
        @bound_geom = geom
      end

      def upload_indices(geom : UInt32, data : Slice(UInt32), usage : Usage) : Nil
        g = @geoms[geom]
        GL.bind_vertex_array(g.vao)
        GL.bind_buffer(GL::ELEMENT_ARRAY_BUFFER, g.ebo)
        GL.buffer_data(GL::ELEMENT_ARRAY_BUFFER, (data.size * 4).to_i64, data.to_unsafe.as(Void*), gl_usage(usage))
        @bound_geom = geom
      end

      private def gl_prim(p : Primitive) : UInt32
        case p
        in Primitive::Triangles then GL::TRIANGLES
        in Primitive::TriangleStrip then GL::TRIANGLE_STRIP
        in Primitive::TriangleFan then GL::TRIANGLE_FAN
        in Primitive::Lines then GL::LINES
        in Primitive::LineStrip then GL::LINE_STRIP
        in Primitive::LineLoop then GL::LINE_LOOP
        in Primitive::Points then GL::POINTS
        end
      end

      def draw(geom : UInt32, primitive : Primitive, count : Int32, offset : Int32 = 0, indexed : Bool = false, instances : Int32 = 1) : Nil
        return if count <= 0
        g = @geoms[geom]
        GL.bind_vertex_array(g.vao)
        @bound_geom = geom
        if indexed
          ptr = Pointer(Void).new((offset * 4).to_u64)
          if instances > 1
            GL.draw_elements_instanced(gl_prim(primitive), count, GL::UNSIGNED_INT, ptr, instances)
          else
            GL.draw_elements(gl_prim(primitive), count, GL::UNSIGNED_INT, ptr)
          end
        else
          if instances > 1
            GL.draw_arrays_instanced(gl_prim(primitive), offset, count, instances)
          else
            GL.draw_arrays(gl_prim(primitive), offset, count)
          end
        end
      end

      def delete_geometry(geom : UInt32) : Nil
        if g = @geoms.delete(geom)
          vao = g.vao; vbo = g.vbo; ebo = g.ebo
          GL.delete_vertex_arrays(1, pointerof(vao))
          GL.delete_buffers(1, pointerof(vbo))
          GL.delete_buffers(1, pointerof(ebo))
        end
      end

      # --- render targets ----------------------------------------------------
      def create_render_target(w : Int32, h : Int32, depth : Bool, filter : Filter) : RenderTargetHandle
        color = create_texture(w, h, PixelFormat::RGBA8, nil, filter, Wrap::Clamp, false)
        fbo = 0_u32
        GL.gen_framebuffers(1, pointerof(fbo))
        GL.bind_framebuffer(GL::FRAMEBUFFER, fbo)
        GL.framebuffer_texture2d(GL::FRAMEBUFFER, GL::COLOR_ATTACHMENT0, GL::TEXTURE_2D, color, 0)
        depth_id = 0_u32
        if depth
          rb = 0_u32
          GL.gen_renderbuffers(1, pointerof(rb))
          GL.bind_renderbuffer(GL::RENDERBUFFER, rb)
          GL.renderbuffer_storage(GL::RENDERBUFFER, GL::DEPTH24_STENCIL8, w, h)
          GL.framebuffer_renderbuffer(GL::FRAMEBUFFER, GL::DEPTH_STENCIL_ATTACHMENT, GL::RENDERBUFFER, rb)
          depth_id = rb
        end
        status = GL.check_framebuffer_status(GL::FRAMEBUFFER)
        GL.bind_framebuffer(GL::FRAMEBUFFER, 0_u32)
        raise Error.new("Framebuffer incomplete: 0x#{status.to_s(16)}") if status != GL::FRAMEBUFFER_COMPLETE
        RenderTargetHandle.new(fbo, color, depth_id, w, h)
      end

      def create_depth_target(w : Int32, h : Int32) : RenderTargetHandle
        depth = create_texture(w, h, PixelFormat::Depth24, nil, Filter::Nearest, Wrap::Clamp, false)
        GL.bind_texture(GL::TEXTURE_2D, depth)
        GL.tex_parameteri(GL::TEXTURE_2D, GL::TEXTURE_COMPARE_MODE, GL::NONE.to_i)
        fbo = 0_u32
        GL.gen_framebuffers(1, pointerof(fbo))
        GL.bind_framebuffer(GL::FRAMEBUFFER, fbo)
        GL.framebuffer_texture2d(GL::FRAMEBUFFER, GL::DEPTH_ATTACHMENT, GL::TEXTURE_2D, depth, 0)
        none = GL::NONE
        GL.draw_buffers(1, pointerof(none))
        GL.read_buffer(GL::NONE)
        status = GL.check_framebuffer_status(GL::FRAMEBUFFER)
        GL.bind_framebuffer(GL::FRAMEBUFFER, 0_u32)
        raise Error.new("Depth framebuffer incomplete: 0x#{status.to_s(16)}") if status != GL::FRAMEBUFFER_COMPLETE
        RenderTargetHandle.new(fbo, 0_u32, depth, w, h, true)
      end

      def current_target : RenderTargetHandle?; @bound_target; end

      def bind_render_target(target : RenderTargetHandle?) : Nil
        @bound_target = target
        if t = target
          GL.bind_framebuffer(GL::FRAMEBUFFER, t.fbo)
          GL.viewport(0, 0, t.width, t.height)
        else
          GL.bind_framebuffer(GL::FRAMEBUFFER, 0_u32)
          GL.viewport(0, 0, @default_fbo_size[0], @default_fbo_size[1])
        end
      end

      def delete_render_target(target : RenderTargetHandle) : Nil
        fbo = target.fbo
        GL.delete_framebuffers(1, pointerof(fbo))
        delete_texture(target.color) if target.color != 0
        if target.depth != 0
          d = target.depth
          target.depth_texture? ? delete_texture(d) : GL.delete_renderbuffers(1, pointerof(d))
        end
      end

      # Returns RGBA8 rows top-to-bottom. Render targets are stored top-row-first
      # (Eagle renders into them with a flipped projection) so only the default
      # framebuffer needs flipping.
      def read_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Bytes
        buf = Bytes.new(w * h * 4)
        if t = @bound_target
          GL.read_pixels(x, y, w, h, GL::RGBA, GL::UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
          return buf
        end
        fb_h = @default_fbo_size[1]
        GL.read_pixels(x, fb_h - y - h, w, h, GL::RGBA, GL::UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
        # flip vertically
        row = w * 4
        tmp = Bytes.new(row)
        (h // 2).times do |r|
          a = buf[r * row, row]; b = buf[(h - 1 - r) * row, row]
          tmp.copy_from(a); a.copy_from(b); b.copy_from(tmp)
        end
        buf
      end
    end
  end
end
