require "../../src/eagle"
require "./game"
include Eagle

# Neon Bastion is a compact first-person shooter built entirely from procedural meshes and
# synthesized audio. F1 starts escalating Waves; F2 starts a 15-frag Deathmatch.
class NeonBastion < App
  MOVE_SPEED = 8_f32
  @game = EagleFPS::Game.new
  @camera = Camera3D.new(position: v3(0, 1.65, 0))
  @enemy_nodes = {} of Int32 => MeshInstance3D
  @yaw = 0_f32
  @pitch = 0_f32
  @bob = 0_f32
  @flash = 0_f32
  @tracer : {Vec3, Vec3, Color}? = nil
  @shot_sound = NeonBastion.shot_sound
  @scatter_sound = NeonBastion.scatter_sound
  @impact_sound = NeonBastion.impact_sound
  @hurt_sound = Sound.tone(110, 0.18, Sound::Wave::Saw, 0.25)
  @step_sound = NeonBastion.step_sound
  @death_sound = NeonBastion.death_sound
  @grunt_hum = NeonBastion.grunt_hum
  @charger_hum = NeonBastion.charger_hum
  @old_health = 100
  @tip_time = 8_f32
  @step_timer = 0_f32

  def self.shot_sound : Sound
    rng = Random.new(24)
    Sound.generate(0.22) { |t| ((rng.rand(-1.0..1.0) * 0.35 + Math.sin(t * 105 * Math::TAU) * 0.5) * Math.exp(-t * 25)).to_f32 }
  end

  def self.scatter_sound : Sound
    rng = Random.new(71)
    Sound.generate(0.35) { |t| ((rng.rand(-1.0..1.0) * 0.7 + Math.sin(t * 58 * Math::TAU) * 0.55) * Math.exp(-t * 15)).to_f32 }
  end

  def self.impact_sound : Sound
    Sound.generate(0.12) { |t| (Math.sin(t * 340 * Math::TAU) * Math.exp(-t * 35) * 0.35).to_f32 }
  end

  def self.step_sound : Sound
    rng = Random.new(3)
    Sound.generate(0.09) { |t| (rng.rand(-1.0..1.0) * Math.exp(-t * 42) * 0.45).to_f32 }
  end

  def self.death_sound : Sound
    Sound.generate(0.32) { |t| (Math.sin(t * 86 * Math::TAU) * Math.exp(-t * 7) * 0.5 + Math.sin(t * 38 * Math::TAU) * Math.exp(-t * 5) * 0.4).to_f32 }
  end

  def self.grunt_hum : Sound
    Sound.generate(1.0) { |t| (Math.sin(t * 88 * Math::TAU) * 0.16 + Math.sin(t * 176 * Math::TAU) * 0.05).to_f32 }
  end

  def self.charger_hum : Sound
    Sound.generate(1.0) { |t| (Math.sin(t * 42 * Math::TAU) * 0.2 + Math.sin(t * 63 * Math::TAU) * 0.08).to_f32 }
  end

  def load
    Input.map "left", Key::A, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "forward", Key::W, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "back", Key::S, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "fire", MouseButton::Left, GamepadButton::RightShoulder
    Input.map "sprint", Key::LShift, GamepadButton::LeftStick
    {% unless flag?(:wasm32) %}
      Window.relative_mouse = true
    {% end %}
    Window.cursor_visible = false

    env = Scene3D.environment
    env.sky_colors(Color.hex("#050817"), Color.hex("#182342"), Color.hex("#070b16"))
    env.fog(30, 65, Color.hex("#101830"))
    env.ambient = Color.new(0.16, 0.18, 0.28)
    env.shadows = true
    root = SceneTree.root
    floor_tex = Texture.new(Image.checkerboard(64, 64, 8, Color.hex("#171d30"), Color.hex("#202943")), wrap: GPU::Wrap::Repeat)
    root.add(MeshInstance3D.new(Mesh.plane(50, 50, 8, uv_scale: 16), Material.new(texture: floor_tex, specular: 0.12)))
    @game.arena.obstacles.each_with_index do |wall, i|
      height = i < 4 ? 4_f32 : 1.8_f32 + (i % 3) * 0.7_f32
      color = i < 4 ? Color.hex("#202b47") : Color.hsv(205 + i * 9, 0.52, 0.62)
      mesh = MeshInstance3D.new(Mesh.box(wall.half.x * 2, height, wall.half.y * 2), Material.new(color, shininess: 36, specular: 0.25), position: v3(wall.center.x, height / 2, wall.center.y))
      root.add(mesh)
    end
    root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.25), Color.hex("#9eb8ff"), 0.65))
    [-16, 0, 16].each do |x|
      root.add(PointLight3D.new(v3(x, 3.5, -8), Color.hex(x == 0 ? "#ff3d9a" : "#39d8ff"), 1.8, 15))
    end
    # A low positional beacon makes orientation audible even before the first shot.
    beacon = MeshInstance3D.new(Mesh.cylinder(0.45, 2.2, 12), Material.new(Color.hex("#ff3d9a"), emissive: Color.hex("#531536")), position: v3(0, 1.1, -10))
    beacon.add(AudioPlayer3D.new(Sound.tone(72, 2, Sound::Wave::Saw, volume: 0.08), loop: true, autoplay: true, min_distance: 3, max_distance: 35))
    root.add(beacon, @camera)
    sync_enemies
  end

  def update(dt : Float32)
    @tip_time -= dt
    @flash = Math.max(0_f32, @flash - dt)
    if Input.pressed?(Key::F1)
      restart(EagleFPS::Mode::Waves)
    elsif Input.pressed?(Key::F2)
      restart(EagleFPS::Mode::Deathmatch)
    elsif Input.pressed?(Key::R)
      restart(@game.mode)
    end
    @game.switch_weapon(0) if Input.pressed?(Key::Num1)
    @game.switch_weapon(1) if Input.pressed?(Key::Num2)

    # Calling this from a click is required by browser pointer-lock's user-gesture rule;
    # repeating it is harmless and lets a click recapture after Escape releases the lock.
    Window.relative_mouse = true if Input.mouse_pressed?(MouseButton::Left)
    @yaw -= Input.mouse_delta.x * 0.0025
    @pitch = (@pitch - Input.mouse_delta.y * 0.0025).clamp(-1.25_f32, 1.25_f32)
    if pad = Input.gamepad
      @yaw -= pad.right_stick.x * dt * 2.4
      @pitch = (@pitch - pad.right_stick.y * dt * 2.0).clamp(-1.25_f32, 1.25_f32)
    end

    input = Input.vector("left", "right", "forward", "back")
    forward = v2(Math.sin(@yaw), -Math.cos(@yaw))
    right = v2(Math.cos(@yaw), Math.sin(@yaw))
    speed = MOVE_SPEED * (Input.down?("sprint") ? 1.55_f32 : 1_f32)
    motion = (right * input.x + forward * -input.y).limit(1) * speed * dt
    @game.move_player(motion)
    @bob += motion.length * 1.6
    footstep(dt, motion)

    if Input.down?("fire")
      result = @game.shoot(forward)
      fire(result) if result.fired
    end
    @game.update(dt)
    if @game.health < @old_health
      Audio.play_at(@hurt_sound, @camera.position, volume: 0.65, min_distance: 1, max_distance: 20)
      @flash = 0.22_f32
      if @game.health <= 0
        Audio.play_at(@death_sound, @camera.position, volume: 0.85, pitch: 0.72, min_distance: 1, max_distance: 24)
      end
    end
    @old_health = @game.health
    sync_enemies

    bob_y = motion.length > 0.001 ? Math.sin(@bob) * 0.035 : 0
    @camera.position = v3(@game.player.x, 1.65 + bob_y, @game.player.y)
    look = look_direction
    @camera.look_at(@camera.position + look)
    draw_debug(look)
    if Input.pressed?(Key::Escape)
      Window.relative_mouse = false
      Window.cursor_visible = true
      Eagle.quit
    end
  end

  private def fire(result : EagleFPS::ShotResult) : Nil
    sound = @game.weapon_index == 0 ? @shot_sound : @scatter_sound
    Audio.play_at(sound, @camera.position + look_direction * 0.5, volume: 0.8, min_distance: 2, max_distance: 50)
    endpoint = v3(result.endpoint.x, 1.1, result.endpoint.y)
    color = @game.weapon_index == 0 ? Color.hex("#69e9ff") : Color.hex("#ffbd59")
    @tracer = {@camera.position + look_direction * 0.6, endpoint, color}
    @flash = 0.08_f32
    if result.hits > 0
      Audio.play_at(@impact_sound, endpoint, volume: 0.65, min_distance: 2, max_distance: 35)
    end
    if result.kills > 0
      Audio.play_at(@death_sound, endpoint, volume: 0.75, pitch: 0.9 + result.kills * 0.06, min_distance: 2, max_distance: 40)
    end
  end

  private def footstep(dt : Float32, motion : Vec2) : Nil
    if @game.health > 0 && motion.length > 0.001
      @step_timer += dt * (Input.down?("sprint") ? 1.55_f32 : 1_f32)
      if @step_timer >= 0.38
        @step_timer = 0
        Audio.play_at(@step_sound, v3(@game.player.x, 0.08, @game.player.y), volume: 0.45, pitch: 0.88 + Random.rand * 0.22, min_distance: 0.6, max_distance: 14)
      end
    else
      @step_timer = 0.28_f32
    end
  end

  private def look_direction : Vec3
    cp = Math.cos(@pitch)
    v3(Math.sin(@yaw) * cp, Math.sin(@pitch), -Math.cos(@yaw) * cp).normalized
  end

  private def sync_enemies : Nil
    alive_ids = @game.enemies.select(&.alive?).map(&.id)
    @enemy_nodes.keys.each do |id|
      unless alive_ids.includes?(id)
        @enemy_nodes.delete(id).try(&.free)
      end
    end
    @game.enemies.each do |enemy|
      next unless enemy.alive?
      node = @enemy_nodes[enemy.id]? || begin
        charger = enemy.kind.charger?
        mesh = charger ? Mesh.sphere(0.78, 16, 10) : Mesh.capsule(0.48, 1.0, 16)
        color = charger ? Color.hex("#ff416c") : Color.hex("#5ee7ff")
        created = MeshInstance3D.new(mesh, Material.new(color, emissive: color * 0.18, shininess: 48, specular: 0.35))
        hum = AudioPlayer3D.new(charger ? @charger_hum : @grunt_hum, loop: true, autoplay: true, volume: charger ? 0.28 : 0.16, min_distance: 1.2, max_distance: 22)
        created.add(hum)
        SceneTree.root.add(created)
        @enemy_nodes[enemy.id] = created
      end
      height = enemy.kind.charger? ? 0.8_f32 : 1.0_f32
      node.position = v3(enemy.position.x, height + Math.sin(Clock.elapsed * 4 + enemy.id) * 0.05, enemy.position.y)
      node.look_at(v3(@game.player.x, height, @game.player.y))
      node.scale = 0.82_f32 + 0.18_f32 * (enemy.health / (enemy.kind.charger? ? 105_f32 : 70_f32)).clamp(0_f32, 1_f32)
    end
  end

  private def draw_debug(_look : Vec3) : Nil
    if tracer = @tracer
      Scene3D.debug_line(tracer[0], tracer[1], tracer[2])
      @tracer = nil
    end
    # Directional markers over enemies remain readable in dark cover.
    @game.enemies.each do |enemy|
      next unless enemy.alive?
      p = v3(enemy.position.x, enemy.kind.charger? ? 1.7 : 2.0, enemy.position.y)
      Scene3D.debug_line(p, p + v3(0, 0.18, 0), enemy.kind.charger? ? Color.hex("#ff416c") : Color.hex("#5ee7ff"))
    end
  end

  private def restart(mode : EagleFPS::Mode) : Nil
    @enemy_nodes.each_value(&.free)
    @enemy_nodes.clear
    @game = EagleFPS::Game.new(mode)
    @old_health = @game.health
    @tip_time = 5_f32
    @step_timer = 0_f32
    sync_enemies
  end

  def draw(g : Graphics)
    w = Window.width
    h = Window.height
    # Weapon silhouette and recoil flash make firing legible without an external model.
    gun = @game.weapon_index == 0 ? Color.hex("#4d5e82") : Color.hex("#6a5238")
    g.polygon([v2(w * 0.56, h), v2(w * 0.62, h * 0.76), v2(w * 0.75, h * 0.8), v2(w * 0.82, h)], color: gun)
    if @flash > 0
      g.circle(v2(w * 0.63, h * 0.75), 9 + @flash * 35, color: Color.new(1, 0.75, 0.25, (@flash * 4).clamp(0_f32, 1_f32)))
    end
    cross = @game.cooldown > 0 ? Color.hex("#8190aa") : Color::WHITE
    g.line(w / 2 - 12, h / 2, w / 2 - 3, h / 2, cross, 2)
    g.line(w / 2 + 3, h / 2, w / 2 + 12, h / 2, cross, 2)
    g.line(w / 2, h / 2 - 12, w / 2, h / 2 - 3, cross, 2)
    g.line(w / 2, h / 2 + 3, w / 2, h / 2 + 12, cross, 2)
    panel_h = @game.message.empty? ? 70 : 94
    g.rect(12, 12, 340, panel_h, color: Color.new(0.02, 0.03, 0.08, 0.78))
    g.print("#{@game.mode}  #{@game.mode.waves? ? "WAVE #{@game.wave}" : "FRAGS #{@game.score}/15"}", 24, 22, Color.hex("#69e9ff"))
    g.print("HP #{@game.health.to_s.rjust(3)}   #{@game.weapon.name.upcase}   K #{@game.score} / D #{@game.deaths}", 24, 48, @game.health < 30 ? Color.hex("#ff416c") : Color::WHITE)
    g.print(@game.message, 24, 72, Color.hex("#ffbd59")) unless @game.message.empty?
    if @game.health <= 0 || @game.finished?
      text = @game.finished? ? "VICTORY\nR TO RESTART" : "SYSTEM DOWN\nRESPAWNING"
      g.printf(text, 0, h * 0.38, w, align: TextAlign::Center, color: Color::WHITE, scale: 2)
    elsif @tip_time > 0
      g.rect(0, h - 54, w, 54, color: Color.new(0, 0, 0, 0.62))
      g.printf("Click to capture mouse. WASD move, Shift sprint, click/RB fire.", 0, h - 42, w, align: TextAlign::Center, color: Color.gray(0.86))
      g.printf("1/2 weapons. F1 Waves. F2 Deathmatch.", 0, h - 22, w, align: TextAlign::Center, color: Color.gray(0.86))
    end
  end
end

Eagle.run(NeonBastion, title: "Eagle: Neon Bastion", width: 1100, height: 680, msaa: 4)
