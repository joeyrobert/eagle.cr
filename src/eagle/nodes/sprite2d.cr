module Eagle
  # Draws a texture, or part of one, at the node's position. It is the workhorse of 2D games.
  #
  # Sprites are centered on their position by default, so rotation and scale happen around
  # the middle. For sprite sheets, set `hframes`/`vframes` and pick a `frame`, or use an
  # `AnimatedSprite2D`.
  #
  # ```
  # player = Sprite2D.new(Texture.new(Image.circle(32, Color::YELLOW)), v2(200, 150))
  # player.flip_h = true              # face left
  # player.modulate = Color::RED      # tint, including children
  # SceneTree.root.add(player)
  #
  # coin = Sprite2D.load("res://coin.png", v2(300, 150))
  # coin.hframes = 6                  # a 6-frame strip
  # coin.frame = 2
  # ```
  class Sprite2D < Node2D
    # The texture or region to draw. `nil` draws nothing.
    property texture : Drawable?
    # Draw centered on the node's position (the default) or with the top-left there.
    property? centered = true
    # Extra offset in local space, for example to line up feet with the position.
    property offset : Vec2 = Vec2::ZERO
    # Mirror horizontally, for characters that turn around.
    property? flip_h = false
    # Mirror vertically.
    property? flip_v = false
    # Tint for this sprite only. `modulate` also tints children.
    property color : Color = Color::WHITE
    # Number of columns when the texture is a sprite sheet.
    property hframes : Int32 = 1
    # Number of rows when the texture is a sprite sheet.
    property vframes : Int32 = 1
    # Which cell of the sheet to show, counting left to right, top to bottom.
    property frame : Int32 = 0

    # Creates a sprite, optionally with a texture.
    def initialize(name : String = "", @texture : Drawable? = nil, position : Vec2 = Vec2::ZERO, @centered = true)
      super(name, position)
    end

    # Creates a sprite showing *texture* at *position*.
    def initialize(texture : Drawable, position : Vec2 = Vec2::ZERO, name : String = "")
      super(name, position)
      @texture = texture
    end

    # Creates a sprite from an image file.
    def self.load(path : String, position : Vec2 = Vec2::ZERO, filter : GPU::Filter = Texture.default_filter) : Sprite2D
      new(Texture.load(path, filter), position)
    end

    # Sets the texture by loading a file.
    def texture=(path : String)
      @texture = Texture.load(path)
    end

    # Sets the texture.
    def texture=(t : Drawable?)
      @texture = t
    end

    # Size of one frame in pixels, before scale.
    def size : Vec2
      t = @texture
      return Vec2::ZERO unless t
      s = case t
          in Texture then t.size
          in TextureRegion then t.size
          end
      Vec2.new(s.x / @hframes, s.y / @vframes)
    end

    # Frame width in pixels.
    def width : Float32; size.x; end
    # Frame height in pixels.
    def height : Float32; size.y; end

    # The drawn area in local space, accounting for `centered` and `offset`.
    def rect : Rect
      s = size
      origin = @centered ? -s / 2 : Vec2::ZERO
      Rect.new(origin + @offset, s)
    end

    # The drawn area in world space. When rotated, this is the axis-aligned box around it.
    def global_rect : Rect
      t = global_transform
      r = rect
      pts = [t * r.position, t * Vec2.new(r.right, r.y), t * r.max, t * Vec2.new(r.x, r.bottom)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    # True when a world-space point falls on the sprite's rect. Handy for clicking sprites.
    #
    # ```
    # card = Sprite2D.new(Texture.new(Image.new(60, 90, Color::WHITE)), v2(100, 100))
    # card.modulate = Color::YELLOW if card.contains_point?(Input.mouse)
    # ```
    def contains_point?(global : Vec2) : Bool
      rect.contains?(to_local(global))
    end

    # The region actually drawn this frame, after frame selection and flips.
    def current_region : Drawable?
      t = @texture
      return nil unless t
      d = t
      if @hframes > 1 || @vframes > 1
        base = t.is_a?(Texture) ? t.region(t.rect) : t
        fw = base.width / @hframes; fh = base.height / @vframes
        fx = (@frame % @hframes) * fw; fy = ((@frame // @hframes) % @vframes) * fh
        d = base.texture.region(base.rect.x + fx, base.rect.y + fy, fw, fh)
      end
      if @flip_h || @flip_v
        d = d.is_a?(Texture) ? d.region(d.rect) : d
        d = d.flipped_x if @flip_h
        d = d.flipped_y if @flip_v
      end
      d
    end

    # Draws the current region.
    def draw(g : Graphics) : Nil
      d = current_region
      return unless d
      s = size
      origin = @centered ? s / 2 : Vec2::ZERO
      g.draw(d, @offset.x, @offset.y, 0, 1, 1, origin.x, origin.y, g.color * @color)
    end
  end
end
