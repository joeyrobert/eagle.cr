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

  gpu_it "anchors inside its parent" do
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

  gpu_it "toggles buttons and checkboxes" do
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

  gpu_it "edits text input" do
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

  gpu_it "lays out boxes and grids" do
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

private def rows(n)
  list = VBox.new
  n.times { |i| list.add(Button.new("Row #{i}", size: v2(50, 30))) }
  list
end

private def option_items
  SceneTree.root.children.compact_map { |c| c.as?(OptionButton::Overlay) }.first?
end

private def item_at(index : Int32) : OptionButton::Item
  found = [] of OptionButton::Item
  SceneTree.root.each_descendant { |n| found << n.as(OptionButton::Item) if n.is_a?(OptionButton::Item) }
  found.find! { |i| i.index == index }
end

describe Eagle::ScrollContainer do
  before_each { SceneTree.reset }

  gpu_it "sizes content and scrolls with the wheel" do
    sc = ScrollContainer.new(size: v2(200, 100))
    list = rows(10)
    sc.add(list)
    SceneTree.root.add(sc)
    offsets = [] of Float32
    sc.on_scrolled { |o| offsets << o.y }
    sc.layout
    list.layout
    sc.viewport.should eq v2(190, 100)
    list.size.x.should eq 190
    list.size.y.should be > 100
    sc.max_scroll.y.should eq list.size.y - 100
    SceneTree.dispatch_input(MouseMotionEvent.new(v2(50, 50), Vec2::ZERO))
    SceneTree.dispatch_input(MouseWheelEvent.new(v2(0, -1), v2(50, 50)))
    sc.scroll.y.should eq 32
    list.position.y.should eq -32
    SceneTree.dispatch_input(MouseWheelEvent.new(v2(0, 5), v2(50, 50)))
    sc.scroll.y.should eq 0
    sc.scroll_to(v2(0, 10000))
    sc.scroll.y.should eq sc.max_scroll.y
    offsets.size.should eq 3
    sc.scroll.x.should eq 0
  end

  gpu_it "hides bars and ignores scrolling when content fits" do
    sc = ScrollContainer.new(size: v2(200, 400))
    sc.add(rows(2))
    SceneTree.root.add(sc)
    sc.layout
    sc.viewport.should eq v2(200, 400)
    sc.max_scroll.should eq Vec2::ZERO
    sc.scroll_to(v2(0, 50))
    sc.scroll.should eq Vec2::ZERO
  end

  gpu_it "scrolls horizontally when enabled" do
    sc = ScrollContainer.new(size: v2(100, 100))
    sc.horizontal = true
    sc.vertical = false
    row = HBox.new
    6.times { |i| row.add(Button.new("Btn #{i}", size: v2(60, 30))) }
    sc.add(row)
    SceneTree.root.add(sc)
    sc.layout
    sc.viewport.y.should eq 90
    sc.max_scroll.x.should be > 0
    sc.max_scroll.y.should eq 0
    sc.scroll_to(v2(40, 20))
    sc.scroll.should eq v2(40, 0)
  end

  gpu_it "drags the bar and pages on the track" do
    sc = ScrollContainer.new(size: v2(200, 100))
    sc.add(rows(10))
    SceneTree.root.add(sc)
    sc.layout
    x = sc.viewport.x + 5
    click(sc, v2(x, 95))
    sc.scroll.y.should eq Math.min(100_f32, sc.max_scroll.y)
    sc.scroll_to(Vec2::ZERO)
    SceneTree.dispatch_input(MouseMotionEvent.new(v2(x, 5), Vec2::ZERO))
    SceneTree.dispatch_input(MouseButtonEvent.new(MouseButton::Left, true, v2(x, 5)))
    SceneTree.dispatch_input(MouseMotionEvent.new(v2(x, 500), Vec2::ZERO))
    sc.scroll.y.should eq sc.max_scroll.y
    SceneTree.dispatch_input(MouseButtonEvent.new(MouseButton::Left, false, v2(x, 500)))
    SceneTree.dispatch_input(MouseMotionEvent.new(v2(x, 0), Vec2::ZERO))
    sc.scroll.y.should eq sc.max_scroll.y
  end

  gpu_it "does not click content clipped out of view" do
    sc = ScrollContainer.new(size: v2(200, 100))
    list = VBox.new
    list.add(Button.new("top").tap { |b| b.min_size = v2(50, 90) })
    far = Button.new("far")
    far.min_size = v2(50, 90)
    list.add(far)
    sc.add(list)
    SceneTree.root.add(sc)
    sc.layout
    list.layout
    hits = 0
    far.on_pressed { hits += 1 }
    click(far, v2(20, 150))
    hits.should eq 0
    sc.ensure_visible(far)
    sc.layout
    list.layout
    sc.scroll.y.should be > 0
    click(far)
    hits.should eq 1
  end

  gpu_it "clips drawing to the viewport" do
    root = SceneTree.root
    layer = CanvasLayer.new
    sc = ScrollContainer.new(position: v2(10, 10), size: v2(40, 30))
    sc.color = Color::BLACK
    sc.add(Panel.new(size: v2(200, 200)).tap { |p| p.color = Color::WHITE; p.show_border = false })
    layer.add(sc)
    root.add(layer)
    root.process_tree(0.016_f32)
    img = GPUSpec.render(100, 100) { |g| root.draw_tree(g) }
    img.average(15, 15, 10, 10).r.should be > 0.9
    img.average(60, 60, 30, 30).r.should be < 0.05
    img.average(15, 45, 20, 20).r.should be < 0.05
  end
end

describe Eagle::OptionButton do
  before_each { SceneTree.reset }

  gpu_it "selects an item by clicking the list" do
    ob = OptionButton.new(["Forest", "Desert", "Ocean"], position: v2(20, 20))
    SceneTree.root.add(ob)
    picked = [] of Int32
    ob.on_item_selected { |i| picked << i }
    ob.selected.should eq 0
    ob.selected_text.should eq "Forest"
    click(ob)
    ob.open?.should be_true
    SceneTree.root.process_tree(0.016_f32)
    click(item_at(2))
    ob.open?.should be_false
    ob.selected.should eq 2
    ob.selected_text.should eq "Ocean"
    picked.should eq [2]
    option_items.should be_nil
  end

  gpu_it "closes on an outside click and escape" do
    ob = OptionButton.new(["A", "B"], position: v2(20, 20))
    SceneTree.root.add(ob)
    click(ob)
    ob.open?.should be_true
    SceneTree.root.process_tree(0.016_f32)
    click(ob, v2(400, 300))
    ob.open?.should be_false
    ob.selected.should eq 0
    ob.grab_focus
    key(Key::Enter)
    ob.open?.should be_true
    key(Key::Escape)
    ob.open?.should be_false
  end

  gpu_it "picks with the keyboard" do
    ob = OptionButton.new(["A", "B", "C"], position: v2(20, 20))
    SceneTree.root.add(ob)
    picked = [] of Int32
    ob.on_item_selected { |i| picked << i }
    ob.grab_focus
    key(Key::Down)
    ob.open?.should be_true
    key(Key::Down)
    key(Key::Down)
    key(Key::Down)
    key(Key::Enter)
    ob.selected.should eq 2
    picked.should eq [2]
    ob.open?.should be_false
  end

  gpu_it "edits items and handles empty or disabled lists" do
    ob = OptionButton.new
    ob.selected.should eq -1
    ob.selected_text.should eq ""
    SceneTree.root.add(ob)
    ob.open
    ob.open?.should be_false
    ob.add_item("One")
    ob.add_item("Two")
    ob.selected.should eq 0
    ob.selected = 5
    ob.selected.should eq 1
    ob.items = ["X"]
    ob.selected.should eq 0
    ob.disabled = true
    ob.open
    ob.open?.should be_false
    ob.clear
    ob.selected.should eq -1
  end

  gpu_it "draws the closed field and open list" do
    root = SceneTree.root
    layer = CanvasLayer.new
    ob = OptionButton.new(["Alpha", "Beta"], position: v2(10, 10))
    layer.add(ob)
    root.add(layer)
    root.process_tree(0.016_f32)
    ob.open
    root.process_tree(0.016_f32)
    img = GPUSpec.render(200, 200) { |g| root.draw_tree(g) }
    img.average(10, 10, ob.size.x.to_i, ob.size.y.to_i).a.should be > 0.5
    img.average(10, (ob.size.y + 12).to_i, 20, 10).a.should be > 0.5
  end
end

describe Eagle::RichTextLabel do
  before_each { SceneTree.reset }

  it "parses bold, color and url markup" do
    spans = RichTextLabel.parse("a **b** [color=#ff0000]c[/color][b]d[/b][url=go]e[/url] [x] [color=zz]")
    spans.map(&.text).should eq ["a ", "b", " ", "c", "d", "e", " [x] [color=zz]"]
    spans[1].bold?.should be_true
    spans[0].bold?.should be_false
    spans[3].color.should eq Color.hex("#ff0000")
    spans[4].bold?.should be_true
    spans[5].url.should eq "go"
    spans[6].color.should be_nil
  end

  it "strips markup for plain text and re-parses on change" do
    l = RichTextLabel.new("x **y**")
    l.plain_text.should eq "x y"
    l.text = "[b]z[/b]"
    l.plain_text.should eq "z"
    RichText.new("q").plain_text.should eq "q"
  end

  gpu_it "lays out runs with styles and newlines" do
    l = RichTextLabel.new("ab **cd**\n[color=#00ff00]ef[/color]")
    l.layout
    l.line_count.should eq 2
    l.runs.first.position.should eq Vec2::ZERO
    l.runs.first.color.should eq Theme.default.text
    bold = l.runs.find!(&.bold?)
    bold.position.x.should be > 0
    last = l.runs.last
    last.position.y.should be > 0
    last.position.x.should eq 0
    last.color.should eq Color.hex("#00ff00")
  end

  gpu_it "wraps to the width" do
    l = RichTextLabel.new("one two three four five six seven eight", size: v2(80, 10))
    l.wrap = true
    l.layout
    l.line_count.should be > 2
    l.runs.each { |r| (r.position.x + r.size.x).should be <= 80.01 }
    l.height.should be > 30
  end

  gpu_it "emits meta_clicked for links only" do
    l = RichTextLabel.new("go [url=door]here[/url] now", position: v2(10, 10))
    SceneTree.root.add(l)
    l.layout
    metas = [] of String
    l.on_meta_clicked { |m| metas << m }
    link = l.runs.find! { |r| r.url }
    click(l, l.to_global(link.rect.center))
    metas.should eq ["door"]
    click(l, l.to_global(l.runs.first.rect.center))
    metas.should eq ["door"]
  end

  gpu_it "draws text" do
    root = SceneTree.root
    layer = CanvasLayer.new
    layer.add(RichTextLabel.new("**Hi** [color=#ff0000]there[/color]", position: v2(4, 4)))
    root.add(layer)
    root.process_tree(0.016_f32)
    img = GPUSpec.render(100, 30) { |g| root.draw_tree(g) }
    img.average(0, 0, 100, 30).a.should be > 0.01
  end
end
