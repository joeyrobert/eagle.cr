require "../../src/eagle"
include Eagle

# Coin Rush (3D game): roll the ball with WASD / left stick, jump with space,
# collect all coins before time runs out. Third-person follow camera, shadows, UI.
class CoinRush < App
  ARENA = 22_f32
  @cam = Camera3D.new(position: v3(0, 8, 12))
  @ball = MeshInstance3D.new(Mesh.sphere(0.5, 24, 16), Material.new(Color.hex("#ff6b6b"), shininess: 64, specular: 0.6), position: v3(0, 0.5, 0))
  @vel = Vec3::ZERO
  @coins = [] of MeshInstance3D
  @obstacles = [] of AABB
  @score = 0
  @time_left = 45_f32
  @state = :playing
  @hud = Label.new("")
  @big = Label.new("", align: TextAlign::Center)
  @snd_coin : Sound? = nil
  @snd_jump : Sound? = nil
  @rng = Random.new(3)
  @yaw = 0_f32

  def load
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "jump", Key::Space, GamepadButton::A
    @snd_coin = Sound.tone(1300, 0.1, Sound::Wave::Sine, 0.3)
    @snd_jump = Sound.tone(400, 0.12, Sound::Wave::Triangle, 0.25)
    root = SceneTree.root
    env = Scene3D.environment
    env.fog(25, 70, Color.hex("#c9d8ee"))
    env.sky_colors(Color.hex("#6fa8ff"), Color.hex("#dbe8ff"), Color.hex("#4d5a70"))
    tex = Texture.new(Image.checkerboard(32, 32, 16, Color.hex("#8bc34a"), Color.hex("#7cb342")), wrap: GPU::Wrap::Repeat)
    root.add(MeshInstance3D.new(Mesh.plane(ARENA * 2, ARENA * 2, 1, uv_scale: 11), Material.new(texture: tex, specular: 0.05)))
    # walls
    [{v3(0, 1, -ARENA), v3(ARENA * 2, 2, 1)}, {v3(0, 1, ARENA), v3(ARENA * 2, 2, 1)}, {v3(-ARENA, 1, 0), v3(1, 2, ARENA * 2)}, {v3(ARENA, 1, 0), v3(1, 2, ARENA * 2)}].each do |(pos, size)|
      root.add(MeshInstance3D.new(Mesh.box(size.x, size.y, size.z), Material.new(Color.hex("#556270")), position: pos))
      @obstacles << AABB.from_center(pos, size / 2)
    end
    # obstacles
    14.times do
      size = v3(1 + @rng.rand * 3, 1 + @rng.rand * 2, 1 + @rng.rand * 3)
      pos = v3((@rng.rand - 0.5) * ARENA * 1.6, size.y / 2, (@rng.rand - 0.5) * ARENA * 1.6)
      next if pos.xz.length < 4
      root.add(MeshInstance3D.new(Mesh.box(size.x, size.y, size.z), Material.new(Color.hsv(@rng.rand * 360, 0.35, 0.9)), position: pos))
      @obstacles << AABB.from_center(pos, size / 2)
    end
    # coins
    20.times do
      pos = v3((@rng.rand - 0.5) * ARENA * 1.7, 0.8, (@rng.rand - 0.5) * ARENA * 1.7)
      next if @obstacles.any? { |o| o.contains?(pos) }
      coin = MeshInstance3D.new(Mesh.cylinder(0.45, 0.12, 20), Material.new(Color.hex("#ffd700"), shininess: 96, specular: 0.9, emissive: Color.new(0.15, 0.1, 0)), position: pos)
      coin.rotate_x(Math::PI / 2)
      root.add(coin)
      @coins << coin
    end
    root.add(@ball)
    root.add(DirectionalLight3D.new(v3(-0.4, -1, -0.5), Color.hex("#fff4e0"), 1.1))
    root.add(PointLight3D.new(v3(0, 4, 0), Color.hex("#ffe0a0"), 1.5, 14))
    root.add(@cam)
    hud = CanvasLayer.new
    @hud.position = v2(12, 10)
    @hud.shadow = Color::BLACK
    @hud.shadow_offset = v2(2, 2)
    @big.anchor = Anchor::Center
    @big.font_scale = 2
    @big.shadow = Color::BLACK
    @big.shadow_offset = v2(3, 3)
    hud.add(@hud, @big)
    root.add(hud)
  end

  def update(dt : Float32)
    if @state == :playing
      @time_left -= dt
      move(dt)
      @coins.each { |c| c.rotate(Vec3::UP, dt * 2) }
      @coins.reject! do |c|
        if c.global_position.distance(@ball.position) < 1.0
          c.free
          @score += 1
          @snd_coin.try(&.play(pitch: 1 + @score * 0.03))
          true
        end
      end
      if @coins.empty?
        @state = :won
      elsif @time_left <= 0
        @state = :lost
      end
    elsif Input.pressed?(Key::R)
      SceneTree.reset
      @coins.clear; @obstacles.clear; @score = 0; @time_left = 45_f32; @state = :playing
      @ball = MeshInstance3D.new(Mesh.sphere(0.5, 24, 16), Material.new(Color.hex("#ff6b6b"), shininess: 64, specular: 0.6), position: v3(0, 0.5, 0))
      @vel = Vec3::ZERO
      @cam = Camera3D.new(position: v3(0, 8, 12))
      load
    end
    # camera: orbit with right drag, follow the ball
    @yaw -= Input.mouse_delta.x * 0.005 if Input.mouse_down?(MouseButton::Right)
    if g = Input.gamepad
      @yaw -= g.right_stick.x * dt * 2
    end
    offset = Quat.from_axis_angle(Vec3::UP, @yaw) * v3(0, 6, 10)
    @cam.position = Mathf.damp(@cam.position, @ball.position + offset, 6, dt)
    @cam.look_at(@ball.position + v3(0, 0.5, 0))
    @hud.text = "coins #{@score}/#{@score + @coins.size}   time #{@time_left.clamp(0, 999).ceil.to_i}   fps #{Clock.fps.round.to_i}"
    @big.text = case @state
                when :won then "YOU WIN!\nR to play again"
                when :lost then "TIME'S UP\nR to play again"
                else ""
                end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  private def move(dt : Float32)
    # input relative to the camera yaw
    inp = Input.vector("left", "right", "up", "down")
    dir = Quat.from_axis_angle(Vec3::UP, @yaw) * v3(inp.x, 0, inp.y)
    @vel += dir * 40 * dt
    @vel = v3(@vel.x * (1 / (1 + dt * 2.5)), @vel.y - 25 * dt, @vel.z * (1 / (1 + dt * 2.5)))
    on_ground = @ball.position.y <= 0.501
    if on_ground && Input.pressed?("jump")
      @vel = v3(@vel.x, 9, @vel.z)
      @snd_jump.try(&.play)
    end
    pos = @ball.position + @vel * dt
    if pos.y < 0.5
      pos = v3(pos.x, 0.5, pos.z); @vel = v3(@vel.x, 0, @vel.z)
    end
    # sphere vs boxes: push out along the smallest axis
    @obstacles.each do |box|
      closest = pos.max(box.min).min(box.max)
      d = pos - closest
      dist = d.length
      if dist < 0.5
        n = dist > 1e-4 ? d / dist : Vec3::UP
        pos = closest + n * 0.5
        vn = @vel.dot(n)
        @vel -= n * vn * 1.3 if vn < 0
      end
    end
    # roll the ball visually
    horiz = v3(@vel.x, 0, @vel.z)
    if horiz.length > 0.01
      axis = Vec3::UP.cross(horiz).normalized
      @ball.rotate(axis, horiz.length * dt / 0.5)
    end
    @ball.position = pos
  end
end

Eagle.run(CoinRush, title: "Eagle Coin Rush", width: 1024, height: 640, msaa: 4)
