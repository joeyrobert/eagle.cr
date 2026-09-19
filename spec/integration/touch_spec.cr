require "../gpu_spec_helper"

private def frames(n)
  n.times { Eagle.step(1 / 60) }
end

private class Dragger < Node2D
  getter drags = [] of TouchDragKind
  getter touches = 0
  getter mouse = 0
  property claim = false

  def input(e : Event)
    case e
    when TouchDragEvent
      @drags << e.kind
      self.position += e.delta if e.moved?
    when TouchEvent
      @touches += 1
      e.handled = true if @claim
    when MouseButtonEvent then @mouse += 1
    end
  end
end

describe "touch through the engine loop" do
  before_each { SceneTree.reset; Input.reset; Script.clear }

  gpu_it "delivers drag events to nodes" do
    d = Dragger.new(position: v2(100, 100))
    SceneTree.root.add(d)
    Script.touch_drag(v2(50, 50), v2(150, 50), seconds: 0.2, steps: 5)
    frames(30)
    d.drags.first.should eq TouchDragKind::Started
    d.drags.last.should eq TouchDragKind::Ended
    d.position.x.should be > 100
    Touch.any?.should be_false
  end

  gpu_it "taps a button through mouse emulation exactly once" do
    layer = CanvasLayer.new
    b = Button.new("x", position: v2(30, 30), size: v2(80, 40))
    pressed = 0
    b.on_pressed { pressed += 1 }
    layer.add(b)
    SceneTree.root.add(layer)
    Script.touch_tap(v2(50, 50))
    frames(2)
    pressed.should eq 1
    Script.touch_tap(v2(400, 400))
    frames(2)
    pressed.should eq 1
  end

  gpu_it "drags a slider with a finger" do
    layer = CanvasLayer.new
    s = Slider.new(0, 100, 0, position: v2(20, 20), size: v2(200, 24))
    layer.add(s)
    SceneTree.root.add(layer)
    Script.touch_drag(v2(20, 32), v2(120, 32), seconds: 0.2, steps: 4)
    frames(30)
    s.value.should be_close(50, 5)
  end

  gpu_it "skips mouse events for touches a node claims" do
    d = Dragger.new
    d.claim = true
    SceneTree.root.add(d)
    Script.touch_tap(v2(5, 5))
    frames(2)
    d.touches.should eq 2
    d.mouse.should eq 0
  end

  gpu_it "emits mouse events for unclaimed touches and honors the flag" do
    d = Dragger.new
    SceneTree.root.add(d)
    Script.touch_tap(v2(5, 5))
    frames(2)
    d.mouse.should eq 2
    Touch.emulate_mouse = false
    Script.touch_tap(v2(5, 5))
    frames(2)
    d.mouse.should eq 2
  end

  gpu_it "handles a cancelled touch without clicking" do
    layer = CanvasLayer.new
    b = Button.new("x", position: v2(30, 30), size: v2(80, 40))
    pressed = 0
    b.on_pressed { pressed += 1 }
    layer.add(b)
    SceneTree.root.add(layer)
    Script.touch_down(0, v2(50, 50))
    frames(1)
    Script.touch_cancel(0, v2(50, 50))
    frames(2)
    pressed.should eq 0
    Touch.any?.should be_false
  end

  gpu_it "pinches and twists through the recognizer" do
    g = GestureRecognizer.new
    scale = 1_f32
    angle = 0_f32
    g.on_pinched { |s, _, _| scale = s }
    g.on_rotated { |a, _, _| angle = a }
    SceneTree.root.add(g)
    Script.pinch(v2(300, 200), 100, 200, seconds: 0.2, steps: 4)
    frames(30)
    scale.should be_close(2, 0.01)
    Script.twist(v2(300, 200), 60, Mathf::PI / 2, seconds: 0.2, start: 0, steps: 4)
    frames(30)
    angle.should be_close(Mathf::PI / 2, 0.05)
  end

  gpu_it "drives actions from the joystick and virtual buttons with multi-touch" do
    Input.map "left", Key::A
    Input.map "right", Key::D
    Input.map "up", Key::W
    Input.map "down", Key::S
    Input.map "jump", Key::Space
    layer = CanvasLayer.new
    stick = VirtualJoystick.new(v2(20, 300), 60).bind("left", "right", "up", "down")
    jump = VirtualButton.new("jump", "A", v2(400, 300), 80)
    layer.add(stick, jump)
    SceneTree.root.add(layer)
    Script.touch_down(0, v2(80, 360))
    Script.touch_down(1, v2(440, 340))
    frames(2)
    stick.held?.should be_true
    jump.held?.should be_true
    Input.down?("jump").should be_true
    Script.touch_move(0, v2(140, 360))
    frames(2)
    Input.strength("right").should be > 0.9
    Input.down?("left").should be_false
    Script.touch_up(0, v2(140, 360))
    frames(2)
    stick.value.should eq Vec2::ZERO
    Input.down?("right").should be_false
    Input.down?("jump").should be_true
    Script.touch_cancel(1, v2(440, 340))
    frames(2)
    Input.down?("jump").should be_false
  end
end
