module Eagle
  # A child node that gives its parent physics body a shape. It's an alternative to
  # calling `circle`, `box` or `polygon` on the body directly, and it's handy when the shape
  # should appear in the scene tree or be switched off with `disabled`.
  #
  # ```
  # body = RigidBody2D.new(position: v2(100, 0))
  # body.add(CollisionShape2D.circle(16))
  # body.add(CollisionShape2D.box(40, 8, offset: v2(0, 20)))
  # ```
  class CollisionShape2D < Node
    # The physics shape this node contributes.
    getter shape : Physics2D::Shape
    # When true, the shape is ignored by collisions.
    property? disabled = false

    # Wraps a `Physics2D::Shape`.
    def initialize(@shape : Physics2D::Shape, name : String = "")
      super(name)
    end

    # A circle of *radius*, optionally offset from the body's origin.
    def self.circle(radius : Number, offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Circle.new(radius, offset))
    end

    # A *w* by *h* box centered on *offset*.
    def self.box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Polygon.box(w, h, offset))
    end

    # A convex polygon from local points.
    def self.polygon(points : Array(Vec2), offset : Vec2 = Vec2::ZERO) : CollisionShape2D
      new(Physics2D::Polygon.new(points, offset))
    end

    # Attaches the shape to the parent body.
    def enter_tree : Nil
      if (b = parent).is_a?(CollisionObject2D)
        b.body.add_shape(@shape) unless @disabled
      end
    end

    # Detaches the shape from the parent body.
    def exit_tree : Nil
      if (b = parent).is_a?(CollisionObject2D)
        b.body.remove_shape(@shape)
      end
    end

    # Draws nothing. The parent body draws shapes when its `debug` is on.
    def draw(g : Graphics) : Nil
      return unless false
      c = Color.new(0, 1, 0.5, 0.7)
      case (s = @shape)
      when Physics2D::Circle then g.circle(s.offset, s.radius, DrawMode::Line, c)
      when Physics2D::Polygon then g.polyline(s.points, c, 1, closed: true)
      end
    end
  end

  # Base class for 2D physics nodes. It owns a `Physics2D::Body` in `Physics2D.world` and keeps
  # the node's transform and the body in sync.
  #
  # Give it a shape with `circle`, `box`, `polygon` or a `CollisionShape2D` child. Pick the
  # subclass by how the object should move:
  #
  # * `StaticBody2D` never moves: floors, walls.
  # * `RigidBody2D` is moved by the simulation: crates, balls, ragdolls.
  # * `KinematicBody2D` is moved by your code with `move_and_slide`: players, moving platforms.
  # * `Area2D` only detects overlaps: pickups, triggers, damage zones.
  #
  # Collision layers decide what touches what. Two objects collide when each one's `layer`
  # has a bit in common with the other's `mask`.
  #
  # ```
  # PLAYER = 1_u32
  # ENEMY = 2_u32
  # player = KinematicBody2D.new(position: v2(100, 100)).box(20, 32)
  # player.layer = PLAYER
  # player.mask = ENEMY | 4_u32 # collide with enemies and the world (bit 3)
  #
  # pickup = Area2D.new(position: v2(300, 100)).circle(10)
  # pickup.on_body_entered { |other| pickup.queue_free if other == player }
  # ```
  #
  # Set `debug = true` to draw the shapes' outlines.
  abstract class CollisionObject2D < Node2D
    # The underlying physics body, for settings the node doesn't expose.
    getter body : Physics2D::Body
    # Draws the body's shapes as outlines.
    property? debug = false
    # The physics world the body lives in. Defaults to `Physics2D.world`.
    property world : Physics2D::World
    @begin_handler : Proc(Physics2D::Body, Physics2D::Body, Nil)? = nil
    @end_handler : Proc(Physics2D::Body, Physics2D::Body, Nil)? = nil

    signal body_entered(other : CollisionObject2D)
    signal body_exited(other : CollisionObject2D)

    # Creates the node and its body.
    def initialize(type : Physics2D::BodyType, name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(name, position)
      @world = Physics2D.world
      @body = Physics2D::Body.new(type, position, shape)
      @body.owner = self
      @body.sensor = self.is_a?(Area2D)
    end

    # The layer bits this object is on.
    def layer : UInt32; @body.layer; end
    # Sets the layer bits.
    def layer=(v : UInt32); @body.layer = v; end
    # The layer bits this object collides with.
    def mask : UInt32; @body.mask; end
    # Sets the mask bits.
    def mask=(v : UInt32); @body.mask = v; end

    # Adds a raw `Physics2D::Shape`. Returns self.
    def add_shape(s : Physics2D::Shape) : self
      @body.add_shape(s)
      self
    end

    # Adds a circle shape. Returns self, so it chains after `new`.
    def circle(radius : Number, offset : Vec2 = Vec2::ZERO) : self; add_shape(Physics2D::Circle.new(radius, offset)); end
    # Adds a box shape centered on *offset*. Returns self.
    def box(w : Number, h : Number, offset : Vec2 = Vec2::ZERO) : self; add_shape(Physics2D::Polygon.box(w, h, offset)); end
    # Adds a convex polygon shape. Returns self.
    def polygon(points : Array(Vec2)) : self; add_shape(Physics2D::Polygon.new(points)); end

    # Adds the body to the world.
    def enter_tree : Nil
      push_transform
      @world.add_body(@body)
      @begin_handler = @world.on_contact_begin { |a, b| on_contact(a, b, true) }
      @end_handler = @world.on_contact_end { |a, b| on_contact(a, b, false) }
    end

    # Removes the body from the world.
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

    # Draws shape outlines when `debug` is on.
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

    # Every collision object currently touching or overlapping this one.
    def overlapping : Array(CollisionObject2D)
      @body.contacts.compact_map { |b| b.owner.as?(CollisionObject2D) }
    end

    # True when *other* is touching or overlapping this one.
    def overlaps?(other : CollisionObject2D) : Bool; @body.contacts.includes?(other.body); end

    # Copies the node's global position and rotation onto the body. Call it after teleporting
    # a rigid body by setting its position.
    def push_transform : Nil
      @body.position = global_position
      @body.rotation = global_rotation
      @body.update_world_shapes
    end

    # Copies the body's position and rotation onto the node.
    def pull_transform : Nil
      self.global_position = @body.position
      @rotation = @body.rotation - (global_rotation - @rotation)
    end

    # Syncs the node and the body after each physics step.
    def physics_process(dt : Float32) : Nil
      # Runs after World#step (engine order): dynamic bodies pull, others push.
      if @body.dynamic?
        pull_transform
      else
        push_transform
      end
    end
  end

  # A body that never moves: floors, walls and other level geometry.
  #
  # ```
  # floor = StaticBody2D.new(position: v2(400, 580)).box(800, 40)
  # SceneTree.root.add(floor)
  # ```
  class StaticBody2D < CollisionObject2D
    # Creates a static body.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Static, name, position, shape)
    end
  end

  # A body moved by the physics simulation: it falls, bounces, stacks and gets pushed.
  #
  # Don't set its position every frame. Push it with forces and impulses instead, or set
  # `velocity` directly for arcade-style control.
  #
  # ```
  # ball = RigidBody2D.new(position: v2(400, 0)).circle(16)
  # ball.restitution = 0.7 # bouncy
  # ball.friction = 0.2
  # ball.apply_impulse(v2(200, -300)) # kick it up and to the right
  # ball.on_body_entered { |other| puts "bonk" }
  # SceneTree.root.add(ball)
  # ```
  class RigidBody2D < CollisionObject2D
    # Creates a dynamic body.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Dynamic, name, position, shape)
    end

    # Linear velocity in pixels per second.
    def velocity : Vec2; @body.velocity; end
    # Sets the linear velocity.
    def velocity=(v : Vec2); @body.velocity = v; end
    # Spin in radians per second.
    def angular_velocity : Float32; @body.angular_velocity; end
    # Sets the spin.
    def angular_velocity=(v : Number); @body.angular_velocity = v.to_f32; end
    # Mass. Heavier bodies push lighter ones around.
    def mass : Float32; @body.mass; end
    # Sets the mass. Inertia follows the shapes.
    def mass=(m : Number); @body.mass = m; end
    # Bounciness from 0 (dead stop) to 1 (bounces back at full speed).
    def restitution=(r : Number); @body.restitution = r.to_f32; end
    # Surface grip from 0 (ice) upward. 0.5 is a good default.
    def friction=(f : Number); @body.friction = f.to_f32; end
    # Multiplies gravity for this body. 0 makes it float.
    def gravity_scale=(s : Number); @body.gravity_scale = s.to_f32; end
    # Drag that slows the body over time, like air resistance.
    def linear_damping=(d : Number); @body.linear_damping = d.to_f32; end
    # Stops the body from rotating, which is useful for characters driven by physics.
    def fixed_rotation=(v : Bool); @body.fixed_rotation = v; end
    # Pushes continuously during the next step. Call it every physics frame for thrust or wind.
    # Applied at *point* in world space, it also causes spin.
    def apply_force(f : Vec2, point : Vec2? = nil); @body.apply_force(f, point); end
    # Changes velocity instantly, for jumps, kicks and explosions. Applied at *point*, it also causes spin.
    def apply_impulse(i : Vec2, point : Vec2? = nil); @body.apply_impulse(i, point); end
    # Spins the body during the next step.
    def apply_torque(t : Number); @body.apply_torque(t); end
  end

  # A body you move from code that still collides: players, enemies and moving platforms.
  #
  # Set `velocity` and call `move_and_slide` in `physics_process`. The body slides along
  # walls and floors instead of stopping dead, and `on_floor?` tells you when it can jump.
  #
  # ```
  # class Player < KinematicBody2D
  #   def ready : Nil
  #     box(20, 32)
  #   end
  #
  #   def physics_process(dt : Float32) : Nil
  #     self.velocity += v2(0, 1400 * dt) # gravity
  #     self.velocity = v2(Input.axis("left", "right") * 220, velocity.y)
  #     self.velocity = v2(velocity.x, -520) if Input.pressed?("jump") && on_floor?
  #     move_and_slide(dt)
  #   end
  # end
  # ```
  class KinematicBody2D < CollisionObject2D
    # Velocity in pixels per second, used by `move_and_slide`.
    property velocity : Vec2 = Vec2::ZERO
    # True when the last move ended on a floor, meaning a surface facing `up_direction` within `floor_max_angle`.
    getter? on_floor = false
    # True when the last move hit a wall.
    getter? on_wall = false
    # True when the last move hit a ceiling.
    getter? on_ceiling = false
    # The normal of the floor under the body, for slope-aware movement.
    getter floor_normal : Vec2 = Vec2::ZERO
    # Which way is up, used to tell floors from ceilings. Screen up by default.
    property up_direction : Vec2 = Vec2.new(0, -1)
    # Steepest slope that still counts as floor, in radians. About 46° by default.
    property floor_max_angle : Float32 = Mathf.deg2rad(46)
    # How far below the body to look for ground each move, so `on_floor?` stays true while resting.
    property floor_snap : Float32 = 2_f32

    # Creates a kinematic body.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Kinematic, name, position, shape)
    end

    # Moves by `velocity * dt`, sliding along anything in the way. Velocity into a surface is
    # removed, so falling onto a floor zeroes the vertical speed. Updates `on_floor?`,
    # `on_wall?` and `on_ceiling?`. Returns the new velocity.
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

    # Moves by *motion* and stops at the first obstacle, without sliding. Returns the hit
    # normal, or `nil` if the path was clear. Good for bullets and pucks that bounce.
    def move_and_collide(motion : Vec2) : Vec2?
      push_transform
      normals = @world.move_and_slide(@body, motion, 1)
      self.global_position = @body.position
      normals.first?
    end

    # Keeps the body in sync with the node.
    def physics_process(dt : Float32) : Nil
      push_transform
    end
  end

  # Godot 4's name for `KinematicBody2D`.
  alias CharacterBody2D = KinematicBody2D

  # A region that detects overlaps without blocking anything: coins, checkpoints, damage
  # zones and sight cones.
  #
  # ```
  # coin = Area2D.new(position: v2(200, 300)).circle(12)
  # coin.on_body_entered { |body| coin.queue_free if body.is_a?(KinematicBody2D) }
  # lava = Area2D.new(position: v2(0, 500)).box(800, 40)
  # ```
  class Area2D < CollisionObject2D
    # Creates an area.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, shape : Physics2D::Shape? = nil)
      super(Physics2D::BodyType::Kinematic, name, position, shape)
      @body.sensor = true
    end

    # Everything currently inside the area.
    def bodies : Array(CollisionObject2D); overlapping; end
    # True when a world-space point is inside the area.
    def has_point?(p : Vec2) : Bool; @body.contains_point?(p); end
  end

  # Casts a ray from the node toward `target` every physics step, for line of sight, ground
  # checks and laser beams.
  #
  # ```
  # eye = RayCast2D.new(v2(200, 0)) # 200 px to the right, rotated with the parent
  # enemy = Node2D.new
  # enemy.add(eye)
  # if eye.colliding?
  #   hit_at = eye.collision_point
  # end
  # ```
  class RayCast2D < Node2D
    # End of the ray in local space.
    property target : Vec2
    # Layers the ray can hit.
    property mask : UInt32 = 0xFFFFFFFF_u32
    # Ignores the parent body, so a ray starting inside a character doesn't hit itself.
    property exclude_parent : Bool = true
    # The last hit, or `nil`.
    getter hit : Physics2D::RayHit? = nil

    # Creates a ray ending at *target*, in local space.
    def initialize(@target : Vec2 = Vec2.new(0, 50), name : String = "")
      super(name)
    end

    # True when the last cast hit something.
    def colliding? : Bool; !@hit.nil?; end
    # The collision object that was hit, if any.
    def collider : CollisionObject2D?; @hit.try(&.body.owner.as?(CollisionObject2D)); end
    # Where the ray hit, in world space.
    def collision_point : Vec2?; @hit.try(&.point); end
    # The surface normal at the hit.
    def collision_normal : Vec2?; @hit.try(&.normal); end

    # Casts right now instead of waiting for the next physics step. Returns the hit.
    def update_cast : Physics2D::RayHit?
      origin = global_position
      to = to_global(@target)
      excl = @exclude_parent ? parent_2d.as?(CollisionObject2D).try(&.body) : nil
      @hit = Physics2D.world.raycast(origin, to - origin, (to - origin).length, @mask, excl)
    end

    # Casts the ray. Called by the engine.
    def physics_process(dt : Float32) : Nil
      update_cast
    end
  end
end
