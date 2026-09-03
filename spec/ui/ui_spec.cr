require "../gpu_spec_helper"

private def click(control : Control, at : Vec2? = nil)
  p = at || control.global_rect.center
  SceneTree.dispatch_input(MouseMotionEvent.new(p, Vec2::ZERO))
  SceneTree.dispatch_input(MouseButtonEvent.new(MouseButton::Left, true, p))
  SceneTree.dispatch_input(MouseButtonEvent.new(MouseButton::Left, false, p))
end

private def key(k : Key, mods = KeyMod::None)
  SceneTree.dispatch_input(KeyEvent.new(k, true, false, mods))
  SceneTree.dispatch_input(KeyEvent.new(k, false, false, mods))
end

describe Eagle::Control do
  before_each { SceneTree.reset }

  it "anchors inside its parent" do
    panel = Panel.new(size: v2(200, 100))
    b = Panel.new(size: v2(50, 20))
    b.anchor = Anchor::BottomRight
    b.margin = Vec4.new(-10, -10, 0, 0)
    panel.add(b)
    SceneTree.root.add(panel)
    b.layout
    b.position.should eq v2(140, 70)
    fill = Panel.new
    fill.anchor = Anchor::Fill
    fill.margin = Vec4.new(5, 5, 5, 5)
    panel.add(fill)
    fill.layout
    fill.position.should eq v2(5, 5)
    fill.size.should eq v2(190, 90)
    c = Label.new("t")
    c.anchor = Anchor::Center
    panel.add(c)
    c.layout
    c.position.x.should be_close(100 - c.size.x / 2, 0.01)
  end

  it "tracks hover, focus and click" do
    b = Button.new("Go", position: v2(10, 10), size: v2(80, 30))
    SceneTree.root.add(b)
    hits = 0
    b.on_pressed { hits += 1 }
    entered = 0
    b.on_mouse_entered { entered += 1 }
    click(b)
    hits.should eq 1
    entered.should eq 1
    b.hovered?.should be_true
    b.focused?.should be_true
    Control.focused.should eq b
    click(b, v2(300, 300)) # outside: releases focus
    b.focused?.should be_false
    b.hovered?.should be_false
    hits.should eq 1
    b.disabled = true
    click(b)
    hits.should eq 1
    b.disabled = false
    b.grab_focus
    key(Key::Enter)
    hits.should eq 2
    b.click
    hits.should eq 3
  end

  it "toggles buttons and checkboxes" do
    b = Button.new("T", size: v2(40, 20))
    b.toggle_mode = true
    states = [] of Bool
    b.on_toggled { |s| states << s }
    SceneTree.root.add(b)
    click(b); click(b)
    states.should eq [true, false]
    c = CheckBox.new("Enable", position: v2(0, 50))
    SceneTree.root.add(c)
    got = [] of Bool
    c.on_toggled { |v| got << v }
    click(c)
    c.checked?.should be_true
    c.grab_focus
    key(Key::Space)
    c.checked?.should be_false
    got.should eq [true, false]
  end

  it "slides values with mouse, wheel and keys" do
    s = Slider.new(0, 100, 50, step: 10, size: v2(200, 20))
    SceneTree.root.add(s)
    changes = [] of Float32
    s.on_value_changed { |v| changes << v }
    s.value = 55
    s.value.should eq 60 # snapped
    click(s, v2(199, 10))
    s.value.should eq 100
    click(s, v2(0, 10))
    s.value.should eq 0
    s.grab_focus
    key(Key::Right)
    s.value.should eq 10
    SceneTree.dispatch_input(MouseMotionEvent.new(v2(100, 10), Vec2::ZERO))
    SceneTree.dispatch_input(MouseWheelEvent.new(v2(0, 1), v2(100, 10)))
    s.value.should eq 20
    s.ratio.should eq 0.2_f32
    changes.size.should eq 5
  end

  it "edits text input" do
    t = TextInput.new("", "type here", size: v2(200, 30))
    SceneTree.root.add(t)
    submitted = [] of String
    t.on_submitted { |s| submitted << s }
    click(t)
    t.focused?.should be_true
    SceneTree.dispatch_input(TextEvent.new("ab"))
    SceneTree.dispatch_input(TextEvent.new("c"))
    t.text.should eq "abc"
    key(Key::Left)
    key(Key::Backspace)
    t.text.should eq "ac"
    key(Key::Home)
    key(Key::Delete)
    t.text.should eq "c"
    key(Key::End)
    SceneTree.dispatch_input(TextEvent.new("d"))
    t.text.should eq "cd"
    key(Key::Enter)
    submitted.should eq ["cd"]
    t.max_length = 3
    SceneTree.dispatch_input(TextEvent.new("xyz"))
    t.text.size.should eq 3
    key(Key::Escape)
    t.focused?.should be_false
  end

  it "lays out boxes and grids" do
    v = VBox.new(size: v2(200, 300))
    a = Button.new("A", size: v2(50, 30))
    b = Button.new("B", size: v2(50, 30))
    b.size_flags = SizeFlags::ExpandY
    v.add(a, b)
    SceneTree.root.add(v)
    v.padding = 10; v.spacing = 5
    v.layout
    a.position.should eq v2(10, 10)
    a.size.x.should eq 180 # stretched
    b.position.y.should eq 10 + a.size.y + 5
    (b.position.y + b.size.y).should be_close(290, 0.01)
    h = HBox.new(size: v2(300, 50))
    h.padding = 0; h.spacing = 0
    h.align = :center
    x = Label.new("x"); y = Spacer.new; z = Label.new("z")
    h.add(x, y, z)
    SceneTree.root.add(h)
    h.layout
    x.position.x.should eq 0
    z.position.x.should be_close(300 - z.size.x, 0.01)
    g = GridContainer.new(2, size: v2(200, 100))
    g.padding = 0; g.spacing = 0
    4.times { |i| g.add(Button.new("#{i}", size: v2(40, 20))) }
    SceneTree.root.add(g)
    g.layout
    kids = g.control_children
    kids[1].position.x.should eq 100
    kids[2].position.y.should eq kids[0].size.y
    v.content_min_size.y.should be > 60
  end

  it "inherits themes" do
    t = Theme.new
    t.text = Color::RED
    panel = Panel.new
    panel.theme = t
    l = Label.new("x")
    panel.add(l)
    l.theme_or_inherited.should eq t
    Label.new("y").theme_or_inherited.should eq Theme.default
    t.light.text.should_not eq Color::RED
  end

  gpu_it "draws widgets" do
    root = SceneTree.root
    layer = CanvasLayer.new
    v = VBox.new(size: v2(200, 200))
    v.add(Label.new("Hello"), Button.new("Press"), CheckBox.new("Check", true), Slider.new(0, 1, 0.5), ProgressBar.new(0.75), TextInput.new("text"))
    layer.add(v)
    root.add(layer)
    root.process_tree(0.016_f32)
    img = GPUSpec.render(200, 200) { |g| root.draw_tree(g) }
    img.average.r.should be > 0.05
    img.average(0, 0, 200, 200).a.should be > 0.5
  end
end
