module Eagle
  # The layer between Eagle and the graphics API. Everything draws through `GPU.device`,
  # which is OpenGL 3.3 on desktop and WebGL2 in the browser.
  #
  # Game code rarely touches this module directly. You meet its enums as arguments
  # elsewhere: `BlendMode` for `Graphics#blend=` and particles, `Filter` and `Wrap` for
  # textures, and `UniformValue` for shader uniforms. Shaders are written in the common
  # subset of GLSL 3.30 and GLSL ES 3.00, and each backend adds its own prelude.
  module GPU
    # How newly drawn pixels combine with what's already there.
    #
    # * `Alpha` is normal transparency, and the default.
    # * `Additive` adds light, for fire, lasers, glows and sparks.
    # * `Multiply` darkens, for shadows and tinted glass.
    # * `Screen` lightens more softly than `Additive`.
    # * `None` overwrites, ignoring alpha.
    enum BlendMode
      # Overwrite pixels, ignoring alpha.
      None
      # Normal transparency.
      Alpha         # premultiplied-friendly: src*1 + dst*(1-srcA) when `premultiplied`, else srcA/(1-srcA)
      # Add color, which brightens. For glows and fire.
      Additive
      # Multiply color, which darkens. For shadows and tinted glass.
      Multiply
      # Lighten softly.
      Screen
    end

    # Which triangle faces the GPU skips.
    enum CullMode
      None
      Back
      Front
    end

    # The depth comparison used by 3D rendering.
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

    # How vertices are assembled into shapes.
    enum Primitive
      Triangles
      TriangleStrip
      TriangleFan
      Lines
      LineStrip
      LineLoop
      Points
    end

    # Texture storage formats.
    enum PixelFormat
      RGBA8
      RGB8
      R8
      RG8
      RGBA16F
      Depth24
      Depth24Stencil8

      # Bytes per pixel in this format.
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

      # Number of color channels.
      def channels : Int32
        case self
        in RGBA8, RGBA16F then 4
        in RGB8 then 3
        in RG8 then 2
        in R8, Depth24, Depth24Stencil8 then 1
        end
      end
    end

    # How textures are sampled when drawn larger or smaller than their size.
    # `Nearest` keeps hard pixel edges for pixel art, and `Linear` blends smoothly.
    enum Filter
      # Crisp pixels when scaled. Best for pixel art.
      Nearest
      # Smooth blending between pixels.
      Linear
    end

    # What a texture shows outside its edges. `Repeat` tiles it, which `Graphics#draw_tiled` and
    # floor textures need. `Mirror` tiles with every other copy flipped, and `Clamp` stretches the edge pixels.
    enum Wrap
      # Stretch the edge pixels.
      Clamp
      # Tile the texture.
      Repeat
      # Tile with every other copy flipped.
      Mirror
    end

    # How often a buffer's contents change, as a hint to the driver.
    enum Usage
      Static
      Dynamic
      Stream
    end

    # Data type of a vertex attribute.
    enum AttribType
      Float32
      UInt8Normalized
    end

    # One attribute in an interleaved vertex buffer.
    struct VertexAttrib
      # Attribute name as used in the shader.
      getter name : String
      # Number of values, such as 3 for a position.
      getter components : Int32
      # Data type of each value.
      getter type : AttribType
      # Byte offset within a vertex.
      getter offset : Int32
      # Creates an attribute description.
      def initialize(@name, @components, @type, @offset); end

      # Size of the attribute in bytes.
      def byte_size : Int32
        case @type
        in AttribType::Float32 then 4 * @components
        in AttribType::UInt8Normalized then @components
        end
      end
    end

    # Describes the attributes in an interleaved vertex buffer, for custom geometry.
    #
    # ```
    # layout = GPU::VertexLayout.new.float("a_position", 3).float("a_uv", 2).color("a_color")
    # ```
    class VertexLayout
      # The attributes in order.
      getter attribs = [] of VertexAttrib
      # Bytes per vertex.
      getter stride = 0

      # Adds a float attribute with *components* values. Returns self.
      def float(name : String, components : Int32) : self
        @attribs << VertexAttrib.new(name, components, AttribType::Float32, @stride)
        @stride += 4 * components
        self
      end

      # Adds a packed RGBA color attribute, normalized to 0..1 in the shader. Returns self.
      def color(name : String) : self
        @attribs << VertexAttrib.new(name, 4, AttribType::UInt8Normalized, @stride)
        @stride += 4
        self
      end

      # Floats per vertex.
      def float_count : Int32; @stride // 4; end
    end

    # GPU handles for an off-screen render target. `Canvas` wraps one.
    struct RenderTargetHandle
      # Framebuffer object id.
      getter fbo : UInt32
      # Color texture id.
      getter color : UInt32
      # Depth buffer or texture id.
      getter depth : UInt32
      # Width in pixels.
      getter width : Int32
      # Height in pixels.
      getter height : Int32
      # True when `depth` is a sampleable depth texture (shadow maps).
      getter? depth_texture : Bool
      # Wraps render-target handles.
      def initialize(@fbo, @color, @depth, @width, @height, @depth_texture = false); end
    end

    # Every type a shader uniform can be set to.
    alias UniformValue = Int32 | Float32 | Vec2 | Vec3 | Vec4 | Color | Mat3 | Mat4 | Bool | Array(Float32) | Array(Vec3) | Array(Mat4) | Array(Int32) | Array(Vec4) | Array(Vec2)

    # The interface every graphics backend implements. Custom rendering code can call it
    # through `GPU.device`, but prefer `Graphics`, `Shader`, `Texture` and `Mesh`, which
    # handle state and batching for you.
    abstract class Device
      # Human-readable backend and driver name, as logged at startup.
      abstract def name : String
      # The `#version` line and precision statements added to shaders for *stage*.
      abstract def shader_prelude(stage : Symbol) : String
      # Largest texture width or height the GPU supports.
      abstract def max_texture_size : Int32

      # --- frame state ---
      # Clears the current target's color, depth and stencil as requested.
      abstract def clear(color : Color? = nil, depth : Bool = false, stencil : Bool = false) : Nil
      # Sets the drawing area in pixels.
      abstract def viewport(x : Int32, y : Int32, w : Int32, h : Int32) : Nil
      # Clips drawing to *rect*, or turns clipping off with `nil`.
      abstract def scissor(rect : Rect?, framebuffer_height : Int32) : Nil
      # Sets the blend mode.
      abstract def blend_mode(mode : BlendMode) : Nil
      # Configures depth testing and depth writes.
      abstract def depth_test(enabled : Bool, write : Bool = true, func : DepthFunc = DepthFunc::Less) : Nil
      # Sets which faces are culled.
      abstract def cull(mode : CullMode) : Nil
      # Turns wireframe rendering on or off where supported.
      abstract def wireframe(enabled : Bool) : Nil
      # True on backends without wireframe fill modes, such as WebGL. Meshes then draw their edges as lines.
      def emulate_wireframe? : Bool; false; end
      # True while wireframe rendering is on.
      def wireframe? : Bool; false; end
      # Sets whether counter-clockwise triangles face forward.
      abstract def front_face_ccw(ccw : Bool) : Nil
      # Logs any pending GPU errors, tagged with *where*. Enable with `EAGLE_GL_DEBUG=1`.
      abstract def check_errors(where : String = "") : Nil

      # --- programs ---
      # Compiles and links a shader program. Raises `ShaderError` on failure.
      abstract def create_program(vertex : String, fragment : String, attribs : Array(String)) : UInt32
      # Frees a shader program.
      abstract def delete_program(id : UInt32) : Nil
      # Makes a program current.
      abstract def use_program(id : UInt32) : Nil
      # Looks up a uniform, returning -1 when the program doesn't use it.
      abstract def uniform_location(program : UInt32, name : String) : Int32
      # Sets a uniform on the current program.
      abstract def set_uniform(location : Int32, value : UniformValue) : Nil

      # --- textures ---
      # Creates a texture, optionally with initial pixels.
      abstract def create_texture(w : Int32, h : Int32, format : PixelFormat, data : Bytes?, filter : Filter, wrap : Wrap, mipmaps : Bool) : UInt32
      # Replaces part of a texture.
      abstract def update_texture(id : UInt32, x : Int32, y : Int32, w : Int32, h : Int32, format : PixelFormat, data : Bytes) : Nil
      # Changes filtering, wrapping and mipmaps.
      abstract def texture_params(id : UInt32, filter : Filter, wrap : Wrap, mipmaps : Bool) : Nil
      # Frees a texture.
      abstract def delete_texture(id : UInt32) : Nil
      # Binds a texture to a sampler unit.
      abstract def bind_texture(unit : Int32, id : UInt32) : Nil

      # --- geometry (vertex + index buffers with a layout) ---
      # Creates vertex and index buffers for a layout.
      abstract def create_geometry(layout : VertexLayout) : UInt32
      # Uploads vertex data as floats.
      abstract def upload_vertices(geom : UInt32, data : Slice(Float32), usage : Usage) : Nil
      # Uploads vertex data as raw bytes.
      abstract def upload_vertices(geom : UInt32, data : Bytes, usage : Usage) : Nil
      # Uploads triangle indices.
      abstract def upload_indices(geom : UInt32, data : Slice(UInt32), usage : Usage) : Nil
      # Draws geometry.
      abstract def draw(geom : UInt32, primitive : Primitive, count : Int32, offset : Int32 = 0, indexed : Bool = false, instances : Int32 = 1) : Nil
      # Frees geometry buffers.
      abstract def delete_geometry(geom : UInt32) : Nil

      # --- render targets ---
      # Creates an off-screen color target, optionally with depth.
      abstract def create_render_target(w : Int32, h : Int32, depth : Bool, filter : Filter) : RenderTargetHandle
      # Creates a depth-only target whose depth can be sampled, for shadow maps.
      abstract def create_depth_target(w : Int32, h : Int32) : RenderTargetHandle
      # Draws into *target*, or the screen with `nil`.
      abstract def bind_render_target(target : RenderTargetHandle?) : Nil
      # The target being drawn into, or `nil` for the screen.
      abstract def current_target : RenderTargetHandle?
      # Frees a render target.
      abstract def delete_render_target(target : RenderTargetHandle) : Nil
      # Reads RGBA pixels back from the current target.
      abstract def read_pixels(x : Int32, y : Int32, w : Int32, h : Int32) : Bytes
    end

    @@device : Device? = nil

    # The active device. Raises if called before the engine has started, which usually means
    # a texture or shader was created too early. Create them in `App#load` or `Node#ready`.
    def self.device : Device
      @@device || raise Error.new("No GPU device yet. Create textures, shaders and other GPU resources after the engine starts: in App#load, Node#ready, or by passing your App *class* to Eagle.run (e.g. `Eagle.run(MyGame)`) so it is constructed after init.")
    end

    # Sets the active device. The engine does this.
    def self.device=(d : Device?)
      @@device = d
    end

    # True once a device exists.
    def self.ready? : Bool
      !@@device.nil?
    end
  end
end
