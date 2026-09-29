require "./board"
include Eagle
include EagleTiltMaze

# Tilt Maze is a small marble-rolling game inspired by tabletop tilt mazes.
# Tilt with WASD, arrow keys, or the left stick. Avoid the holes and reach the
# glowing blue goal before time runs out.
class TiltMaze < App
  @board = Board.new
  @level = Node3D.new("tilting level")
  @ball = MeshInstance3D.new
  @goal = MeshInstance3D.new
  @camera = Camera3D.new(position: v3(0, 14, 16), fov: 52)
  @hud = Label.new("")
  @message = Label.new("", align: TextAlign::Center)
  @fall_sound : Sound? = nil
  @win_sound : Sound? = nil

  def load
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
    @fall_sound = Sound.tone(110, 0.22, Sound::Wave::Sine, 0.3)
    @win_sound = Sound.tone(880, 0.18, Sound::Wave::Triangle, 0.3)
    make_level
  end

  def update(dt : Float32)
    if @board.state.playing?
      @fall_sound.try(&.play) if @board.step(Input.vector("left", "right", "up", "down"), dt)
      @win_sound.try(&.play) if @board.state.won?
      sync_ball(dt)
    elsif Input.pressed?(Key::R)
      restart
    end

    # Keep the viewpoint locked to the marble so the action stays centred as the board rolls underneath it.
    @camera.position = @ball.global_position + v3(0, 14, 16)
    @camera.look_at(@ball.global_position + v3(0, 0, -3))
    goal = @board.goal
    @goal.rotate_y(dt * 2.5)
    @goal.position = v3(goal.x, 0.18 + (@board.state.won? ? Math.sin(Clock.elapsed * 7) * 0.12 : 0), goal.y)
    @hud.text = "TILT MAZE    time #{@board.time_left.clamp(0, 99).ceil.to_i}    falls #{@board.falls}"
    @message.text = case @board.state
                    in .won?     then "GOAL!\nPress R to play again"
                    in .lost?    then "TIME UP\nPress R to try again"
                    in .playing? then "WASD / ARROWS: tilt the level    R: restart"
                    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  private def sync_ball(dt : Float32)
    marble = @board.marble
    @ball.position = v3(marble.x, BALL_RADIUS, marble.y)
    horizontal = v3(@board.velocity.x, 0, @board.velocity.y)
    @ball.rotate_local(Vec3::UP.cross(horizontal).normalized, horizontal.length * dt / BALL_RADIUS) if horizontal.length > 0.01
    @level.rotation = @board.rotation
  end

  private def make_level
    root = SceneTree.root
    Scene3D.environment.fog(24, 55, Color.hex("#c5d6e8"))
    Scene3D.environment.sky_colors(Color.hex("#72a8d8"), Color.hex("#e9f4ff"), Color.hex("#5a6778"))
    root.add(@level)

    board_material = Material.new(Color.hex("#d9a55e"), shininess: 32, specular: 0.3)
    @level.add(MeshInstance3D.new(Mesh.box(BOARD_HALF * 2, 0.45, BOARD_HALF * 2), board_material, position: v3(0, -0.25, 0)))
    # The dark under-frame makes the board's tilt easy to read at a glance.
    @level.add(MeshInstance3D.new(Mesh.box(17.2, 0.45, 17.2), Material.new(Color.hex("#51372b")), position: v3(0, -0.65, 0)))
    tiles = Texture.new(Image.checkerboard(64, 64, 8, Color.hex("#f9dc8a"), Color.hex("#ecc56e")), wrap: GPU::Wrap::Repeat)
    @level.add(MeshInstance3D.new(Mesh.plane(15.4, 15.4, 1, uv_scale: 8), Material.new(texture: tiles, specular: 0.08), position: v3(0, 0.005, 0)))

    wall_material = Material.new(Color.hex("#80523a"), shininess: 12)
    @board.walls.each do |wall|
      @level.add(MeshInstance3D.new(Mesh.box(wall.half.x * 2, 0.7, wall.half.y * 2), wall_material, position: v3(wall.center.x, 0.34, wall.center.y)))
    end
    @board.holes.each do |pos|
      @level.add(MeshInstance3D.new(Mesh.cylinder(HOLE_RADIUS, 0.03, 24), Material.new(Color.hex("#20202b"), specular: 0), position: v3(pos.x, -0.01, pos.y)))
      @level.add(MeshInstance3D.new(Mesh.torus(HOLE_RADIUS, 0.08, 24, 8), Material.new(Color.hex("#75462d"), shininess: 12), position: v3(pos.x, 0.02, pos.y)))
    end

    goal = @board.goal
    @level.add(MeshInstance3D.new(Mesh.cylinder(0.8, 0.04, 32), Material.new(Color.hex("#62c889"), emissive: Color.hex("#123a25")), position: v3(START.x, 0.025, START.y)))
    @level.add(MeshInstance3D.new(Mesh.cylinder(0.68, 0.08, 32), Material.new(Color.hex("#183f55"), emissive: Color.hex("#0a1720")), position: v3(goal.x, 0.04, goal.y)))
    @goal = MeshInstance3D.new(Mesh.torus(0.48, 0.13, 32, 10), Material.new(Color.hex("#55e6ff"), emissive: Color.hex("#207080"), shininess: 96, specular: 0.9), position: v3(goal.x, 0.18, goal.y))
    @level.add(@goal)
    @ball = MeshInstance3D.new(Mesh.sphere(BALL_RADIUS, 24, 16), Material.new(Color.hex("#f45b69"), shininess: 96, specular: 0.9), position: v3(START.x, BALL_RADIUS, START.y))
    @level.add(@ball)
    root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.35), Color.hex("#fff1d2"), 1.2))
    root.add(PointLight3D.new(v3(0, 7, 0), Color.hex("#d5f2ff"), 1.2, 22))
    @camera.look_at(Vec3::ZERO)
    root.add(@camera)
    hud_layer = CanvasLayer.new
    @hud.position = v2(18, 15)
    @hud.shadow = Color::BLACK
    @hud.shadow_offset = v2(2, 2)
    @message.anchor = Anchor::Bottom
    @message.position = v2(Window.width / 2, Window.height - 20)
    @message.shadow = Color::BLACK
    @message.shadow_offset = v2(2, 2)
    hud_layer.add(@hud, @message)
    root.add(hud_layer)
  end

  private def restart
    SceneTree.reset
    @board = Board.new
    @level = Node3D.new("tilting level")
    @camera = Camera3D.new(position: v3(0, 14, 16), fov: 52)
    make_level
  end
end

Eagle.run(TiltMaze, title: "Eagle Tilt Maze", width: 1024, height: 640, msaa: 4)
