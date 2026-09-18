module Eagle
  # A GPU program for custom visual effects: glows, color grading, waves, outlines and more.
  #
  # The easiest way in is `Shader.effect`, where you write a single GLSL function that
  # decides the color of each pixel, in the style of LÖVE. Eagle supplies the vertex shader
  # and the uniforms `u_time`, `u_resolution` and `u_texture`.
  #
  # ```
  # wave = Shader.effect(<<-GLSL)
  #   vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen) {
  #     uv.x += sin(uv.y * 20.0 + u_time * 3.0) * 0.01;
  #     return texture(tex, uv) * color;
  #   }
  #   GLSL
  #
  # canvas = Canvas.new(320, 180)
  # g.with_shader(wave) { g.draw(canvas, Window.rect) }
  #
  # tint = Shader.effect("uniform vec3 u_tint; vec4 effect(vec4 c, sampler2D t, vec2 uv, vec2 s) { return texture(t, uv) * c * vec4(u_tint, 1.0); }")
  # tint["u_tint"] = Vec3.new(1, 0.5, 0.5)
  # ```
  #
  # Write GLSL in the common subset of desktop GLSL 3.30 and WebGL2 GLSL ES 3.00, so the same
  # shader runs natively and in the browser. Eagle adds the `#version` line. For full control,
  # pass both stages to `Shader.new` or load a file with `#vertex` and `#fragment` sections.
  class Shader
    # The GPU program handle.
    getter id : UInt32
    # The vertex shader source as compiled, without Eagle's version prelude.
    getter vertex_source : String
    # The fragment shader source as compiled.
    getter fragment_source : String
    @locations = {} of String => Int32
    @cache = {} of Int32 => GPU::UniformValue

    # Vertex attribute names, in order, for Eagle's 2D batches.
    ATTRIBS_2D = %w(a_position a_uv a_color)
    ATTRIBS_3D = %w(a_position a_normal a_uv a_color a_tangent)

    # Compiles and links a program from vertex and fragment sources. Raises `ShaderError` with
    # the driver's log if either fails.
    def initialize(@vertex_source : String, @fragment_source : String, attribs : Array(String) = ATTRIBS_2D)
      @id = GPU.device.create_program(@vertex_source, @fragment_source, attribs)
    end

    # Loads a shader file through the asset cache. See `parse` for the file format.
    def self.load(path : String) : Shader
      Assets.shader(path)
    end

    # Builds a shader from one source string with `#vertex` and `#fragment` section markers,
    # or an `#effect` section for the `effect` style.
    def self.parse(source : String, attribs : Array(String) = ATTRIBS_2D) : Shader
      sections = {} of String => String
      current = "common"
      buf = {} of String => Array(String)
      source.each_line do |line|
        if m = line.strip.match(/^#(vertex|fragment|effect|common)\b/)
          current = m[1]
        else
          (buf[current] ||= [] of String) << line
        end
      end
      common = buf["common"]?.try(&.join("\n")) || ""
      if fx = buf["effect"]?
        return effect(common + "\n" + fx.join("\n"))
      end
      vs = buf["vertex"]?.try(&.join("\n")) || raise ShaderError.new("Shader has no #vertex section")
      fs = buf["fragment"]?.try(&.join("\n")) || raise ShaderError.new("Shader has no #fragment section")
      new(common + "\n" + vs, common + "\n" + fs, attribs)
    end

    # Builds a 2D pixel effect from a function with this signature:
    #
    # ```glsl
    # vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen_coords)
    # ```
    #
    # *color* is the draw color, *tex* the texture being drawn, *uv* its texture coordinate and
    # *screen_coords* the pixel position. Declare your own uniforms above the function.
    def self.effect(body : String) : Shader
      new(DEFAULT_2D_VERTEX, EFFECT_PRELUDE + body + EFFECT_MAIN)
    end

    DEFAULT_2D_VERTEX = <<-GLSL
      in vec2 a_position;
      in vec2 a_uv;
      in vec4 a_color;
      uniform mat4 u_projection;
      out vec2 v_uv;
      out vec4 v_color;
      void main() {
        v_uv = a_uv;
        v_color = a_color;
        gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
      }
      GLSL

    DEFAULT_2D_FRAGMENT = <<-GLSL
      precision mediump float;
      uniform sampler2D u_texture;
      in vec2 v_uv;
      in vec4 v_color;
      out vec4 frag_color;
      void main() {
        frag_color = texture(u_texture, v_uv) * v_color;
      }
      GLSL

    # :nodoc:
    EFFECT_PRELUDE = <<-GLSL
      precision mediump float;
      uniform sampler2D u_texture;
      uniform float u_time;
      uniform vec2 u_resolution;
      in vec2 v_uv;
      in vec4 v_color;
      out vec4 frag_color;

      GLSL

    # :nodoc:
    EFFECT_MAIN = <<-GLSL

      void main() {
        frag_color = effect(v_color, u_texture, v_uv, gl_FragCoord.xy);
      }
      GLSL

    # The built-in shader Eagle uses for 2D drawing.
    def self.default_2d : Shader
      new(DEFAULT_2D_VERTEX, DEFAULT_2D_FRAGMENT)
    end

    # Makes this the active program, for custom rendering code.
    def use : Nil
      GPU.device.use_program(@id)
    end

    # The uniform location for *name*, or -1 if the shader doesn't use it.
    def location(name : String) : Int32
      @locations[name] ||= GPU.device.uniform_location(@id, name)
    end

    # True when the shader declares and uses the uniform *name*.
    def has_uniform?(name : String) : Bool
      location(name) >= 0
    end

    # Sets a uniform. Accepts numbers, `Vec2`, `Vec3`, `Vec4`, `Color` and `Mat4`.
    # Setting a uniform the shader doesn't use is a no-op.
    def []=(name : String, value : GPU::UniformValue) : Nil
      set(name, value)
    end

    # Same as `[]=`.
    def set(name : String, value : GPU::UniformValue) : Nil
      loc = location(name)
      return if loc < 0
      use
      # Skip redundant scalar/vector uploads.
      case value
      when Int32, Float32, Bool, Vec2, Vec3, Vec4, Color
        return if @cache[loc]? == value
        @cache[loc] = value
      end
      GPU.device.set_uniform(loc, value)
    end

    # Sets a float uniform from a `Float64`.
    def set(name : String, value : Float64); set(name, value.to_f32); end
    # Sets an int uniform.
    def set(name : String, value : Int); set(name, value.to_i32); end
    # Sets a float uniform from a `Float64`.
    def []=(name : String, value : Float64); set(name, value.to_f32); end
    # Sets an int uniform.
    def []=(name : String, value : Int); set(name, value.to_i32); end

    # Binds *texture* to sampler unit *unit* and points the uniform *name* at it, for
    # shaders that read more than one texture.
    def set_texture(name : String, texture : Texture, unit : Int32 = 0) : Nil
      texture.bind(unit)
      set(name, unit)
    end

    # Frees the GPU program.
    def dispose : Nil
      return if @id == 0
      GPU.device.delete_program(@id) if GPU.ready?
      @id = 0_u32
    end
  end
end
