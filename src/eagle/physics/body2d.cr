module Eagle
  module Physics2D
    enum BodyType
      Static
      Kinematic
      Dynamic
    end

    # A rigid body. Create via `World#add_body` or through the physics nodes.
    class Body
      property type : BodyType
      property position : Vec2
      property rotation : Float32 = 0_f32
      property velocity : Vec2 = Vec2::ZERO
      property angular_velocity : Float32 = 0_f32
      property force : Vec2 = Vec2::ZERO
      property torque : Float32 = 0_f32
      property restitution : Float32 = 0_f32
      property friction : Float32 = 0.5_f32
      property gravity_scale : Float32 = 1_f32
      property linear_damping : Float32 = 0_f32
      property angular_damping : Float32 = 0_f32
      property? fixed_rotation = false
      # Sensors detect overlaps but don't collide.
      property? sensor = false
      # Bit masks: a pair collides when (a.layer & b.mask) != 0 && (b.layer & a.mask) != 0
      property layer : UInt32 = 1_u32
      property mask : UInt32 = 0xFFFFFFFF_u32
      property? enabled = true
      # Arbitrary owner (the physics node uses this).
      property owner : Node? = nil
      property tag : String = ""
      getter shapes = [] of Shape
      getter mass : Float32 = 1_f32
      getter inv_mass : Float32 = 1_f32
      getter inertia : Float32 = 1_f32
      getter inv_inertia : Float32 = 1_f32
      getter world_shapes = [] of Shape
      getter aabb : Rect = Rect.new
      getter id : Int32
      property density : Float32 = 1_f32
      # Bodies currently touching (updated each step).
      getter contacts = Set(Body).new
      @@next_id = 0

      def initialize(@type : BodyType = BodyType::Dynamic, @position : Vec2 = Vec2::ZERO, shape : Shape? = nil)
        @id = (@@next_id += 1)
        add_shape(shape) if shape
        update_mass
      end

      def static? : Bool; @type.static?; end
      def dynamic? : Bool; @type.dynamic?; end
      def kinematic? : Bool; @type.kinematic?; end

      def add_shape(s : Shape) : Shape
        @shapes << s
        update_mass
        s
      end

      def remove_shape(s : Shape) : Nil
        @shapes.delete(s)
        update_mass
      end

      def mass=(m : Number)
        @mass = m.to_f32
        @inv_mass = @mass > 0 && dynamic? ? 1 / @mass : 0_f32
        recompute_inertia
      end

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

      def fixed_rotation=(v : Bool)
        @fixed_rotation = v
        recompute_inertia
      end

      def type=(t : BodyType)
        @type = t
        update_mass
      end

      def transform : Transform2D; Transform2D.trs(@position, @rotation, Vec2::ONE); end

      def apply_force(f : Vec2, point : Vec2? = nil) : Nil
        @force += f
        @torque += (point - @position).cross(f) if point
      end

      def apply_impulse(i : Vec2, point : Vec2? = nil) : Nil
        @velocity += i * @inv_mass
        @angular_velocity += (point - @position).cross(i) * @inv_inertia if point
      end

      def apply_torque(t : Number) : Nil; @torque += t; end

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

      def each_world_shape(& : Shape ->) : Nil
        @world_shapes.each { |s| yield s }
      end

      def contains_point?(p : Vec2) : Bool
        @world_shapes.any? do |s|
          case s
          when Circle then s.contains?(p)
          when Polygon then s.contains?(p)
          else false
          end
        end
      end

      def collides_with?(o : Body) : Bool
        (@layer & o.mask) != 0 && (o.layer & @mask) != 0
      end

      def to_s(io : IO) : Nil
        io << "Body#" << @id << "(" << @type << " " << @position << ")"
      end
    end
  end
end
