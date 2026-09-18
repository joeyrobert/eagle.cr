module Eagle
  # Base class for 3D physics nodes. It owns a `Physics3D::Body` in `Physics3D.world` and keeps
  # the node's transform and the body in sync. It works like `CollisionObject2D`, with spheres
  # and boxes as shapes and units in meters.
  #
  # ```
  # floor = StaticBody3D.new(position: v3(0, -0.5, 0)).box(20, 1, 20)
  # ball = RigidBody3D.new(position: v3(0, 5, 0)).sphere(0.5)
  # ball.restitution = 0.5
  # SceneTree.root.add(floor, ball)
  # ```
  abstract class CollisionObject3D < Node3D
    # The underlying physics body.
    getter body : Physics3D::Body
    # The physics world the body lives in. Defaults to `Physics3D.world`.
    property world : Physics3D::World
    # Draws the body's shapes as wireframes.
    property? debug = false
    @begin_handler : Proc(Physics3D::Body, Physics3D::Body, Nil)? = nil
    @end_handler : Proc(Physics3D::Body, Physics3D::Body, Nil)? = nil

    # Emitted when another collision object starts touching or overlapping this one.
    # Connect with `on_body_entered { |other| ... }`.
    signal body_entered(other : CollisionObject3D)
    # Emitted when another collision object stops touching or overlapping this one.
    signal body_exited(other : CollisionObject3D)

    # Creates the node and its body.
    def initialize(type : Physics3D::BodyType, name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(name, position)
      @world = Physics3D.world
      @body = Physics3D::Body.new(type, position, shape)
      @body.owner = self
    end

    # Adds a raw `Physics3D::Shape`. Returns self.
    def add_shape(s : Physics3D::Shape) : self; @body.add_shape(s); self; end
    # Adds a sphere shape. Returns self, so it chains after `new`.
    def sphere(radius : Number, offset : Vec3 = Vec3::ZERO) : self; add_shape(Physics3D::Sphere.new(radius, offset)); end
    # Adds a box shape of *size*. Returns self.
    def box(size : Vec3, offset : Vec3 = Vec3::ZERO) : self; add_shape(Physics3D::Cuboid.new(size, offset)); end
    # Adds a *w* by *h* by *d* box. Returns self.
    def box(w : Number, h : Number, d : Number) : self; box(Vec3.new(w, h, d)); end
    # The layer bits this object is on.
    def layer : UInt32; @body.layer; end
    # Sets the layer bits.
    def layer=(v : UInt32); @body.layer = v; end
    # The layer bits this object collides with.
    def mask : UInt32; @body.mask; end
    # Sets the mask bits.
    def mask=(v : UInt32); @body.mask = v; end

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

    private def on_contact(a, b, began)
      other = a == @body ? b : (b == @body ? a : nil)
      return unless other
      if (o = other.owner).is_a?(CollisionObject3D)
        began ? emit_body_entered(o) : emit_body_exited(o)
      end
    end

    # Every collision object currently touching or overlapping this one.
    def overlapping : Array(CollisionObject3D)
      @body.contacts.compact_map { |b| b.owner.as?(CollisionObject3D) }
    end

    # Copies the node's global transform onto the body.
    def push_transform : Nil
      @body.position = global_position
      @body.rotation = global_rotation
      @body.update_world_shapes
    end

    # Copies the body's transform onto the node.
    def pull_transform : Nil
      self.global_position = @body.position
      @rotation = if (p = parent_3d) && !@top_level
                    (p.global_rotation.inverse * @body.rotation).normalized
                  else
                    @body.rotation
                  end
    end

    # Syncs the node and the body after each physics step.
    def physics_process(dt : Float32) : Nil
      @body.dynamic? ? pull_transform : push_transform
    end

    # Draws debug wireframes when `debug` is on.
    def process(dt : Float32) : Nil
      return unless @debug
      c = @body.sensor? ? Color.new(0, 0.6, 1) : (@body.dynamic? ? Color.new(0.2, 1, 0.4) : Color.gray(0.7))
      @body.world_shapes.each do |ws|
        case (s = ws.shape)
        when Physics3D::Sphere then Scene3D.debug_sphere(ws.center, s.radius, c)
        when Physics3D::Cuboid then Scene3D.debug_box(ws.center, s.half, ws.rotation, c)
        end
      end
    end
  end

  # A 3D body that never moves: floors, walls and level geometry.
  class StaticBody3D < CollisionObject3D
    # Creates a static body.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Static, name, position, shape)
    end
  end

  # A 3D body moved by the simulation. Push it with forces and impulses.
  #
  # ```
  # crate = RigidBody3D.new(position: v3(0, 3, 0)).box(1, 1, 1)
  # crate.apply_impulse(v3(0, 4, -2))
  # ```
  class RigidBody3D < CollisionObject3D
    # Creates a dynamic body.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Dynamic, name, position, shape)
    end

    # Linear velocity in meters per second.
    def velocity : Vec3; @body.velocity; end
    # Sets the linear velocity.
    def velocity=(v : Vec3); @body.velocity = v; end
    # Spin as an axis scaled by radians per second.
    def angular_velocity : Vec3; @body.angular_velocity; end
    # Sets the spin.
    def angular_velocity=(v : Vec3); @body.angular_velocity = v; end
    # Mass.
    def mass : Float32; @body.mass; end
    # Sets the mass.
    def mass=(m : Number); @body.mass = m; end
    # Bounciness from 0 to 1.
    def restitution=(r : Number); @body.restitution = r.to_f32; end
    # Surface grip from 0 (ice) upward.
    def friction=(f : Number); @body.friction = f.to_f32; end
    # Multiplies gravity for this body.
    def gravity_scale=(s : Number); @body.gravity_scale = s.to_f32; end
    # Stops the body from rotating.
    def fixed_rotation=(v : Bool); @body.fixed_rotation = v; end
    # Pushes continuously during the next step, at *point* if given.
    def apply_force(f : Vec3, point : Vec3? = nil); @body.apply_force(f, point); end
    # Changes velocity instantly, at *point* if given.
    def apply_impulse(i : Vec3, point : Vec3? = nil); @body.apply_impulse(i, point); end
    # Spins the body during the next step.
    def apply_torque(t : Vec3); @body.apply_torque(t); end
  end

  # A 3D body moved from code that slides along obstacles: first- and third-person
  # characters and moving platforms.
  #
  # ```
  # class Walker < KinematicBody3D
  #   def ready : Nil
  #     box(0.6, 1.8, 0.6)
  #   end
  #
  #   def physics_process(dt : Float32) : Nil
  #     input = Input.vector("left", "right", "up", "down")
  #     self.velocity = v3(input.x * 5, velocity.y - 20 * dt, input.y * 5)
  #     self.velocity = v3(velocity.x, 8, velocity.z) if on_floor? && Input.pressed?("jump")
  #     move_and_slide(dt)
  #   end
  # end
  # ```
  class KinematicBody3D < CollisionObject3D
    # Velocity in meters per second, used by `move_and_slide`.
    property velocity : Vec3 = Vec3::ZERO
    # True when the last move ended on a floor.
    getter? on_floor = false
    # True when the last move hit a wall.
    getter? on_wall = false
    # True when the last move hit a ceiling.
    getter? on_ceiling = false
    # The normal of the floor under the body.
    getter floor_normal : Vec3 = Vec3::ZERO
    # Which way is up, used to tell floors from ceilings.
    property up_direction : Vec3 = Vec3::UP
    # Steepest slope that still counts as floor, in radians.
    property floor_max_angle : Float32 = Mathf.deg2rad(46)
    # How far below the body to look for ground each move.
    property floor_snap : Float32 = 0.1_f32

    # Creates a kinematic body.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Kinematic, name, position, shape)
    end

    # Moves by `velocity * dt`, sliding along obstacles, and updates the floor, wall and
    # ceiling flags. Returns the new velocity.
    def move_and_slide(dt : Float32, velocity : Vec3? = nil) : Vec3
      @velocity = velocity if velocity
      push_transform
      normals = @world.move_and_slide(@body, @velocity * dt)
      @on_floor = @on_wall = @on_ceiling = false
      @floor_normal = Vec3::ZERO
      normals.each do |n|
        d = n.dot(@up_direction)
        if d >= Math.cos(@floor_max_angle)
          @on_floor = true; @floor_normal = n
        elsif d <= -Math.cos(@floor_max_angle)
          @on_ceiling = true
        else
          @on_wall = true
        end
        vn = @velocity.dot(n)
        @velocity -= n * vn if vn < 0
      end
      if !@on_floor && @floor_snap > 0 && @velocity.dot(@up_direction) <= 0
        if n = @world.probe_floor(@body, @up_direction, @floor_snap, @floor_max_angle)
          @on_floor = true; @floor_normal = n
        end
      end
      self.global_position = @body.position
      @velocity
    end

    # Keeps the body in sync with the node.
    def physics_process(dt : Float32) : Nil; push_transform; end
  end

  # Godot 4's name for `KinematicBody3D`.
  alias CharacterBody3D = KinematicBody3D

  # A 3D region that detects overlaps without blocking: triggers, pickups and kill planes.
  class Area3D < CollisionObject3D
    # Creates an area.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Kinematic, name, position, shape)
      @body.sensor = true
    end

    # Everything currently inside the area.
    def bodies : Array(CollisionObject3D); overlapping; end
  end

  # Casts a ray from the node toward `target` every physics step. Use it for ground checks,
  # line of sight and hit-scan weapons.
  class RayCast3D < Node3D
    # End of the ray in local space.
    property target : Vec3
    # Layers the ray can hit.
    property mask : UInt32 = 0xFFFFFFFF_u32
    # Ignores the parent body.
    property? exclude_parent = true
    # The last hit, or `nil`.
    getter hit : Physics3D::RayHit? = nil

    # Creates a ray ending at *target*, in local space.
    def initialize(@target : Vec3 = Vec3.new(0, -1, 0), name : String = "")
      super(name)
    end

    # True when the last cast hit something.
    def colliding? : Bool; !@hit.nil?; end
    # The collision object that was hit, if any.
    def collider : CollisionObject3D?; @hit.try(&.body.owner.as?(CollisionObject3D)); end
    # Where the ray hit, in world space.
    def collision_point : Vec3?; @hit.try(&.point); end
    # The surface normal at the hit.
    def collision_normal : Vec3?; @hit.try(&.normal); end

    # Casts right now. Returns the hit.
    def update_cast : Physics3D::RayHit?
      origin = global_position
      to = to_global(@target)
      excl = @exclude_parent ? parent_3d.as?(CollisionObject3D).try(&.body) : nil
      @hit = Physics3D.world.raycast(origin, to - origin, (to - origin).length, @mask, excl)
    end

    # Casts the ray. Called by the engine.
    def physics_process(dt : Float32) : Nil; update_cast; end
  end
end
