require "../../src/eagle"
require "./world"
include Eagle

# Voxel Island: a finite noise-generated island you walk, break and paint.
# Left click breaks, right click places the selected colour, E opens the palette.
class VoxelIslandApp < App
  EYE    = 1.62_f32
  HEIGHT = 1.7_f32
  RADIUS = 0.28_f32
  SPEED  = 6.2_f32
  GRAVITY = 28_f32
  JUMP    = 9.2_f32
  REACH   = 8_f32

  @island = EagleVoxel::Island.new((ENV["EAGLE_WORLD_SEED"]? || "2026").to_i)
  @mesh = Mesh.new("island")
  @terrain = MeshInstance3D.new
  @camera = Camera3D.new(position: v3(0, 8, 0), fov: 70)
  @feet = Vec3::ZERO
  @velocity = Vec3::ZERO
  @yaw = 0_f32
  @pitch = -0.18_f32
  @on_ground = false
  @kind = EagleVoxel::GRASS
  @menu = false
  @dirty = true
  @tip_time = 8_f32
  @cinematic = false
  @break_sound : Sound? = nil
  @place_sound : Sound? = nil
  @step_sound : Sound? = nil
  @step_timer = 0_f32
  @bob = 0_f32

  def load
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "forward", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "back", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "jump", Key::Space, GamepadButton::A
    Input.map "sprint", Key::LShift, GamepadButton::LeftStick
    Input.map "break", MouseButton::Left, GamepadButton::LeftShoulder
    Input.map "place", MouseButton::Right, GamepadButton::RightShoulder
    Input.map "palette", Key::E, GamepadButton::Y
    {% unless flag?(:wasm32) %}
      Window.relative_mouse = true
    {% end %}
    Window.cursor_visible = false

    @feet = @island.spawn
    look = @island.center - @feet
    @yaw = Math.atan2(look.x, -look.z).to_f32
    if ENV["EAGLE_DEMO"]? == "1" || ENV.has_key?("EAGLE_FRAMES")
      @feet, ground_y = @island.overlook
      target = v3(EagleVoxel::Island::WIDTH * 0.5, ground_y + 4, EagleVoxel::Island::DEPTH * 0.55)
      to = target - (@feet + v3(0, EYE, 0))
      @yaw = Math.atan2(to.x, -to.z).to_f32
      @pitch = Math.atan2(to.y, Math.hypot(to.x, to.z)).to_f32
      @island.stamp_palette(@feet.x.to_i - 2, ground_y + 1, @feet.z.to_i + 4)
      @tip_time = 0
      if ENV.has_key?("EAGLE_FRAMES")
        @cinematic = true
        @camera.position = v3(4, 30, 4)
        @camera.look_at(v3(24, 8, 24))
      end
    end

    env = Scene3D.environment
    env.sky_colors(Color.hex("#6fa8ff"), Color.hex("#dbe8ff"), Color.hex("#4d5a70"))
    env.fog(40, 90, Color.hex("#c9d8ee"))
    env.ambient = Color.new(0.38, 0.4, 0.42)
    env.shadows = true
    env.shadow_distance = 48

    @island.build_mesh(@mesh)
    @dirty = false
    mat = Material.new(Color::WHITE, shininess: 18, specular: 0.14)
    @terrain = MeshInstance3D.new(@mesh, mat, "terrain")
    @break_sound = Sound.generate(0.14) { |t| (Math.sin(t * 90 * Math::TAU) * Math.exp(-t * 18) * 0.45 + Random.rand(-0.2..0.2) * Math.exp(-t * 30)).to_f32 }
    @place_sound = Sound.tone(640, 0.07, Sound::Wave::Triangle, 0.28)
    @step_sound = Sound.generate(0.08) { |t| (Random.rand(-1.0..1.0) * Math.exp(-t * 40) * 0.4).to_f32 }

    root = SceneTree.root
    root.add(@terrain, DirectionalLight3D.new(v3(-0.45, -1, -0.28), Color.hex("#fff4e0"), 1.05), @camera)
    sync_camera
  end

  def update(dt : Float32)
    @tip_time -= dt
    if Input.pressed?("palette")
      toggle_menu
    end
    if Input.pressed?(Key::Escape)
      if @menu
        toggle_menu(false)
      else
        Window.relative_mouse = false
        Window.cursor_visible = true
        Eagle.quit
      end
    end
    if Input.pressed?(Key::R)
      seed = @island.seed
      @island = EagleVoxel::Island.new(seed)
      @feet = @island.spawn
      @velocity = Vec3::ZERO
      @dirty = true
    end

    select_colour
    unless @menu || ENV.has_key?("EAGLE_FRAMES")
      Window.relative_mouse = true if Input.mouse_pressed?(MouseButton::Left)
      look(dt)
      walk(dt)
      edit
    else
      pick_menu if @menu
    end

    rebuild if @dirty
    sync_camera
    if hit = aimed
      unless ENV.has_key?("EAGLE_FRAMES")
        Scene3D.debug_box(v3(hit.x + 0.5, hit.y + 0.5, hit.z + 0.5), v3(0.505, 0.505, 0.505), color: Color.new(1, 1, 1, 0.85))
      end
    end
  end

  def draw(g : Graphics)
    w = Window.width
    h = Window.height
    g.line(w / 2 - 10, h / 2, w / 2 - 3, h / 2, Color::WHITE, 2)
    g.line(w / 2 + 3, h / 2, w / 2 + 10, h / 2, Color::WHITE, 2)
    g.line(w / 2, h / 2 - 10, w / 2, h / 2 - 3, Color::WHITE, 2)
    g.line(w / 2, h / 2 + 3, w / 2, h / 2 + 10, Color::WHITE, 2)

    g.rect(12, 12, 280, 52, color: Color.new(0.05, 0.07, 0.1, 0.72))
    g.print("Voxel Island   #{EagleVoxel::NAMES[@kind]}", 22, 20, Color::WHITE)
    g.print("blocks #{@island.occupied}   quads #{@island.mesh_quads}", 22, 40, Color.gray(0.8))

    draw_hotbar(g)
    draw_menu(g) if @menu
    if @tip_time > 0 && !@menu
      g.rect(0, h - 54, w, 54, color: Color.new(0, 0, 0, 0.62))
      g.printf("Click to capture mouse. WASD move, Space jump, Shift sprint.", 0, h - 42, w, align: TextAlign::Center, color: Color.gray(0.86))
      g.printf("Left break · Right place · E colour menu · scroll / 1-9 palette · R regen", 0, h - 22, w, align: TextAlign::Center, color: Color.gray(0.86))
    end
  end

  private def look(dt : Float32)
    @yaw -= Input.mouse_delta.x * 0.0025
    @pitch = (@pitch - Input.mouse_delta.y * 0.0025).clamp(-1.35_f32, 1.35_f32)
    if pad = Input.gamepad
      @yaw -= pad.right_stick.x * dt * 2.4
      @pitch = (@pitch - pad.right_stick.y * dt * 2.0).clamp(-1.35_f32, 1.35_f32)
    end
  end

  private def look_direction : Vec3
    cp = Math.cos(@pitch)
    v3(Math.sin(@yaw) * cp, Math.sin(@pitch), -Math.cos(@yaw) * cp).normalized
  end

  private def walk(dt : Float32)
    input = Input.vector("left", "right", "forward", "back")
    forward = v3(Math.sin(@yaw), 0, -Math.cos(@yaw))
    right = v3(Math.cos(@yaw), 0, Math.sin(@yaw))
    speed = SPEED * (Input.down?("sprint") ? 1.55_f32 : 1_f32)
    wish = (right * input.x + forward * -input.y)
    wish = wish.length > 1e-5 ? wish.normalized * speed : Vec3::ZERO
    @velocity = v3(wish.x, @velocity.y - GRAVITY * dt, wish.z)
    if @on_ground && Input.pressed?("jump")
      @velocity = v3(@velocity.x, JUMP, @velocity.z)
      @on_ground = false
    end
    @feet, @velocity, @on_ground = @island.move(@feet, @velocity, dt, RADIUS, HEIGHT)
    moving = wish.length > 0.01 && @on_ground
    @bob = moving ? @bob + dt * speed : 0_f32
    if moving
      @step_timer += dt * (Input.down?("sprint") ? 1.5_f32 : 1_f32)
      if @step_timer >= 0.42
        @step_timer = 0
        @step_sound.try(&.play(pitch: 0.9 + Random.rand * 0.2, volume: 0.35))
      end
    else
      @step_timer = 0.3_f32
    end
  end

  private def aimed : EagleVoxel::Hit?
    @island.raycast(eye, look_direction, REACH)
  end

  private def eye : Vec3
    bob = @on_ground && @bob > 0 ? Math.sin(@bob * 10) * 0.03 : 0
    @feet + v3(0, EYE + bob, 0)
  end

  private def edit
    hit = aimed
    return unless hit
    if Input.pressed?("break")
      if @island.break_at(hit) != 0
        @dirty = true
        @break_sound.try(&.play(pitch: 0.85 + Random.rand * 0.3))
      end
    elsif Input.pressed?("place")
      if @island.place_at(hit, @kind, @feet, RADIUS, HEIGHT)
        @dirty = true
        @place_sound.try(&.play(pitch: 0.95 + Random.rand * 0.15))
      end
    end
  end

  private def select_colour
    keys = {Key::Num1, Key::Num2, Key::Num3, Key::Num4, Key::Num5, Key::Num6, Key::Num7, Key::Num8, Key::Num9, Key::Num0}
    keys.each_with_index do |key, i|
      n = i == 9 ? 10 : i + 1
      @kind = n.to_u8 if Input.pressed?(key) && n < EagleVoxel::PALETTE.size
    end
    wheel = Input.wheel.y
    if wheel != 0
      n = EagleVoxel::PALETTE.size - 1
      @kind = (((@kind.to_i - 1 - (wheel > 0 ? 1 : -1)) % n + n) % n + 1).to_u8
    end
  end

  private def toggle_menu(open : Bool? = nil)
    @menu = open.nil? ? !@menu : open.as(Bool)
    Window.relative_mouse = !@menu
    Window.cursor_visible = @menu
  end

  private def pick_menu
    return unless Input.mouse_pressed?(MouseButton::Left)
    mx, my = Input.mouse.x, Input.mouse.y
    slot = menu_slot_at(mx, my) || hotbar_slot_at(mx, my)
    if slot && slot > 0 && slot < EagleVoxel::PALETTE.size
      @kind = slot.to_u8
    end
  end

  private def rebuild
    @island.build_mesh(@mesh)
    @dirty = false
  end

  private def sync_camera
    return if @cinematic
    @camera.position = eye
    @camera.look_at(@camera.position + look_direction)
  end

  private def hotbar_geometry
    n = EagleVoxel::PALETTE.size - 1
    size = 40_f32
    gap = 6_f32
    total = n * size + (n - 1) * gap
    x0 = (Window.width - total) / 2
    y = Window.height - 52
    {n, size, gap, x0, y}
  end

  private def hotbar_slot_at(mx : Float32, my : Float32) : Int32?
    n, size, gap, x0, y = hotbar_geometry
    return nil unless my >= y && my <= y + size
    n.times do |i|
      x = x0 + i * (size + gap)
      return i + 1 if mx >= x && mx <= x + size
    end
    nil
  end

  private def draw_hotbar(g : Graphics)
    n, size, gap, x0, y = hotbar_geometry
    n.times do |i|
      kind = (i + 1).to_u8
      x = x0 + i * (size + gap)
      g.rect(x, y, size, size, color: EagleVoxel::PALETTE[kind])
      if kind == @kind
        g.rect(x - 2, y - 2, size + 4, size + 4, DrawMode::Line, Color::WHITE)
      else
        g.rect(x, y, size, size, DrawMode::Line, Color.new(0, 0, 0, 0.45))
      end
    end
  end

  private def menu_geometry
    cols = 4
    size = 56_f32
    gap = 10_f32
    n = EagleVoxel::PALETTE.size - 1
    rows = (n + cols - 1) // cols
    panel_w = cols * size + (cols + 1) * gap + 160
    panel_h = rows * size + (rows + 1) * gap + 48
    x0 = (Window.width - panel_w) / 2
    y0 = (Window.height - panel_h) / 2 - 20
    {cols, size, gap, n, x0, y0, panel_w, panel_h}
  end

  private def menu_slot_at(mx : Float32, my : Float32) : Int32?
    cols, size, gap, n, x0, y0, _, _ = menu_geometry
    n.times do |i|
      col = i % cols
      row = i // cols
      x = x0 + gap + col * (size + gap)
      y = y0 + 40 + row * (size + gap)
      return i + 1 if mx >= x && mx <= x + size && my >= y && my <= y + size
    end
    nil
  end

  private def draw_menu(g : Graphics)
    cols, size, gap, n, x0, y0, panel_w, panel_h = menu_geometry
    g.rect(x0, y0, panel_w, panel_h, color: Color.new(0.07, 0.09, 0.12, 0.92))
    g.print("Colours  ·  click a block to build with it", x0 + 16, y0 + 14, Color.gray(0.9))
    n.times do |i|
      kind = (i + 1).to_u8
      col = i % cols
      row = i // cols
      x = x0 + gap + col * (size + gap)
      y = y0 + 40 + row * (size + gap)
      g.rect(x, y, size, size, color: EagleVoxel::PALETTE[kind])
      if kind == @kind
        g.rect(x - 2, y - 2, size + 4, size + 4, DrawMode::Line, Color::WHITE)
      end
      g.print(EagleVoxel::NAMES[kind], x + size + 8, y + 20, Color.gray(0.85))
    end
  end
end

Eagle.run(VoxelIslandApp, title: "Eagle: Voxel Island", width: 1100, height: 680, msaa: 4)
