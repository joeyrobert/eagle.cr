require "../spec_helper"

private def touch(id, phase, x, y)
  ev = TouchEvent.new(id, phase, v2(x, y))
  Input.handle(ev)
  ev
end

# feeds a touch into Input then the recognizer, like the engine does
private def feed(g, id, phase, x, y)
  ev = TouchEvent.new(id, phase, v2(x, y))
  Input.handle(ev)
  g.input(ev)
end

private def wait(g, secs)
  # Clock clamps a single step, so advance in small ones
  (secs / 0.05).round.to_i.times do
    Clock.advance(0.05)
    g.process(0.05_f32)
  end
end

describe Eagle::Touch do
  before_each { Input.reset; Clock.reset }

  it "tracks several fingers with stable ids" do
    Input.begin_frame
    touch(0, TouchPhase::Began, 10, 10)
    touch(1, TouchPhase::Began, 50, 60)
    Touch.count.should eq 2
    Touch.finger(1).not_nil!.position.should eq v2(50, 60)
    touch(0, TouchPhase::Moved, 12, 14)
    Touch.finger(0).not_nil!.delta.should eq v2(2, 4)
    touch(0, TouchPhase::Ended, 12, 14)
    Touch.count.should eq 1
    Touch.released.map(&.id).should eq [0]
    Touch.finger(1).should_not be_nil
    Input.begin_frame
    Touch.released.should be_empty
    Touch.finger(1).not_nil!.began?.should be_false
  end

  it "removes cancelled fingers and marks them" do
    Input.begin_frame
    touch(3, TouchPhase::Began, 5, 5)
    touch(3, TouchPhase::Cancelled, 5, 5)
    Touch.any?.should be_false
    Touch.released.first.cancelled?.should be_true
  end

  it "reports pressure and event deltas" do
    Input.begin_frame
    Input.handle(TouchEvent.new(0, TouchPhase::Began, v2(0, 0), 0.4_f32))
    Touch.finger(0).not_nil!.pressure.should be_close(0.4, 1e-6)
    ev = touch(0, TouchPhase::Moved, 3, 4)
    ev.delta.should eq v2(3, 4)
  end

  it "separates taps from drags with a threshold" do
    Input.begin_frame
    touch(0, TouchPhase::Began, 100, 100)
    touch(0, TouchPhase::Moved, 104, 103)
    Touch.finger(0).not_nil!.dragging?.should be_false
    Touch.take_derived.should be_empty
    touch(0, TouchPhase::Moved, 130, 100)
    Touch.finger(0).not_nil!.dragging?.should be_true
    d = Touch.take_derived
    d.size.should eq 1
    d[0].as(TouchDragEvent).started?.should be_true
    touch(0, TouchPhase::Moved, 140, 100)
    m = Touch.take_derived[0].as(TouchDragEvent)
    m.moved?.should be_true
    m.delta.should eq v2(10, 0)
    m.total.should eq v2(40, 0)
    touch(0, TouchPhase::Ended, 140, 100)
    Touch.take_derived[0].as(TouchDragEvent).ended?.should be_true
  end

  it "honors a custom drag threshold" do
    Touch.drag_threshold = 50
    Input.begin_frame
    touch(0, TouchPhase::Began, 0, 0)
    touch(0, TouchPhase::Moved, 30, 0)
    Touch.finger(0).not_nil!.dragging?.should be_false
  end

  it "emulates the left mouse with the first finger only" do
    Input.begin_frame
    down = TouchEvent.new(0, TouchPhase::Began, v2(20, 30))
    Input.handle(down)
    evs = Touch.mouse_events(down)
    evs.size.should eq 2
    evs[1].as(MouseButtonEvent).pressed?.should be_true
    evs.all? { |e| e.as?(MouseButtonEvent).try(&.from_touch?) || e.as?(MouseMotionEvent).try(&.from_touch?) }.should be_true
    second = TouchEvent.new(1, TouchPhase::Began, v2(80, 80))
    Input.handle(second)
    Touch.mouse_events(second).should be_empty
    up = TouchEvent.new(0, TouchPhase::Ended, v2(20, 30))
    Input.handle(up)
    Touch.mouse_events(up).last.as(MouseButtonEvent).released?.should be_true
  end

  it "can turn mouse emulation off" do
    Touch.emulate_mouse?.should be_true
    Touch.emulate_mouse = false
    Touch.emulate_mouse?.should be_false
    Input.reset
    Touch.emulate_mouse?.should be_true
  end

  it "drives actions from virtual input" do
    Input.begin_frame
    Input.set_virtual("jump", 1)
    Input.pressed?("jump").should be_true
    Input.down?("jump").should be_true
    Input.strength("jump").should eq 1
    Input.begin_frame
    Input.pressed?("jump").should be_false
    Input.down?("jump").should be_true
    Input.set_virtual("jump", 0)
    Input.released?("jump").should be_true
    Input.down?("jump").should be_false
  end
end

describe Eagle::GestureRecognizer do
  before_each { Input.reset; Clock.reset }

  it "recognizes a tap and a double tap" do
    g = GestureRecognizer.new
    taps = [] of Vec2
    doubles = [] of Vec2
    g.on_tapped { |p| taps << p }
    g.on_double_tapped { |p| doubles << p }
    feed(g, 0, TouchPhase::Began, 50, 50)
    wait(g, 0.05)
    feed(g, 0, TouchPhase::Ended, 50, 50)
    taps.should eq [v2(50, 50)]
    wait(g, 0.1)
    feed(g, 0, TouchPhase::Began, 55, 52)
    wait(g, 0.05)
    feed(g, 0, TouchPhase::Ended, 55, 52)
    doubles.should eq [v2(55, 52)]
    taps.size.should eq 1
  end

  it "does not double tap when the gap is too long" do
    g = GestureRecognizer.new
    doubles = 0
    g.on_double_tapped { |_| doubles += 1 }
    2.times do
      feed(g, 0, TouchPhase::Began, 50, 50)
      feed(g, 0, TouchPhase::Ended, 50, 50)
      wait(g, 0.6)
    end
    doubles.should eq 0
  end

  it "fires a long press once and suppresses the tap" do
    g = GestureRecognizer.new
    presses = 0
    taps = 0
    g.on_long_pressed { |_| presses += 1 }
    g.on_tapped { |_| taps += 1 }
    feed(g, 0, TouchPhase::Began, 10, 10)
    wait(g, 0.3)
    presses.should eq 0
    wait(g, 0.3)
    wait(g, 0.3)
    presses.should eq 1
    feed(g, 0, TouchPhase::Ended, 10, 10)
    taps.should eq 0
  end

  it "recognizes a fast swipe but not a slow drag" do
    g = GestureRecognizer.new
    swipes = [] of Vec2
    g.on_swiped { |dir, _, _| swipes << dir }
    feed(g, 0, TouchPhase::Began, 100, 100)
    wait(g, 0.05)
    feed(g, 0, TouchPhase::Moved, 200, 100)
    wait(g, 0.05)
    feed(g, 0, TouchPhase::Ended, 250, 100)
    swipes.size.should eq 1
    swipes[0].x.should be_close(1, 1e-4)
    feed(g, 0, TouchPhase::Began, 100, 100)
    wait(g, 0.8)
    feed(g, 0, TouchPhase::Moved, 200, 100)
    feed(g, 0, TouchPhase::Ended, 250, 100)
    swipes.size.should eq 1
  end

  it "reports pinch scale and two-finger rotation" do
    g = GestureRecognizer.new
    scale = 0_f32
    angle = 0_f32
    taps = 0
    g.on_pinched { |s, _, _| scale = s }
    g.on_rotated { |a, _, _| angle = a }
    g.on_tapped { |_| taps += 1 }
    feed(g, 0, TouchPhase::Began, 100, 100)
    feed(g, 1, TouchPhase::Began, 200, 100)
    feed(g, 0, TouchPhase::Moved, 50, 100)
    feed(g, 1, TouchPhase::Moved, 250, 100)
    scale.should be_close(2, 1e-4)
    # rotate a quarter turn: finger 1 goes below finger 0
    feed(g, 0, TouchPhase::Moved, 150, 50)
    feed(g, 1, TouchPhase::Moved, 150, 150)
    angle.should be_close(Mathf::PI / 2, 1e-3)
    feed(g, 1, TouchPhase::Ended, 150, 150)
    feed(g, 0, TouchPhase::Ended, 150, 50)
    taps.should eq 0
  end
end
