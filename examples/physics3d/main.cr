require "../../src/eagle"
include Eagle

# 3D physics playground: click to fire spheres, space to drop a box, R to reset.
class Physics3DDemo < App
  @cam = Camera3D.new(position: v3(0, 6, 14))
  @rng = Random.new(1)
  @shot : Sound? = nil

  def load
    @shot = Sound.tone(200, 0.1, Sound::Wave::Triangle, 0.3)
    root = SceneTree.root
    Scene3D.environment.fog(30, 80)
    tex = Texture.new(Image.checkerboard(32, 32, 16, Color.hex("#cfd6dd"), Color.hex("#8b96a3")), wrap: GPU::Wrap::Repeat)
    floor = StaticBody3D.new(position: v3(0, -0.5, 0)).box(40, 1, 40)
    floor.add(MeshInstance3D.new(Mesh.box(40, 1, 40), Material.new(texture: tex, specular: 0.05)))
    root.add(floor)
    ramp = StaticBody3D.new(position: v3(-6, 1, 0))
    ramp.rotate_z(-0.4)
    ramp.box(8, 0.4, 6)
    ramp.add(MeshInstance3D.new(Mesh.box(8, 0.4, 6), Material.new(Color.hex("#6c7a89"))))
    root.add(ramp)
    # a pyramid of boxes
    4.times do |layer|
      (4 - layer).times do |i|
        b = RigidBody3D.new(position: v3(3 + i * 1.05 + layer * 0.525, 0.5 + layer * 1.02, 0)).box(1, 1, 1)
        b.add(MeshInstance3D.new(Mesh.cube(1), Material.new(Color.hsv(layer * 40 + i * 15, 0.6, 0.95))))
        root.add(b)
      end
    end
    6.times { |i| spawn_sphere(v3(-8 + i * 0.6, 4 + i, 0), Vec3::ZERO, 0.3 + @rng.rand * 0.3) }
    root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.4)), @cam)
    @cam.look_at(v3(0, 1, 0))
  end

  def spawn_sphere(pos : Vec3, vel : Vec3, r : Float64)
    s = RigidBody3D.new(position: pos).sphere(r)
    s.velocity = vel
    s.restitution = 0.4
    s.add(MeshInstance3D.new(Mesh.sphere(r, 16, 12), Material.new(Color.hsv(@rng.rand * 360, 0.7, 1), shininess: 64, specular: 0.5)))
    SceneTree.root.add(s)
  end

  def update(dt : Float32)
    @cam.fly(dt, 8)
    if Input.mouse_pressed?(MouseButton::Left)
      ray = @cam.mouse_ray
      spawn_sphere(ray.origin + ray.direction, ray.direction * 20, 0.35)
      @shot.try(&.play)
    end
    if Input.pressed?(Key::Space)
      b = RigidBody3D.new(position: @cam.position + @cam.forward * 3).box(1, 1, 1)
      b.rotation = Quat.from_euler(@rng.rand, @rng.rand, @rng.rand)
      b.velocity = @cam.forward * 8
      b.add(MeshInstance3D.new(Mesh.cube(1), Material.new(Color::ORANGE)))
      SceneTree.root.add(b)
    end
    if Input.pressed?(Key::C)
      c = RigidBody3D.new(position: @cam.position + @cam.forward * 3).capsule(0.3, 0.8)
      c.velocity = @cam.forward * 8
      c.add(MeshInstance3D.new(Mesh.capsule(0.3, 0.8), Material.new(Color::CYAN)))
      SceneTree.root.add(c)
    end
    if Input.pressed?(Key::R)
      SceneTree.reset
      load
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    g.rect(0, 0, Window.width, 30, color: Color.new(0, 0, 0, 0.4))
    g.print("3D physics  bodies #{Physics3D.world.bodies.size}  fps #{Clock.fps.round}   click: fire sphere  space: throw box  C: capsule  R reset  WASD/right-drag fly", 10, 8)
  end
end

Eagle.run(Physics3DDemo, title: "Eagle physics 3D", width: 1024, height: 640, msaa: 4)
