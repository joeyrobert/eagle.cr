module Eagle
  # Base for 3D physics nodes.
  abstract class CollisionObject3D < Node3D
    getter body : Physics3D::Body
    property world : Physics3D::World
    property? debug = false
    @begin_handler : Proc(Physics3D::Body, Physics3D::Body, Nil)? = nil
    @end_handler : Proc(Physics3D::Body, Physics3D::Body, Nil)? = nil

    signal body_entered(other : CollisionObject3D)
    signal body_exited(other : CollisionObject3D)

    def initialize(type : Physics3D::BodyType, name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(name, position)
      @world = Physics3D.world
      @body = Physics3D::Body.new(type, position, shape)
      @body.owner = self
    end

    def add_shape(s : Physics3D::Shape) : self; @body.add_shape(s); self; end
    def sphere(radius : Number, offset : Vec3 = Vec3::ZERO) : self; add_shape(Physics3D::Sphere.new(radius, offset)); end
    def box(size : Vec3, offset : Vec3 = Vec3::ZERO) : self; add_shape(Physics3D::Cuboid.new(size, offset)); end
    def box(w : Number, h : Number, d : Number) : self; box(Vec3.new(w, h, d)); end
    def layer : UInt32; @body.layer; end
    def layer=(v : UInt32); @body.layer = v; end
    def mask : UInt32; @body.mask; end
    def mask=(v : UInt32); @body.mask = v; end

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

    private def on_contact(a, b, began)
      other = a == @body ? b : (b == @body ? a : nil)
      return unless other
      if (o = other.owner).is_a?(CollisionObject3D)
        began ? emit_body_entered(o) : emit_body_exited(o)
      end
    end

    def overlapping : Array(CollisionObject3D)
      @body.contacts.compact_map { |b| b.owner.as?(CollisionObject3D) }
    end

    def push_transform : Nil
      @body.position = global_position
      @body.rotation = global_rotation
      @body.update_world_shapes
    end

    def pull_transform : Nil
      self.global_position = @body.position
      @rotation = if (p = parent_3d) && !@top_level
                    (p.global_rotation.inverse * @body.rotation).normalized
                  else
                    @body.rotation
                  end
    end

    def physics_process(dt : Float32) : Nil
      @body.dynamic? ? pull_transform : push_transform
    end

    # Debug wireframes via Scene3D debug lines.
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

  class StaticBody3D < CollisionObject3D
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Static, name, position, shape)
    end
  end

  class RigidBody3D < CollisionObject3D
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Dynamic, name, position, shape)
    end

    def velocity : Vec3; @body.velocity; end
    def velocity=(v : Vec3); @body.velocity = v; end
    def angular_velocity : Vec3; @body.angular_velocity; end
    def angular_velocity=(v : Vec3); @body.angular_velocity = v; end
    def mass : Float32; @body.mass; end
    def mass=(m : Number); @body.mass = m; end
    def restitution=(r : Number); @body.restitution = r.to_f32; end
    def friction=(f : Number); @body.friction = f.to_f32; end
    def gravity_scale=(s : Number); @body.gravity_scale = s.to_f32; end
    def fixed_rotation=(v : Bool); @body.fixed_rotation = v; end
    def apply_force(f : Vec3, point : Vec3? = nil); @body.apply_force(f, point); end
    def apply_impulse(i : Vec3, point : Vec3? = nil); @body.apply_impulse(i, point); end
    def apply_torque(t : Vec3); @body.apply_torque(t); end
  end

  class KinematicBody3D < CollisionObject3D
    property velocity : Vec3 = Vec3::ZERO
    getter? on_floor = false
    getter? on_wall = false
    getter? on_ceiling = false
    getter floor_normal : Vec3 = Vec3::ZERO
    property up_direction : Vec3 = Vec3::UP
    property floor_max_angle : Float32 = Mathf.deg2rad(46)
    property floor_snap : Float32 = 0.1_f32

    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Kinematic, name, position, shape)
    end

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

    def physics_process(dt : Float32) : Nil; push_transform; end
  end

  alias CharacterBody3D = KinematicBody3D

  class Area3D < CollisionObject3D
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, shape : Physics3D::Shape? = nil)
      super(Physics3D::BodyType::Kinematic, name, position, shape)
      @body.sensor = true
    end

    def bodies : Array(CollisionObject3D); overlapping; end
  end

  class RayCast3D < Node3D
    property target : Vec3
    property mask : UInt32 = 0xFFFFFFFF_u32
    property? exclude_parent = true
    getter hit : Physics3D::RayHit? = nil

    def initialize(@target : Vec3 = Vec3.new(0, -1, 0), name : String = "")
      super(name)
    end

    def colliding? : Bool; !@hit.nil?; end
    def collider : CollisionObject3D?; @hit.try(&.body.owner.as?(CollisionObject3D)); end
    def collision_point : Vec3?; @hit.try(&.point); end
    def collision_normal : Vec3?; @hit.try(&.normal); end

    def update_cast : Physics3D::RayHit?
      origin = global_position
      to = to_global(@target)
      excl = @exclude_parent ? parent_3d.as?(CollisionObject3D).try(&.body) : nil
      @hit = Physics3D.world.raycast(origin, to - origin, (to - origin).length, @mask, excl)
    end

    def physics_process(dt : Float32) : Nil; update_cast; end
  end
end
