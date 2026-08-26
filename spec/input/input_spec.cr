require "../spec_helper"

describe Eagle::Input do
  before_each { Input.reset }

  it "tracks key down/pressed/released per frame" do
    Input.begin_frame
    Input.handle(KeyEvent.new(Key::Space, true))
    Input.pressed?(Key::Space).should be_true
    Input.down?(Key::Space).should be_true
    Input.begin_frame
    Input.pressed?(Key::Space).should be_false
    Input.down?(Key::Space).should be_true
    Input.handle(KeyEvent.new(Key::Space, false))
    Input.released?(Key::Space).should be_true
    Input.down?(Key::Space).should be_false
  end

  it "ignores key repeats for pressed?" do
    Input.begin_frame
    Input.handle(KeyEvent.new(Key::A, true))
    Input.begin_frame
    Input.handle(KeyEvent.new(Key::A, true, repeat: true))
    Input.pressed?(Key::A).should be_false
  end

  it "tracks the mouse" do
    Input.begin_frame
    Input.handle(MouseMotionEvent.new(v2(10, 20), v2(1, 2)))
    Input.handle(MouseMotionEvent.new(v2(12, 22), v2(2, 2)))
    Input.mouse.should eq v2(12, 22)
    Input.mouse_delta.should eq v2(3, 4)
    Input.handle(MouseButtonEvent.new(MouseButton::Right, true, v2(12, 22)))
    Input.mouse_pressed?(MouseButton::Right).should be_true
    Input.mouse_down?(MouseButton::Left).should be_false
    Input.handle(MouseWheelEvent.new(v2(0, 1), v2(0, 0)))
    Input.wheel.y.should eq 1
    Input.begin_frame
    Input.mouse_delta.should eq Vec2::ZERO
    Input.wheel.should eq Vec2::ZERO
  end

  it "maps actions to keys, buttons and gamepad axes" do
    Input.map "jump", Key::Space, GamepadButton::A
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Input.axis(GamepadAxis::LeftX, 1)
    Input.begin_frame
    Input.handle(KeyEvent.new(Key::Space, true))
    Input.pressed?("jump").should be_true
    Input.down?("jump").should be_true
    Input.strength("jump").should eq 1
    Input.handle(KeyEvent.new(Key::Left, true))
    Input.axis("left", "right").should eq -1
    Input.vector("left", "right", "jump", "jump").length.should be_close(1, 1e-5)

    # gamepad
    Input.handle(GamepadConnectionEvent.new(7, true))
    Input.gamepads.size.should eq 1
    Input.handle(GamepadAxisEvent.new(7, GamepadAxis::LeftX, 0.9_f32))
    Input.handle(KeyEvent.new(Key::Left, false))
    Input.end_poll
    Input.strength("right").should be_close((0.9 - 0.15) / 0.85, 1e-4)
    Input.down?("right").should be_true
    Input.pressed?("right").should be_true
    Input.begin_frame
    Input.end_poll
    Input.pressed?("right").should be_false
    Input.handle(GamepadAxisEvent.new(7, GamepadAxis::LeftX, 0.0_f32))
    Input.end_poll
    Input.released?("right").should be_true
    Input.handle(GamepadButtonEvent.new(7, GamepadButton::A, true))
    Input.pressed?("jump").should be_true
    Input.gamepad.not_nil!.down?(GamepadButton::A).should be_true
    Input.handle(GamepadConnectionEvent.new(7, false))
    Input.gamepads.should be_empty
  end

  it "applies gamepad deadzone" do
    Input.handle(GamepadConnectionEvent.new(1, true))
    Input.handle(GamepadAxisEvent.new(1, GamepadAxis::LeftY, 0.1_f32))
    Input.gamepad.not_nil!.axis(GamepadAxis::LeftY).should eq 0
    Input.gamepad.not_nil!.raw_axis(GamepadAxis::LeftY).should eq 0.1_f32
  end

  it "parses key names" do
    Key.named?("Space").should eq Key::Space
    Key.named?("space").should eq Key::Space
    Key.named?("nope").should be_nil
  end
end
