require "../gpu_spec_helper"

describe Eagle::Mesh do
  it "builds primitives with sane bounds and normals" do
    c = Mesh.cube(2)
    c.vertex_count.should eq 24
    c.triangle_count.should eq 12
    c.bounds.min.should eq v3(-1, -1, -1)
    c.bounds.max.should eq v3(1, 1, 1)
    s = Mesh.sphere(1, 8, 4)
    s.positions.each { |p| p.length.should be_close(1, 1e-4) }
    s.normals.each_with_index { |n, i| n.approx?(s.positions[i], 1e-4).should be_true }
    p = Mesh.plane(4, 4, 2)
    p.vertex_count.should eq 9
    p.triangle_count.should eq 8
    p.normals.all?(&.approx?(Vec3::UP)).should be_true
    # winding must agree with the normal (front face up)
    a, b, c = p.indices[0, 3].map { |i| p.positions[i] }
    (b - a).cross(c - a).dot(Vec3::UP).should be > 0
    # every primitive: triangle winding must agree with its normals (else culling hides it)
    {Mesh.cube, Mesh.sphere, Mesh.cylinder, Mesh.cone, Mesh.capsule, Mesh.torus, Mesh.plane, Mesh.quad, Mesh.box(1, 2, 3)}.each do |mesh|
      bad = 0
      (0...mesh.indices.size).step(3) do |i|
        x, y, z = mesh.indices[i, 3].map { |k| mesh.positions[k] }
        n = (y - x).cross(z - x)
        next if n.length < 1e-8
        bad += 1 if n.dot(mesh.normals[mesh.indices[i]]) < 0
      end
      bad.should eq 0
    end
    Mesh.cylinder.triangle_count.should be > 40
    Mesh.cone.vertex_count.should be > 20
    Mesh.torus(1, 0.25, 8, 4).positions.each { |q| (q.xz.length - 1).abs.should be <= 0.25 + 1e-4 }
    Mesh.capsule.bounds.max.y.should be_close(1, 1e-4)
    Mesh.grid(10, 2).indices.size.should eq 12
    Mesh.axes.primitive.should eq GPU::Primitive::Lines
  end

  it "recomputes normals, flattens, transforms and appends" do
    m = Mesh.new
    a = m.add_vertex(v3(0, 0, 0)); b = m.add_vertex(v3(1, 0, 0)); c = m.add_vertex(v3(0, 0, -1))
    m.add_triangle(a, b, c)
    m.compute_normals
    m.normals[0].approx?(Vec3::UP).should be_true
    f = m.flat_shaded
    f.vertex_count.should eq 3
    m.transform!(Mat4.translation(0, 5, 0))
    m.bounds.min.y.should eq 5
    m.append(Mesh.cube(1), Mat4.translation(10, 0, 0))
    m.vertex_count.should eq 27
    m.bounds.max.x.should eq 10.5
  end

  it "round-trips OBJ" do
    cube = Mesh.cube(1)
    text = Codecs::OBJ.encode(cube)
    back = Codecs::OBJ.decode(text, "cube.obj")
    back.triangle_count.should eq 12
    back.bounds.min.should eq cube.bounds.min
    quads = "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n"
    q = Codecs::OBJ.decode(quads)
    q.triangle_count.should eq 2
    q.normals[0].approx?(Vec3::BACK).should be_true
    neg = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf -3 -2 -1\n"
    Codecs::OBJ.decode(neg).triangle_count.should eq 1
    expect_raises(AssetError) { Codecs::OBJ.decode("v 0 0 0\n") }
  end

  gpu_it "uploads and draws" do
    m = Mesh.cube
    m.upload
    Material.standard_shader.use # drawing needs a bound program
    m.draw
    m.dispose
  end
end

describe Eagle::Node3D do
  before_each { SceneTree.reset }

  it "composes transforms and looks at targets" do
    parent = Node3D.new(position: v3(10, 0, 0))
    parent.rotate_y(Math::PI / 2)
    child = Node3D.new(position: v3(1, 0, 0))
    parent.add(child)
    child.global_position.approx?(v3(10, 0, -1), 1e-4).should be_true
    child.global_position = v3(10, 5, 0)
    child.position.approx?(v3(0, 5, 0), 1e-4).should be_true
    n = Node3D.new
    n.look_at(v3(0, 0, -10))
    n.forward.approx?(Vec3::FORWARD, 1e-4).should be_true
    n.look_at(v3(5, 0, 0))
    n.forward.approx?(Vec3::RIGHT, 1e-4).should be_true
    n.up.approx?(Vec3::UP, 1e-4).should be_true
    n.translate_local(v3(0, 0, -1))
    n.position.approx?(v3(1, 0, 0), 1e-4).should be_true
    n.set_euler(0.2, 0.3)
    n.euler.x.should be_close(0.2, 1e-3)
    n.euler.y.should be_close(0.3, 1e-3)
    n.to_local(n.to_global(v3(1, 2, 3))).approx?(v3(1, 2, 3), 1e-3).should be_true
  end

  it "camera projects and unprojects" do
    cam = Camera3D.new(position: v3(0, 0, 10))
    cam.look_at(Vec3::ZERO)
    vp = v2(800, 600)
    cam.world_to_screen(Vec3::ZERO, vp).not_nil!.approx?(v2(400, 300), 0.01).should be_true
    cam.world_to_screen(v3(0, 0, 20), vp).should be_nil
    ray = cam.screen_to_ray(v2(400, 300), vp)
    ray.direction.approx?(Vec3::FORWARD, 1e-3).should be_true
    ray.intersect_sphere(Vec3::ZERO, 1).not_nil!.should be_close(8.9, 0.05) # ray starts on the near plane
    right = cam.screen_to_ray(v2(800, 300), vp)
    right.direction.x.should be > 0
    cam.orthographic = true
    cam.ortho_size = 5
    cam.world_to_screen(v3(0, 5, 0), vp).not_nil!.y.should be_close(0, 0.01)
    SceneTree.root.add(cam)
    Camera3D.current.should eq cam
    cam.free
    Camera3D.current.should be_nil
  end

  it "lights produce light data" do
    d = DirectionalLight3D.new(v3(0, -1, 0))
    d.light_data.kind.directional?.should be_true
    d.light_data.direction.approx?(v3(0, -1, 0), 1e-4).should be_true
    p = PointLight3D.new(v3(1, 2, 3), range: 7)
    p.light_data.position.should eq v3(1, 2, 3)
    p.light_data.range.should eq 7
    s = SpotLight3D.new(v3(0, 5, 0), angle: 0.5)
    s.look_at(Vec3::ZERO)
    s.light_data.kind.spot?.should be_true
    s.light_data.direction.approx?(v3(0, -1, 0), 1e-4).should be_true
  end
end

describe Eagle::Renderer3D do
  before_each { SceneTree.reset }

  gpu_it "renders a lit scene into a canvas" do
    root = SceneTree.root
    cam = Camera3D.new(position: v3(0, 0, 4))
    cam.look_at(Vec3::ZERO)
    sphere = MeshInstance3D.new(Mesh.sphere(1, 32, 16), Material.new(Color::WHITE, shininess: 8, specular: 0))
    light = DirectionalLight3D.new(v3(-1, 0, -0.3)) # light from the front-right: right side lit
    light.shadows = false
    Scene3D.environment.sky = false
    Scene3D.environment.background = Color::BLACK
    Scene3D.environment.ambient = Color::BLACK
    root.add(cam, sphere, light)
    canvas = Canvas.new(64, 64, depth: true)
    g = Eagle.graphics
    g.begin_frame
    g.with_canvas(canvas, clear: nil) { Scene3D.render(root, cam, canvas.size, flip_y: true) }
    g.end_frame
    img = canvas.to_image
    right = img.average(36, 28, 8, 8)
    left = img.average(20, 28, 8, 8)
    corner = img[1, 1]
    right.r.should be > 0.4
    left.r.should be < 0.1
    corner.should eq Color::BLACK
    Scene3D.renderer.draw_calls.should eq 1
    canvas.dispose
  end

  gpu_it "casts shadows onto the floor" do
    root = SceneTree.root
    cam = Camera3D.new(position: v3(0, 6, 0.01))
    cam.look_at(Vec3::ZERO)
    env = Scene3D.environment
    env.sky = false; env.background = Color::BLACK; env.ambient = Color::BLACK
    env.shadows = true; env.shadow_size = 512
    floor = MeshInstance3D.new(Mesh.plane(20, 20), Material.new(Color::WHITE, specular: 0))
    block = MeshInstance3D.new(Mesh.cube(1), Material.new(Color::WHITE, specular: 0), position: v3(0, 1, 0))
    sun = DirectionalLight3D.new(v3(0.01, -1, 0.01))
    root.add(cam, floor, block, sun)
    canvas = Canvas.new(64, 64, depth: true)
    g = Eagle.graphics
    g.begin_frame
    g.with_canvas(canvas, clear: nil) { Scene3D.render(root, cam, canvas.size, flip_y: true) }
    g.end_frame
    img = canvas.to_image
    # the floor far from the block is lit
    lit = img.average(4, 4, 6, 6)
    lit.r.should be > 0.5
    # the block sits in the middle; directly around it the floor is in its shadow
    # (light points straight down so the shadow is the block's footprint; sample just inside the edge)
    center = img.average(30, 30, 4, 4)
    center.r.should be > 0.5 # top of block is lit
    env.shadows = false
    g.begin_frame
    g.with_canvas(canvas, clear: nil) { Scene3D.render(root, cam, canvas.size, flip_y: true) }
    g.end_frame
    img2 = canvas.to_image
    img2.average(4, 4, 6, 6).r.should be > 0.5
    canvas.dispose
    # a tilted light: the shadow falls beside the block
    env.shadows = true
    sun.direction = v3(-1, -1, 0)
    canvas = Canvas.new(64, 64, depth: true)
    g.begin_frame
    g.with_canvas(canvas, clear: nil) { Scene3D.render(root, cam, canvas.size, flip_y: true) }
    g.end_frame
    img3 = canvas.to_image
    # camera looks straight down (up falls back to +Z, so screen right = -X); light travels toward -X so the shadow lands on screen right
    shadow_side = img3.average(39, 30, 5, 4)
    open_side = img3.average(12, 30, 6, 4)
    shadow_side.r.should be < 0.15
    open_side.r.should be > 0.4
    canvas.dispose
  end

  gpu_it "renders sky, shadows, textures and transparency without errors" do
    root = SceneTree.root
    cam = Camera3D.new(position: v3(0, 3, 6))
    cam.look_at(Vec3::ZERO)
    env = Scene3D.environment
    env.sky = true
    env.shadows = true
    env.shadow_size = 256
    env.fog(2, 20)
    tex = Texture.new(Image.checkerboard(8, 8, 2))
    floor = MeshInstance3D.new(Mesh.plane(10, 10), Material.new(texture: tex))
    cube = MeshInstance3D.new(Mesh.cube, Material.new(Color::RED), position: v3(0, 0.5, 0))
    glass = MeshInstance3D.new(Mesh.sphere, Material.new(Color.new(0, 0, 1, 0.5), transparent: true), position: v3(1.5, 0.5, 0))
    wire = MeshInstance3D.new(Mesh.torus, Material.new(Color::GREEN), position: v3(-2, 1, 0))
    wire.material.wireframe = true
    unlit = MeshInstance3D.new(Mesh.grid, Material.unlit(Color::GRAY))
    root.add(cam, floor, cube, glass, wire, unlit, DirectionalLight3D.new, PointLight3D.new(v3(0, 2, 2), Color::YELLOW), SpotLight3D.new(v3(0, 4, 0)))
    canvas = Canvas.new(64, 48, depth: true)
    g = Eagle.graphics
    g.begin_frame
    g.with_canvas(canvas, clear: nil) { Scene3D.render(root, cam, canvas.size, flip_y: true) }
    g.end_frame
    GPU.device.check_errors("3d render")
    img = canvas.to_image
    # sky at the top should be bluish, not black
    top = img.average(0, 0, 64, 4)
    top.b.should be > 0.3
    # something drawn in the middle
    img.average(20, 16, 24, 24).a.should be > 0.9
    Scene3D.renderer.draw_calls.should be > 5
    canvas.dispose
  end
end
