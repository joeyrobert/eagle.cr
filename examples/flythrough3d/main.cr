require "../../src/eagle"
include Eagle

# 3D feature fly-through: primitives, textures, lights, shadows, fog, sky,
# transparency, wireframe, OBJ export/import, picking and a 2D HUD.
# Controls: WASD/QE move, right-drag or arrows look, Ctrl = fast, F toggles wireframe.
class FlyThrough < App
  @cam = Camera3D.new(position: v3(0, 4, 14))
  @spinners = [] of MeshInstance3D
  @sun = DirectionalLight3D.new(v3(-0.6, -1, -0.4), Color.hex("#fff2d0"), 1.2)
  @picked : MeshInstance3D? = nil
  @wire = false

  def load
    root = SceneTree.root
    env = Scene3D.environment
    env.fog(30, 90, Color.hex("#b9d4f5"))
    env.ambient = Color.new(0.28, 0.3, 0.36)

    checker = Texture.new(Image.checkerboard(64, 64, 8, Color.hex("#cfd6dd"), Color.hex("#8b96a3")), wrap: GPU::Wrap::Repeat)
    floor = MeshInstance3D.new(Mesh.plane(80, 80, 8, uv_scale: 16), Material.new(texture: checker, shininess: 24, specular: 0.08))
    root.add(floor)

    prims = [Mesh.cube(1.5), Mesh.sphere(1), Mesh.cylinder(0.8, 1.8), Mesh.cone(1, 2), Mesh.capsule(0.6, 1.2), Mesh.torus(1, 0.35)]
    prims.each_with_index do |m, i|
      mat = Material.new(Color.hsv(i * 60, 0.6, 0.95), shininess: 48, specular: 0.5)
      mi = MeshInstance3D.new(m, mat, position: v3(-7.5 + i * 3, 1.2, 0))
      root.add(mi)
      @spinners << mi
    end
    # flat-shaded low-poly sphere via OBJ round trip
    obj = Codecs::OBJ.encode(Mesh.sphere(1.2, 10, 6))
    low = MeshInstance3D.new(Codecs::OBJ.decode(obj).flat_shaded, Material.new(Color.hex("#e0e0e0"), metallic: 0.6, shininess: 96), position: v3(0, 1.4, -5))
    root.add(low)
    @spinners << low

    glass = MeshInstance3D.new(Mesh.sphere(1.3), Material.new(Color.new(0.3, 0.7, 1, 0.45), transparent: true, shininess: 128, specular: 1), position: v3(5, 1.5, -5))
    root.add(glass)
    wire = MeshInstance3D.new(Mesh.torus(1.4, 0.5, 24, 12), Material.new(Color::GREEN, unlit: true), position: v3(-5, 1.5, -5))
    wire.material.wireframe = true
    root.add(wire)
    @spinners << wire

    # towers casting long shadows
    6.times do |i|
      h = 2 + i * 1.2
      root.add(MeshInstance3D.new(Mesh.box(1, h, 1), Material.new(Color.hex("#6c7a89")), position: v3(-10 + i * 4, h / 2, -12)))
    end
    root.add(MeshInstance3D.new(Mesh.grid(80, 40), Material.unlit(Color.new(1, 1, 1, 0.15)), position: v3(0, 0.01, 0)).tap(&.material.transparent = true))
    root.add(MeshInstance3D.new(Mesh.axes(2), Material.unlit, position: v3(0, 0.02, 6)))

    root.add(@sun)
    root.add(PointLight3D.new(v3(3, 2, 4), Color.hex("#ff8040"), 2, 10))
    spot = SpotLight3D.new(v3(-6, 6, 4), Color.hex("#80c0ff"), 3, 20, 0.5, 0.15)
    spot.look_at(v3(-6, 0, 0))
    root.add(spot)

    @cam.look_at(v3(0, 1, 0))
    root.add(@cam)
  end

  def update(dt : Float32)
    @cam.fly(dt, 8)
    @spinners.each_with_index { |s, i| s.rotate_y(dt * (0.3 + i * 0.1)) }
    # sun slowly orbits
    @sun.rotate(Vec3::UP, dt * 0.05)
    if Input.pressed?(Key::F)
      @wire = !@wire
      SceneTree.root.find_all(MeshInstance3D).each { |m| m.material.wireframe = @wire unless m.material.unlit? }
    end
    if Input.mouse_pressed?(MouseButton::Left)
      ray = @cam.mouse_ray
      best = nil.as(MeshInstance3D?); best_t = Float32::INFINITY
      SceneTree.root.find_all(MeshInstance3D).each do |m|
        next unless (b = m.global_bounds)
        if (t = ray.intersect_aabb(b)) && t < best_t
          best = m; best_t = t
        end
      end
      @picked = best
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    g.rect(0, 0, Window.width, 30, color: Color.new(0, 0, 0, 0.45))
    g.print("Eagle 3D  fps #{Clock.fps.round}  draw calls #{Scene3D.renderer.draw_calls}  WASD/QE move, right-drag look, F wireframe, click to pick", 10, 10, Color::WHITE)
    if p = @picked
      if s = @cam.world_to_screen(p.global_position)
        g.circle(s.x, s.y, 12, DrawMode::Line, Color::YELLOW)
        g.print(p.mesh.try(&.name) || "?", s.x + 16, s.y - 8, Color::YELLOW)
      end
    end
  end
end

Eagle.run(FlyThrough, title: "Eagle 3D fly-through", width: 1024, height: 640, msaa: 4)
