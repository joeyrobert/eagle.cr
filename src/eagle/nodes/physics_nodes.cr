module Eagle
  # Child of a physics body/area holding a shape.
  #
  #   body = RigidBody2D.new(position: v2(100, 0))
  #   body.add(CollisionShape2D.circle(16))
  class CollisionShape2D < Node
    getter shape : Physics2D::Shape
    property? disabled = false

    def initialize(@shape : Physics2D::Shape, name : String = "")
      super(name)
    end

    def self.circle(radius : Number, offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Circle.new(radius, offset))
    end

    def self.box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Polygon.box(w, h, offset))
    end

    def self.polygon(points : Array(Vec2), offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Polygon.new(points, offset))
    end

    def enter_tree : Nil
      if (b = parent).is_a?(CollisionObject2D)
        b.body.add_shape(@shape) unless @disabled
      end
    end

    def exit_tree : Nil
      if (b = parent).is_a?(CollisionObject2D)
        b.body.remove_shape(@shape)
      end
    end

    # Shapes are drawn by the parent body's debug draw.
    def draw(g : Graphics) : Nil
      return unless false
      c = Color.new(0, 1, 0.5, 0.7)
      case (s = @shape)
      when Physics2D::Circle then g.circle(s.offset, s.radius, DrawMode::Line, c)
      when Physics2D::Polygon then g.polyline(s.points, c, 1, closed: true)
      end
    end
  end

  # Base for nodes backed by a physics body. Syncs the node transform and the body.
  abstract class CollisionObject2D < Node2D
    getter body : Physics2D::Body
    property? debug = false
    property world : Physics2D::World
    @begin_handler : Proc(Physics2D::Body, Physics2D::Body, Nil)? = nil
    @end_handler : Proc(Physics2D::Body, Physics2D::Body, Nil)? = nil

    signal body_entered(other : CollisionObject2D)
    signal body_exited(other : CollisionObject2D)

    def initialize(type : Physics2D::BodyType, name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(name, position)
      @world = Physics2D.world
      @body = Physics2D::Body.new(type, position, shape)
      @body.owner = self
      @body.sensor = self.is_a?(Area2D)
    end

    def layer : UInt32; @body.layer; end
    def layer=(v : UInt32); @body.layer = v; end
    def mask : UInt32; @body.mask; end
    def mask=(v : UInt32); @body.mask = v; end

    # Convenience: add a shape directly (no CollisionShape2D child needed).
    def add_shape(s : Physics2D::Shape) : self
      @body.add_shape(s)
      self
    end

    def circle(radius : Number, offset : Vec2 = Vec2::ZERO) : self; add_shape(Physics2D::Circle.new(radius, offset)); end
    def box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : self; add_shape(Physics2D::Polygon.box(w, h, offset)); end
    def polygon(points : Array(Vec2)) : self; add_shape(Physics2D::Polygon.new(points)); end

    def enter_tree : Nil
      push_transform
      @world.add_body(@body)
      @begin_handler = @world.on_contact_begin { |a, b| on_contact(a, b, true) }
      @end_handler = @world.on_contact_end { |a, b| on_contact(a, b, false) }
    end

    def exit_tree : Nil
      @world.remove_body(@body)
      @begin_handler.try { |h| @world.contact_begin.disconnect(h) }
      @end_handler.try { |h| @world.contact_end.disconnect(h) }
    end

    private def on_contact(a : Physics2D::Body, b : Physics2D::Body, began : Bool)
      other = a == @body ? b : (b == @body ? a : nil)
      return unless other
      if (o = other.owner).is_a?(CollisionObject2D)
        began ? emit_body_entered(o) : emit_body_exited(o)
      end
    end

    # Debug outline of every shape on the body (enable with `debug = true`).
    def draw(g : Graphics) : Nil
      return unless @debug
      c = @body.sensor? ? Color.new(0, 0.6, 1, 0.8) : (@body.dynamic? ? Color.new(0.2, 1, 0.4, 0.9) : Color.new(0.7, 0.7, 0.7, 0.9))
      @body.shapes.each do |s|
        case s
        when Physics2D::Circle
          g.circle(s.offset, s.radius, DrawMode::Line, g.color * c)
          g.line(s.offset, s.offset + Vec2.new(s.radius, 0), g.color * c)
        when Physics2D::Polygon
          g.polyline(s.points, g.color * c, 1, closed: true)
        end
      end
    end

    # Other collision objects currently touching/overlapping this one.
    def overlapping : Array(CollisionObject2D)
      @body.contacts.compact_map { |b| b.owner.as?(CollisionObject2D) }
    end

    def overlaps?(other : CollisionObject2D) : Bool; @body.contacts.includes?(other.body); end

    # Node → body (for static/kinematic and manual repositioning).
    def push_transform : Nil
      @body.position = global_position
      @body.rotation = global_rotation
      @body.update_world_shapes
    end

    # Body → node (dynamic).
    def pull_transform : Nil
      self.global_position = @body.position
      @rotation = @body.rotation - (global_rotation - @rotation)
    end

    def physics_process(dt : Float32) : Nil
      # Runs after World#step (engine order): dynamic bodies pull, others push.
      if @body.dynamic?
        pull_transform
      else
        push_transform
      end
    end
  end

  # Immovable body (walls, floors).
  class StaticBody2D < CollisionObject2D
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Static, name, position, shape)
    end
  end

  # Simulated body: gravity, collisions, forces.
  class RigidBody2D < CollisionObject2D
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Dynamic, name, position, shape)
    end

    def velocity : Vec2; @body.velocity; end
    def velocity=(v : Vec2); @body.velocity = v; end
    def angular_velocity : Float32; @body.angular_velocity; end
    def angular_velocity=(v : Number); @body.angular_velocity = v.to_f32; end
    def mass : Float32; @body.mass; end
    def mass=(m : Number); @body.mass = m; end
    def restitution=(r : Number); @body.restitution = r.to_f32; end
    def friction=(f : Number); @body.friction = f.to_f32; end
    def gravity_scale=(s : Number); @body.gravity_scale = s.to_f32; end
    def linear_damping=(d : Number); @body.linear_damping = d.to_f32; end
    def fixed_rotation=(v : Bool); @body.fixed_rotation = v; end
    def apply_force(f : Vec2, point : Vec2? = nil); @body.apply_force(f, point); end
    def apply_impulse(i : Vec2, point : Vec2? = nil); @body.apply_impulse(i, point); end
    def apply_torque(t : Number); @body.apply_torque(t); end
  end

  # Body moved by code (characters, platforms). Use `move_and_slide`.
  class KinematicBody2D < CollisionObject2D
    property velocity : Vec2 = Vec2::ZERO
    getter? on_floor = false
    getter? on_wall = false
    getter? on_ceiling = false
    getter floor_normal : Vec2 = Vec2::ZERO
    # Up direction used to classify floor/ceiling.
    property up_direction : Vec2 = Vec2.new(0, -1)
    property floor_max_angle : Float32 = Mathf.deg2rad(46)
    # Distance to probe for ground each move so `on_floor?` stays true while resting.
    property floor_snap : Float32 = 2_f32

    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Kinematic, name, position, shape)
    end

    # Move by `velocity * dt` sliding along collisions; updates on_floor etc.
    def move_and_slide(dt : Float32, velocity : Vec2? = nil) : Vec2
      @velocity = velocity if velocity
      push_transform
      normals = @world.move_and_slide(@body, @velocity * dt)
      @on_floor = @on_wall = @on_ceiling = false
      @floor_normal = Vec2::ZERO
      normals.each do |n|
        d = n.dot(@up_direction)
        if d >= Math.cos(@floor_max_angle)
          @on_floor = true; @floor_normal = n
        elsif d <= -Math.cos(@floor_max_angle)
          @on_ceiling = true
        else
          @on_wall = true
        end
        # remove velocity into the surface
        vn = @velocity.dot(n)
        @velocity -= n * vn if vn < 0
      end
      if !@on_floor && @floor_snap > 0 && @velocity.dot(@up_direction) <= 0
        if n = @world.probe_floor(@body, @up_direction, @floor_snap, @floor_max_angle)
          @on_floor = true
          @floor_normal = n
        end
      end
      self.global_position = @body.position
      @velocity
    end

    # Move by `motion` and stop at the first collision (no sliding). Returns the hit normal.
    def move_and_collide(motion : Vec2) : Vec2?
      push_transform
      normals = @world.move_and_slide(@body, motion, 1)
      self.global_position = @body.position
      normals.first?
    end

    def physics_process(dt : Float32) : Nil
      push_transform
    end
  end

  # Alias matching Godot 4 naming.
  alias CharacterBody2D = KinematicBody2D

  # Detects overlaps without colliding. Signals: body_entered / body_exited.
  class Area2D < CollisionObject2D
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Kinematic, name, position, shape)
      @body.sensor = true
    end

    # Bodies/areas currently inside.
    def bodies : Array(CollisionObject2D); overlapping; end
    def has_point?(p : Vec2) : Bool; @body.contains_point?(p); end
  end

  # Ray query node (like Godot's RayCast2D).
  class RayCast2D < Node2D
    property target : Vec2
    property mask : UInt32 = 0xFFFFFFFF_u32
    property exclude_parent : Bool = true
    getter hit : Physics2D::RayHit? = nil

    def initialize(@target : Vec2 = Vec2.new(0, 50), name : String = "")
      super(name)
    end

    def colliding? : Bool; !@hit.nil?; end
    def collider : CollisionObject2D?; @hit.try(&.body.owner.as?(CollisionObject2D)); end
    def collision_point : Vec2?; @hit.try(&.point); end
    def collision_normal : Vec2?; @hit.try(&.normal); end

    def update_cast : Physics2D::RayHit?
      origin = global_position
      to = to_global(@target)
      excl = @exclude_parent ? parent_2d.as?(CollisionObject2D).try(&.body) : nil
      @hit = Physics2D.world.raycast(origin, to - origin, (to - origin).length, @mask, excl)
    end

    def physics_process(dt : Float32) : Nil
      update_cast
    end
  end
end
