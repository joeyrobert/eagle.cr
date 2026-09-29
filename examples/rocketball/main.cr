require "../../src/eagle"
require "./match"
require "./menu"
require "./settings"
require "./stage"
require "./audio"
include Eagle
include EagleRocketBall

# Boost Ball is rocket-powered car soccer: drive, jump, flip and boost to knock a giant ball into the other
# team's goal. It has quick and custom matches with bot opponents, free play, goal replays, boost pads,
# demolitions, overtime, a scoreboard and full menus. Every model and sound is generated in code.
class BoostBall < App
  enum Screen
    Title
    Setup
    Options
    Controls
    Game
    Pause
    Results
  end

  ARENA_DIAGONAL = 120_f32

  @screen = Screen::Title
  @return_to = Screen::Title
  @config = MatchConfig.new
  @match : Match = Match.new(MatchConfig.new)
  @stage : Stage? = nil
  @fx : Fx? = nil
  @sfx : Sfx? = nil
  @ball_node : MeshInstance3D? = nil
  @camera = Camera3D.new(position: v3(0, 20, 60), fov: 75)
  @views = [] of CarView
  @menus = {} of Screen => Menu
  @cam_dir = Vec3.new(0, 0, -1)
  @cam_pos = Vec3.new(0, 6, 40)
  @ball_cam = true
  @time = 0_f32
  @shake = 0_f32
  @steer = 0_f32
  @go_flash = 0_f32
  @count_pop = 0_f32
  @swell = 0_f32
  @tip_time = 0_f32
  @results_shown = false
  @feed = [] of {String, Color, Float32}
  @pickup : {Float32, Float32}? = nil
  @engine_voice : Voice? = nil
  @boost_voice : Voice? = nil
  @crowd_voice : Voice? = nil
  @music_voice : Voice? = nil
  @rng = Random.new(21)
  @last_touch_team = 0
  @trail_clock = 0_f32
  @orbit = 0_f32
  @autopilot : Bot? = nil

  private def stage : Stage
    @stage.not_nil!
  end

  private def fx : Fx
    @fx.not_nil!
  end

  private def sfx : Sfx
    @sfx.not_nil!
  end

  def load
    map_inputs
    @sfx = Sfx.new
    root = SceneTree.root
    @stage = Stage.new(root)
    @fx = Fx.new(root)
    ball_texture = Texture.new(Image.checkerboard(128, 64, 16, Color.hex("#eef2fb"), Color.hex("#39486b")), mipmaps: true)
    @ball_node = MeshInstance3D.new(Mesh.sphere(1, 28, 18), Material.new(texture: ball_texture, shininess: 100, specular: 0.9, emissive: Color.hex("#141c30")))
    root.add(@ball_node.not_nil!)
    root.add(@camera)
    @camera.make_current
    @camera.far = 400
    build_menus
    music = Audio.play(sfx.music, volume: 0.6, loop: true, bus: "music")
    @music_voice = music
    @engine_voice = Audio.play(sfx.engine, volume: 0, loop: true, bus: "sfx")
    @boost_voice = Audio.play(sfx.boost_loop, volume: 0, loop: true, bus: "sfx")
    @crowd_voice = Audio.play(sfx.crowd, volume: 0.1, loop: true, bus: "sfx")
    start_demo
    {% unless flag?(:wasm32) %}
      # Lets CI and screenshots jump straight into a match: EAGLE_ROCKETBALL=play or training.
      case ENV["EAGLE_ROCKETBALL"]?
      when "play"
        start_match(quick_config)
        @match.human.try { |car| @autopilot = Bot.new(car, Difficulty::Pro, Random.new(3)) }
      when "training" then start_match(training_config)
      end
    {% end %}
  end

  private def map_inputs
    Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1), Input.axis(GamepadAxis::TriggerRight, 1, 0.1)
    Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1), Input.axis(GamepadAxis::TriggerLeft, 1, 0.1)
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1, 0.15)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1, 0.15)
    Input.map "jump", Key::Space, GamepadButton::A
    Input.map "boost", Key::LShift, Key::RShift, MouseButton::Left, GamepadButton::X, GamepadButton::RightShoulder
    Input.map "handbrake", Key::LCtrl, Key::C, GamepadButton::B
    Input.map "roll_left", Key::Q, GamepadButton::LeftShoulder
    Input.map "roll_right", Key::E, GamepadButton::Y
    Input.map "ballcam", Key::B, GamepadButton::RightStick
    Input.map "pause", Key::Escape, Key::P, GamepadButton::Start
    Input.map "reset", Key::R, GamepadButton::Back
    Input.map "ui_up", Key::Up, Key::W, GamepadButton::DpadUp, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "ui_down", Key::Down, Key::S, GamepadButton::DpadDown, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "ui_left", Key::Left, Key::A, GamepadButton::DpadLeft, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "ui_right", Key::Right, Key::D, GamepadButton::DpadRight, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "ui_accept", Key::Enter, Key::Space, GamepadButton::A
    Input.map "ui_back", Key::Escape, Key::Backspace, GamepadButton::B
  end

  # ---- match setup ----

  private def quick_config : MatchConfig
    cfg = MatchConfig.new
    cfg.team_size = 2
    cfg.difficulty = Difficulty::Pro
    cfg.minutes = 3
    cfg.seed = (Time.utc.to_unix % 1000).to_i
    cfg
  end

  private def training_config : MatchConfig
    cfg = MatchConfig.new
    cfg.training = true
    cfg.minutes = 999
    cfg
  end

  private def start_demo : Nil
    cfg = MatchConfig.new
    cfg.human = false
    cfg.team_size = 2
    cfg.minutes = 999
    cfg.difficulty = Difficulty::Pro
    cfg.seed = 7
    m = Match.new(cfg)
    # Play a little ahead so the backdrop never starts on a kickoff line-up.
    (60 * 20).times do
      m.update(1_f32 / 60)
      m.events.clear
      m.skip_replay if m.phase.replay?
    end
    set_match(m)
    @screen = Screen::Title
  end

  private def start_match(cfg : MatchConfig) : Nil
    @config = cfg
    set_match(Match.new(cfg))
    @screen = Screen::Game
    @ball_cam = Settings.ball_cam?
    @cam_dir = Vec3.new(0, 0, -1)
    @tip_time = 9
    @results_shown = false
    @feed.clear
    fx.burst(Vec3.new(0, 1, 0), Color::WHITE, 0, 1)
  end

  private def set_match(m : Match) : Nil
    @views.each(&.free)
    @views.clear
    @match = m
    stage.bind_pads(m.pads)
    stage.recolor
    m.cars.each { |c| @views << CarView.new(c.team, Settings.team_color(c.team), SceneTree.root) }
    @ball_node.try(&.scale = m.ball.radius)
    @feed.clear
    @results_shown = false
    @go_flash = 0
  end

  private def leave_to_title : Nil
    start_demo
    @screen = Screen::Title
  end

  # ---- menus ----

  private def toggle(label : String, value : Bool, &block : Bool ->) : MenuItem
    MenuItem.choice(label, ["Off", "On"], value ? 1 : 0) { |i| block.call(i == 1) }
  end

  private def build_menus : Nil
    title = Menu.new("BOOST BALL", subtitle: "Rocket-powered car soccer")
    title << MenuItem.button("Quick Match") { start_match(quick_config) }
    title << MenuItem.button("Custom Match") { go(Screen::Setup) }
    title << MenuItem.button("Free Play") { start_match(training_config) }
    title << MenuItem.button("Settings") { open_side(Screen::Options) }
    title << MenuItem.button("Controls") { open_side(Screen::Controls) }
    {% unless flag?(:wasm32) %}
      title << MenuItem.button("Quit") { Eagle.quit }
    {% end %}
    @menus[Screen::Title] = title

    cfg = MatchConfig.new
    setup = Menu.new("MATCH SETUP", subtitle: "Pick your rules, then kick off")
    setup << MenuItem.choice("Team size", ["1 v 1", "2 v 2", "3 v 3"], cfg.team_size - 1) { |i| cfg.team_size = i + 1 }
    setup << MenuItem.choice("Bot skill", ["Rookie", "Pro", "All-Star"], cfg.difficulty.value) { |i| cfg.difficulty = Difficulty.from_value(i) }
    setup << MenuItem.choice("Match length", ["1 minute", "3 minutes", "5 minutes", "10 minutes"], 1) { |i| cfg.minutes = [1, 3, 5, 10][i] }
    setup << MenuItem.choice("Boost", ["Normal", "Unlimited", "None"], 0) { |i| cfg.boost_mode = BoostMode.from_value(i) }
    setup << MenuItem.choice("Ball size", ["Small", "Normal", "Big"], 1) { |i| cfg.ball_scale = [0.7_f32, 1_f32, 1.6_f32][i] }
    setup << MenuItem.choice("Gravity", ["Low", "Normal", "High"], 1) { |i| cfg.gravity_scale = [0.55_f32, 1_f32, 1.4_f32][i] }
    setup << MenuItem.choice("Your team", PALETTE.map(&.[0]), Settings.blue) { |i| Settings.blue = i; stage.recolor }
    setup << MenuItem.choice("Rivals", PALETTE.map(&.[0]), Settings.orange) { |i| Settings.orange = i; stage.recolor }
    setup << MenuItem.button("Kick Off!") do
      cfg.seed = (Time.utc.to_unix % 1000).to_i
      start_match(cfg)
    end
    setup << MenuItem.button("Back") { @screen = Screen::Title }
    setup.back = -> { @screen = Screen::Title; nil }
    @menus[Screen::Setup] = setup

    options = Menu.new("SETTINGS")
    options << MenuItem.slider("Master volume", 0, 1, Settings.master, 0.05) { |v| Settings.master = v }
    options << MenuItem.slider("Music", 0, 1, Settings.music, 0.05) { |v| Settings.music = v }
    options << MenuItem.slider("Effects", 0, 1, Settings.effects, 0.05) { |v| Settings.effects = v }
    fov = MenuItem.slider("Field of view", 70, 110, Settings.fov, 2) { |v| Settings.fov = v }
    fov.formatter = ->(v : Float32) { "#{v.to_i}°" }
    options << fov
    dist = MenuItem.slider("Camera distance", 0.7, 1.5, Settings.distance, 0.1) { |v| Settings.distance = v }
    dist.formatter = ->(v : Float32) { "x#{v.round(1)}" }
    options << dist
    options << toggle("Ball cam by default", Settings.ball_cam?) { |on| Settings.ball_cam = on }
    options << toggle("Screen shake", Settings.shake?) { |on| Settings.shake = on }
    options << toggle("Minimap", Settings.minimap?) { |on| Settings.minimap = on }
    {% unless flag?(:wasm32) %}
      options << toggle("Fullscreen", Window.fullscreen?) { |on| Window.fullscreen = on }
    {% end %}
    options << MenuItem.button("Back") { @screen = @return_to }
    options.back = -> { @screen = @return_to; nil }
    @menus[Screen::Options] = options

    controls = Menu.new("CONTROLS")
    controls << MenuItem.button("Back") { @screen = @return_to }
    controls.back = -> { @screen = @return_to; nil }
    @menus[Screen::Controls] = controls

    pause = Menu.new("PAUSED")
    pause << MenuItem.button("Resume") { @screen = Screen::Game }
    pause << MenuItem.button("Restart") { restart_match }
    pause << MenuItem.button("Settings") { open_side(Screen::Options, Screen::Pause) }
    pause << MenuItem.button("Controls") { open_side(Screen::Controls, Screen::Pause) }
    pause << MenuItem.button("Quit to Menu") { leave_to_title }
    pause.back = -> { @screen = Screen::Game; nil }
    @menus[Screen::Pause] = pause

    results = Menu.new("FULL TIME")
    results << MenuItem.button("Rematch") { restart_match }
    results << MenuItem.button("Main Menu") { leave_to_title }
    results.back = -> { leave_to_title; nil }
    @menus[Screen::Results] = results
  end

  private def go(screen : Screen) : Nil
    @screen = screen
  end

  private def open_side(screen : Screen, back : Screen = Screen::Title) : Nil
    @return_to = back
    @screen = screen
  end

  private def restart_match : Nil
    cfg = @config
    cfg.seed += 1
    start_match(cfg)
  end

  # ---- per-frame update ----

  def update(dt : Float32)
    dt = Math.min(dt, 0.05_f32)
    @time += dt
    @shake = Math.max(0_f32, @shake - dt * 2.2_f32)
    @go_flash = Math.max(0_f32, @go_flash - dt)
    @count_pop = Math.max(0_f32, @count_pop - dt)
    @swell = Math.max(0_f32, @swell - dt * 0.35_f32)
    @tip_time = Math.max(0_f32, @tip_time - dt)
    @feed = @feed.compact_map { |(t, c, ttl)| ttl - dt > 0 ? {t, c, ttl - dt} : nil }
    @pickup = @pickup.try { |(amt, ttl)| ttl - dt > 0 ? {amt, ttl - dt} : nil }
    apply_volumes

    case @screen
    when .game?
      update_game(dt)
    when .pause?
      update_menu(@menus[Screen::Pause], dt)
    when .results?
      @match.update(dt)
      handle_events
      update_menu(@menus[Screen::Results], dt)
    else
      @match.update(dt)
      handle_events
      @match.skip_replay if @match.phase.replay?
      update_menu(@menus[@screen], dt) unless @screen.game?
    end
    update_scene(dt)
  end

  private def update_game(dt : Float32) : Nil
    if Input.pressed?("pause")
      @screen = Screen::Pause
      return
    end
    if (human = @match.human) && !@autopilot
      c = human.controls
      c.throttle = Input.axis("down", "up")
      target = Input.axis("left", "right")
      @steer += (target - @steer) * (1 - Math.exp(-14_f32 * dt).to_f32)
      @steer = target if target == 0 && @steer.abs < 0.05
      c.steer = @steer
      c.roll = Input.axis("roll_right", "roll_left")
      c.jump = Input.down?("jump") || Input.pressed?("jump")
      c.boost = Input.down?("boost")
      c.handbrake = Input.down?("handbrake")
      @ball_cam = !@ball_cam if Input.pressed?("ballcam")
    end
    @autopilot.try(&.think(@match, dt))
    if @match.training? && Input.pressed?("reset")
      @match.kickoff
    end
    @match.skip_replay if @match.phase.replay? && (Input.pressed?("jump") || Input.pressed?("ui_accept"))
    @match.update(dt)
    handle_events
    if @match.finished? && @match.phase_time > 2.4 && !@results_shown
      @results_shown = true
      @screen = Screen::Results
    end
  end

  private def apply_volumes : Nil
    Audio.volume = Settings.master
    Audio.bus("sfx").volume = Settings.effects
    Audio.bus("music").volume = Settings.music * 0.55_f32
    playing = @screen.game?
    @music_voice.try(&.volume = playing ? 0.45_f32 : 0.7_f32)
    human = @match.human
    if playing && human && !human.demolished? && @match.phase.playing?
      speed = human.speed
      @engine_voice.try do |v|
        v.volume = 0.16_f32 + Math.min(0.2_f32, speed / 160)
        v.pitch = 0.55_f32 + speed / MAX_BOOST_SPEED * 1.5_f32
      end
      @boost_voice.try(&.volume = human.boosting? ? 0.9_f32 : 0_f32)
    else
      @engine_voice.try(&.volume = 0_f32)
      @boost_voice.try(&.volume = 0_f32)
    end
    @crowd_voice.try(&.volume = 0.1_f32 + @swell * 0.5_f32)
  end

  # ---- events: sound, particles and the feed ----

  private def handle_events : Nil
    @match.drain_events.each do |e|
      case e.kind
      in .countdown?
        Audio.play(sfx.beep, volume: 0.6, pitch: 1, bus: "sfx")
        @count_pop = 0.9_f32
      in .kickoff?
        Audio.play(sfx.go, volume: 0.6, bus: "sfx")
        @go_flash = 0.9_f32
      in .touch?
        team_color = Settings.team_color(e.team)
        Audio.play_at(sfx.hit, e.pos, volume: 0.35_f32 + e.value * 0.65_f32, pitch: 0.85_f32 + e.value * 0.4_f32, bus: "sfx", min_distance: 10, max_distance: 140)
        fx.burst(e.pos, team_color, (6 + e.value * 14).to_i, 6 + e.value * 14, 0.35_f32, 0.6_f32, @rng)
        @shake = Math.max(@shake, e.value * 0.5_f32) if e.car.try(&.human?)
        @last_touch_team = e.team
      in .bounce?
        Audio.play_at(sfx.bounce, e.pos, volume: (e.value / 30).clamp(0.1_f32, 0.8_f32), bus: "sfx", min_distance: 10, max_distance: 140)
      in .goal?
        color = Settings.team_color(e.team)
        Audio.play(sfx.horn, volume: 0.7, bus: "sfx")
        Audio.play(sfx.roar, volume: 0.8, bus: "sfx")
        fx.burst(e.pos, color, 70, 26, 0.9_f32, 1.6_f32, @rng)
        stage.flash_goal(e.team)
        @shake = 1.2_f32
        @swell = 1
      in .pad?
        if e.car.try(&.human?)
          Audio.play(e.value > 50 ? sfx.pad_big : sfx.pad_small, volume: 0.7, bus: "sfx")
          @pickup = {e.value, 1.2_f32}
        else
          Audio.play_at(e.value > 50 ? sfx.pad_big : sfx.pad_small, e.pos, volume: 0.5, bus: "sfx", min_distance: 12, max_distance: 90)
        end
      in .jump?, .dodge?
        Audio.play_at(e.kind.dodge? ? sfx.dodge : sfx.jump, e.pos, volume: 0.5, pitch: 0.9_f32 + @rng.rand.to_f32 * 0.2_f32, bus: "sfx", min_distance: 10, max_distance: 90)
      in .demo?
        color = Settings.team_color(e.team)
        Audio.play_at(sfx.demo, e.pos, volume: 0.9, bus: "sfx", min_distance: 12, max_distance: 140)
        fx.burst(e.pos, color, 50, 22, 0.8_f32, 1.2_f32, @rng)
        @shake = Math.max(@shake, 0.7_f32)
        add_feed("#{e.car.try(&.name)} demolished a rival", color)
      in .save?
        Audio.play(sfx.save, volume: 0.7, bus: "sfx")
        add_feed("SAVE by #{e.car.try(&.name)}", Settings.team_color(e.team))
      in .overtime?
        Audio.play(sfx.horn, volume: 0.5, pitch: 1.3, bus: "sfx")
        add_feed("OVERTIME: next goal wins", Color.hex("#ff5060"))
      in .whistle?
        Audio.play(sfx.whistle, volume: 0.8, bus: "sfx")
        @swell = 1
      end
    end
  end

  private def add_feed(text : String, color : Color) : Nil
    @feed << {text, color, 4_f32}
    @feed.shift if @feed.size > 4
  end

  # ---- scene sync and camera ----

  private def update_scene(dt : Float32) : Nil
    m = @match
    frame = m.replay_frame
    ball_pos = frame ? frame.ball : m.ball.pos
    ball_roll = frame ? frame.roll : m.ball.roll
    @ball_node.try do |n|
      n.position = ball_pos
      n.rotation = ball_roll
    end
    m.cars.each_with_index do |car, i|
      view = @views[i]? || next
      if frame
        cs = frame.cars[i]
        view.sync(dt, cs.pos, cs.orient, cs.boosting, cs.visible, 0_f32)
        emit_trail(car, cs.pos, cs.orient, cs.boosting, dt)
      else
        view.sync(dt, car.pos, car.orient, car.boosting? && !car.demolished?, !car.demolished?, car.vel.dot(car.forward))
        emit_trail(car, car.pos, car.orient, car.boosting? && !car.demolished?, dt)
      end
    end
    ball_color = Settings.team_color(m.ball.last_touch.try(&.team) || @last_touch_team)
    stage.update(dt, ball_pos, EagleRocketBall.mix(ball_color, Color::WHITE, 0.3), @time)
    if m.ball.vel.length > 30 && !frame
      fx.emit(m.ball.pos, v3(@rng.rand * 2 - 1, @rng.rand * 2 - 1, @rng.rand * 2 - 1) * 1.5, ball_color, m.ball.radius * 0.9_f32, 0.35, 0)
    end
    fx.update(dt)
    update_camera(dt, ball_pos)
  end

  private def emit_trail(car : Car, pos : Vec3, orient : Quat, boosting : Bool, dt : Float32) : Nil
    return unless boosting
    color = EagleRocketBall.mix(Settings.team_color(car.team), Color.hex("#ffd9a0"), 0.5)
    rear = pos + orient * v3(0, -0.05, 2.6)
    fx.emit(rear, orient * v3(@rng.rand * 2 - 1, @rng.rand * 2 - 1, 6) * 0.9, color, 0.9_f32, 0.32_f32)
  end

  private def flat(v : Vec3, fallback : Vec3) : Vec3
    f = Vec3.new(v.x, 0, v.z)
    f.length > 0.05 ? f.normalized : fallback
  end

  private def update_camera(dt : Float32, ball_pos : Vec3) : Nil
    cam = @camera
    m = @match
    human = m.human
    fov = 75_f32
    if (@screen.game? || @screen.pause?) && m.phase.replay?
      side = m.last_goal_team == 0 ? -1_f32 : 1_f32
      target = v3(50 * (ball_pos.x >= 0 ? 1 : -1), 16, ball_pos.z * 0.8_f32)
      @cam_pos = @cam_pos.lerp(target, 1 - Math.exp(-3_f32 * dt).to_f32)
      cam.position = @cam_pos
      cam.look_at(ball_pos + v3(0, 1, 0))
      fov = 65_f32 + side * 0
    elsif (@screen.game? || @screen.pause?) && m.phase.goal?
      a = 0.6_f32 + m.phase_time * 0.9_f32
      target = ball_pos + v3(Math.sin(a) * 20, 8, Math.cos(a) * 20)
      @cam_pos = @cam_pos.lerp(target, 1 - Math.exp(-4_f32 * dt).to_f32)
      cam.position = @cam_pos
      cam.look_at(ball_pos)
    elsif (@screen.game? || @screen.pause?) && human && !human.demolished? && !m.finished?
      chase(cam, human, m.ball.pos, dt)
      fov = Settings.fov + (human.speed / MAX_BOOST_SPEED) * 10 + (human.boosting? ? 4 : 0)
    else
      spectate(cam, ball_pos, dt)
      fov = 70_f32
    end
    if Settings.shake? && @shake > 0
      cam.position = cam.position + v3(@rng.rand * 2 - 1, @rng.rand * 2 - 1, @rng.rand * 2 - 1) * (@shake * 0.5_f32)
    end
    cam.fov_degrees = cam.fov_degrees + (fov - cam.fov_degrees) * (1 - Math.exp(-6_f32 * dt).to_f32)
  end

  private def chase(cam : Camera3D, car : Car, ball : Vec3, dt : Float32) : Nil
    fwd = flat(car.forward, @cam_dir)
    desired = fwd
    if @ball_cam
      to_ball = flat(ball - car.pos, fwd)
      desired = to_ball if (ball - car.pos).length > 6
    end
    @cam_dir = (@cam_dir + (desired - @cam_dir) * (1 - Math.exp(-(@ball_cam ? 5.5_f32 : 4_f32) * dt).to_f32)).normalized
    dist = 10_f32 * Settings.distance
    height = 4.4_f32 * (0.7_f32 + Settings.distance * 0.3_f32)
    target = car.pos - @cam_dir * dist + v3(0, height, 0)
    target = Vec3.new(target.x.clamp(-HALF_W - 5, HALF_W + 5), Math.max(1.8_f32, target.y), target.z.clamp(-HALF_L - 14, HALF_L + 14))
    @cam_pos = @cam_pos.lerp(target, 1 - Math.exp(-16_f32 * dt).to_f32)
    cam.position = @cam_pos
    look = car.pos + @cam_dir * 9 + v3(0, 1.4, 0)
    look = look.lerp(ball + v3(0, 0.5, 0), 0.6_f32) if @ball_cam
    cam.look_at(look)
  end

  private def spectate(cam : Camera3D, ball : Vec3, dt : Float32) : Nil
    @orbit += dt * 0.11_f32
    shot = (@time / 10).to_i % 3
    target, look = case shot
                   when 0
                     {v3(Math.sin(@orbit) * 64, 28, Math.cos(@orbit) * 78), ball * 0.35_f32 + v3(0, 2, 0)}
                   when 1
                     {v3(ball.x * 0.4_f32, 11, HALF_L + 24), ball}
                   else
                     {v3(-HALF_W - 14, 16, ball.z * 0.7_f32), ball}
                   end
    @cam_pos = @cam_pos.lerp(target, 1 - Math.exp(-2.2_f32 * dt).to_f32)
    cam.position = @cam_pos
    cam.look_at(look)
  end

  # ---- menu handling ----

  private def menu_geometry(menu : Menu) : {Float32, Float32, Float32, Float32, Float32}
    w = Window.width.to_f32
    h = Window.height.to_f32
    n = menu.items.size
    fit = (h / 720).clamp(0.62_f32, 1.2_f32)
    row = (n > 8 ? 38_f32 : 48_f32) * fit
    gap = (n > 8 ? 6_f32 : 10_f32) * fit
    top = case @screen
          when .title?            then h * 0.4_f32
          when .pause?, .results? then h * 0.4_f32
          when .controls?         then h * 0.84_f32
          else                         h * 0.2_f32
          end
    if @screen.results?
      top = h * 0.78_f32
    end
    {w / 2, top, Math.min(520_f32, w - 40), row, gap}
  end

  private def update_menu(menu : Menu, dt : Float32) : Nil
    cx, top, width, row, gap = menu_geometry(menu)
    rects = menu.layout(cx, top, width, row, gap)
    if Input.pressed?("ui_up")
      menu.move(-1)
      Audio.play(sfx.ui_move, bus: "sfx")
    elsif Input.pressed?("ui_down")
      menu.move(1)
      Audio.play(sfx.ui_move, bus: "sfx")
    end
    if Input.pressed?("ui_left")
      menu.adjust(-1)
      Audio.play(sfx.ui_move, bus: "sfx")
    elsif Input.pressed?("ui_right")
      menu.adjust(1)
      Audio.play(sfx.ui_move, bus: "sfx")
    end
    if Input.pressed?("ui_accept")
      Audio.play(sfx.ui_ok, bus: "sfx")
      menu.activate
      return
    end
    if Input.pressed?("ui_back") || (Input.pressed?("pause") && @screen.pause?)
      if menu.go_back
        Audio.play(sfx.ui_back, bus: "sfx")
      end
      return
    end
    mouse = Input.mouse
    hover = menu.item_at(mouse, rects)
    if Input.mouse_delta.length > 0.5 && hover && hover != menu.cursor
      menu.select(hover)
      Audio.play(sfx.ui_move, volume: 0.4, bus: "sfx")
    end
    return unless hover
    item = menu.items[hover]
    if item.kind.slider?
      if Input.mouse_down?(MouseButton::Left)
        menu.select(hover)
        r = rects[hover]
        track_x = r.x + r.w * 0.5_f32
        track_w = r.w * 0.44_f32
        item.set_fraction((mouse.x - track_x) / track_w)
      end
    elsif Input.mouse_pressed?(MouseButton::Left)
      menu.select(hover)
      Audio.play(sfx.ui_ok, bus: "sfx")
      if item.kind.choice? && mouse.x < rects[hover].x + rects[hover].w * 0.5_f32
        item.adjust(-1)
      else
        item.activate
      end
    end
  end

  # ---- drawing ----

  private def shadow_text(g : Graphics, text : String, x : Number, y : Number, color : Color = Color::WHITE, scale : Number = 1, align : TextAlign = TextAlign::Left) : Nil
    g.print(text, x + scale.to_f32.ceil, y + scale.to_f32.ceil, Color.new(0, 0, 0, 0.7), scale: scale, align: align)
    g.print(text, x, y, color, scale: scale, align: align)
  end

  private def panel(g : Graphics, x : Number, y : Number, w : Number, h : Number, alpha : Float32 = 0.72_f32, r : Number = 10) : Nil
    g.rounded_rect(x, y, w, h, r, color: Color.new(0.02, 0.04, 0.1, alpha))
  end

  def draw(g : Graphics)
    w = Window.width.to_f32
    h = Window.height.to_f32
    case @screen
    when .game?
      draw_hud(g, w, h)
    when .pause?
      draw_hud(g, w, h)
      g.rect(0, 0, w, h, color: Color.new(0, 0.02, 0.06, 0.55))
      draw_menu(g, @menus[Screen::Pause], w, h)
    when .results?
      draw_results(g, w, h)
      draw_menu(g, @menus[Screen::Results], w, h)
    when .controls?
      draw_controls(g, w, h)
      draw_menu(g, @menus[Screen::Controls], w, h)
    else
      g.rect(0, 0, w, h, color: Color.new(0, 0.02, 0.06, 0.35))
      draw_menu(g, @menus[@screen], w, h)
    end
  end

  private def draw_menu(g : Graphics, menu : Menu, w : Float32, h : Float32) : Nil
    cx, top, width, row, gap = menu_geometry(menu)
    rects = menu.layout(cx, top, width, row, gap)
    blue = Settings.team_color(0)
    orange = Settings.team_color(1)
    if @screen.title? || @screen.setup? || @screen.options?
      if @screen.title?
        ts = (w / 1280 * 7).clamp(3_f32, 7_f32)
        shadow_text(g, "BOOST", cx - 10, h * 0.08, blue, ts, TextAlign::Right)
        shadow_text(g, "BALL", cx + 10, h * 0.08, orange, ts)
        shadow_text(g, menu.subtitle, cx, h * 0.08 + ts * 15, Color.gray(0.85), 2, TextAlign::Center)
      else
        shadow_text(g, menu.title, cx, h * 0.07, Color::WHITE, 5, TextAlign::Center)
        shadow_text(g, menu.subtitle, cx, h * 0.07 + 54, Color.gray(0.8), 2, TextAlign::Center) unless menu.subtitle.empty?
      end
    elsif @screen.pause?
      shadow_text(g, menu.title, cx, h * 0.2, Color::WHITE, 6, TextAlign::Center)
    end
    first = rects.first?
    last = rects.last?
    if first && last
      panel(g, first.x - 16, first.y - 14, first.w + 32, last.y + last.h - first.y + 28, 0.62_f32, 14)
    end
    menu.items.each_with_index do |item, i|
      r = rects[i]
      selected = i == menu.cursor
      accent = selected ? blue : Color.new(0.14, 0.2, 0.34, 1)
      g.rounded_rect(r.x, r.y, r.w, r.h, 8, color: selected ? Color.new(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55, 0.95) : Color.new(0.07, 0.1, 0.18, 0.85))
      g.rect(r.x, r.y + 6, 5, r.h - 12, color: accent) if selected
      label_scale = 2
      ty = r.y + (r.h - 8 * label_scale) / 2
      case item.kind
      in .button?
        shadow_text(g, item.label, r.x + r.w / 2, ty, selected ? Color::WHITE : Color.gray(0.82), label_scale, TextAlign::Center)
      in .header?
        shadow_text(g, item.label, r.x + 16, ty, Color.gray(0.6), label_scale)
      in .choice?
        shadow_text(g, item.label, r.x + 16, ty, selected ? Color::WHITE : Color.gray(0.82), label_scale)
        text = item.display
        shadow_text(g, selected ? "< #{text} >" : text, r.x + r.w - 16, ty, selected ? orange : Color.gray(0.9), label_scale, TextAlign::Right)
      in .slider?
        shadow_text(g, item.label, r.x + 16, ty, selected ? Color::WHITE : Color.gray(0.82), label_scale)
        tx = r.x + r.w * 0.5_f32
        tw = r.w * 0.34_f32
        g.rounded_rect(tx, r.y + r.h / 2 - 4, tw, 8, 4, color: Color.new(0.03, 0.05, 0.1, 1))
        g.rounded_rect(tx, r.y + r.h / 2 - 4, Math.max(8_f32, tw * item.fraction), 8, 4, color: selected ? orange : Color.gray(0.75))
        g.circle(tx + tw * item.fraction, r.y + r.h / 2, 9, color: Color::WHITE)
        shadow_text(g, item.display, r.x + r.w - 16, ty, selected ? orange : Color.gray(0.9), label_scale, TextAlign::Right)
      end
    end
    g.printf("Arrows / WASD or mouse to choose    Enter to select    Esc to go back", 0, h - 30, w, align: TextAlign::Center, color: Color.gray(0.65))
  end

  private def draw_controls(g : Graphics, w : Float32, h : Float32) : Nil
    g.rect(0, 0, w, h, color: Color.new(0, 0.02, 0.06, 0.55))
    shadow_text(g, "CONTROLS", w / 2, h * 0.07, Color::WHITE, 5, TextAlign::Center)
    rows = [
      {"W / S", "Accelerate / reverse (in the air: pitch)"},
      {"A / D", "Steer (in the air: yaw)"},
      {"Space", "Jump. Press again for a double jump,"},
      {"", "or with a direction held for a flip"},
      {"Shift or Mouse 1", "Boost (uses the boost meter)"},
      {"Ctrl or C", "Handbrake for power slides"},
      {"Q / E", "Air roll left / right"},
      {"B", "Toggle ball cam"},
      {"Esc or P", "Pause"},
      {"R", "Reset the ball (free play)"},
    ]
    x = w / 2 - Math.min(400_f32, w / 2 - 20)
    y = h * 0.2_f32
    panel(g, x - 16, y - 14, Math.min(800_f32, w - 8), rows.size * 32 + 28, 0.7_f32, 14)
    rows.each_with_index do |(key, action), i|
      shadow_text(g, key, x, y + i * 32, Settings.team_color(1), 2)
      shadow_text(g, action, x + 290, y + i * 32, Color.gray(0.92), 2)
    end
    shadow_text(g, "Gamepad: triggers drive, left stick steers, A jump, X boost, B handbrake, LB/Y air roll", w / 2, y + rows.size * 32 + 26, Color.gray(0.8), 1, TextAlign::Center)
    shadow_text(g, "Hit the ball with the front of the car while boosting for the hardest shots. Hit a rival at supersonic speed to demolish them.", w / 2, y + rows.size * 32 + 46, Color.gray(0.7), 1, TextAlign::Center)
  end

  private def draw_results(g : Graphics, w : Float32, h : Float32) : Nil
    m = @match
    g.rect(0, 0, w, h, color: Color.new(0, 0.02, 0.06, 0.6))
    mine = m.human.try(&.team) || 0
    headline = m.winner == -1 ? "DRAW" : (m.winner == mine ? "VICTORY" : "DEFEAT")
    tint = m.winner == -1 ? Color.gray(0.9) : Settings.team_color(m.winner)
    shadow_text(g, headline, w / 2, h * 0.05, tint, 8, TextAlign::Center)
    shadow_text(g, "#{m.scores[0]}  -  #{m.scores[1]}", w / 2, h * 0.05 + 82, Color::WHITE, 5, TextAlign::Center)
    x0 = w / 2 - Math.min(400_f32, w / 2 - 20)
    cols = ["PLAYER", "SCORE", "G", "A", "SV", "SH", "DM"]
    xs = [0_f32, 290_f32, 400_f32, 450_f32, 500_f32, 555_f32, 610_f32]
    y0 = h * 0.28_f32
    panel(g, x0 - 16, y0 - 12, 660, m.cars.size * 30 + 52, 0.7_f32, 12)
    cols.each_with_index { |c, i| shadow_text(g, c, x0 + xs[i], y0, Color.gray(0.6), 2) }
    m.cars.sort_by { |c| {c.team, -c.score} }.each_with_index do |car, i|
      y = y0 + 30 + i * 30
      color = Settings.team_color(car.team)
      g.rect(x0 - 8, y - 2, 4, 22, color: color)
      vals = [car.name, car.score.to_s, car.goals.to_s, car.assists.to_s, car.saves.to_s, car.shots.to_s, car.demos.to_s]
      vals.each_with_index { |v, k| shadow_text(g, v, x0 + xs[k], y, k == 0 ? color : Color::WHITE, 2) }
    end
  end

  private def draw_hud(g : Graphics, w : Float32, h : Float32) : Nil
    m = @match
    human = m.human
    blue = Settings.team_color(0)
    orange = Settings.team_color(1)
    s = (w / 1280).clamp(0.7_f32, 1.4_f32)
    frame = m.replay_frame
    unless frame
      draw_tags(g, m, w, h)
    end
    # Scoreboard.
    bw = 116 * s
    tw = 230 * s
    top = 12 * s
    bh = 56 * s
    left = w / 2 - tw / 2 - bw
    g.rounded_rect(left, top, bw, bh, 8, color: Color.new(blue.r * 0.7, blue.g * 0.7, blue.b * 0.7, 0.9))
    g.rounded_rect(w / 2 + tw / 2, top, bw, bh, 8, color: Color.new(orange.r * 0.7, orange.g * 0.7, orange.b * 0.7, 0.9))
    g.rect(w / 2 - tw / 2, top, tw, bh, color: Color.new(0.02, 0.04, 0.1, 0.88))
    shadow_text(g, m.scores[0].to_s, left + bw / 2, top + 8 * s, Color::WHITE, 5 * s, TextAlign::Center)
    shadow_text(g, m.scores[1].to_s, w / 2 + tw / 2 + bw / 2, top + 8 * s, Color::WHITE, 5 * s, TextAlign::Center)
    if m.training?
      shadow_text(g, "FREE PLAY", w / 2, top + 20 * s, Color.gray(0.9), 2 * s, TextAlign::Center)
    elsif m.overtime?
      shadow_text(g, "OVERTIME", w / 2, top + 20 * s, Color.hex("#ff5060"), 2 * s, TextAlign::Center)
    else
      secs = m.clock.ceil.to_i
      shadow_text(g, "#{secs // 60}:#{(secs % 60).to_s.rjust(2, '0')}", w / 2, top + 16 * s, secs <= 10 ? Color.hex("#ff5060") : Color::WHITE, 3 * s, TextAlign::Center)
    end
    # Feed.
    @feed.each_with_index do |(text, color, ttl), i|
      a = Math.min(1_f32, ttl)
      shadow_text(g, text, w - 16, 16 + i * 24 * s, Color.new(color.r, color.g, color.b, a), 2 * s, TextAlign::Right)
    end
    if human
      draw_gauges(g, human, w, h, s)
      draw_minimap(g, m, w, h, s) if Settings.minimap?
      shadow_text(g, @ball_cam ? "BALL CAM" : "CAR CAM", 16, 16, Color.gray(0.8), 2 * s) unless frame
    end
    draw_banners(g, m, w, h, s, frame != nil)
    if @tip_time > 0 && m.phase.countdown?
      g.printf("Drive into the ball to hit it. Boost pads refill your meter. Supersonic hits demolish rivals.", 0, h - 70 * s, w, align: TextAlign::Center, color: Color.gray(0.9), scale: 1.5)
    end
  end

  private def draw_tags(g : Graphics, m : Match, w : Float32, h : Float32) : Nil
    m.cars.each do |car|
      next if car.demolished? || car.human?
      p = @camera.world_to_screen(car.pos + v3(0, 2.6, 0)) || next
      next if p.x < -50 || p.x > w + 50 || p.y < -50 || p.y > h + 50
      d = (car.pos - @camera.position).length
      scale = (28 / Math.max(d, 10_f32)).clamp(0.75_f32, 1.4_f32) * 1.5_f32
      color = Settings.team_color(car.team)
      shadow_text(g, car.name, p.x, p.y - 8 * scale, color, scale, TextAlign::Center)
    end
  end

  private def draw_gauges(g : Graphics, car : Car, w : Float32, h : Float32, s : Float32) : Nil
    cx = w - 110 * s
    cy = h - 110 * s
    r = 66 * s
    g.circle(cx, cy, r + 14 * s, color: Color.new(0.02, 0.04, 0.1, 0.7))
    frac = (car.boost / 100).clamp(0_f32, 1_f32)
    color = @match.config.boost_mode.off? ? Color.gray(0.5) : EagleRocketBall.mix(Color.hex("#ff9a2e"), Color.hex("#ffe27a"), frac)
    ring(g, cx, cy, r, 1_f32, Color.new(1, 1, 1, 0.12), 9 * s)
    ring(g, cx, cy, r, @match.config.boost_mode.unlimited? ? 1_f32 : frac, color, 9 * s)
    label = @match.config.boost_mode.unlimited? ? "INF" : car.boost.round.to_i.to_s
    shadow_text(g, label, cx, cy - 26 * s, Color::WHITE, 4 * s, TextAlign::Center)
    shadow_text(g, "BOOST", cx, cy + 34 * s, Color.gray(0.75), 1.5 * s, TextAlign::Center)
    kph = (car.speed * 3.6).round.to_i
    shadow_text(g, "#{kph} KM/H#{car.supersonic? ? "  SUPERSONIC" : ""}", cx - r - 16 * s, cy + r - 6 * s, car.supersonic? ? Color.hex("#7ff0ff") : Color.gray(0.8), 1.5 * s, TextAlign::Right)
    if pop = @pickup
      shadow_text(g, "+#{pop[0].round.to_i}", cx, cy - r - 34 * s - (1.2_f32 - pop[1]) * 20, Color.new(1, 0.85, 0.3, Math.min(1_f32, pop[1] * 2)), 3 * s, TextAlign::Center)
    end
  end

  private def ring(g : Graphics, cx : Number, cy : Number, r : Number, frac : Float32, color : Color, width : Number) : Nil
    return if frac <= 0
    steps = Math.max(2, (frac * 60).ceil.to_i)
    pts = Array(Vec2).new(steps + 1) do |i|
      a = -Math::PI / 2 + Math::TAU * frac * i / steps
      Vec2.new(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
    end
    g.polyline(pts, color, width)
  end

  private def draw_minimap(g : Graphics, m : Match, w : Float32, h : Float32, s : Float32) : Nil
    k = 2.1_f32 * s
    mw = HALF_W * 2 * k
    mh = (HALF_L * 2 + 10) * k
    x = 16 * s
    y = h - mh - 16 * s
    panel(g, x - 6, y - 6, mw + 12, mh + 12, 0.6_f32, 8)
    g.rect(x, y, mw, mh, color: Color.new(0.05, 0.25, 0.16, 0.7))
    at = ->(p : Vec3) { Vec2.new(x + (p.x + HALF_W) * k, y + (p.z + HALF_L + 5) * k) }
    g.rect(x + (HALF_W - GOAL_HALF_W) * k, y, GOAL_HALF_W * 2 * k, 5 * k, color: Settings.team_color(1))
    g.rect(x + (HALF_W - GOAL_HALF_W) * k, y + mh - 5 * k, GOAL_HALF_W * 2 * k, 5 * k, color: Settings.team_color(0))
    g.line(x, at.call(Vec3::ZERO).y, x + mw, at.call(Vec3::ZERO).y, Color.new(1, 1, 1, 0.3), 1)
    m.pads.each do |p|
      next unless p.big?
      g.circle(at.call(p.pos), 3.5 * s, color: p.active? ? Color.hex("#ffc94d") : Color.new(0.4, 0.3, 0.1, 0.8))
    end
    m.cars.each do |car|
      next if car.demolished?
      pt = at.call(car.pos)
      g.circle(pt, (car.human? ? 5.5 : 4.5) * s, color: Settings.team_color(car.team))
      g.circle_line(pt.x, pt.y, (car.human? ? 5.5 : 4.5) * s, Color::WHITE) if car.human?
      f = car.forward
      g.line(pt, pt + Vec2.new(f.x, f.z) * 9 * s, Color::WHITE, 1.5)
    end
    g.circle(at.call(m.ball.pos), 4 * s, color: Color::WHITE)
  end

  private def draw_banners(g : Graphics, m : Match, w : Float32, h : Float32, s : Float32, replaying : Bool) : Nil
    if m.phase.countdown?
      n = m.countdown.ceil.to_i
      pop = 1 + @count_pop * 0.6_f32
      shadow_text(g, n.to_s, w / 2, h * 0.3_f32, Color::WHITE, 14 * s * pop, TextAlign::Center) if n >= 1
    elsif @go_flash > 0 && m.phase.playing?
      shadow_text(g, "GO!", w / 2, h * 0.3_f32, Color.new(1, 0.9, 0.3, Math.min(1_f32, @go_flash * 2)), 14 * s, TextAlign::Center)
    end
    if m.phase.goal? || m.phase.replay?
      team = m.last_goal_team
      color = Settings.team_color(team)
      if m.phase.goal?
        pulse = 1 + Math.sin(@time * 12).abs * 0.12_f32
        shadow_text(g, "GOAL!", w / 2, h * 0.22_f32, color, 14 * s * pulse, TextAlign::Center)
        who = m.last_scorer
        text = who ? "Scored by #{who.name}" : "Own goal"
        text += "     Assist: #{m.last_assist.try(&.name)}" if m.last_assist
        shadow_text(g, text, w / 2, h * 0.22_f32 + 130 * s, Color::WHITE, 3 * s, TextAlign::Center)
      else
        bar = 54 * s
        g.rect(0, 0, w, bar, color: Color.new(0, 0, 0, 0.75))
        g.rect(0, h - bar, w, bar, color: Color.new(0, 0, 0, 0.75))
        shadow_text(g, "REPLAY", 30, 14 * s, color, 4 * s)
        shadow_text(g, "Press Space to skip", w / 2, h - bar + 16 * s, Color.gray(0.85), 2 * s, TextAlign::Center)
      end
    end
    if m.phase.finished?
      shadow_text(g, "FULL TIME", w / 2, h * 0.3_f32, Color::WHITE, 12 * s, TextAlign::Center)
    end
  end
end

Eagle.run(BoostBall, title: "Eagle: Boost Ball", width: 1280, height: 720, msaa: 4)
