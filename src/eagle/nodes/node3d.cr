module Eagle
  # A node with a 3D position, rotation and scale. It is the base of every 3D object.
  #
  # As in 2D, children move with their parent. Rotation is a `Quat`, but you rarely touch
  # it directly: `rotate_y`, `look_at`, `euler=` and `set_euler` cover most needs.
  #
  # ```
  # class Spinner < Node3D
  #   def ready : Nil
  #     add(MeshInstance3D.new(Mesh.cube, Material.new(Color::ORANGE)))
  #   end
  #
  #   def process(dt : Float32) : Nil
  #     rotate_y(dt)                         # turn around the world's up axis
  #     translate_local(Vec3::FORWARD * dt)  # move the way it faces
  #   end
  # end
  #
  # s = Spinner.new
  # s.position = v3(0, 1, 0)
  # s.set_euler(0, Mathf.deg2rad(45), 0)
  # s.look_at(v3(5, 1, 0))
  # ```
  class Node3D < Node
    # Position relative to the parent.
    property position : Vec3 = Vec3::ZERO
    # Orientation relative to the parent.
    property rotation : Quat = Quat::IDENTITY
    # Scale relative to the parent.
    property scale : Vec3 = Vec3::ONE
    # When true, the node ignores its parent's transform.
    property? top_level = false

    # Creates a 3D node.
    def initialize(name : String = "", @position = Vec3::ZERO, @rotation = Quat::IDENTITY, @scale = Vec3::ONE)
      super(name)
    end

    # Sets a uniform scale.
    def scale=(s : Number); @scale = Vec3.new(s); end
    # Sets the scale per axis.
    def scale=(s : Vec3); @scale = s; end

    # Rotation as Euler angles `(pitch, yaw, roll)` in radians.
    def euler : Vec3; @rotation.to_euler; end
    # Sets the rotation from Euler angles in radians.
    def euler=(e : Vec3); @rotation = Quat.from_euler(e); end
    # Sets the rotation from pitch, yaw and roll in radians. Returns self.
    def set_euler(pitch : Number, yaw : Number, roll : Number = 0) : self
      @rotation = Quat.from_euler(pitch, yaw, roll)
      self
    end

    # Rotates around a world-space *axis*.
    def rotate(axis : Vec3, rad : Number) : Nil; @rotation = (Quat.from_axis_angle(axis, rad) * @rotation).normalized; end
    # Rotates around the world X axis (pitch).
    def rotate_x(rad : Number) : Nil; rotate(Vec3::RIGHT, rad); end
    # Rotates around the world Y axis (yaw), the usual way to turn a character.
    def rotate_y(rad : Number) : Nil; rotate(Vec3::UP, rad); end
    # Rotates around the Z axis (roll).
    def rotate_z(rad : Number) : Nil; rotate(Vec3::BACK, rad); end
    # Rotates around an axis in the node's own space.
    def rotate_local(axis : Vec3, rad : Number) : Nil; @rotation = (@rotation * Quat.from_axis_angle(axis, rad)).normalized; end
    # Moves by *v* in parent space.
    def translate(v : Vec3) : Nil; @position += v; end
    # Moves by *v* in the node's own space, so `Vec3::FORWARD` moves the way it faces.
    def translate_local(v : Vec3) : Nil; @position += @rotation * v; end

    # The local transform matrix.
    def transform : Mat4; Mat4.trs(@position, @rotation, @scale); end

    # The transform from this node's space to world space.
    def global_transform : Mat4
      return transform if @top_level
      (p = parent_3d) ? p.global_transform * transform : transform
    end

    # Position in world space.
    def global_position : Vec3; global_transform.translation; end

    # Moves the node so it ends up at *p* in world space.
    def global_position=(p : Vec3)
      if (par = parent_3d) && !@top_level
        @position = par.global_transform.inverse.transform_point(p)
      else
        @position = p
      end
    end

    # Orientation in world space.
    def global_rotation : Quat
      (p = parent_3d) && !@top_level ? (p.global_rotation * @rotation).normalized : @rotation
    end

    # The nearest ancestor that is a `Node3D`, or `nil`.
    def parent_3d : Node3D?
      p = @parent
      while p
        return p if p.is_a?(Node3D)
        p = p.parent
      end
      nil
    end

    # The direction the node faces, in world space.
    def forward : Vec3; global_rotation * Vec3::FORWARD; end
    # The opposite of `forward`.
    def back : Vec3; -forward; end
    # The node's up direction in world space.
    def up : Vec3; global_rotation * Vec3::UP; end
    # The node's right direction in world space.
    def right : Vec3; global_rotation * Vec3::RIGHT; end

    # Turns the node so `forward` points at a world-space target.
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

    # Converts a world-space point to local space.
    def to_local(global : Vec3) : Vec3; global_transform.inverse.transform_point(global); end
    # Converts a local point to world space.
    def to_global(local : Vec3) : Vec3; global_transform.transform_point(local); end
    # Distance to another 3D node.
    def distance_to(o : Node3D) : Float32; global_position.distance(o.global_position); end

    # 3D nodes don't draw in the 2D pass, but children still may.
    def draw_tree(g : Graphics) : Nil
      return unless @visible
      draw(g)
      draw_children(g)
    end
  end

  # Draws a `Mesh` with a `Material`. It is the 3D counterpart of `Sprite2D`.
  #
  # ```
  # crate = MeshInstance3D.new(Mesh.cube, Material.new(texture: Texture.new(Image.checkerboard(64, 64))))
  # crate.position = v3(0, 0.5, 0)
  # ball = MeshInstance3D.new(Mesh.sphere(0.5), Material.new(Color::RED, shininess: 64))
  # glass = MeshInstance3D.new(Mesh.cube, Material.new(Color.new(0.6, 0.8, 1, 0.4), transparent: true))
  # SceneTree.root.add(crate, ball, glass)
  # ```
  class MeshInstance3D < Node3D
    # The geometry to draw. `nil` draws nothing.
    property mesh : Mesh?
    # The surface appearance.
    property material : Material
    # Whether this mesh casts shadows.
    property? cast_shadows = true

    # Creates a mesh instance. Without a material, a plain white one is used.
    def initialize(mesh : Mesh? = nil, material : Material? = nil, name : String = "", position : Vec3 = Vec3::ZERO)
      super(name, position)
      @mesh = mesh
      @material = material || Material.new
    end

    # Creates a mesh instance from an OBJ file.
    def self.load(path : String, material : Material? = nil) : MeshInstance3D
      new(Mesh.load(path), material)
    end

    # World-space bounds of the mesh, for picking and culling.
    def global_bounds : AABB?
      @mesh.try(&.bounds.transformed(global_transform))
    end

    # What the renderer draws for this node this frame.
    def draw_item : DrawItem?
      m = @mesh
      return nil unless m
      DrawItem.new(m, @material, global_transform)
    end
  end

  # The viewpoint a 3D scene is rendered from. The first camera added to the tree becomes
  # current, and when a current camera exists, Eagle renders the 3D scene under the 2D layer
  # every frame.
  #
  # ```
  # cam = Camera3D.new(position: v3(0, 3, 8), fov: 60)
  # cam.look_at(Vec3::ZERO)
  # SceneTree.root.add(cam)
  #
  # class Viewer < App
  #   @cam = Camera3D.new(position: v3(0, 2, 6))
  #
  #   def load : Nil
  #     SceneTree.root.add(@cam)
  #   end
  #
  #   def update(dt : Float32) : Nil
  #     @cam.fly(dt) # WASD, right-drag to look: handy while building a scene
  #     if Input.mouse_pressed?
  #       ray = @cam.mouse_ray # pick things under the cursor with Ray#intersect_aabb
  #     end
  #   end
  # end
  # ```
  class Camera3D < Node3D
    # Vertical field of view in radians. See `fov_degrees` for degrees.
    property fov : Float32 = Mathf.deg2rad(60)
    # Nearest distance that is drawn. Keep it as large as you can to avoid depth artifacts.
    property near : Float32 = 0.1_f32
    # Farthest distance that is drawn.
    property far : Float32 = 500_f32
    # Use an orthographic projection with no perspective, for isometric and strategy views.
    property? orthographic = false
    # Half the view height in world units when orthographic.
    property ortho_size : Float32 = 5_f32
    # True when this camera renders the scene.
    getter? current = false
    @@current : Camera3D? = nil

    # Creates a camera. *fov* is in degrees here.
    def initialize(name : String = "", position : Vec3 = Vec3::ZERO, fov : Number = 60, current : Bool = false)
      super(name, position)
      @fov = Mathf.deg2rad(fov)
      make_current if current
    end

    # The camera the scene renders from, if any.
    def self.current : Camera3D?; @@current; end
    # Switches the active camera. `nil` stops 3D rendering.
    def self.current=(c : Camera3D?)
      @@current.try(&.clear_current)
      @@current = c
      c.try(&.set_current)
    end
    # :nodoc:
    def self.reset; @@current = nil; end

    # Makes this the active camera. Returns self.
    def make_current : self; Camera3D.current = self; self; end
    protected def set_current; @current = true; end
    protected def clear_current; @current = false; end

    # Becomes current if no other camera is.
    def enter_tree : Nil
      make_current if Camera3D.current.nil?
    end

    # Stops being current when removed.
    def exit_tree : Nil
      Camera3D.current = nil if Camera3D.current == self
    end

    # Field of view in degrees.
    def fov_degrees : Float32; Mathf.rad2deg(@fov); end
    # Sets the field of view in degrees.
    def fov_degrees=(d : Number); @fov = Mathf.deg2rad(d); end

    # The view matrix (world to camera).
    def view : Mat4; global_transform.inverse; end

    # The projection matrix for an aspect ratio.
    def projection(aspect : Number) : Mat4
      if @orthographic
        h = @ortho_size; w = h * aspect
        Mat4.orthographic(-w, w, -h, h, @near, @far)
      else
        Mat4.perspective(@fov, aspect, @near, @far)
      end
    end

    # The view, projection and position packed for the renderer.
    def camera_view(aspect : Number) : CameraView
      CameraView.new(view, projection(aspect), global_position)
    end

    # The world-space ray through a screen point.
    def screen_to_ray(screen : Vec2, viewport : Vec2 = Window.size) : Ray
      ndc = Vec2.new(screen.x / viewport.x * 2 - 1, 1 - screen.y / viewport.y * 2)
      inv = (projection(viewport.x / viewport.y) * view).inverse
      near_p = inv.transform_point(Vec3.new(ndc.x, ndc.y, -1))
      far_p = inv.transform_point(Vec3.new(ndc.x, ndc.y, 1))
      Ray.new(near_p, far_p - near_p)
    end

    # Projects a world point to screen space, for name tags and markers over 3D objects.
    # Returns `nil` when the point is behind the camera.
    def world_to_screen(p : Vec3, viewport : Vec2 = Window.size) : Vec2?
      clip = projection(viewport.x / viewport.y) * view * p.to_vec4(1)
      return nil if clip.w <= 0
      ndc = clip.homogenized
      Vec2.new((ndc.x + 1) / 2 * viewport.x, (1 - ndc.y) / 2 * viewport.y)
    end

    # The ray through the mouse cursor.
    def mouse_ray : Ray; screen_to_ray(Input.mouse); end

    # A free-flying debug camera. WASD moves, Q and E go down and up, right-drag or the arrow
    # keys look around, and Ctrl moves faster. A gamepad works too.
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

  # Base class for lights. Up to eight lights affect a scene at once.
  abstract class Light3D < Node3D
    # Light color.
    property color : Color = Color::WHITE
    # Brightness multiplier.
    property intensity : Float32 = 1_f32
    # Turns the light off without removing it.
    property? enabled = true
    abstract def light_data : LightData
  end

  # Light from a single direction with parallel rays, like the sun. It can cast shadows,
  # which follow the camera across large scenes.
  #
  # ```
  # sun = DirectionalLight3D.new(v3(-0.5, -1, -0.3), Color.hex("#fff4e0"), intensity: 1.1)
  # sun.shadows = false # skip shadows on low-end targets
  # ```
  class DirectionalLight3D < Light3D
    # Whether this light casts shadows.
    property? shadows = true

    # Creates a directional light shining along *direction*.
    def initialize(direction : Vec3 = Vec3.new(-0.5, -1, -0.3), color : Color = Color::WHITE, intensity : Number = 1, name : String = "")
      super(name)
      self.color = color; self.intensity = intensity.to_f32
      look_at(direction)
    end

    # Direction the light shines.
    def direction : Vec3; forward; end
    # Changes the direction the light shines.
    def direction=(d : Vec3); look_at(global_position + d); end

    # What the renderer uses for this light.
    def light_data : LightData
      LightData.directional(forward, @color, @intensity, @shadows)
    end
  end

  # Light radiating from a point in every direction, like a bulb or a torch. It fades out at `range`.
  #
  # ```
  # torch = PointLight3D.new(v3(2, 1.5, 0), Color::ORANGE, intensity: 2, range: 6)
  # ```
  class PointLight3D < Light3D
    # Distance at which the light fades to nothing.
    property range : Float32 = 10_f32

    # Creates a point light.
    def initialize(position : Vec3 = Vec3::ZERO, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10, name : String = "")
      super(name, position)
      self.color = color; self.intensity = intensity.to_f32; @range = range.to_f32
    end

    # What the renderer uses for this light.
    def light_data : LightData
      LightData.point(global_position, @color, @intensity, @range)
    end
  end

  # A cone of light from a point, like a flashlight or a stage light. It points along the node's `forward`.
  #
  # ```
  # flashlight = SpotLight3D.new(v3(0, 2, 0), angle: 0.4, range: 15)
  # flashlight.look_at(v3(0, 0, -5))
  # ```
  class SpotLight3D < Light3D
    # Distance at which the light fades to nothing.
    property range : Float32 = 10_f32
    # Half-angle of the cone, in radians.
    property angle : Float32 = 0.6_f32
    # Width of the soft edge, in radians.
    property softness : Float32 = 0.1_f32

    # Creates a spot light.
    def initialize(position : Vec3 = Vec3::ZERO, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10, angle : Number = 0.6, softness : Number = 0.1, name : String = "")
      super(name, position)
      self.color = color; self.intensity = intensity.to_f32; @range = range.to_f32; @angle = angle.to_f32; @softness = softness.to_f32
    end

    # What the renderer uses for this light.
    def light_data : LightData
      LightData.spot(global_position, forward, @color, @intensity, @range, @angle, @softness)
    end
  end

  # Renders the 3D part of the scene tree, and holds the environment: sky, ambient light,
  # fog and shadow settings.
  #
  # The engine calls `render` for you whenever a `Camera3D` is current. Use this module to
  # tweak the environment and to draw debug shapes.
  #
  # ```
  # Scene3D.environment.fog(20, 80)
  # Scene3D.environment.sky_colors(Color.hex("#3b6fd6"), Color.hex("#b9d4f5"), Color.hex("#3a3a44"))
  # Scene3D.environment.ambient = Color.gray(0.3)
  #
  # Scene3D.debug_line(Vec3::ZERO, v3(0, 2, 0), Color::RED) # visible for one frame
  # Scene3D.debug_sphere(v3(1, 1, 1), 0.5_f32)
  # ```
  module Scene3D
    @@renderer : Renderer3D? = nil
    @@environment = Environment.new
    @@debug_mesh : Mesh? = nil

    # Draws a line for the next frame only. Call it every frame to keep it visible.
    def self.debug_line(a : Vec3, b : Vec3, color : Color = Color::GREEN) : Nil
      m = (@@debug_mesh ||= Mesh.new("debug").tap(&.primitive = GPU::Primitive::Lines))
      i = m.add_vertex(a, Vec3::UP, Vec2::ZERO, color)
      j = m.add_vertex(b, Vec3::UP, Vec2::ZERO, color)
      m.indices << i << j
    end

    # Draws a box outline for the next frame only.
    def self.debug_box(center : Vec3, half : Vec3, rotation : Quat = Quat::IDENTITY, color : Color = Color::GREEN) : Nil
      c = [] of Vec3
      [-1, 1].each { |x| [-1, 1].each { |y| [-1, 1].each { |z| c << center + rotation * Vec3.new(half.x * x, half.y * y, half.z * z) } } }
      [{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}].each { |(i, j)| debug_line(c[i], c[j], color) }
    end

    # Draws a sphere outline for the next frame only.
    def self.debug_sphere(center : Vec3, radius : Float32, color : Color = Color::GREEN, segments : Int32 = 16) : Nil
      segments.times do |i|
        a0 = Math::PI * 2 * i / segments; a1 = Math::PI * 2 * (i + 1) / segments
        debug_line(center + Vec3.new(Math.cos(a0) * radius, 0, Math.sin(a0) * radius), center + Vec3.new(Math.cos(a1) * radius, 0, Math.sin(a1) * radius), color)
        debug_line(center + Vec3.new(Math.cos(a0) * radius, Math.sin(a0) * radius, 0), center + Vec3.new(Math.cos(a1) * radius, Math.sin(a1) * radius, 0), color)
        debug_line(center + Vec3.new(0, Math.cos(a0) * radius, Math.sin(a0) * radius), center + Vec3.new(0, Math.cos(a1) * radius, Math.sin(a1) * radius), color)
      end
    end

    # :nodoc:
    def self.take_debug_item : DrawItem?
      m = @@debug_mesh
      return nil if m.nil? || m.indices.empty?
      @@debug_mesh = nil
      DrawItem.new(m, Material.unlit(Color::WHITE), Mat4.identity)
    end

    # The sky, ambient light, fog and shadow settings.
    def self.environment : Environment; @@environment; end
    # Replaces the environment.
    def self.environment=(e : Environment); @@environment = e; renderer.environment = e; end

    # The shared 3D renderer.
    def self.renderer : Renderer3D
      @@renderer ||= Renderer3D.new(@@environment)
    end

    # :nodoc:
    def self.reset : Nil
      @@renderer.try(&.dispose)
      @@renderer = nil
      @@debug_mesh = nil
      @@environment = Environment.new
      Camera3D.reset
    end

    # Gathers draw items and lights from a subtree.
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

    # Renders a subtree from *camera* into the current target. The engine calls this each
    # frame; call it yourself to render into a `Canvas`, for mirrors or minimaps.
    def self.render(root : Node = SceneTree.root, camera : Camera3D? = Camera3D.current, target_size : Vec2 = Window.size, flip_y : Bool = false, clear : Bool = true) : Nil
      cam = camera
      return unless cam
      items, lights = collect(root)
      if dbg = take_debug_item
        items << dbg
        SceneTree.defer { dbg.mesh.dispose }
      end
      renderer.render(cam.camera_view(target_size.x / target_size.y), items, lights, target_size, flip_y, clear)
    end
  end
end
