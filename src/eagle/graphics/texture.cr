module Eagle
  # A GPU texture. Create from an `Image`, a file, or a size.
  class Texture
    getter width : Int32
    getter height : Int32
    getter id : UInt32
    getter format : GPU::PixelFormat
    getter filter : GPU::Filter
    getter wrap : GPU::Wrap
    getter? mipmaps : Bool
    getter path : String? = nil

    @@white : Texture? = nil
    @@default_filter = GPU::Filter::Linear

    # Default filter for new textures (`Nearest` for pixel art games).
    def self.default_filter : GPU::Filter; @@default_filter; end
    def self.default_filter=(f : GPU::Filter); @@default_filter = f; end

    def initialize(image : Image, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false, @path = nil)
      @width = image.width; @height = image.height
      @format = GPU::PixelFormat::RGBA8
      @filter = filter; @wrap = wrap; @mipmaps = mipmaps
      @id = GPU.device.create_texture(@width, @height, @format, image.pixels, filter, wrap, mipmaps)
    end

    def initialize(@width : Int32, @height : Int32, @format : GPU::PixelFormat = GPU::PixelFormat::RGBA8, data : Bytes? = nil, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false)
      @filter = filter; @wrap = wrap; @mipmaps = mipmaps
      @id = GPU.device.create_texture(@width, @height, @format, data, filter, wrap, mipmaps)
    end

    # Wrap an existing GPU texture id (used by Canvas).
    protected def initialize(@id : UInt32, @width : Int32, @height : Int32, @format : GPU::PixelFormat, @filter : GPU::Filter, @wrap : GPU::Wrap)
      @mipmaps = false
    end

    def self.wrap_handle(id : UInt32, w : Int32, h : Int32, filter : GPU::Filter = GPU::Filter::Linear) : Texture
      new(id, w, h, GPU::PixelFormat::RGBA8, filter, GPU::Wrap::Clamp)
    end

    # Load via the asset cache (`res://` paths allowed).
    def self.load(path : String, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false) : Texture
      Assets.texture(path, filter, wrap, mipmaps)
    end

    def self.from_color(width : Int32, height : Int32, color : Color = Color::WHITE) : Texture
      new(Image.new(width, height, color))
    end

    # Shared 1x1 white texture used for untextured shapes.
    def self.white : Texture
      @@white ||= from_color(1, 1)
    end

    # :nodoc:
    def self.reset_shared; @@white = nil; end

    def size : Vec2; Vec2.new(@width, @height); end
    def rect : Rect; Rect.new(0, 0, @width, @height); end
    def center : Vec2; size / 2; end

    def filter=(f : GPU::Filter)
      @filter = f
      GPU.device.texture_params(@id, f, @wrap, @mipmaps)
    end

    def wrap=(w : GPU::Wrap)
      @wrap = w
      GPU.device.texture_params(@id, @filter, w, @mipmaps)
    end

    def update(image : Image, x : Int32 = 0, y : Int32 = 0) : Nil
      GPU.device.update_texture(@id, x, y, image.width, image.height, GPU::PixelFormat::RGBA8, image.pixels)
    end

    def update(data : Bytes, x : Int32, y : Int32, w : Int32, h : Int32) : Nil
      GPU.device.update_texture(@id, x, y, w, h, @format, data)
    end

    # A sub-rectangle of this texture, drawable like a texture (sprite sheets).
    def region(x : Number, y : Number, w : Number, h : Number) : TextureRegion
      TextureRegion.new(self, Rect.new(x, y, w, h))
    end

    def region(r : Rect) : TextureRegion; TextureRegion.new(self, r); end

    # Split into a grid of equally sized frames, row-major.
    def frames(frame_w : Int32, frame_h : Int32, count : Int32? = nil) : Array(TextureRegion)
      cols = @width // frame_w; rows = @height // frame_h
      total = count || cols * rows
      Array(TextureRegion).new(total) { |i| region((i % cols) * frame_w, (i // cols) * frame_h, frame_w, frame_h) }
    end

    def bind(unit : Int32 = 0) : Nil; GPU.device.bind_texture(unit, @id); end

    def dispose : Nil
      return if @id == 0
      GPU.device.delete_texture(@id) if GPU.ready?
      @id = 0_u32
    end

    def finalize
      # GPU objects must be freed from the main thread with a live context;
      # rely on explicit dispose / Assets.clear instead.
    end
  end

  # A rectangle inside a texture with precomputed UVs.
  struct TextureRegion
    getter texture : Texture
    getter rect : Rect
    getter u0 : Float32
    getter v0 : Float32
    getter u1 : Float32
    getter v1 : Float32

    def initialize(@texture, @rect)
      @u0 = @rect.x / @texture.width
      @v0 = @rect.y / @texture.height
      @u1 = (@rect.x + @rect.w) / @texture.width
      @v1 = (@rect.y + @rect.h) / @texture.height
    end

    def width : Float32; @rect.w; end
    def height : Float32; @rect.h; end
    def size : Vec2; @rect.size; end
    def flipped_x : TextureRegion; r = dup; r.set_uv(@u1, @v0, @u0, @v1); r; end
    def flipped_y : TextureRegion; r = dup; r.set_uv(@u0, @v1, @u1, @v0); r; end

    protected def set_uv(@u0, @v0, @u1, @v1); end
  end

  alias Drawable = Texture | TextureRegion
end
