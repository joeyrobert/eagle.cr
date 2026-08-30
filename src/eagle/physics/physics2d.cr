require "./shapes2d"
require "./collision2d"
require "./body2d"
require "./world2d"

module Eagle
  # 2D rigid-body physics. `Physics2D.world` is the global world used by the
  # physics nodes; you can also create `Physics2D::World` instances directly.
  module Physics2D
    @@world = World.new

    def self.world : World; @@world; end
    def self.world=(w : World); @@world = w; end
    def self.active? : Bool; !@@world.bodies.empty?; end
    def self.reset : Nil; @@world = World.new; end

    # Draw all bodies as outlines (debug).
    def self.debug_draw(g : Graphics, color : Color = Color.new(0, 1, 0, 0.6)) : Nil
      @@world.bodies.each do |b|
        c = b.sensor? ? Color.new(0, 0.6, 1, 0.5) : (b.dynamic? ? color : color.lerp(Color::GRAY, 0.5))
        b.each_world_shape do |s|
          case s
          when Circle
            g.circle(s.center, s.radius, DrawMode::Line, c)
            g.line(s.center, s.center + Vec2.from_angle(b.rotation, s.radius), c)
          when Polygon
            g.polyline(s.points, c, 1, closed: true)
          end
        end
      end
    end
  end
end
