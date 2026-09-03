require "../gpu_spec_helper"

describe Eagle::Node2D do
  before_each { SceneTree.reset }

  it "composes global transforms through parents" do
    parent = Node2D.new(position: v2(100, 0), rotation: (Math::PI / 2).to_f32)
    child = Node2D.new(position: v2(10, 0))
    parent.add(child)
    child.global_position.approx?(v2(100, 10)).should be_true
    child.global_rotation.should be_close(Math::PI / 2, 1e-5)
    child.to_local(v2(100, 10)).approx?(Vec2::ZERO).should be_true
    child.to_global(Vec2::ZERO).approx?(v2(100, 10)).should be_true
    child.global_position = v2(100, 20)
    child.position.approx?(v2(20, 0)).should be_true
  end

  it "ignores parents when top_level" do
    parent = Node2D.new(position: v2(100, 100))
    child = Node2D.new(position: v2(5, 5))
    child.top_level = true
    parent.add(child)
    child.global_position.should eq v2(5, 5)
  end

  it "looks at targets and computes directions" do
    n = Node2D.new
    n.look_at(v2(0, 10))
    n.rotation.should be_close(Math::PI / 2, 1e-5)
    n.right.approx?(v2(0, 1)).should be_true
    o = Node2D.new(position: v2(3, 4))
    n.distance_to(o).should eq 5
    n.direction_to(o).approx?(v2(0.6, 0.8)).should be_true
    n.rotation_degrees = 180
    n.rotation.should be_close(Math::PI, 1e-5)
  end

  gpu_it "draws children with the inherited transform and modulate" do
    root = SceneTree.root
    parent = Node2D.new(position: v2(8, 8))
    parent.modulate = Color.new(1, 0, 0)
    child = Polygon2D.rect(4, 4, Color::WHITE, centered: false)
    child.position = v2(2, 2)
    parent.add(child)
    root.add(parent)
    img = GPUSpec.render(16, 16) { |g| root.draw_tree(g) }
    img[11, 11].should eq Color::RED
    img[9, 9].should eq Color::BLACK
    img[14, 14].should eq Color::BLACK
  end

  gpu_it "orders siblings by z_index and hides invisible nodes" do
    root = SceneTree.root
    a = Polygon2D.rect(8, 8, Color::RED, centered: false)
    b = Polygon2D.rect(8, 8, Color::BLUE, centered: false)
    a.z_index = 1
    root.add(a, b)
    img = GPUSpec.render(8, 8) { |g| root.draw_tree(g) }
    img[4, 4].should eq Color::RED
    a.visible = false
    img = GPUSpec.render(8, 8) { |g| root.draw_tree(g) }
    img[4, 4].should eq Color::BLUE
  end
end

describe Eagle::Sprite2D do
  before_each { SceneTree.reset }

  gpu_it "draws centred, flipped and framed sprites" do
    src = Image.new(4, 2)
    src.fill_rect(0, 0, 2, 2, Color::RED)
    src.fill_rect(2, 0, 2, 2, Color::BLUE)
    tex = Texture.new(src, GPU::Filter::Nearest)
    s = Sprite2D.new(tex, v2(8, 8))
    s.scale = 2
    s.size.should eq v2(4, 2)
    s.rect.should eq Rect.new(-2, -1, 4, 2)
    s.global_rect.should eq Rect.new(4, 6, 8, 4)
    s.contains_point?(v2(5, 7)).should be_true
    s.contains_point?(v2(0, 0)).should be_false
    img = GPUSpec.render(16, 16) { |g| s.draw_tree(g) }
    img[5, 7].should eq Color::RED
    img[10, 7].should eq Color::BLUE
    img[8, 12].should eq Color::BLACK
    s.flip_h = true
    img = GPUSpec.render(16, 16) { |g| s.draw_tree(g) }
    img[5, 7].should eq Color::BLUE
    s.flip_h = false
    s.hframes = 2
    s.frame = 1
    s.size.should eq v2(2, 2)
    img = GPUSpec.render(16, 16) { |g| s.draw_tree(g) }
    img[7, 7].should eq Color::BLUE
    img[9, 9].should eq Color::BLUE
    tex.dispose
  end
end

describe Eagle::AnimatedSprite2D do
  gpu_it "advances frames, loops and finishes" do
    tex = Texture.new(Image.new(8, 2))
    frames = tex.frames(2, 2)
    frames.size.should eq 4
    s = AnimatedSprite2D.new
    finished = [] of String
    changed = 0
    s.on_animation_finished { |n| finished << n }
    s.on_frame_changed { changed += 1 }
    s.add_animation("run", frames, fps: 4)
    s.add_animation("once", frames[0, 2], fps: 2, loop: false)
    s.play("run")
    s.playing?.should be_true
    s.process(0.3_f32)
    s.frame_index.should eq 1
    s.process(0.9_f32) # total 1.2s => frame 4.8 -> loops to 0
    s.frame_index.should eq 0
    changed.should be >= 2
    s.play("once")
    s.process(0.6_f32)
    s.frame_index.should eq 1
    s.process(0.5_f32)
    s.playing?.should be_false
    finished.should eq ["once"]
    expect_raises(Eagle::Error) { s.play("nope") }
    tex.dispose
  end
end

describe Eagle::Label do
  gpu_it "measures and draws text" do
    l = Label.new("Hi", v2(0, 0))
    l.size.should eq v2(2 * 6 * 2, 8 * 2)
    l.wrap = true
    l.width = 30
    l.text = "one two"
    l.layout
    l.size.y.should eq 2 * 16
    img = GPUSpec.render(32, 32) { |g| l.draw_tree(g) }
    img.average(0, 0, 32, 32).r.should be > 0.02
  end
end

describe Eagle::Camera2D do
  before_each { SceneTree.reset }

  it "becomes current when entering the tree and follows targets" do
    cam = Camera2D.new(zoom: 2)
    cam.viewport = v2(100, 100)
    Camera2D.current.should be_nil
    SceneTree.root.add(cam)
    Camera2D.current.should eq cam
    cam.current?.should be_true
    target = Node2D.new(position: v2(50, 50))
    SceneTree.root.add(target)
    cam.follow(target)
    cam.smoothing = 0
    cam.process(0.016_f32)
    cam.global_position.should eq v2(50, 50)
    cam.world_to_screen(v2(50, 50)).should eq v2(50, 50)
    cam.screen_to_world(v2(0, 0)).should eq v2(25, 25)
    cam.bounds.should eq Rect.new(25, 25, 50, 50)
    cam.limits = Rect.new(0, 0, 60, 60)
    cam.effective_position.should eq v2(35, 35)
    cam.free
    Camera2D.current.should be_nil
  end

  it "shakes and settles" do
    cam = Camera2D.new
    cam.shake(10, 0.5)
    cam.process(0.1_f32)
    cam.effective_position.should_not eq Vec2::ZERO
    cam.process(1.0_f32)
    cam.effective_position.should eq Vec2::ZERO
  end

  gpu_it "is applied to the scene tree but not to CanvasLayers" do
    root = SceneTree.root
    cam = Camera2D.new(position: v2(100, 100))
    cam.viewport = v2(16, 16)
    world = Polygon2D.rect(4, 4, Color::RED, centered: false)
    world.position = v2(100, 100)
    hud = CanvasLayer.new
    hud.add(Polygon2D.rect(2, 2, Color::GREEN, centered: false))
    root.add(cam, world, hud)
    img = GPUSpec.render(16, 16) do |g|
      g.camera = Camera2D.current
      root.draw_tree(g)
      g.camera = nil
    end
    img[9, 9].should eq Color::RED
    img[0, 0].should eq Color::GREEN
    img[4, 4].should eq Color::BLACK
  end
end

describe Eagle::Timer do
  before_each { SceneTree.reset }

  it "fires timeouts, one-shot or repeating" do
    hits = 0
    t = Timer.new(1.0, one_shot: true, autostart: true) { hits += 1 }
    SceneTree.root.add(t)
    t.running?.should be_true
    t.process(0.6_f32)
    hits.should eq 0
    t.time_left.should be_close(0.4, 1e-5)
    t.progress.should be_close(0.6, 1e-5)
    t.process(0.5_f32)
    hits.should eq 1
    t.running?.should be_false
    r = Timer.new(0.5).start
    n = 0
    r.on_timeout { n += 1 }
    r.process(1.2_f32)
    n.should eq 2
    r.paused = true
    r.process(1.0_f32)
    n.should eq 2
    r.stop
    r.stopped?.should be_true
  end
end

describe Eagle::TileMap do
  gpu_it "stores cells, converts coordinates and draws" do
    img = Image.new(4, 2)
    img.fill_rect(0, 0, 2, 2, Color::RED)
    img.fill_rect(2, 0, 2, 2, Color::BLUE)
    tex = Texture.new(img, GPU::Filter::Nearest)
    map = TileMap.new(tex, 2, 2)
    map.tile_count.should eq 2
    map.load_layout("0 1\n. 0")
    map[0, 0].should eq 0
    map[1, 0].should eq 1
    map[0, 1].should eq -1
    map.cell_count.should eq 3
    map.width.should eq 2
    map.position = v2(4, 4)
    map.world_to_cell(v2(7, 5)).should eq({1, 0})
    map.cell_to_world(1, 1).should eq v2(6, 6)
    out_img = GPUSpec.render(16, 16) { |g| map.draw_tree(g) }
    out_img[4, 4].should eq Color::RED
    out_img[6, 4].should eq Color::BLUE
    out_img[4, 6].should eq Color::BLACK
    out_img[6, 6].should eq Color::RED
    map.set_cell(0, 0, -1)
    map.cell_count.should eq 2
    tex.dispose
  end
end
