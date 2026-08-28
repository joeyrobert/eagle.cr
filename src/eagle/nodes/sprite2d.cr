module Eagle
  # Draws a texture (or region) at the node's transform.
  class Sprite2D < Node2D
    property texture : Drawable?
    # Draw centred on the node position (default) or from the top-left.
    property? centered = true
    property offset : Vec2 = Vec2::ZERO
    property? flip_h = false
    property? flip_v = false
    property color : Color = Color::WHITE
    # Sprite-sheet support: split the texture into a grid and show `frame`.
    property hframes : Int32 = 1
    property vframes : Int32 = 1
    property frame : Int32 = 0

    def initialize(name : String = "", @texture : Drawable? = nil, position : Vec2 = Vec2::ZERO, @centered = true)
      super(name, position)
    end

    def initialize(texture : Drawable, position : Vec2 = Vec2::ZERO, name : String = "")
      super(name, position)
      @texture = texture
    end

    def self.load(path : String, position : Vec2 = Vec2::ZERO, filter : GPU::Filter = Texture.default_filter) : Sprite2D
      new(Texture.load(path, filter), position)
    end

    def texture=(path : String)
      @texture = Texture.load(path)
    end

    def texture=(t : Drawable?)
      @texture = t
    end

    def size : Vec2
      t = @texture
      return Vec2::ZERO unless t
      s = case t
          in Texture then t.size
          in TextureRegion then t.size
          end
      Vec2.new(s.x / @hframes, s.y / @vframes)
    end

    def width : Float32; size.x; end
    def height : Float32; size.y; end

    # Local-space bounding rect.
    def rect : Rect
      s = size
      origin = @centered ? -s / 2 : Vec2::ZERO
      Rect.new(origin + @offset, s)
    end

    # World-space axis-aligned bounds.
    def global_rect : Rect
      t = global_transform
      r = rect
      pts = [t * r.position, t * Vec2.new(r.right, r.y), t * r.max, t * Vec2.new(r.x, r.bottom)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    def contains_point?(global : Vec2) : Bool
      rect.contains?(to_local(global))
    end

    # The drawable for the current frame / flips.
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

    def draw(g : Graphics) : Nil
      d = current_region
      return unless d
      s = size
      origin = @centered ? s / 2 : Vec2::ZERO
      g.draw(d, @offset.x, @offset.y, 0, 1, 1, origin.x, origin.y, g.color * @color)
    end
  end
end
