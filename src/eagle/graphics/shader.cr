module Eagle
  # A GPU shader program. Write GLSL in the 330-core / 300-es common subset;
  # Eagle adds the version prelude.
  #
  # Three ways to create one:
  #   Shader.new(vertex_src, fragment_src)
  #   Shader.load("res://fx.glsl")            # one file with `#vertex` / `#fragment` sections
  #   Shader.effect("vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen) { ... }")
  class Shader
    getter id : UInt32
    getter vertex_source : String
    getter fragment_source : String
    @locations = {} of String => Int32
    @cache = {} of Int32 => GPU::UniformValue

    # Attribute order used for every Eagle-generated layout.
    ATTRIBS_2D = %w(a_position a_uv a_color)
    ATTRIBS_3D = %w(a_position a_normal a_uv a_color a_tangent)

    def initialize(@vertex_source : String, @fragment_source : String, attribs : Array(String) = ATTRIBS_2D)
      @id = GPU.device.create_program(@vertex_source, @fragment_source, attribs)
    end

    def self.load(path : String) : Shader
      Assets.shader(path)
    end

    # Parses a single-file shader with `#vertex` / `#fragment` section markers.
    # Also supports a `#effect` section (LÖVE-style, see `.effect`).
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

    # LÖVE-style pixel effect for 2D drawing. Provide:
    #   vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen_coords)
    # Uniforms available: u_time, u_resolution, u_texture. Add your own.
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

    EFFECT_PRELUDE = <<-GLSL
      precision mediump float;
      uniform sampler2D u_texture;
      uniform float u_time;
      uniform vec2 u_resolution;
      in vec2 v_uv;
      in vec4 v_color;
      out vec4 frag_color;

      GLSL

    EFFECT_MAIN = <<-GLSL

      void main() {
        frag_color = effect(v_color, u_texture, v_uv, gl_FragCoord.xy);
      }
      GLSL

    def self.default_2d : Shader
      new(DEFAULT_2D_VERTEX, DEFAULT_2D_FRAGMENT)
    end

    def use : Nil
      GPU.device.use_program(@id)
    end

    def location(name : String) : Int32
      @locations[name] ||= GPU.device.uniform_location(@id, name)
    end

    def has_uniform?(name : String) : Bool
      location(name) >= 0
    end

    # Set a uniform. The program is bound as a side effect.
    def []=(name : String, value : GPU::UniformValue) : Nil
      set(name, value)
    end

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

    def set(name : String, value : Float64); set(name, value.to_f32); end
    def set(name : String, value : Int); set(name, value.to_i32); end
    def []=(name : String, value : Float64); set(name, value.to_f32); end
    def []=(name : String, value : Int); set(name, value.to_i32); end

    # Bind a texture to a unit and point the sampler at it.
    def set_texture(name : String, texture : Texture, unit : Int32 = 0) : Nil
      texture.bind(unit)
      set(name, unit)
    end

    def dispose : Nil
      return if @id == 0
      GPU.device.delete_program(@id) if GPU.ready?
      @id = 0_u32
    end
  end
end
