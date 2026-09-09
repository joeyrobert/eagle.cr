require "../gpu_spec_helper"

# End-to-end: drive the real frame loop (Eagle.step) with injected events.
private def frames(n)
  n.times { Eagle.step }
end

private class Mover < Node2D
  getter clicks = 0
  getter keys = [] of Key
  def process(dt : Float32)
    self.position += Input.vector("left", "right", "up", "down") * 100 * dt
  end
  def input(e : Event)
    case e
    when MouseButtonEvent then @clicks += 1 if e.pressed? && to_local(e.position).length < 20
    when KeyEvent then @keys << e.key if e.pressed?
    end
  end
end

describe "interactions through the engine loop" do
  before_each { SceneTree.reset; Input.reset; Script.clear }

  gpu_it "moves a node with held action keys" do
    Input.map "left", Key::A
    Input.map "right", Key::D
    Input.map "up", Key::W
    Input.map "down", Key::S
    m = Mover.new(position: v2(100, 100))
    SceneTree.root.add(m)
    Eagle.inject(KeyEvent.new(Key::D, true))
    frames(10)
    m.position.x.should be > 100
    Eagle.inject(KeyEvent.new(Key::D, false))
    x = m.position.x
    frames(3)
    m.position.x.should eq x
    m.keys.should eq [Key::D]
  end

  gpu_it "delivers clicks to nodes and respects handled" do
    m = Mover.new(position: v2(50, 50))
    SceneTree.root.add(m)
    Script.click(v2(50, 50))
    frames(2)
    m.clicks.should eq 1
    Script.click(v2(300, 300))
    frames(2)
    m.clicks.should eq 1
    # a button on top consumes the click
    layer = CanvasLayer.new
    b = Button.new("x", position: v2(30, 30), size: v2(40, 40))
    pressed = 0
    b.on_pressed { pressed += 1 }
    layer.add(b)
    SceneTree.root.add(layer)
    Script.click(v2(50, 50))
    frames(2)
    pressed.should eq 1
    m.clicks.should eq 1
  end

  gpu_it "drags a node with press/move/release" do
    dragged = [] of Vec2
    n = Node2D.new(position: v2(100, 100))
    dragging = false
    handler = Node.new
    handler.on_tree_entered { }
    SceneTree.root.add(n)
    Eagle.app.on_input do |e|
      case e
      when MouseButtonEvent
        dragging = e.pressed? && (e.position - n.position).length < 30
      when MouseMotionEvent
        if dragging
          n.position += e.delta
          dragged << n.position
        end
      end
    end
    Script.drag(v2(100, 100), v2(300, 200), seconds: 0.2, steps: 5)
    30.times { Eagle.step }
    n.position.approx?(v2(300, 200), 0.5).should be_true
    dragged.size.should be >= 5
  end

  gpu_it "types into a focused text input and submits" do
    layer = CanvasLayer.new
    t = TextInput.new("", "name", position: v2(10, 10), size: v2(200, 30))
    got = [] of String
    t.on_submitted { |s| got << s }
    layer.add(t)
    SceneTree.root.add(layer)
    Script.click(v2(50, 25))
    frames(2)
    t.focused?.should be_true
    Script.type("abc")
    Script.key(Key::Enter)
    frames(3)
    t.text.should eq "abc"
    got.should eq ["abc"]
  end

  gpu_it "cycles focus with Tab and Shift+Tab" do
    layer = CanvasLayer.new
    a = Button.new("a", position: v2(0, 0)); b = Button.new("b", position: v2(0, 50)); c = Button.new("c", position: v2(0, 100))
    layer.add(a, b, c)
    SceneTree.root.add(layer)
    Script.key(Key::Tab)
    frames(2)
    Control.focused.should eq a
    Script.key(Key::Tab)
    frames(2)
    Control.focused.should eq b
    Script.key(Key::Tab, KeyMod::Shift)
    frames(2)
    Control.focused.should eq a
    Script.key(Key::Escape)
    frames(2)
    Control.focused.should be_nil
  end

  gpu_it "handles gamepad events end to end" do
    Input.map "fire", GamepadButton::A
    Input.map "right", Input.axis(GamepadAxis::LeftX, 1)
    fired = 0
    Eagle.app.on_update { |dt| fired += 1 if Input.pressed?("fire") }
    Script.connect_gamepad(3)
    Script.gamepad_button(3, GamepadButton::A)
    frames(2)
    fired.should eq 1
    Script.gamepad_axis(3, GamepadAxis::LeftX, 1.0)
    frames(2)
    Input.strength("right").should eq 1
    Input.gamepad.not_nil!.id.should eq 3
  end

  gpu_it "runs scripts on a timeline" do
    order = [] of Int32
    Script.at(0.0) { order << 0 }
    Script.at(0.05) { order << 1 }
    Script.at(0.3) { order << 2 }
    frames(1)
    order.should eq [0]
    Script.tick(0.1)
    order.should eq [0, 1]
    Script.tick(0.3)
    order.should eq [0, 1, 2]
    Script.running?.should be_false
  end

  gpu_it "pauses the tree and keeps Always nodes running" do
    m = Mover.new; a = Mover.new
    a.process_mode = Node::ProcessMode::Always
    Input.map "right", Key::D
    SceneTree.root.add(m, a)
    SceneTree.paused = true
    Eagle.inject(KeyEvent.new(Key::D, true))
    frames(5)
    m.position.x.should eq 0
    a.position.x.should be > 0
    SceneTree.paused = false
    frames(2)
    m.position.x.should be > 0
    Eagle.inject(KeyEvent.new(Key::D, false))
  end

  gpu_it "reports Area2D enter/exit as a body moves through it" do
    Physics2D.reset
    zone = Area2D.new(position: v2(200, 100)).box(60, 60)
    body = KinematicBody2D.new(position: v2(100, 100)).box(20, 20)
    events = [] of String
    zone.on_body_entered { |b| events << "in" }
    zone.on_body_exited { |b| events << "out" }
    SceneTree.root.add(zone, body)
    body.velocity = v2(400, 0)
    Eagle.app.on_fixed_update { |dt| body.move_and_slide(dt) }
    frames(60)
    events.should eq ["in", "out"]
    body.position.x.should be > 260
  end

  gpu_it "resizes and forwards window events" do
    sizes = [] of Vec2
    Eagle.app.on_input { |e| sizes << e.size if e.is_a?(WindowEvent) && e.kind.resized? }
    Eagle.inject(WindowEvent.new(WindowEventKind::Resized, v2(320, 240)))
    frames(1)
    sizes.should eq [v2(320, 240)]
  end
end
