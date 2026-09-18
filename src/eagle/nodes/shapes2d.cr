module Eagle
  # A filled or outlined polygon node: quick shapes for prototypes, vector-style games and debug markers.
  #
  # ```
  # ship = Polygon2D.new([v2(12, 0), v2(-8, -8), v2(-8, 8)], Color::WHITE, DrawMode::Line)
  # ship.line_width = 2
  # wall = Polygon2D.rect(200, 20, Color::GRAY)
  # hex = Polygon2D.regular(6, 30, Color::CYAN)
  # ```
  class Polygon2D < Node2D
    # Vertices in local space.
    property points : Array(Vec2)
    # Fill or line color.
    property color : Color
    # `Fill` or `Line`.
    property mode : DrawMode
    # Outline thickness when `mode` is `Line`.
    property line_width : Float32 = 1_f32

    # Creates a polygon from local-space points.
    def initialize(@points : Array(Vec2), @color = Color::WHITE, @mode = DrawMode::Fill, name : String = "", position : Vec2 = Vec2::ZERO)
      super(name, position)
    end

    # A rectangle, centered on the origin by default.
    def self.rect(w : Number, h : Number, color : Color = Color::WHITE, centered : Bool = true) : Polygon2D
      o = centered ? Vec2.new(-w / 2, -h / 2) : Vec2::ZERO
      new([o, o + Vec2.new(w, 0), o + Vec2.new(w, h), o + Vec2.new(0, h)], color)
    end

    # A circle approximated with *segments* sides.
    def self.circle(radius : Number, color : Color = Color::WHITE, segments : Int32 = 32) : Polygon2D
      new(Array(Vec2).new(segments) { |i| Vec2.from_angle(Math::PI * 2 * i / segments, radius) }, color)
    end

    # A regular polygon: 3 sides for a triangle, 6 for a hexagon and so on.
    def self.regular(sides : Int32, radius : Number, color : Color = Color::WHITE) : Polygon2D
      circle(radius, color, sides)
    end

    # Draws the polygon.
    def draw(g : Graphics) : Nil
      if @mode.line?
        g.polyline(@points, g.color * @color, @line_width, closed: true)
      else
        g.polygon(@points, DrawMode::Fill, g.color * @color)
      end
    end
  end

  # A line through a list of points, for trails, ropes, paths and laser beams.
  #
  # ```
  # trail = Line2D.new(width: 3, color: Color::ORANGE)
  # trail.add_point(v2(0, 0))
  # trail.add_point(v2(50, 20))
  # ```
  class Line2D < Node2D
    # Points in local space.
    property points : Array(Vec2)
    # Line color.
    property color : Color
    # Line thickness in points.
    property width : Float32
    # Joins the last point back to the first.
    property? closed = false

    # Creates a line.
    def initialize(@points : Array(Vec2) = [] of Vec2, @color = Color::WHITE, width : Number = 1, name : String = "")
      super(name)
      @width = width.to_f32
    end

    # Appends a point.
    def add_point(p : Vec2) : Nil; @points << p; end
    # Removes every point.
    def clear_points : Nil; @points.clear; end

    # Draws the line.
    def draw(g : Graphics) : Nil
      g.polyline(@points, g.color * @color, @width, closed: @closed)
    end
  end
end
