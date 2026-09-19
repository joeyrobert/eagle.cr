module Eagle
  # An image on the GPU that you can draw. Sprites, tile sets, fonts and canvases all use textures.
  #
  # Load one from a file with `Texture.load`, which caches it, or build one from an `Image`
  # you generated in code. Draw it with `Graphics#draw` or give it to a `Sprite2D`.
  #
  # ```
  # player = Texture.load("res://player.png")
  # tiles = Texture.load("res://tiles.png", filter: GPU::Filter::Nearest)
  #
  # sheet = Texture.new(Image.checkerboard(128, 32, 16))
  # frames = sheet.frames(32, 32) # four 32x32 regions, left to right
  # dot = Texture.new(Image.circle(8, Color::WHITE))
  # ```
  #
  # For pixel art, set `Texture.default_filter = GPU::Filter::Nearest` before loading so
  # pixels stay crisp when scaled.
  class Texture
    # Width in pixels.
    getter width : Int32
    # Height in pixels.
    getter height : Int32
    # The GPU texture handle, for custom rendering code.
    getter id : UInt32
    # Pixel format on the GPU.
    getter format : GPU::PixelFormat
    # How the texture is sampled when scaled: `Nearest` for crisp pixels, `Linear` for smooth.
    getter filter : GPU::Filter
    # What happens outside 0..1 texture coordinates: `Clamp`, `Repeat` or `Mirror`.
    getter wrap : GPU::Wrap
    # True when mipmaps were generated. They reduce shimmering on textures drawn much smaller than their size.
    getter? mipmaps : Bool
    # The file the texture came from, if any.
    getter path : String? = nil
    # Center of a solid white texel in this texture, if it has one. Shapes sample it so they can
    # share a batch with text or sprites from this texture instead of switching to `Texture.white`.
    property white_uv : Vec2? = nil

    @@white : Texture? = nil
    @@default_filter = GPU::Filter::Linear

    # Filter used by new textures and canvases when none is given.
    def self.default_filter : GPU::Filter; @@default_filter; end
    # Sets the filter for new textures. Use `GPU::Filter::Nearest` for pixel-art games.
    def self.default_filter=(f : GPU::Filter); @@default_filter = f; end

    # Uploads an `Image` to the GPU.
    def initialize(image : Image, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false, @path = nil)
      @width = image.width; @height = image.height
      @format = GPU::PixelFormat::RGBA8
      @filter = filter; @wrap = wrap; @mipmaps = mipmaps
      @id = GPU.device.create_texture(@width, @height, @format, image.pixels, filter, wrap, mipmaps)
    end

    # Creates a blank texture of the given size, optionally filled with raw pixel *data*.
    def initialize(@width : Int32, @height : Int32, @format : GPU::PixelFormat = GPU::PixelFormat::RGBA8, data : Bytes? = nil, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false)
      @filter = filter; @wrap = wrap; @mipmaps = mipmaps
      @id = GPU.device.create_texture(@width, @height, @format, data, filter, wrap, mipmaps)
    end

    # Wrap an existing GPU texture id (used by Canvas).
    protected def initialize(@id : UInt32, @width : Int32, @height : Int32, @format : GPU::PixelFormat, @filter : GPU::Filter, @wrap : GPU::Wrap)
      @mipmaps = false
    end

    # Wraps an existing GPU texture id. `Canvas` uses this.
    def self.wrap_handle(id : UInt32, w : Int32, h : Int32, filter : GPU::Filter = GPU::Filter::Linear) : Texture
      new(id, w, h, GPU::PixelFormat::RGBA8, filter, GPU::Wrap::Clamp)
    end

    # Loads a texture from a file through the asset cache, so loading the same path twice returns
    # the same texture. `res://` paths resolve against the assets folder.
    def self.load(path : String, filter : GPU::Filter = @@default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false) : Texture
      Assets.texture(path, filter, wrap, mipmaps)
    end

    # A texture filled with a single color.
    def self.from_color(width : Int32, height : Int32, color : Color = Color::WHITE) : Texture
      new(Image.new(width, height, color))
    end

    # A shared 1x1 white texture. Shapes use it so they can batch with sprites.
    def self.white : Texture
      @@white ||= from_color(1, 1)
    end

    # :nodoc:
    def self.reset_shared; @@white = nil; end

    # `(width, height)`.
    def size : Vec2; Vec2.new(@width, @height); end
    # The whole texture as a `Rect`.
    def rect : Rect; Rect.new(0, 0, @width, @height); end
    # The center point, handy as a pivot: `g.draw(tex, pos, origin: tex.center)`.
    def center : Vec2; size / 2; end

    # Changes the sampling filter.
    def filter=(f : GPU::Filter)
      @filter = f
      GPU.device.texture_params(@id, f, @wrap, @mipmaps)
    end

    # Changes the wrap mode.
    def wrap=(w : GPU::Wrap)
      @wrap = w
      GPU.device.texture_params(@id, @filter, w, @mipmaps)
    end

    # Replaces pixels starting at *x*, *y* with *image*. Use it for textures that change,
    # like a minimap or a paint canvas.
    def update(image : Image, x : Int32 = 0, y : Int32 = 0) : Nil
      GPU.device.update_texture(@id, x, y, image.width, image.height, GPU::PixelFormat::RGBA8, image.pixels)
    end

    # Replaces a rectangle of pixels with raw RGBA bytes.
    def update(data : Bytes, x : Int32, y : Int32, w : Int32, h : Int32) : Nil
      GPU.device.update_texture(@id, x, y, w, h, @format, data)
    end

    # A sub-rectangle of this texture that can be drawn like a texture. Use it for sprite sheets and atlases.
    #
    # ```
    # sheet = Texture.new(Image.checkerboard(64, 64, 16))
    # icon = sheet.region(16, 0, 16, 16)
    # g.draw(icon, 10, 10, sx: 4)
    # ```
    def region(x : Number, y : Number, w : Number, h : Number) : TextureRegion
      TextureRegion.new(self, Rect.new(x, y, w, h))
    end

    # A sub-rectangle given as a `Rect`.
    def region(r : Rect) : TextureRegion; TextureRegion.new(self, r); end

    # Cuts the texture into a grid of equal frames, left to right and top to bottom.
    # Pass *count* to stop early when the last row isn't full. Feed the result to `AnimatedSprite2D`.
    def frames(frame_w : Int32, frame_h : Int32, count : Int32? = nil) : Array(TextureRegion)
      cols = @width // frame_w; rows = @height // frame_h
      total = count || cols * rows
      Array(TextureRegion).new(total) { |i| region((i % cols) * frame_w, (i // cols) * frame_h, frame_w, frame_h) }
    end

    # Binds the texture to a sampler unit, for custom rendering code.
    def bind(unit : Int32 = 0) : Nil; GPU.device.bind_texture(unit, @id); end

    # Frees the GPU texture. Textures loaded through `Assets` are freed by `Assets.clear` instead.
    def dispose : Nil
      return if @id == 0
      GPU.device.delete_texture(@id) if GPU.ready?
      @id = 0_u32
    end

    # :nodoc:
    def finalize
      # GPU objects must be freed from the main thread with a live context;
      # rely on explicit dispose / Assets.clear instead.
    end
  end

  # A rectangle inside a texture, drawable anywhere a texture is. Create one with
  # `Texture#region` or `Texture#frames`.
  struct TextureRegion
    # The texture this region is cut from.
    getter texture : Texture
    # The region in pixels.
    getter rect : Rect
    # Left texture coordinate.
    getter u0 : Float32
    # Top texture coordinate.
    getter v0 : Float32
    # Right texture coordinate.
    getter u1 : Float32
    # Bottom texture coordinate.
    getter v1 : Float32

    # Creates a region of *texture* covering *rect*, in pixels.
    def initialize(@texture, @rect)
      @u0 = @rect.x / @texture.width
      @v0 = @rect.y / @texture.height
      @u1 = (@rect.x + @rect.w) / @texture.width
      @v1 = (@rect.y + @rect.h) / @texture.height
    end

    # Width in pixels.
    def width : Float32; @rect.w; end
    # Height in pixels.
    def height : Float32; @rect.h; end
    # `(width, height)`.
    def size : Vec2; @rect.size; end
    # The same region mirrored horizontally, for sprites that face left and right.
    def flipped_x : TextureRegion; r = dup; r.set_uv(@u1, @v0, @u0, @v1); r; end
    # The same region mirrored vertically.
    def flipped_y : TextureRegion; r = dup; r.set_uv(@u0, @v1, @u1, @v0); r; end

    protected def set_uv(@u0, @v0, @u1, @v1); end
  end

  # Anything `Graphics#draw` can draw directly: a whole texture or a region of one.
  alias Drawable = Texture | TextureRegion
end
