require "./shapes2d"
require "./collision2d"
require "./body2d"
require "./world2d"

module Eagle
  # 2D rigid-body physics in pure Crystal: circles and convex polygons, stacking, friction,
  # restitution, sensors, raycasts and kinematic character movement.
  #
  # Most games use it through the physics nodes (`RigidBody2D`, `StaticBody2D`,
  # `KinematicBody2D`, `Area2D`, `RayCast2D`), which share the global `Physics2D.world`.
  # The engine steps that world at the fixed rate before `physics_process` runs.
  #
  # You can also use a `World` directly, without nodes, for simulations and tests:
  #
  # ```
  # world = Physics2D::World.new
  # world.gravity = v2(0, 600)
  # ground = world.add(Physics2D::BodyType::Static, v2(400, 580), Physics2D::Polygon.box(800, 40))
  # ball = world.add(Physics2D::BodyType::Dynamic, v2(400, 0), Physics2D::Circle.new(16))
  # 60.times { world.step(1_f32 / 60) }
  # ball.position # resting on the ground
  #
  # if hit = world.raycast(v2(0, 300), v2(1, 0), max_distance: 800)
  #   hit.point
  # end
  # ```
  #
  # Units are pixels and seconds, and gravity defaults to 980 px/s² downward.
  module Physics2D
    @@world = World.new

    # The shared world used by the physics nodes.
    def self.world : World; @@world; end
    # Replaces the shared world.
    def self.world=(w : World); @@world = w; end
    # True when the shared world has bodies. The engine skips stepping an empty world.
    def self.active? : Bool; !@@world.bodies.empty?; end
    # Replaces the shared world with an empty one.
    def self.reset : Nil; @@world = World.new; end

    # Draws the outline of every body in the shared world. Call it from `App#draw` while tuning collisions.
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
