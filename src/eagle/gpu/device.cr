module Eagle
  # GPU abstraction. The engine renders only through `GPU::Device`; backends
  # (GL 3.3 core today, WebGL2 later) implement it. All shaders are written in
  # the GLSL 300 es / 330 core common subset and get a backend prelude.
  module GPU
    enum BlendMode
      None
      Alpha         # premultiplied-friendly: src*1 + dst*(1-srcA) when `premultiplied`, else srcA/(1-srcA)
      Additive
      Multiply
      Screen
    end

    enum CullMode
      None
      Back
      Front
    end

    enum DepthFunc
      Less
      LessEqual
      Always
      Equal
      Greater
      GreaterEqual
      Never
      NotEqual
    end

    enum Primitive
      Triangles
      TriangleStrip
      TriangleFan
      Lines
      LineStrip
      LineLoop
      Points
    end

    enum PixelFormat
      RGBA8
      RGB8
      R8
      RG8
      RGBA16F
      Depth24
      Depth24Stencil8

      def bytes_per_pixel : Int32
        case self
        in RGBA8 then 4
        in RGB8 then 3
        in R8 then 1
        in RG8 then 2
        in RGBA16F then 8
        in Depth24 then 4
        in Depth24Stencil8 then 4
        end
      end

      def channels : Int32
        case self
        in RGBA8, RGBA16F then 4
        in RGB8 then 3
        in RG8 then 2
        in R8, Depth24, Depth24Stencil8 then 1
        end
      end
    end

    enum Filter
      Nearest
      Linear
    end

    enum Wrap
      Clamp
      Repeat
      Mirror
    end

    enum Usage
      Static
      Dynamic
      Stream
    end

    enum AttribType
      Float32
      UInt8Normalized
    end

    # Describes one vertex attribute in an interleaved buffer.
    struct VertexAttrib
      getter name : String
      getter components : Int32
      getter type : AttribType
      getter offset : Int32
      def initialize(@name, @components, @type, @offset); end

      def byte_size : Int32
        case @type
        in AttribType::Float32 then 4 * @components
        in AttribType::UInt8Normalized then @components
        end
      end
    end

    # Builder for interleaved vertex layouts.
    #   layout = VertexLayout.new.float("a_position", 3).float("a_uv", 2).color("a_color")
    class VertexLayout
      getter attribs = [] of VertexAttrib
      getter stride = 0

      def float(name : String, components : Int32) : self
        @attribs << VertexAttrib.new(name, components, AttribType::Float32, @stride)
        @stride += 4 * components
        self
      end

      # 4 bytes packed RGBA, normalized to 0..1 in the shader.
      def color(name : String) : self
        @attribs << VertexAttrib.new(name, 4, AttribType::UInt8Normalized, @stride)
        @stride += 4
        self
      end

      def float_count : Int32; @stride // 4; end
    end

    struct RenderTargetHandle
      getter fbo : UInt32
      getter color : UInt32
      getter depth : UInt32
      getter width : Int32
      getter height : Int32
      # True when `depth` is a sampleable depth texture (shadow maps).
      getter? depth_texture : Bool
      def initialize(@fbo, @color, @depth, @width, @height, @depth_texture = false); end
    end

    # Uniform value union.
    alias UniformValue = Int32 | Float32 | Vec2 | Vec3 | Vec4 | Color | Mat3 | Mat4 | Bool | Array(Float32) | Array(Vec3) | Array(Mat4) | Array(Int32) | Array(Vec4) | Array(Vec2)

    abstract class Device
      abstract def name : String
      abstract def shader_prelude(stage : Symbol) : String
      abstract def max_texture_size : Int32

      # --- frame state ---
      abstract def clear(color : Color? = nil, depth : Bool = false, stencil : Bool = false) : Nil
      abstract def viewport(x : Int32, y : Int32, w : Int32, h : Int32) : Nil
      abstract def scissor(rect : Rect?, framebuffer_height : Int32) : Nil
      abstract def blend_mode(mode : BlendMode) : Nil
      abstract def depth_test(enabled : Bool, write : Bool = true, func : DepthFunc = DepthFunc::Less) : Nil
      abstract def cull(mode : CullMode) : Nil
      abstract def wireframe(enabled : Bool) : Nil
      # Winding order considered front-facing (true = counter-clockwise, the default).
      abstract def front_face_ccw(ccw : Bool) : Nil
      abstract def check_errors(where : String = "") : Nil

      # --- programs ---
      abstract def create_program(vertex : String, fragment : String, attribs : Array(String)) : UInt32
      abstract def delete_program(id : UInt32) : Nil
      abstract def use_program(id : UInt32) : Nil
      abstract def uniform_location(program : UInt32, name : String) : Int32
      abstract def set_uniform(location : Int32, value : UniformValue) : Nil

      # --- textures ---
      abstract def create_texture(w : Int32, h : Int32, format : PixelFormat, data : Bytes?, filter : Filter, wrap : Wrap, mipmaps : Bool) : UInt32
      abstract def update_texture(id : UInt32, x : Int32, y : Int32, w : Int32, h : Int32, format : PixelFormat, data : Bytes) : Nil
      abstract def texture_params(id : UInt32, filter : Filter, wrap : Wrap, mipmaps : Bool) : Nil
      abstract def delete_texture(id : UInt32) : Nil
      abstract def bind_texture(unit : Int32, id : UInt32) : Nil

      # --- geometry (vertex + index buffers with a layout) ---
      abstract def create_geometry(layout : VertexLayout) : UInt32
      abstract def upload_vertices(geom : UInt32, data : Slice(Float32), usage : Usage) : Nil
      abstract def upload_vertices(geom : UInt32, data : Bytes, usage : Usage) : Nil
      abstract def upload_indices(geom : UInt32, data : Slice(UInt32), usage : Usage) : Nil
      abstract def draw(geom : UInt32, primitive : Primitive, count : Int32, offset : Int32 = 0, indexed : Bool = false, instances : Int32 = 1) : Nil
      abstract def delete_geometry(geom : UInt32) : Nil

      # --- render targets ---
      abstract def create_render_target(w : Int32, h : Int32, depth : Bool, filter : Filter) : RenderTargetHandle
      # Depth-only target whose depth buffer is a texture (for shadow maps).
      abstract def create_depth_target(w : Int32, h : Int32) : RenderTargetHandle
      abstract def bind_render_target(target : RenderTargetHandle?) : Nil
      abstract def current_target : RenderTargetHandle?
      abstract def delete_render_target(target : RenderTargetHandle) : Nil
      abstract def read_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Bytes
    end

    @@device : Device? = nil

    def self.device : Device
      @@device || raise Error.new("No GPU device yet. Create textures, shaders and other GPU resources after the engine starts: in App#load, Node#ready, or by passing your App *class* to Eagle.run (e.g. `Eagle.run(MyGame)`) so it is constructed after init.")
    end

    def self.device=(d : Device?)
      @@device = d
    end

    def self.ready? : Bool
      !@@device.nil?
    end
  end
end
