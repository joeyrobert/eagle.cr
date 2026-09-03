module Eagle
  # A node with a 3D transform (position, rotation quaternion, scale).
  class Node3D < Node
    property position : Vec3 = Vec3::ZERO
    property rotation : Quat = Quat::IDENTITY
    property scale : Vec3 = Vec3::ONE
    property? top_level = false

    def initialize(name : String = "", @position = Vec3::ZERO, @rotation = Quat::IDENTITY, @scale = Vec3::ONE)
      super(name)
    end

    def scale=(s : Number); @scale = Vec3.new(s); end
    def scale=(s : Vec3); @scale = s; end

    # Euler angles (pitch, yaw, roll) in radians.
    def euler : Vec3; @rotation.to_euler; end
    def euler=(e : Vec3); @rotation = Quat.from_euler(e); end
    def set_euler(pitch : Number, yaw : Number, roll : Number = 0) : self
      @rotation = Quat.from_euler(pitch, yaw, roll)
      self
    end

    def rotate(axis : Vec3, rad : Number) : Nil; @rotation = (Quat.from_axis_angle(axis, rad) * @rotation).normalized; end
    def rotate_x(rad : Number) : Nil; rotate(Vec3::RIGHT, rad); end
    def rotate_y(rad : Number) : Nil; rotate(Vec3::UP, rad); end
    def rotate_z(rad : Number) : Nil; rotate(Vec3::BACK, rad); end
    # Rotate around a local axis.
    def rotate_local(axis : Vec3, rad : Number) : Nil; @rotation = (@rotation * Quat.from_axis_angle(axis, rad)).normalized; end
    def translate(v : Vec3) : Nil; @position += v; end
    # Move along local axes.
    def translate_local(v : Vec3) : Nil; @position += @rotation * v; end

    def transform : Mat4; Mat4.trs(@position, @rotation, @scale); end

    def global_transform : Mat4
      return transform if @top_level
      (p = parent_3d) ? p.global_transform * transform : transform
    end

    def global_position : Vec3; global_transform.translation; end

    def global_position=(p : Vec3)
      if (par = parent_3d) && !@top_level
        @position = par.global_transform.inverse.transform_point(p)
      else
        @position = p
      end
    end

    def global_rotation : Quat
      (p = parent_3d) && !@top_level ? (p.global_rotation * @rotation).normalized : @rotation
    end

    def parent_3d : Node3D?
      p = @parent
      while p
        return p if p.is_a?(Node3D)
        p = p.parent
      end
      nil
    end

    def forward : Vec3; global_rotation * Vec3::FORWARD; end
    def back : Vec3; -forward; end
    def up : Vec3; global_rotation * Vec3::UP; end
    def right : Vec3; global_rotation * Vec3::RIGHT; end

    def look_at(target : Vec3, up : Vec3 = Vec3::UP) : Nil
      dir = target - global_position
      return if dir.length_squared < 1e-10
      q = Quat.look_rotation(dir, up)
      if (p = parent_3d) && !@top_level
        @rotation = (p.global_rotation.inverse * q).normalized
      else
        @rotation = q
      end
    end

    def to_local(global : Vec3) : Vec3; global_transform.inverse.transform_point(global); end
    def to_global(local : Vec3) : Vec3; global_transform.transform_point(local); end
    def distance_to(o : Node3D) : Float32; global_position.distance(o.global_position); end

    # 3D nodes don't draw in the 2D pass, but children still may.
    def draw_tree(g : Graphics) : Nil
      return unless @visible
      draw(g)
      draw_children(g)
    end
  end

  # Draws a Mesh with a Material at the node's transform.
  class MeshInstance3D < Node3D
    property mesh : Mesh?
    property material : Material
    property? cast_shadows = true

    def initialize(mesh : Mesh? = nil, material : Material? = nil, name : String = "", position : Vec3 = Vec3::ZERO)
      super(name, position)
      @mesh = mesh
      @material = material || Material.new
    end

    def self.load(path : String, material : Material? = nil) : MeshInstance3D
      new(Mesh.load(path), material)
    end

    # World-space bounds.
    def global_bounds : AABB?
      @mesh.try(&.bounds.transformed(global_transform))
    end

    def draw_item : DrawItem?
      m = @mesh
      return nil unless m
      DrawItem.new(m, @material, global_transform)
    end
  end

  # Perspective (or orthographic) camera. `current` cameras render the tree.
  class Camera3D < Node3D
    property fov : Float32 = Mathf.deg2rad(60)
    property near : Float32 = 0.1_f32
    property far : Float32 = 500_f32
    property? orthographic = false
    # Half-height of the view in world units when orthographic.
    property ortho_size : Float32 = 5_f32
    getter? current = false
    @@current : Camera3D? = nil

    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, fov : Number = 60, current : Bool = false)
      super(name, position)
      @fov = Mathf.deg2rad(fov)
      make_current if current
    end

    def self.current : Camera3D?; @@current; end
    def self.current=(c : Camera3D?)
      @@current.try(&.clear_current)
      @@current = c
      c.try(&.set_current)
    end
    # :nodoc:
    def self.reset; @@current = nil; end

    def make_current : self; Camera3D.current = self; self; end
    protected def set_current; @current = true; end
    protected def clear_current; @current = false; end

    def enter_tree : Nil
      make_current if Camera3D.current.nil?
    end

    def exit_tree : Nil
      Camera3D.current = nil if Camera3D.current == self
    end

    def fov_degrees : Float32; Mathf.rad2deg(@fov); end
    def fov_degrees=(d : Number); @fov = Mathf.deg2rad(d); end

    def view : Mat4; global_transform.inverse; end

    def projection(aspect : Number) : Mat4
      if @orthographic
        h = @ortho_size; w = h * aspect
        Mat4.orthographic(-w, w, -h, h, @near, @far)
      else
        Mat4.perspective(@fov, aspect, @near, @far)
      end
    end

    def camera_view(aspect : Number) : CameraView
      CameraView.new(view, projection(aspect), global_position)
    end

    # World-space ray through a screen point (viewport size defaults to the window).
    def screen_to_ray(screen : Vec2, viewport : Vec2 = Window.size) : Ray
      ndc = Vec2.new(screen.x / viewport.x * 2 - 1, 1 - screen.y / viewport.y * 2)
      inv = (projection(viewport.x / viewport.y) * view).inverse
      near_p = inv.transform_point(Vec3.new(ndc.x, ndc.y, -1))
      far_p = inv.transform_point(Vec3.new(ndc.x, ndc.y, 1))
      Ray.new(near_p, far_p - near_p)
    end

    # Project a world point to screen space; nil if behind the camera.
    def world_to_screen(p : Vec3, viewport : Vec2 = Window.size) : Vec2?
      clip = projection(viewport.x / viewport.y) * view * p.to_vec4(1)
      return nil if clip.w <= 0
      ndc = clip.homogenized
      Vec2.new((ndc.x + 1) / 2 * viewport.x, (1 - ndc.y) / 2 * viewport.y)
    end

    def mouse_ray : Ray; screen_to_ray(Input.mouse); end

    # Simple free-fly controls: WASD/QE + right-mouse or arrow-key look.
    def fly(dt : Float32, speed : Number = 6, look_speed : Number = 0.003) : Nil
      move = Vec3::ZERO
      move += Vec3::FORWARD if Input.down?(Key::W)
      move += Vec3::BACK if Input.down?(Key::S)
      move += Vec3::LEFT if Input.down?(Key::A)
      move += Vec3::RIGHT if Input.down?(Key::D)
      move += Vec3::UP if Input.down?(Key::E) || Input.down?(Key::Space)
      move += Vec3::DOWN if Input.down?(Key::Q) || Input.down?(Key::LShift)
      spd = speed.to_f32 * (Input.down?(Key::LCtrl) ? 3 : 1)
      translate_local(move.normalized * spd * dt) unless move.zero?
      yaw = 0_f32; pitch = 0_f32
      if Input.mouse_down?(MouseButton::Right)
        d = Input.mouse_delta
        yaw = -d.x * look_speed; pitch = -d.y * look_speed
      end
      yaw += dt * 1.5 if Input.down?(Key::Left)
      yaw -= dt * 1.5 if Input.down?(Key::Right)
      pitch += dt * 1.0 if Input.down?(Key::Up)
      pitch -= dt * 1.0 if Input.down?(Key::Down)
      if g = Input.gamepad
        rs = g.right_stick
        yaw -= rs.x * dt * 2; pitch -= rs.y * dt * 2
        ls = g.left_stick
        translate_local(Vec3.new(ls.x, 0, ls.y) * spd * dt)
      end
      if yaw != 0 || pitch != 0
        e = euler
        e = Vec3.new((e.x + pitch).clamp(-1.55_f32, 1.55_f32), e.y + yaw, 0)
        self.euler = e
      end
    end
  end

  abstract class Light3D < Node3D
    property color : Color = Color::WHITE
    property intensity : Float32 = 1_f32
    property? enabled = true
    abstract def light_data : LightData
  end

  class DirectionalLight3D < Light3D
    property? shadows = true

    def initialize(direction : Vec3 = Vec3.new(-0.5, -1, -0.3), color : Color = Color::WHITE, intensity : Number = 1, name : String = "")
      super(name)
      self.color = color; self.intensity = intensity.to_f32
      look_at(direction)
    end

    def direction : Vec3; forward; end
    def direction=(d : Vec3); look_at(global_position + d); end

    def light_data : LightData
      LightData.directional(forward, @color, @intensity, @shadows)
    end
  end

  class PointLight3D < Light3D
    property range : Float32 = 10_f32

    def initialize(position : Vec3 = Vec3::ZERO, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10, name : String = "")
      super(name, position)
      self.color = color; self.intensity = intensity.to_f32; @range = range.to_f32
    end

    def light_data : LightData
      LightData.point(global_position, @color, @intensity, @range)
    end
  end

  class SpotLight3D < Light3D
    property range : Float32 = 10_f32
    property angle : Float32 = 0.6_f32
    property softness : Float32 = 0.1_f32

    def initialize(position : Vec3 = Vec3::ZERO, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10, angle : Number = 0.6, softness : Number = 0.1, name : String = "")
      super(name, position)
      self.color = color; self.intensity = intensity.to_f32; @range = range.to_f32; @angle = angle.to_f32; @softness = softness.to_f32
    end

    def light_data : LightData
      LightData.spot(global_position, forward, @color, @intensity, @range, @angle, @softness)
    end
  end

  # Collects MeshInstance3D/Light3D nodes from a tree and renders them.
  module Scene3D
    @@renderer : Renderer3D? = nil
    @@environment = Environment.new

    def self.environment : Environment; @@environment; end
    def self.environment=(e : Environment); @@environment = e; renderer.environment = e; end

    def self.renderer : Renderer3D
      @@renderer ||= Renderer3D.new(@@environment)
    end

    # :nodoc:
    def self.reset : Nil
      @@renderer.try(&.dispose)
      @@renderer = nil
      @@environment = Environment.new
      Camera3D.reset
    end

    def self.collect(root : Node) : {Array(DrawItem), Array(LightData)}
      items = [] of DrawItem
      lights = [] of LightData
      collect_into(root, items, lights)
      {items, lights}
    end

    private def self.collect_into(node : Node, items, lights)
      node.children.each do |c|
        next unless c.visible?
        case c
        when MeshInstance3D
          if di = c.draw_item
            items << di
          end
        when Light3D
          lights << c.light_data if c.enabled?
        end
        collect_into(c, items, lights)
      end
    end

    # Render the tree from `camera` into the current target.
    def self.render(root : Node = SceneTree.root, camera : Camera3D? = Camera3D.current, target_size : Vec2 = Window.size, flip_y : Bool = false, clear : Bool = true) : Nil
      cam = camera
      return unless cam
      items, lights = collect(root)
      renderer.render(cam.camera_view(target_size.x / target_size.y), items, lights, target_size, flip_y, clear)
    end
  end
end
