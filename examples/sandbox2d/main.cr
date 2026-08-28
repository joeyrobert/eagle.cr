require "../../src/eagle"
include Eagle

# Scene-tree sandbox: a player sprite you move with WASD/arrows/gamepad,
# a following camera, a tile map, timers, tweens and a HUD on a CanvasLayer.

class Player < Sprite2D
  SPEED = 220

  def initialize
    super("Player")
    img = Image.new(24, 24, Color::TRANSPARENT)
    img.blit(Image.circle(24, Color.hex("#ffcc00")), 0, 0)
    img.fill_rect(15, 8, 4, 4, Color::BLACK)
    self.texture = Texture.new(img)
  end

  def ready
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
  end

  def process(dt : Float32)
    v = Input.vector("left", "right", "up", "down")
    self.position += v * SPEED * dt
    self.rotation = v.angle if !v.zero?
  end
end

class Sandbox < App
  @cam = Camera2D.new(zoom: 2)
  @player = Player.new
  @hud = Label.new("", v2(8, 8))
  @spin = Polygon2D.regular(6, 20, Color.hex("#66ccff"))

  def load
    Texture.default_filter = GPU::Filter::Nearest
    root = SceneTree.root
    # Tileset: 2 tiles, 16px, grass and stone
    ts = Image.new(32, 16)
    ts.fill_rect(0, 0, 16, 16, Color.hex("#3a7d44"))
    ts.fill_rect(16, 0, 16, 16, Color.hex("#6b6b6b"))
    4.times { |i| ts[2 + i * 3, 3 + (i % 2) * 5] = Color.hex("#5cb85c") }
    map = TileMap.new(Texture.new(ts), 16, 16)
    24.times { |y| 32.times { |x| map[x, y] = (x == 0 || y == 0 || x == 31 || y == 23 || (x * y) % 17 == 0) ? 1 : 0 } }
    map.position = v2(-256, -192)
    root.add(map)

    @spin.position = v2(80, -40)
    root.add(@spin)
    Tween.to(2.0, ease: :sine_in_out) { |t| @spin.rotation = t * Math::PI * 2 }.loop = true

    @player.position = v2(0, 0)
    root.add(@player)
    root.add(@cam)
    @cam.follow(@player)
    @cam.limits = Rect.new(-256, -192, 512, 384)

    hud_layer = CanvasLayer.new
    hud_layer.add(@hud)
    root.add(hud_layer)

    t = Timer.new(1.0) { @cam.shake(3, 0.2) }
    t.start
    root.add(t)
  end

  def update(dt : Float32)
    @hud.text = "WASD to move  fps #{Clock.fps.round}  pos #{@player.position.round}  nodes #{SceneTree.node_count}"
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    g.print("draw calls #{g.draw_calls}", 8, Window.height - 24, Color::GRAY)
  end
end

Eagle.run(Sandbox, title: "Eagle sandbox 2D", width: 800, height: 600)
