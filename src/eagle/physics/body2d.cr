module Eagle
  module Physics2D
    # How a body moves: `Static` never moves, `Kinematic` is moved by code, and `Dynamic`
    # is moved by the simulation.
    enum BodyType
      # Never moves: floors and walls.
      Static
      # Moved by your code, pushes dynamic bodies, ignores forces.
      Kinematic
      # Moved by the simulation: gravity, collisions and forces.
      Dynamic
    end

    # A physics body: position, velocity, mass and one or more shapes.
    #
    # The physics nodes create bodies for you. Use `Body` directly with a `World` when you
    # don't need nodes.
    class Body
      # Static, kinematic or dynamic.
      property type : BodyType
      # World-space position of the body's origin.
      property position : Vec2
      # Rotation in radians.
      property rotation : Float32 = 0_f32
      # Linear velocity in pixels per second.
      property velocity : Vec2 = Vec2::ZERO
      # Spin in radians per second.
      property angular_velocity : Float32 = 0_f32
      # Force accumulated for the next step. It is cleared after every step.
      property force : Vec2 = Vec2::ZERO
      # Torque accumulated for the next step. It is cleared after every step.
      property torque : Float32 = 0_f32
      # Bounciness from 0 to 1.
      property restitution : Float32 = 0_f32
      # Surface grip. Contact friction combines both bodies' values.
      property friction : Float32 = 0.5_f32
      # Multiplies the world's gravity for this body.
      property gravity_scale : Float32 = 1_f32
      # Drag on linear velocity.
      property linear_damping : Float32 = 0_f32
      # Drag on spin.
      property angular_damping : Float32 = 0_f32
      # Prevents rotation.
      property? fixed_rotation = false
      # Sensors report overlaps but don't collide.
      property? sensor = false
      # Bits for the layers this body is on. A pair collides when
      # `(a.layer & b.mask) != 0 && (b.layer & a.mask) != 0`.
      property layer : UInt32 = 1_u32
      # Bits for the layers this body collides with.
      property mask : UInt32 = 0xFFFFFFFF_u32
      # Disabled bodies are skipped by the simulation and by queries.
      property? enabled = true
      # The node that owns this body, if any. Physics nodes set it.
      property owner : Node? = nil
      # A free-form label for your own bookkeeping.
      property tag : String = ""
      # Shapes in local space.
      getter shapes = [] of Shape
      # Mass, computed from shapes and density unless set directly.
      getter mass : Float32 = 1_f32
      # 1 / mass, or 0 for static and kinematic bodies.
      getter inv_mass : Float32 = 1_f32
      # Rotational inertia.
      getter inertia : Float32 = 1_f32
      # 1 / inertia, or 0 when rotation is fixed.
      getter inv_inertia : Float32 = 1_f32
      # Shapes transformed into world space for the current step.
      getter world_shapes = [] of Shape
      # World-space bounds of all shapes.
      getter aabb : Rect = Rect.new
      # A unique id.
      getter id : Int32
      # Mass per unit area, used to compute mass from shapes.
      property density : Float32 = 1_f32
      # Bodies touching this one after the last step.
      getter contacts = Set(Body).new
      @@next_id = 0

      # Creates a body, optionally with a first shape.
      def initialize(@type : BodyType = BodyType::Dynamic, @position : Vec2 = Vec2::ZERO, shape : Shape? = nil)
        @id = (@@next_id += 1)
        add_shape(shape) if shape
        update_mass
      end

      # True for static bodies.
      def static? : Bool; @type.static?; end
      # True for dynamic bodies.
      def dynamic? : Bool; @type.dynamic?; end
      # True for kinematic bodies.
      def kinematic? : Bool; @type.kinematic?; end

      # Adds a shape and recomputes mass. Returns the shape.
      def add_shape(s : Shape) : Shape
        @shapes << s
        update_mass
        s
      end

      # Removes a shape and recomputes mass.
      def remove_shape(s : Shape) : Nil
        @shapes.delete(s)
        update_mass
      end

      # Sets the mass directly, scaling inertia to match.
      def mass=(m : Number)
        @mass = m.to_f32
        @inv_mass = @mass > 0 && dynamic? ? 1 / @mass : 0_f32
        recompute_inertia
      end

      # Sets the density and recomputes mass from the shapes.
      def density=(d : Number)
        @density = d.to_f32
        update_mass
      end

      # :nodoc:
      def update_mass : Nil
        if dynamic?
          area = @shapes.sum(&.area)
          @mass = area > 0 ? Math.max(area * @density * 0.001_f32, 0.01_f32) : 1_f32
          @inv_mass = 1 / @mass
        else
          @mass = 0_f32; @inv_mass = 0_f32
        end
        recompute_inertia
      end

      private def recompute_inertia
        if dynamic? && !@fixed_rotation && !@shapes.empty?
          @inertia = @shapes.sum { |s| @mass * (s.inertia_factor + s.offset.length_squared) } / @shapes.size
          @inv_inertia = @inertia > 0 ? 1 / @inertia : 0_f32
        else
          @inertia = 0_f32; @inv_inertia = 0_f32
        end
      end

      # Enables or disables rotation.
      def fixed_rotation=(v : Bool)
        @fixed_rotation = v
        recompute_inertia
      end

      # Changes the body type and recomputes mass.
      def type=(t : BodyType)
        @type = t
        update_mass
      end

      # The body's transform.
      def transform : Transform2D; Transform2D.trs(@position, @rotation, Vec2::ONE); end

      # Adds a force for the next step, at a world-space *point* if given.
      def apply_force(f : Vec2, point : Vec2? = nil) : Nil
        @force += f
        @torque += (point - @position).cross(f) if point
      end

      # Changes velocity instantly, at a world-space *point* if given.
      def apply_impulse(i : Vec2, point : Vec2? = nil) : Nil
        @velocity += i * @inv_mass
        @angular_velocity += (point - @position).cross(i) * @inv_inertia if point
      end

      # Adds torque for the next step.
      def apply_torque(t : Number) : Nil; @torque += t; end

      # Velocity of a world-space point on the body, including spin.
      def velocity_at(point : Vec2) : Vec2
        r = point - @position
        @velocity + Vec2.new(-@angular_velocity * r.y, @angular_velocity * r.x)
      end

      # :nodoc:
      def update_world_shapes : Nil
        t = transform
        @world_shapes.clear
        @shapes.each { |s| @world_shapes << s.transformed(t) }
        first = true
        r = Rect.new
        @world_shapes.each do |s|
          sa = s.aabb
          r = first ? sa : r.union(sa)
          first = false
        end
        @aabb = r
      end

      # Yields each world-space shape.
      def each_world_shape(& : Shape ->) : Nil
        @world_shapes.each { |s| yield s }
      end

      # True when a world-space point is inside any of the shapes.
      def contains_point?(p : Vec2) : Bool
        @world_shapes.any? do |s|
          case s
          when Circle then s.contains?(p)
          when Polygon then s.contains?(p)
          else false
          end
        end
      end

      # True when the layer and mask bits allow these two bodies to collide.
      def collides_with?(o : Body) : Bool
        (@layer & o.mask) != 0 && (o.layer & @mask) != 0
      end

      def to_s(io : IO) : Nil
        io << "Body#" << @id << "(" << @type << " " << @position << ")"
      end
    end
  end
end
