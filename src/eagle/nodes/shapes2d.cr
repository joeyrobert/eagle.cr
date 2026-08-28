module Eagle
  # A filled/outlined polygon.
  class Polygon2D < Node2D
    property points : Array(Vec2)
    property color : Color
    property mode : DrawMode
    property line_width : Float32 = 1_f32

    def initialize(@points : Array(Vec2), @color = Color::WHITE, @mode = DrawMode::Fill, name : String = "", position : Vec2 = Vec2::ZERO)
      super(name, position)
    end

    def self.rect(w : Number, h : Number, color : Color = Color::WHITE, centered : Bool = true) : Polygon2D
      o = centered ? Vec2.new(-w / 2, -h / 2) : Vec2::ZERO
      new([o, o + Vec2.new(w, 0), o + Vec2.new(w, h), o + Vec2.new(0, h)], color)
    end

    def self.circle(radius : Number, color : Color = Color::WHITE, segments : Int32 = 32) : Polygon2D
      new(Array(Vec2).new(segments) { |i| Vec2.from_angle(Math::PI * 2 * i / segments, radius) }, color)
    end

    def self.regular(sides : Int32, radius : Number, color : Color = Color::WHITE) : Polygon2D
      circle(radius, color, sides)
    end

    def draw(g : Graphics) : Nil
      if @mode.line?
        g.polyline(@points, g.color * @color, @line_width, closed: true)
      else
        g.polygon(@points, DrawMode::Fill, g.color * @color)
      end
    end
  end

  # A polyline.
  class Line2D < Node2D
    property points : Array(Vec2)
    property color : Color
    property width : Float32
    property? closed = false

    def initialize(@points : Array(Vec2) = [] of Vec2, @color = Color::WHITE, width : Number = 1, name : String = "")
      super(name)
      @width = width.to_f32
    end

    def add_point(p : Vec2) : Nil; @points << p; end
    def clear_points : Nil; @points.clear; end

    def draw(g : Graphics) : Nil
      g.polyline(@points, g.color * @color, @width, closed: @closed)
    end
  end
end
