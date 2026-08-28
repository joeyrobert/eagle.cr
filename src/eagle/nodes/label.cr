module Eagle
  # Text node.
  class Label < Node2D
    property text : String
    property font : Font? = nil
    property color : Color = Color::WHITE
    property align : TextAlign = TextAlign::Left
    property font_scale : Float32 = 1_f32
    # Wrap width in local units (nil = no wrapping).
    property width : Float32? = nil
    property shadow : Color? = nil
    property shadow_offset : Vec2 = Vec2.new(1, 1)

    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, @color = Color::WHITE, name : String = "", @align = TextAlign::Left, @font = nil)
      super(name, position)
    end

    def font_or_default : Font; @font || Eagle.graphics.font; end

    def size : Vec2
      f = font_or_default
      if w = @width
        lines = f.wrap(@text, w / @font_scale)
        Vec2.new(w, lines.size * f.height * @font_scale)
      else
        f.measure(@text) * @font_scale
      end
    end

    def draw(g : Graphics) : Nil
      f = font_or_default
      if s = @shadow
        draw_text(g, @shadow_offset.x, @shadow_offset.y, g.color * s, f)
      end
      draw_text(g, 0, 0, g.color * @color, f)
    end

    private def draw_text(g, x, y, color, f)
      if w = @width
        g.printf(@text, x, y, w, @align, color, f, @font_scale)
      else
        g.print(@text, x, y, color, f, @font_scale, @align)
      end
    end
  end
end
