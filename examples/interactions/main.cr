require "../../src/eagle"
include Eagle

# Every major interaction pattern in one scene, with a live event log.
# Run with EAGLE_DEMO=1 to have the engine drive the interactions itself.
#
#  1. Keyboard actions (WASD/arrows/gamepad) move the player; modifiers change speed.
#  2. Mouse hover / click / double-click / right-click on shapes (per-node input).
#  3. Drag & drop of crates (press, move, release) with snapping.
#  4. Mouse wheel zooms the camera; middle-drag pans it.
#  5. UI: buttons, slider, checkbox, text input, Tab focus navigation.
#  6. Signals between nodes (door opens when the switch is pressed).
#  7. Area2D triggers (walk into the zone).
#  8. Timers, tweens & audio feedback on interaction.
#  9. Pause (P) and scene reset (R); window resize; file drop.
# 10. Gamepad buttons/axes (real or injected).

class EventLog < CanvasLayer
  @lines = [] of String
  @label = Label.new("")
  MAX = 12
  @@instance : EventLog? = nil

  def self.instance : EventLog; @@instance ||= new; end
  def self.log(msg : String); instance.log(msg); end

  def initialize
    super("Log", 10)
    @label.position = v2(Window.width - 460, 40)
    @label.color = Color.gray(0.85)
    add(@label)
  end

  def lines; @lines; end

  def log(msg : String)
    @lines << "#{Clock.elapsed.round(1)}s #{msg}"
    @lines.shift if @lines.size > MAX
    @label.text = @lines.join("\n")
  end

  def resized(w : Int32, h : Int32)
    @label.position = v2(w - 460, 40)
  end
end

class Player < Sprite2D
  property speed = 200_f32
  signal entered_zone
  signal left_zone

  def initialize
    super(Texture.new(Image.circle(28, Color.hex("#ffd166"))), v2(160, 300), "Player")
    add(Polygon2D.rect(6, 6, Color::BLACK).tap(&.position = v2(6, -4)))
  end

  def process(dt : Float32)
    v = Input.vector("left", "right", "up", "down")
    mult = Input.shift? ? 2.5_f32 : 1_f32
    self.position += v * @speed * mult * dt
    self.position = position.clamp(v2(20, 60), Window.size - v2(20, 20))
  end
end

# A shape that reacts to hover, click, double-click and right-click.
class Clickable < Polygon2D
  property? hovered = false
  @flash = 0_f32
  @label : String

  def initialize(@label, position : Vec2, color : Color)
    super(Polygon2D.circle(26, color).points, color, name: @label, position: position)
  end

  def inside?(p : Vec2) : Bool; to_local(p).length <= 26; end

  def input(e : Event)
    case e
    when MouseMotionEvent
      was = @hovered
      @hovered = inside?(e.position)
      EventLog.log("hover #{@label}") if @hovered && !was
    when MouseButtonEvent
      return unless e.pressed? && inside?(e.position)
      e.handled = true # stop the click reaching nodes behind
      @flash = 0.25_f32
      Sounds.click(e.clicks)
      if e.button.right?
        EventLog.log("right-click #{@label}")
        self.color = Color.hsv(rand(360), 0.7, 1)
      elsif e.clicks >= 2
        EventLog.log("double-click #{@label}")
        Tween.value(self.scale, v2(1.5, 1.5), 0.15, ease: :back_out) { |s| self.scale = s }.on_complete do
          Tween.value(self.scale, Vec2::ONE, 0.2) { |s| self.scale = s }
        end
      else
        EventLog.log("click #{@label} (#{e.button})")
      end
    end
  end

  def process(dt : Float32)
    @flash = Math.max(0_f32, @flash - dt)
  end

  def draw(g : Graphics)
    g.circle(0, 0, 30, DrawMode::Line, Color::WHITE) if @hovered
    g.circle(0, 0, 26 + @flash * 40, DrawMode::Line, Color::WHITE.with_alpha(@flash * 3)) if @flash > 0
    super
    g.print(@label, 0, -6, Color::BLACK, align: TextAlign::Center)
  end
end

# Drag & drop with snapping to a 40px grid.
class Crate < Polygon2D
  @dragging = false
  @offset = Vec2::ZERO
  @@dragging_any = false

  def initialize(position : Vec2, color : Color)
    super(Polygon2D.rect(48, 48, color).points, color, name: "Crate", position: position)
  end

  def inside?(p : Vec2) : Bool
    l = to_local(p)
    l.x.abs <= 24 && l.y.abs <= 24
  end

  def input(e : Event)
    case e
    when MouseButtonEvent
      if e.pressed? && e.button.left? && inside?(e.position) && !@@dragging_any
        @dragging = true; @@dragging_any = true
        @offset = position - e.position
        self.z_index = 1
        e.handled = true
        EventLog.log("drag start crate")
      elsif e.released? && @dragging
        @dragging = false; @@dragging_any = false
        self.z_index = 0
        snapped = v2(Mathf.snapped(position.x, 40), Mathf.snapped(position.y, 40))
        Tween.value(position, snapped, 0.12, ease: :quad_out) { |p| self.position = p }
        Sounds.drop
        EventLog.log("drop crate at #{snapped.round}")
      end
    when MouseMotionEvent
      self.position = e.position + @offset if @dragging
    end
  end

  def draw(g : Graphics)
    g.rect(-26, -26, 52, 52, DrawMode::Line, Color::WHITE) if @dragging
    super
  end
end

class Switch < Area2D
  signal toggled(on : Bool)
  property? on = false

  def initialize(position : Vec2)
    super("Switch", position)
    box(40, 20)
    add(Polygon2D.rect(40, 20, Color.hex("#adb5bd")))
    on_body_entered do |b|
      next unless b.is_a?(Player)
      @on = !@on
      emit_toggled(@on)
      EventLog.log("switch #{@on ? "on" : "off"} (Area2D signal)")
    end
  end

  def draw(g : Graphics)
    g.rect(-14, -6, 28, 12, color: @on ? Color::GREEN : Color::RED)
  end
end

class Door < StaticBody2D
  @open = false
  @height = 100_f32

  def initialize(position : Vec2)
    super("Door", position)
    box(20, 100)
  end

  def open=(v : Bool)
    @open = v
    Tween.value(@height, v ? 4_f32 : 100_f32, 0.4, ease: :cubic_in_out) { |h| @height = h }
    body.enabled = !v
  end

  def draw(g : Graphics)
    g.rect(-10, -50, 20, @height, color: Color.hex("#8d99ae"))
  end
end

module Sounds
  @@click : Sound? = nil
  @@drop : Sound? = nil
  def self.init
    @@click = Sound.tone(900, 0.04, Sound::Wave::Square, 0.2)
    @@drop = Sound.tone(300, 0.1, Sound::Wave::Triangle, 0.3)
  end
  def self.click(n); @@click.try(&.play(pitch: n >= 2 ? 1.5 : 1)); end
  def self.drop; @@drop.try(&.play); end
end

class InteractionsDemo < App
  @player = Player.new
  @cam = Camera2D.new(zoom: 1)
  @world = Node2D.new("World")
  @paused = false
  @status = Label.new("")
  @zone_inside = false
  @gamepad_label = Label.new("gamepad: none")

  def load
    Sounds.init
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "action", Key::Space, GamepadButton::A
    root = SceneTree.root
    root.add(@world, @cam, EventLog.instance)
    build_world
    build_ui
    @cam.position = Window.center
    @cam.limits = Rect.new(-400, -300, Window.width + 800, Window.height + 600)
    demo_script if ENV["EAGLE_DEMO"]? == "1"
  end

  def build_world
    @world.clear_children
    # 2 & 3: clickable shapes and draggable crates
    @world.add(Clickable.new("A", v2(420, 140), Color.hex("#4cc9f0")), Clickable.new("B", v2(500, 140), Color.hex("#f72585")))
    @world.add(Crate.new(v2(420, 260), Color.hex("#b5651d")), Crate.new(v2(500, 260), Color.hex("#c98a3c")))
    # 6 & 7: switch -> door via signal; trigger zone
    switch = Switch.new(v2(200, 440))
    door = Door.new(v2(330, 420))
    switch.on_toggled { |on| door.open = on }
    zone = Area2D.new("Zone", v2(120, 180)).box(120, 100)
    zone.on_body_entered { |b| if b.is_a?(Player); @zone_inside = true; EventLog.log("entered zone"); @player.emit_entered_zone; end }
    zone.on_body_exited { |b| if b.is_a?(Player); @zone_inside = false; EventLog.log("left zone"); end }
    body = KinematicBody2D.new("PlayerBody").box(28, 28)
    body.add(@player.tap(&.position = Vec2::ZERO))
    body.position = v2(160, 300)
    @world.add(zone, switch, door, body)
    @world.add(Timer.new(3.0) { EventLog.log("timer tick (every 3s)") }.start)
  end

  def build_ui
    ui = CanvasLayer.new("UI", 5)
    panel = Panel.new(size: v2(300, 0))
    panel.position = v2(Window.width - 360, Window.height - 340)
    panel.fit_content = true
    box = VBox.new(size: v2(280, 0))
    box.position = v2(10, 10)
    box.fit_content = true
    box.add(Label.new("UI interactions (Tab cycles focus)"))
    row = HBox.new
    row.add(Button.new("Beep") { Sounds.click(1); EventLog.log("button Beep") })
    row.add(Button.new("Shake") { @cam.shake(6, 0.3); EventLog.log("button Shake") })
    row.add(Button.new("Reset (R)") { build_world; EventLog.log("scene reset") })
    box.add(row)
    slider = Slider.new(50, 400, 200, step: 10)
    slider.on_value_changed { |v| @player.speed = v; EventLog.log("speed #{v.to_i}") }
    box.add(HBox.new.tap { |h| h.add(Label.new("Speed"), slider.tap(&.size_flags = SizeFlags::ExpandX)) })
    check = CheckBox.new("Nearest filtering", false)
    check.on_toggled { |on| Texture.default_filter = on ? GPU::Filter::Nearest : GPU::Filter::Linear; EventLog.log("checkbox #{on}") }
    box.add(check)
    input = TextInput.new("", "type a message, Enter to send")
    input.on_submitted { |t| EventLog.log("submitted: #{t}"); input.text = "" }
    box.add(input)
    box.add(@gamepad_label)
    panel.add(box)
    @status.position = v2(10, 10)
    ui.add(panel, @status)
    SceneTree.root.add(ui)
  end

  def input(e : Event)
    case e
    when KeyEvent
      if e.pressed? && !e.repeat?
        case e.key
        when Key::P
          @paused = !@paused
          SceneTree.paused = @paused
          EventLog.log(@paused ? "paused (P)" : "resumed")
        when Key::R then build_world; EventLog.log("scene reset (R)")
        when Key::Escape then Eagle.quit unless Control.focused
        end
      end
    when MouseWheelEvent
      @cam.zoom = (@cam.zoom * (1 + e.delta.y * 0.1)).clamp(0.5_f32, 3_f32)
      EventLog.log("wheel zoom #{@cam.zoom.round(2)}")
    when MouseMotionEvent
      @cam.position -= e.delta / @cam.zoom if Input.mouse_down?(MouseButton::Middle)
    when WindowEvent
      EventLog.log("window #{e.kind} #{e.size.round}") if e.kind.resized?
    when FileDropEvent then EventLog.log("file dropped: #{File.basename(e.path)}")
    when GamepadConnectionEvent then EventLog.log("gamepad #{e.connected? ? "connected" : "removed"} ##{e.gamepad}")
    when GamepadButtonEvent then EventLog.log("gamepad button #{e.button} #{e.pressed? ? "down" : "up"}") if e.pressed?
    end
  end

  def update(dt : Float32)
    if Input.pressed?("action")
      EventLog.log("action pressed (space / A)")
      @cam.shake(3, 0.15)
    end
    if g = Input.gamepad
      @gamepad_label.text = "gamepad: #{g.name} L#{g.left_stick.round} A:#{g.down?(GamepadButton::A)}"
    end
    @status.text = "WASD move (Shift = run)  wheel zoom  middle-drag pan  P pause  R reset  Tab focus  Esc quit   zone: #{@zone_inside ? "inside" : "outside"}   #{@paused ? "PAUSED" : ""}   fps #{Clock.fps.round}"
  end

  def unload
    puts EventLog.instance.lines.join("\n") if ENV["EAGLE_DEMO"]? == "1"
  end

  # Scripted walkthrough used for the automated screenshot.
  def demo_script
    Script.hold(Key::D, 0.6, start: 0.2)
    Script.at(0.9) { Script.click(v2(420, 140)) }
    Script.at(1.1) { Script.click(v2(500, 140), clicks: 2) }
    Script.at(1.3) { Script.click(v2(420, 140), MouseButton::Right) }
    Script.drag(v2(500, 260), v2(600, 330), seconds: 0.4, start: 1.5)
    Script.at(2.1) { Script.wheel(v2(0, 2), v2(400, 300)) }
    Script.at(2.3) { Script.click(SceneTree.root.find_all(Button).find! { |b| b.text == "Beep" }.global_rect.center) }
    Script.at(2.5) { Script.key(Key::Tab); Script.key(Key::Tab) } # Tab to the next widgets
    Script.at(2.6) { Script.click(SceneTree.root.find_all(TextInput).first.global_rect.center) }
    Script.at(2.7) { Script.type("hello from a script"); Script.key(Key::Enter) }
    Script.at(2.9) { Script.connect_gamepad(0); Script.gamepad_button(0, GamepadButton::A) }
    Script.at(3.1) { Script.key(Key::Escape) }
    Script.hold(Key::S, 0.6, start: 3.2)
    Script.hold(Key::A, 0.4, start: 3.9)
    Script.at(4.4) { Script.drop_file("/tmp/level.png") }
  end
end

Eagle.run(InteractionsDemo, title: "Eagle interactions", width: 1100, height: 700)
