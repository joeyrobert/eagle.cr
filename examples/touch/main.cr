require "../../src/eagle"
include Eagle

# Touch showcase for phones and tablets (or Chrome device emulation on the web build).
#
#  1. Drag the cards: each one claims the finger that lands on it and moves with drag events.
#  2. Pinch and twist the big star with two fingers (GestureRecognizer), double tap to reset it.
#  3. The virtual joystick moves the dot through the same "left/right/up/down" actions as WASD.
#  4. The virtual button fires a pulse through the "fire" action, which is also mapped to Space.
#  5. The buttons at the top are plain UI, driven by touch through mouse emulation.
# Run with EAGLE_DEMO=1 to have the engine play synthetic touches itself.

class Card < Node2D
  W = 120
  H = 80
  @finger : Int32? = nil
  @flash = 0_f32

  def initialize(position : Vec2, @color : Color, @label : String)
    super("Card", position)
  end

  def input(e : Event)
    case e
    when TouchEvent
      local = to_local(e.position)
      if e.began? && @finger.nil? && local.x.abs <= W / 2 && local.y.abs <= H / 2
        @finger = e.id
        self.z_index = 1
        e.handled = true
      elsif e.id == @finger && (e.ended? || e.cancelled?)
        @flash = 0.3_f32 unless Touch.released.any? { |f| f.id == e.id && f.dragging? }
        @finger = nil
        self.z_index = 0
      end
    when TouchDragEvent
      self.position += e.delta if e.moved? && e.id == @finger
    end
  end

  def process(dt : Float32)
    @flash = Math.max(0_f32, @flash - dt)
  end

  def draw(g : Graphics)
    g.rounded_rect(-W / 2 + 3, -H / 2 + 5, W, H, 10, color: Color.new(0, 0, 0, 0.35)) if @finger
    g.rounded_rect(-W / 2, -H / 2, W, H, 10, color: @color.lerp(Color::WHITE, @flash * 2))
    g.rounded_rect(-W / 2, -H / 2, W, H, 10, DrawMode::Line, @finger ? Color::WHITE : Color.gray(0.15))
    g.print(@label, 0, -6, Color::BLACK, align: TextAlign::Center)
  end
end

class TouchDemo < App
  @star = Polygon2D.regular(5, 70, Color.hex("#ffd166"))
  @dot : Vec2 = v2(200, 380)
  @pulse = 0_f32
  @log = Label.new("")
  @lines = [] of String
  @fingers = Label.new("")

  def load
    Input.map "left", Key::A, Key::Left
    Input.map "right", Key::D, Key::Right
    Input.map "up", Key::W, Key::Up
    Input.map "down", Key::S, Key::Down
    Input.map "fire", Key::Space

    @star.position = v2(Window.width / 2, Window.height / 2 - 10)
    SceneTree.root.add(@star)
    SceneTree.root.add(Card.new(v2(150, 150), Color.hex("#4cc9f0"), "drag me"))
    SceneTree.root.add(Card.new(v2(Window.width - 150, 150), Color.hex("#f72585"), "or me"))

    gestures = GestureRecognizer.new
    gestures.on_pinched { |_, delta, c| @star.scale *= delta if near_star?(c) }
    gestures.on_rotated { |_, delta, c| @star.rotation += delta if near_star?(c) }
    gestures.on_double_tapped do |p|
      if near_star?(p)
        @star.scale = Vec2::ONE
        @star.rotation = 0
        log("double tap: reset")
      end
    end
    gestures.on_tapped { |p| log("tap #{p.x.to_i},#{p.y.to_i}") }
    gestures.on_long_pressed { |p| log("long press") }
    gestures.on_swiped { |dir, _, _| log("swipe #{dir.x.round(1)},#{dir.y.round(1)}") }
    SceneTree.root.add(gestures)

    hud = CanvasLayer.new
    stick = VirtualJoystick.new(v2(30, Window.height - 190), 80).bind("left", "right", "up", "down")
    fire = VirtualButton.new("fire", "FIRE", v2(Window.width - 130, Window.height - 130), 100)
    row = HBox.new(position: v2(Window.width / 2 - 130, 10))
    row.add(Button.new("Reset") { reset }, Button.new("Clear log") { @lines.clear; @log.text = "" })
    @log.position = v2(Window.width - 260, 200)
    @log.color = Color.gray(0.85)
    @fingers.position = v2(12, 12)
    hud.add(stick, fire, row, @log, @fingers)
    SceneTree.root.add(hud)
    demo_script if ENV["EAGLE_DEMO"]? == "1"
  end

  def reset
    @star.scale = Vec2::ONE
    @star.rotation = 0
    @dot = v2(200, 380)
    log("reset")
  end

  def near_star?(p : Vec2) : Bool
    p.distance(@star.position) < 200
  end

  def log(msg : String)
    @lines << msg
    @lines.shift if @lines.size > 10
    @log.text = @lines.join("\n")
  end

  def update(dt : Float32)
    @dot += Input.vector("left", "right", "up", "down") * 240 * dt
    @dot = @dot.clamp(v2(20, 60), Window.size - v2(20, 20))
    if Input.pressed?("fire")
      @pulse = 1_f32
      log("fire")
    end
    @pulse = Math.max(0_f32, @pulse - dt * 2)
    @fingers.text = "fingers: #{Touch.count}  " + Touch.fingers.map { |f| "##{f.id}#{f.dragging? ? "*" : ""}" }.join(" ")
  end

  def draw(g : Graphics)
    g.circle(@dot, 18 + @pulse * 30, color: Color.hex("#7bd88f"))
    g.circle(@dot, 18 + @pulse * 30, DrawMode::Line, Color::WHITE) if @pulse > 0
  end

  # Scripted walkthrough used for the automated screenshot.
  def demo_script
    Script.touch_drag(v2(150, 150), v2(300, 240), seconds: 0.4, start: 0.3)
    Script.pinch(v2(Window.width / 2, Window.height / 2), 160, 240, seconds: 0.5, start: 1.0)
    Script.twist(v2(Window.width / 2, Window.height / 2), 130, 0.7, seconds: 0.5, start: 1.7)
    Script.at(2.4) { Script.touch_tap(v2(60, 200)) }
    Script.at(2.6) { Script.touch_down(0, v2(110, Window.height - 110)) }
    Script.at(2.7) { Script.touch_move(0, v2(150, Window.height - 110)) }
  end
end

Eagle.run(TouchDemo, title: "Eagle touch", width: 960, height: 540)
