module Portal3
  # Portal 3. A first-person puzzle game built on Eagle: the player carries a device
  # that opens linked portals on white panels, and uses them, weighted cubes, buttons,
  # lifts and lasers to work through a series of test chambers.
  class Game < App
    BLUE   = Color.hex("#1f8fff")
    ORANGE = Color.hex("#ff8a1f")
    GOAL   = Color.hex("#7dff9a")

    # How far the device can reach.
    REACH = 64_f32
    # Off-screen render width for each portal. Height follows the window aspect.
    VIEW_WIDTH = 512

    # Speeds, timings and other feel constants.
    DEATH_FADE   = 0.5_f32
    LINE_SECONDS = 7.0_f32

    @chamber_root : Node3D
    @builder : Builder
    @blue : Portal
    @orange : Portal
    @pair : PortalPair
    @player : Player
    @camera : Camera3D
    @chamber : Chamber?
    @chamber_index = 0

    @ghost : MeshInstance3D
    @ghost_ok : Material
    @ghost_bad : Material
    @aim : Placement?
    @aim_host : Node3D?

    @holding : Cube?
    @line_timer = 0_f32
    @fade = 0_f32
    @transition = 0_f32
    @pending_chamber : Int32? = nil
    @death_lock = 0_f32
    @hud_alpha = 1_f32
    @started = false
    @test_mode = false
    @test_results = [] of Tuple(String, Bool)
    @test_start = v3(0, 0, 0)
    # Where each loose prop was last step, so a field can tell if it was crossed.
    @prop_previous : Hash(Cube | Ball, Vec3) = {} of (Cube | Ball) => Vec3
    # :playing, :paused, :menu or :cutscene.
    @screen : Symbol = :playing
    @cutscene : Cutscene? = nil
    @holding_ball : Ball? = nil
    @perf_start_frame = 0
    @perf_start_time = 0.0
    @dump_path = ENV["EAGLE_DUMP_PORTAL"]?
    @dumped = false
    @footstep_armed = true
    @laser_hum : Array(AudioPlayer3D) = [] of AudioPlayer3D
    @drone : AudioPlayer3D?

    # The whole scene is built here rather than in `load`, because Crystal requires
    # instance variables to be assigned in `initialize`. `Eagle.run` is given the class,
    # so this runs after the GPU device exists and textures are safe to create.
    def initialize
      map_input
      setup_environment

      @chamber_root = Node3D.new("chamber")
      @builder = Builder.new(@chamber_root)
      view_w, view_h = Portal.view_size(VIEW_WIDTH)
      @blue = Portal.new(BLUE, @chamber_root, view_w, view_h)
      @orange = Portal.new(ORANGE, @chamber_root, view_w, view_h)
      @pair = PortalPair.new(@blue, @orange)

      @player = Player.new(v3(0, 1, 0), @pair)
      @camera = Camera3D.new("eye", v3(0, 1.62, 0), 75, true)
      @camera.far = 300_f32

      # The aiming ghost: the silhouette of where the next portal would go.
      @ghost_ok = Material.new(Color.new(0.4, 1.0, 0.6, 0.35), unlit: true, transparent: true)
      @ghost_bad = Material.new(Color.new(1.0, 0.3, 0.3, 0.3), unlit: true, transparent: true)
      @ghost = MeshInstance3D.new(Portal.ellipse_mesh, @ghost_ok)
      @ghost.cast_shadows = false
      @ghost.visible = false
      @chamber_root.add(@ghost)

      # A key from above for shape, and a cooler fill from the opposite side so
      # surfaces facing away from the key are still readable.
      SceneTree.root.add(@chamber_root, @player, @camera,
        DirectionalLight3D.new(v3(-0.35, -1, -0.25), Color.hex("#e6ecfa"), 0.5, "key"),
        DirectionalLight3D.new(v3(0.5, -0.4, 0.6), Color.hex("#b9c6e0"), 0.3, "fill"),
        PointLight3D.new(v3(0, 3.4, 0), Color.hex("#fff4e0"), 0.9, 24, "lamp"))

      # A facility drone that follows the player, so every chamber has a bed of sound.
      drone = AudioPlayer3D.new(Sounds[:chime], position: v3(0, 2, 0), loop: true,
        autoplay: true, volume: 0.05, min_distance: 4, max_distance: 40)
      @drone = drone
      SceneTree.root.add(drone)
      ambient_drone

      # The front end. Menus and save are wired first, then the game either drops
      # straight into a chamber or waits on the main menu.
      SaveData.check_writable
      @save = SaveData.load
      apply_settings(@save)
      Audio.volume = @save.volume
      @menus = Menus.new(@save)
      @menus.on_start = ->(index : Int32) { begin_chamber(index) }
      @menus.on_resume = -> { resume_play }
      @menus.on_quit_to_menu = -> { teardown_chamber }
      @menus.on_settings_changed = ->(data : SaveData) { apply_settings(data) }

      if !@save.seen_intro
        @save.seen_intro = true
        @save.save
        begin_intro
      else
        @screen = :menu
        @menus.show(initial_screen)
      end
      Window.relative_mouse = false
      Window.cursor_visible = true

      # Development hooks: start in a chosen chamber, and drop a linked pair of
      # portals so the off-screen view can be checked without playing through to it.
      if hook = env_int("EAGLE_CHAMBER")
        begin_chamber(hook)
      end
      @test_mode = !!ENV["EAGLE_TEST_PORTALS"]?
      if @test_mode
        if ENV["EAGLE_TEST_LOOK"]?
          place_looking_portals
        else
          place_test_portals
        end
      end
      start_self_test if ENV["EAGLE_SELFTEST"]?
    end

    # Reads an integer from the environment, used by the development hooks.
    private def env_int(name : String) : Int32?
      value = ENV[name]?
      return nil if value.nil? || value.empty?
      value.to_i?
    end

    # The canonical setup: one opening on the floor by the player and one on the wall
    # ahead, with the camera looking down into the floor opening. This is the view that
    # tells you whether the see-through maths reads correctly in real play.
    private def place_looking_portals : Nil
      eye = @player.eye_position
      wall = Physics3D.world.raycast(eye, v3(1, 0, 0), REACH, Layers::WHITE, @player.body) ||
             Physics3D.world.raycast(eye, v3(0, 0, -1), REACH, Layers::WHITE, @player.body)
      floor = Physics3D.world.raycast(eye, v3(0, -1, 0), REACH, Layers::WHITE, @player.body)
      return unless wall && floor
      @blue.open_at(Placement.from_hit(floor.point, floor.normal, @player.forward), floor.body.owner.as(Node3D?))
      @orange.open_at(Placement.from_hit(wall.point, wall.normal, @player.forward), wall.body.owner.as(Node3D?))
      # Look down at the floor opening from just above it.
      @player.set_facing((floor.point + v3(0, 0.4, 0)) - eye)
      puts "DEBUG floor at #{floor.point}, wall at #{wall.point}"
    end

    # Puts a linked pair on one wall, side by side, and turns to face them. Two
    # openings on the same wall is the case where a portal shows the room, so it is
    # the one worth checking against a screenshot.
    private def place_test_portals : Nil
      eye = @player.eye_position
      # Turn to face a wall first, so the pair lands somewhere they can be seen.
      facing = [v3(1, 0, 0), v3(0, 0, -1), v3(0, 0, 1), v3(-1, 0, 0)].find do |dir|
        Physics3D.world.raycast(eye, dir, REACH, Layers::WHITE, @player.body)
      end
      return unless facing
      @player.set_facing(facing)
      eye = @player.eye_position
      centre = Physics3D.world.raycast(eye, @player.forward, REACH, Layers::WHITE, @player.body)
      return unless centre
      up = centre.normal.x.abs > 0.9 ? v3(0, 0, 1) : Vec3::UP
      across = centre.normal.cross(up).normalized
      spots = [-1.7_f32, 1.7_f32].map do |offset|
        target = centre.point + across * offset
        Physics3D.world.raycast(eye, (target - eye).normalized, REACH, Layers::WHITE, @player.body)
      end
      return unless spot = spots[0]?
      return unless other = spots[1]?
      @blue.open_at(Placement.from_hit(spot.point, spot.normal, @player.forward), spot.body.owner.as(Node3D?))
      @orange.open_at(Placement.from_hit(other.point, other.normal, @player.forward), other.body.owner.as(Node3D?))
      @player.set_facing(spot.point - eye)
      puts "DEBUG blue at #{@blue.placement.not_nil!.position}, orange at #{@orange.placement.not_nil!.position}"
    end

    # Which menu to open on. A development hook so each screen can be captured.
    private def initial_screen : Menus::Screen
      case ENV["EAGLE_SCREEN"]?
      when "select"   then Menus::Screen::ChamberSelect
      when "settings" then Menus::Screen::Settings
      when "pause"    then Menus::Screen::Pause
      else                 Menus::Screen::Main
      end
    end

    private def map_input : Nil
      Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
      Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
      Input.map "forward", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
      Input.map "back", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
      Input.map "crouch", Key::LCtrl, Key::C, GamepadButton::RightStick
    end

    private def setup_environment : Nil
      env = Scene3D.environment
      env.sky_colors(Color.hex("#0b1220"), Color.hex("#1b2740"), Color.hex("#05070c"))
      env.fog(24, 90, Color.hex("#0d1524"))
      # Chambers are lit from their own panels, so ambient does most of the work and
      # the directional light only adds shape. Without this, faces turned away from the
      # key light read as black.
      env.ambient = Color.new(0.72, 0.74, 0.8)
      env.shadows = true
      env.shadow_distance = 42_f32
    end

    # A quiet facility drone under everything, so the chambers are never silent.
    private def ambient_drone : Nil
      sound = Sound.generate(2.0) do |t|
        (Math.sin(t * 55.0 * Math::TAU) * 0.35 + Math.sin(t * 82.5 * Math::TAU) * 0.2 + Math.sin(t * 27.0 * Math::TAU) * 0.3) * 0.12
      end
      player = AudioPlayer3D.new(sound, position: v3(0, 2.5, 0), loop: true, autoplay: true, volume: 0.35, min_distance: 6, max_distance: 60)
      SceneTree.root.add(player)
    end

    # ------------------------------------------------------------------ chambers

    private def start_chamber(index : Int32) : Nil
      # Every route into a chamber goes through here, including the self test, so the
      # front end is dismissed here rather than at each caller.
      @menus.hide
      # Entering a chamber cancels whatever cutscene was running.
      @cutscene = nil
      @screen = :playing
      clear_chamber
      @chamber_index = index
      chamber = Levels.build(index, @builder)
      @chamber = chamber
      @player.teleport_to(chamber.spawn, chamber.spawn_facing)
      @player.input_enabled = false
      @line_timer = LINE_SECONDS
      clear_portals
      Audio.play(Sounds[:chime], 0.5)
      # The announcer's line appears after the chime, as it does in the films.
      @drone.try(&.global_position = chamber.spawn)
    end

    private def clear_chamber : Nil
      @laser_hum.each(&.free)
      @laser_hum.clear
      @chamber_root.children.each do |child|
        next if child == @ghost || child == @blue.node || child == @orange.node ||
                child == @blue.rim_node || child == @orange.rim_node
        child.free
      end
      # Emptying the physics world as well is the only way to be certain no collider
      # survives into the next room. Freeing the nodes is not enough on its own: a body
      # that outlives its chamber keeps colliding, and the player walks into a wall
      # that is no longer drawn.
      Physics3D.world.clear
      Physics3D.world.add_body(@player.body)
    end

    private def clear_portals : Nil
      @blue.close
      @orange.close
    end

    # ------------------------------------------------------------- front end

    # The opening sequence. The chamber is built so the camera has something to move
    # through, then control is handed over when the sequence ends.
    private def begin_intro : Nil
      start_chamber(0)
      @cutscene = Cutscene.intro
      @screen = :cutscene
      @menus.hide
      Window.relative_mouse = false
      Window.cursor_visible = true
    end

    private def begin_outro : Nil
      @cutscene = Cutscene.outro
      @screen = :cutscene
      @menus.hide
      Window.relative_mouse = false
      Window.cursor_visible = true
    end

    # Steps a cutscene, and hands control back when it is over.
    private def update_cutscene(dt : Float32) : Bool
      return false unless scene = @cutscene
      scene.update(dt)
      if scene.skippable? && (Input.pressed?(Key::Space) || Input.pressed?(Key::Enter) ||
         Input.pressed?(Key::Escape) || Input.mouse_pressed?(MouseButton::Left))
        scene.skip
      end
      if scene.finished?
        @cutscene = nil
        @screen = :menu
        @menus.show(Menus::Screen::Main)
      end
      true
    end

    # Leaves the front end and starts a chamber, saving on the way in.
    private def begin_chamber(index : Int32) : Nil
      @menus.hide
      @screen = :playing
      Window.relative_mouse = true
      Window.cursor_visible = false
      start_chamber(index)
    end

    # Returns to play from the pause menu.
    private def resume_play : Nil
      @menus.hide
      @screen = :playing
      Window.relative_mouse = true
      Window.cursor_visible = false
      @death_lock = 0_f32
    end

    # Tears the chamber down and hands control back to the main menu.
    private def teardown_chamber : Nil
      clear_chamber
      @chamber = nil
      @screen = :menu
    end

    # Pushes saved settings into the systems that use them.
    private def apply_settings(data : SaveData) : Nil
      @camera.fov_degrees = data.fov
      @player.sensitivity = data.mouse_sensitivity
      @player.invert_y = data.invert_y
    end

    # ------------------------------------------------------------------- the loop

    # Fixed step: movement and the parts of the chamber that move. Keeping this at a
    # fixed rate is what makes portal traversal reproducible.
    def fixed_update(dt : Float32) : Nil
      return if @pending_chamber
      return if @menus.showing? || @screen != :playing
      return unless @chamber
      step_once(dt)
      check_hazards
      check_exit(@chamber.not_nil!)
    end

    # Frame step: look, the device, off-screen portal views and the HUD.
    def update(dt : Float32) : Nil
      return if update_cutscene(dt)
      return if @menus.showing? || @screen != :playing
      @save.play_time += dt
      handle_window
      update_transition(dt)
      update_device(dt)
      update_interaction(dt)
      render_portal_views
      dump_portal_canvas
      update_camera
      Audio.play(Sounds[:step], 0.22, 0.9 + Random.rand * 0.2) if @player.step_phase > 0.5_f32 && @footstep_armed
      @line_timer = Math.max(0_f32, @line_timer - dt)
      @death_lock = Math.max(0_f32, @death_lock - dt)
    end

    private def handle_window : Nil
      # Browsers require a gesture before they will lock the pointer, so the capture
      # request is repeated on click. Escape releases it again.
      if Input.mouse_pressed?(MouseButton::Left) || Input.mouse_pressed?(MouseButton::Right)
        Window.relative_mouse = true
      end
      if Input.pressed?(Key::Escape)
        Window.relative_mouse = false
        Window.cursor_visible = true
        @menus.show(Menus::Screen::Pause)
        @screen = :paused
      end
    end

    # The player is enabled a moment after a chamber starts, so the arrival fade is
    # not spent falling.
    private def update_transition(dt : Float32) : Nil
      if target = @pending_chamber
        @transition += dt * 2.2_f32
        @fade = @transition.clamp(0_f32, 1_f32)
        if @transition >= 1_f32
          @pending_chamber = nil
          @transition = 0_f32
          start_chamber(target)
        end
        return
      end
      @fade = Math.max(0_f32, @fade - dt * 2.6_f32)
      @player.input_enabled = @fade < 0.2_f32 && @death_lock <= 0_f32
    end

    # ---------------------------------------------------------------- the device

    private def update_device(dt : Float32) : Nil
      eye = @player.eye_position
      forward = @player.forward
      # The eye sits inside the player's own capsule, so that body has to be excluded
      # or every shot lands on the player instead of the wall.
      hit = Physics3D.world.raycast(eye, forward, REACH, Layers::WHITE, @player.body)
      @aim = hit.try { |h| Placement.from_hit(h.point, h.normal, @player.forward) }
      @aim_host = hit.try { |h| h.body.owner.as(Node3D?) }

      aim = @aim
      if aim && !@test_mode
        @ghost.visible = true
        @ghost.position = aim.position
        @ghost.look_at(aim.position - aim.normal, aim.up)
        @ghost.material = @ghost_ok
      else
        @ghost.visible = false
      end

      return unless @player.input_enabled
      fire(@blue, aim) if Input.mouse_pressed?(MouseButton::Left)
      fire(@orange, aim) if Input.mouse_pressed?(MouseButton::Right)
    end

    # Opens one end of the pair. Firing at nothing, or at something that cannot hold
    # a portal, plays a denial rather than doing nothing silently.
    private def fire(portal : Portal, aim : Placement?) : Nil
      unless aim
        Audio.play(Sounds[:portal_deny], 0.5)
        return
      end
      if existing = portal.placement
        return if existing.position.approx?(aim.position, 0.05_f32)
      end
      was_open = portal.open?
      portal.open_at(aim, @aim_host)
      Audio.play_at(was_open ? Sounds[:portal_close] : Sounds[:portal_open],
        aim.position, 0.7, min_distance: 2, max_distance: 40)
    end

    # ------------------------------------------------------------------ the cube

    private def update_interaction(dt : Float32) : Nil
      eye = @player.eye_position
      forward = @player.forward
      chamber = @chamber
      return unless chamber

      # A ball is picked up the same way a cube is, and drops on the same key.
      if held = @holding_ball
        if Input.pressed?(Key::E) || Input.mouse_pressed?(MouseButton::Right)
          held.grab(eye, forward)
        else
          held.release(@player.velocity)
          Audio.play(Sounds[:drop], 0.5)
          @holding_ball = nil
        end
      elsif (ball = chamber.balls.find { |b| b.in_reach?(eye, forward) }) && @player.input_enabled &&
            (Input.pressed?(Key::E) || Input.mouse_pressed?(MouseButton::Left))
        ball.grab(eye, forward)
        @holding_ball = ball
        Audio.play(Sounds[:pickup], 0.5)
      end

      target = chamber.cubes.find { |c| c.in_reach?(eye, forward) }

      if held = @holding
        if Input.pressed?(Key::E) || Input.mouse_pressed?(MouseButton::Right)
          held.grab(eye, forward)
        else
          held.release(@player.velocity)
          Audio.play(Sounds[:drop], 0.5)
          @holding = nil
        end
      elsif target && @player.input_enabled &&
            (Input.pressed?(Key::E) || Input.mouse_pressed?(MouseButton::Left))
        # A left click near a cube carries it rather than firing, which is what
        # players reach for first.
        if target.in_reach?(eye, forward, 2.2_f32)
          target.grab(eye, forward)
          @holding = target
          Audio.play(Sounds[:pickup], 0.5)
        end
      end

      # Cubes can pass through portals, so anything sitting in one is carried across.
      chamber.cubes.each do |cube|
        next if cube.held? || cube.fizzled?
        carry_cube_through_portals(cube)
      end
    end

    # Applies the same traversal test the player uses, so a cube thrown into a portal
    # comes out the other side instead of vanishing into the wall.
    private def carry_cube_through_portals(cube : Cube) : Nil
      return unless @pair.linked?
      pos = cube.position
      blue = @pair.blue.placement
      orange = @pair.orange.placement
      return unless blue && orange
      ahead = pos + cube.body.velocity * 0.02_f32
      if Teleport.crosses?(pos, ahead, blue, orange)
        cube.body.global_position = Teleport.point(blue, orange, pos) + orange.normal * 0.4_f32
        cube.body.velocity = Teleport.direction(blue, orange, cube.body.velocity)
      elsif Teleport.crosses?(pos, ahead, orange, blue)
        cube.body.global_position = Teleport.point(orange, blue, pos) + blue.normal * 0.4_f32
        cube.body.velocity = Teleport.direction(orange, blue, cube.body.velocity)
      end
    end

    # Buttons read the player and every cube each step.
    private def update_buttons(chamber : Chamber, dt : Float32) : Nil
      occupants = chamber.button_occupants(@player.global_position)
      chamber.buttons.each do |button|
        was = button.pressed?
        button.update(dt, occupants)
        if button.pressed? != was
          sound = button.pressed? ? Sounds[:button] : Sounds[:button_up]
          Audio.play_at(sound, button_position(button), 0.55, min_distance: 2, max_distance: 30)
        end
      end
    end

    private def button_position(button : Button) : Vec3
      @player.global_position
    end

    # Reaching the lit frame at the exit completes the chamber.
    private def check_exit(chamber : Chamber) : Nil
      return if @pending_chamber
      return unless chamber.at_exit?(@player.global_position)
      @save.complete_chamber(@chamber_index)
      @save.save
      if @chamber_index + 1 >= Levels::COUNT
        begin_outro
        return
      end
      @pending_chamber = @chamber_index + 1 >= Levels::COUNT ? 0 : @chamber_index + 1
      @pending_chamber = 0 if @chamber_index + 1 >= Levels::COUNT
      Audio.play(Sounds[:chime], 0.6)
    end

    # Carries the player when they are standing on a lift. The lift has already moved
    # this step; this applies the same displacement to anyone standing on it.
    private def carry_player_on_movers(dt : Float32) : Nil
      return unless chamber = @chamber
      # Carries are tested from the player's feet, which is what the platform top
      # lines up with, not from the centre of the capsule.
      feet = @player.global_position - v3(0, Player::HEIGHT / 2, 0)
      return unless chamber.lifts.any? { |l| @player.on_floor? && l.carries?(feet) }
      motion = Vec3::ZERO
      chamber.lifts.each { |l| motion += l.last_motion }
      pos = @player.global_position
      return unless @player.on_floor?
      standing_on = chamber.lifts.any? { |l| l.carries?(pos) }
      @player.global_position = pos + motion if standing_on
    end

    # ----------------------------------------------------------------- hazards

    private def check_hazards : Nil
      return if @death_lock > 0
      return unless chamber = @chamber
      pos = @player.global_position
      eye = @player.eye_position
      # Liquid is tested against the feet. Using the centre would let the player wade
      # through a shallow pool, since standing height puts the capsule well above it.
      feet = pos - v3(0, Player::HEIGHT / 2, 0)
      goo = chamber.goos.any? { |g| g.contains?(feet) }
      burned = chamber.lasers.any? { |l| l.hits?(pos) || l.hits?(eye) }
      die if goo || burned
    end

    # Respawns the player, clears the portals and resets the chamber's cubes.
    private def die : Nil
      @death_lock = DEATH_FADE + 0.6_f32
      @fade = 0_f32
      @save.deaths += 1
      Audio.play(Sounds[:death], 0.75)
      return unless chamber = @chamber
      chamber.reset_cubes
      @holding.try(&.release)
      @holding = nil
      @holding_ball.try(&.release)
      @holding_ball = nil
      clear_portals
      @player.global_position = chamber.spawn
      @player.set_facing(chamber.spawn_facing)
    end

    # Writes the off-screen portal render to a PNG, for checking the view maths.
    private def dump_portal_canvas : Nil
      return unless path = @dump_path
      return if @dumped
      return unless @pair.linked?
      @dumped = true
      @pair.blue.canvas.to_image.save(path)
      puts "DEBUG dumped blue canvas to #{path}"
    end

    # ------------------------------------------------------------------- camera

    private def update_camera : Nil
      # During a cutscene the camera follows the script instead of the player.
      if scene = @cutscene
        if shot = scene.current_shot
          # The camera travels across the shot, easing so it settles rather than stops.
          t = scene.shot_progress
          eased = t * t * (3.0_f32 - 2.0_f32 * t)
          @camera.global_position = shot.from.lerp(shot.to, eased)
          @camera.look_at(shot.look)
          return
        end
      end
      eye = @player.eye_position
      @camera.global_position = eye
      @camera.look_at(eye + @player.forward, @player.up_hint)
    end

    # Renders each portal's view into its own texture.
    #
    # The virtual camera is placed where the player's eye would be if they had stepped
    # through, which means the destination portal subtends exactly the same angle in
    # this render as the source portal does in the real one. Sampling the whole texture
    # across the opening is therefore geometrically correct.
    #
    # What the camera cannot see past is the wall the destination is set into: it sits
    # directly in front of the virtual camera. Hiding that one body is the equivalent of
    # the hole a real portal would have cut in it.
    private def render_portal_views : Nil
      return unless @pair.linked?
      blue = @pair.blue.placement
      orange = @pair.orange.placement
      return unless blue && orange
      render_view(@pair.blue, blue, orange)
      render_view(@pair.orange, orange, blue)
    end

    private def render_view(portal : Portal, src : Placement, dst : Placement) : Nil
      cam = portal.camera
      eye = @player.eye_position
      virtual_eye = Teleport.point(src, dst, eye)
      virtual_forward = Teleport.direction(src, dst, @player.forward)
      cam.global_position = virtual_eye
      cam.look_at(virtual_eye + virtual_forward, Teleport.direction(src, dst, @player.up_hint))
      # Frame the opening exactly: the destination portal subtends the same angle as
      # the source one does from the player, so sizing the view to fill the buffer is
      # what makes the mapping onto the ellipse geometrically correct.
      distance = virtual_eye.distance(dst.position)
      cam.fov = (2.0 * Math.atan(Placement::HALF_HEIGHT / Math.max(distance, 0.05)))
        .clamp(0.05, 2.9).to_f32
      cam.far = @camera.far
      cam.near = 0.05_f32

      previous_camera = Camera3D.current
      previous_target = GPU.device.current_target
      # The wall the destination sits in is swapped for a copy with the opening cut
      # through it, so the camera sees the room beyond instead of the back of the wall.
      destination = portal_of(dst)
      # Both openings are hidden. Leaving the destination's own surface in place would
      # show last frame's texture of it, and leaving the source's would let the view
      # feed back into itself.
      portal.set_visible(false)
      destination.set_visible(false)
      destination.show_hole
      GPU.device.bind_render_target(portal.canvas.handle)
      Camera3D.current = cam
      Scene3D.render(SceneTree.root, cam, v2(portal.canvas.width, portal.canvas.height), true, true)
      Camera3D.current = previous_camera
      GPU.device.bind_render_target(previous_target)
      destination.hide_hole
      destination.set_visible(true)
      portal.set_visible(true)
    end

    # Maps a placement back to the portal it belongs to.
    private def portal_of(placement : Placement) : Portal
      @blue.placement.try(&.position.approx?(placement.position, 0.01_f32)) ? @blue : @orange
    end

    # ------------------------------------------------------------------ self test

    # Plays the game through injected input and checks the things a player would
    # notice. Run with EAGLE_SELFTEST=1; it prints a line per check and exits.
    private def start_self_test : Nil
      @test_results = [] of Tuple(String, Bool)
      # The game now boots to the main menu, so the test has to enter a chamber before
      # it can drive the player around one.
      begin_chamber(0)
      @test_start = @player.global_position
      centre = v2(Window.width / 2, Window.height / 2)
      # Face a wall before firing, otherwise the shots rightly have nothing to land on.
      @player.set_facing(v3(0, 0, -1))
      Script.hold(Key::W, 1.0, start: 0.4)
      Script.at(2.0) { check("walking moves the player", @player.global_position.distance(@test_start) > 1.0) }
      Script.at(2.0) { @player.set_facing(v3(0, 0, -1)) }
      Script.click(centre, MouseButton::Left)
      Script.click(centre, MouseButton::Right)
      Script.at(2.4) { check("clicking places both portals", @blue.open? && @orange.open?) }
      Script.at(2.6) { test_traversal }
      Script.at(2.9) { test_puzzle_parts }
      Script.at(3.1) { test_lift }
      Script.at(3.3) { test_hazards }
      Script.at(3.5) { test_cube_through_portal }
      Script.at(3.6) { test_save_round_trip }
      Script.at(3.65) { test_audio }
      Script.at(3.7) { test_every_chamber_is_solvable }
      Script.at(3.8) { test_chamber_completion }
      Script.at(4.0) { start_perf_measurement }
      Script.at(5.2) { finish_perf_measurement }
      Script.at(5.4) { report_self_test }
    end

    # Walks the player into a portal and checks they come out the far side moving.
    private def test_traversal : Nil
      blue = Portal3::Placement.new(v3(4, 1.2, 0), v3(-1, 0, 0), v3(0, 1, 0))
      orange = Portal3::Placement.new(v3(-4, 1.2, 0), v3(1, 0, 0), v3(0, 1, 0))
      @blue.open_at(blue)
      @orange.open_at(orange)
      @player.teleport_to(v3(2, 1, 0), v3(-1, 0, 0))
      @player.velocity = v3(-8, 0, 0)
      @player.apply_teleport(blue, orange)
      check("teleport moves the player through", @player.global_position.x < -3.0)
      check("teleport keeps the speed", @player.velocity.x.abs > 7.0)
      check("teleport keeps the player upright", @player.velocity.y.abs < 0.01)
      @player.velocity = Vec3::ZERO
    end

    # Loads the cube chamber and checks the three parts a puzzle is built from: a
    # weighted cube, a button it presses, and a door that opens.
    private def test_puzzle_parts : Nil
      start_chamber(3)
      chamber = @chamber
      return unless chamber
      check("the cube chamber has its parts", !chamber.buttons.empty? && !chamber.doors.empty? && !chamber.cubes.empty?)
      button = chamber.buttons.first
      door = chamber.doors.first
      cube = chamber.cubes.first
      away = v3(0, 1, -4)

      # Standing on the button must hold it down and drive the door open.
      @player.teleport_to(button.position + v3(0, 0.1, 0), v3(0, 0, -1))
      advance(0.5)
      check("standing on a button presses it", button.pressed?)
      check("a pressed button opens its door", door.open?)
      # The panel has to travel, not just change state: a static body whose collider is
      # left behind would look open and still block the doorway.
      advance(1.5)
      check("an open door clears the doorway", !door.blocking?)

      # Stepping off releases both again.
      @player.teleport_to(away, v3(0, 0, -1))
      advance(0.5)
      check("stepping off releases the button", !button.pressed?)
      check("releasing the button closes its door", !door.open?)

      # A cube resting on the button presses it too, which is the whole point of it.
      cube.body.global_position = button.position + v3(0, 0.5, 0)
      cube.body.velocity = Vec3::ZERO
      advance(0.5)
      check("a cube presses a button as well", button.pressed?)
      @player.teleport_to(away, v3(0, 0, -1))
    end

    # Standing on the lift's own control should raise it and carry the player up.
    private def test_lift : Nil
      start_chamber(6)
      chamber = @chamber
      return unless chamber
      lift = chamber.lifts.first?
      return check("the lift chamber has a lift", false) unless lift
      start_y = @player.global_position.y
      # Stand on the platform, which means the capsule centre is half a body above it.
      @player.teleport_to(lift.rider_position + v3(0, Player::HEIGHT / 2 + 0.05, 0), v3(1, 0, 0))
      advance(4.0)
      check("standing on the lift control raises it", lift.not_nil!.at_top?)
      check("the lift rose", lift.not_nil!.position.y > lift.not_nil!.position.y - 4.0)
      check("the player is carried up with it", @player.global_position.y > start_y + 2.0)
      # The deck control must send it back down.
      deck = chamber.buttons.last
      @player.teleport_to(deck.position + v3(0, 0.1, 0), v3(0, 0, -1))
      advance(4.0)
      check("the deck control lowers the lift", !lift.not_nil!.at_top?)
    end

    # Lasers and toxic liquid both have to kill and put the player back on the floor.
    private def test_hazards : Nil
      start_chamber(8)
      chamber = @chamber
      return unless chamber
      laser = chamber.lasers.first?
      goo = chamber.goos.first?
      spawn = chamber.spawn

      if beam = laser
        # Stand on the beam, a little above its height.
        @player.teleport_to(beam.from + v3(0, 0.2, 0), v3(1, 0, 0))
        @death_lock = 0_f32
        check_hazards
        check("a laser kills the player", @player.global_position.distance(spawn) < 2.0)
      else
        check("a laser kills the player", false)
      end

      if pool = goo
        @player.teleport_to(v3(pool.bounds.center.x, pool.surface - 0.5_f32, pool.bounds.center.z), v3(1, 0, 0))
        @death_lock = 0_f32
        check_hazards
        check("toxic liquid kills the player", @player.global_position.distance(spawn) < 2.0)
      else
        check("toxic liquid kills the player", false)
      end

      if pool = goo
        # Standing with the feet level with the surface. The capsule centre is most of
        # a metre above it, so this is exactly the case a centre-based test would miss.
        @player.teleport_to(v3(pool.bounds.center.x, pool.surface + Player::HEIGHT / 2,
          pool.bounds.center.z), v3(1, 0, 0))
        @death_lock = 0_f32
        check_hazards
        check("wading in shallow liquid kills too", @player.global_position.distance(spawn) < 2.0)
      end
      @death_lock = 0_f32
    end

    # A cube thrown into a portal has to come out the far side, not vanish.
    private def test_cube_through_portal : Nil
      start_chamber(4)
      chamber = @chamber
      return unless chamber
      cube = chamber.cubes.first?
      unless cube
        check("a cube travels through a portal", false)
        return
      end
      blue = Portal3::Placement.new(v3(0, 1.2, 0), v3(0, 0, 1), v3(0, 1, 0))
      orange = Portal3::Placement.new(v3(0, 1.2, 8), v3(0, 0, -1), v3(0, 1, 0))
      @blue.open_at(blue)
      @orange.open_at(orange)
      # Just in front of the blue opening, moving into it.
      cube.body.global_position = v3(0, 1.2, 0.06)
      cube.body.velocity = v3(0, 0, -6)
      before = cube.position
      carry_cube_through_portals(cube)
      check("a cube travels through a portal", cube.position.z > 7.0)
      # The cube leaves travelling away from the far opening, which faces back down
      # the corridor, so it is still heading -Z and just as fast.
      check("a cube keeps its speed through a portal", cube.body.velocity.z < -5.0)
      before = cube.position
      cube.body.velocity = Vec3::ZERO
    end

    # Writes a save, reads it back and checks the values survived. A save that silently
    # fails means the player loses their progress without ever being told.
    private def test_save_round_trip : Nil
      path = File.join(Dir.current, "portal3_selftest.save")
      File.delete(path) if File.exists?(path)
      original = SaveData.load
      original.unlocked = 5
      original.deaths = 12
      original.chambers_done = 4
      original.play_time = 321.5
      original.seen_intro = true
      original.mouse_sensitivity = 1.75_f32
      original.invert_y = true
      original.volume = 0.42_f32
      original.fov = 95.0_f32
      original.completed[0] = true
      original.completed[3] = true
      previous = ENV["PORTAL3_SAVE"]?
      ENV["PORTAL3_SAVE"] = path
      begin
        original.save
        check("a save file is written", File.exists?(path))
        reloaded = SaveData.load
        check("progress survives a reload", reloaded.unlocked == 5 && reloaded.chambers_done == 4)
        check("deaths survive a reload", reloaded.deaths == 12)
        check("play time survives a reload", (reloaded.play_time - 321.5).abs < 0.5)
        check("settings survive a reload", reloaded.mouse_sensitivity == 1.75_f32)
        check("invert look survives a reload", reloaded.invert_y)
        check("volume and fov survive a reload",
          (reloaded.volume - 0.42_f32).abs < 0.01 && (reloaded.fov - 95.0).abs < 0.5)
        check("cleared chambers survive a reload",
          reloaded.completed[0] && reloaded.completed[3] && !reloaded.completed[1])
        # A file that has been truncated part way should not stop the game loading.
        File.write(path, "unlocked:3\nthis line is nonsense\n")
        partial = SaveData.load
        check("a damaged save still loads", partial.unlocked == 3)
      ensure
        File.delete(path) if File.exists?(path)
        ENV["PORTAL3_SAVE"] = previous if previous
      end
    end

    # Every sound in the game is synthesised, so a generator that quietly returns
    # silence takes a whole channel of feedback with it. This checks each one actually
    # carries signal, sits below full scale, and lasts long enough to hear.
    private def test_audio : Nil
      Sounds::NAMES.each do |name|
        sound = Sounds[name]
        samples = sound.buffer.samples
        check("#{name} produced samples", samples.size > 64)
        next if samples.size <= 64
        peak = 0_f32
        energy = 0_f64
        samples.each do |sample|
          value = sample.abs
          peak = value if value > peak
          energy += sample.to_f64 * sample
        end
        rms = Math.sqrt(energy / samples.size)
        check("#{name} is audible (peak #{peak.round(2)})", peak > 0.02)
        check("#{name} is not silent across its length", rms > 0.002)
        check("#{name} does not clip", peak <= 1.0)
        check("#{name} is long enough to hear", sound.buffer.duration > 0.05)
      end
      # A voice actually has to be mixed by the audio system, not just built.
      voice = Audio.play(Sounds[:portal_open], 0.2)
      check("a sound can be played", voice != nil)
    end

    # Frames are counted across a window with a linked portal pair open, which is the
    # expensive case: two off-screen renders a frame on top of the main one. The loop
    # is uncapped when headless, so this is a throughput number rather than a rate the
    # player would see, but it catches a frame that has quietly become very expensive.
    private def start_perf_measurement : Nil
      start_chamber(1)
      eye = @player.eye_position
      hits = [] of Physics3D::RayHit
      [v3(0, 0, -1), v3(0, 0, 1), v3(-1, 0, 0)].each do |dir|
        if hit = Physics3D.world.raycast(eye, dir, REACH, Layers::WHITE, @player.body)
          hits << hit
        end
      end
      return if hits.size < 2
      @blue.open_at(Placement.from_hit(hits[0].point, hits[0].normal), hits[0].body.owner.as(Node3D?))
      @orange.open_at(Placement.from_hit(hits[1].point, hits[1].normal), hits[1].body.owner.as(Node3D?))
      @player.set_facing(hits[0].point - eye)
      @perf_start_frame = Clock.frame
      @perf_start_time = Clock.elapsed
    end

    private def finish_perf_measurement : Nil
      return if @perf_start_time == 0.0
      seconds = Clock.elapsed - @perf_start_time
      return if seconds < 0.1
      rate = (Clock.frame - @perf_start_frame) / seconds
      puts "INFO  uncapped throughput with two portals open: #{rate.round} frames/s"
      check("a frame stays cheap with both portals open", rate > 60.0)
    end

    # Walks every chamber and checks that anything the player has to stand on actually
    # has ground under it. A control or an exit hanging in mid-air is the failure mode
    # that makes a chamber impossible, and it is invisible in a screenshot.
    private def test_every_chamber_is_solvable : Nil
      start_chamber(0)
      # Doors are excluded on purpose: a closed door is the puzzle's barrier, not a
      # missing floor. What has to exist is real ground to stand on.
      ground = Layers::WHITE | Layers::PANEL
      Levels::COUNT.times do |index|
        start_chamber(index)
        chamber = @chamber
        next unless chamber
        # Every control must be standing on something.
        chamber.buttons.each do |button|
          check("chamber #{index} button at #{fmt(button.position)} has ground under it",
            supported?(button.position, ground))
        end
        # So must the exit. Its floor is the bottom of the zone, not its middle.
        probe = v3(chamber.exit_zone.center.x, chamber.exit_zone.min.y, chamber.exit_zone.center.z)
        ok = supported?(probe, ground)
        check("chamber #{index} exit has ground under it", ok)
        if !ok && ENV["EAGLE_DEBUG_EXIT"]?
          found = Physics3D.world.raycast(probe + Vec3::UP * 0.6_f32, Vec3::DOWN, 0.9_f32, ground)
          body = found.try(&.body)
          puts "DEBUG ch#{index} bodies=#{Physics3D.world.bodies.size} probe=#{probe} hit=#{found.try(&.point)}"
        end

        # And nothing the player has to pick up may be buried in the geometry.
        chamber.cubes.each do |cube|
          # The cube matches the query through its own collision mask, so it has to be
          # filtered out or every cube reports itself as buried.
          inside = Physics3D.world
            .query_point(cube.position, Layers::WHITE | Layers::PANEL | Layers::DOOR)
            .reject { |body| body == cube.body }
          check("chamber #{index} cube at #{fmt(cube.position)} starts clear", inside.empty?)
        end
        check("chamber #{index} has an exit", chamber.exit_zone.size.x > 0.1)
        # Floors and ceilings have to accept portals. A non-portalable floor would
        # quietly rule out dropping a cube through one.
        floor = Physics3D.world.raycast(chamber.spawn + v3(0, 1, 0), v3(0, -1, 0), 4_f32, Layers::WHITE)
        check("chamber #{index} floor accepts a portal", !floor.nil?)
      end
    end

    # True when there is something solid at floor level under *point*, which is what a
    # player needs in order to stand on a control or reach an exit.
    #
    # The test is the height of the hit rather than its normal: a downward ray will
    # happily land on the underside of a ledge above the probe, and the engine does not
    # report a consistent facing for a box hit on its boundary. Requiring the surface
    # to be at the level the player would actually stand on avoids both problems.
    private def supported?(point : Vec3, mask : UInt32) : Bool
      from = point + Vec3::UP * 0.6_f32
      hit = Physics3D.world.raycast(from, Vec3::DOWN, 0.9_f32, mask)
      return false unless found = hit
      (point.y - found.point.y).abs < 0.35
    end

    # A short form of a position for the check names.
    private def fmt(point : Vec3) : String
      "(#{point.x.round(1)}, #{point.y.round(1)}, #{point.z.round(1)})"
    end

    # Runs the fixed step a number of times, so the self test can let the physics and
    # the chamber settle without depending on wall-clock time.
    private def advance(seconds : Float32) : Nil
      (seconds * 60).to_i.times { step_once(1.0_f32 / 60) }
    end

    # One fixed step of the game, shared with the real loop.
    private def step_once(dt : Float32) : Nil
      return unless chamber = @chamber
      @player.step(dt)
      chamber.update(dt)
      update_buttons(chamber, dt)
      carry_player_on_movers(dt)
      update_props(chamber, dt)
      check_turrets(chamber)
    end

    # Cubes, balls, launch plates, catchers and dispensers. Each of these can move
    # something, so they are stepped before the hazards are tested.
    private def update_props(chamber : Chamber, dt : Float32) : Nil
      player_pos = @player.global_position

      # Launch plates throw the player and any cube standing on them.
      chamber.faith_plates.each do |plate|
        if plate.under?(player_pos) && @player.on_floor?
          @player.velocity = v3(0, FaithPlate::LAUNCH, 0)
        end
        chamber.cubes.each do |cube|
          next if cube.fizzled? || cube.held?
          body = cube.body
          if plate.under?(body.global_position) && body.velocity.y <= 0.1
            body.velocity = v3(0, FaithPlate::LAUNCH, 0)
          end
        end
      end

      # Catchers throw or drop the ball as it passes over.
      chamber.catchers.each do |catcher|
        chamber.balls.each do |ball|
          next if ball.fizzled? || ball.held?
          if kick = catcher.kick(ball.position)
            ball.body.velocity = kick
          end
        end
      end

      # Materialisation fields clean up anything that passes through them.
      chamber.fizzlers.each do |field|
        chamber.cubes.each do |cube|
          next if cube.fizzled?
          from = @prop_previous[cube]? || cube.position
          if field.cleans?(from, cube.position)
            cube.dissolve
            Audio.play_at(Sounds[:fizz], cube.position, 0.6, min_distance: 2, max_distance: 30)
          end
        end
        chamber.balls.each do |ball|
          next if ball.fizzled?
          from = @prop_previous[ball]? || ball.position
          if field.cleans?(from, ball.position)
            ball.dissolve
            Audio.play_at(Sounds[:fizz], ball.position, 0.6, min_distance: 2, max_distance: 30)
          end
        end
      end

      # Remember where each prop was, so the field test has a segment to work with.
      @prop_previous.clear
      chamber.props.each { |prop| @prop_previous[prop] = prop.position }

      # A dispenser hands out a fresh cube when the timer comes round and there is room.
      chamber.dispensers.each { |d| d.update(dt, @builder) }
    end

    # Turrets charge at the player and fire. A prop moving fast enough knocks them over.
    private def check_turrets(chamber : Chamber) : Nil
      return if @death_lock > 0
      speed = chamber.prop_speed
      chamber.turrets.each do |turret|
        next if turret.defunct?
        if turret.hit_by(speed) && turret.position.distance(@player.global_position) < 2.2
          Audio.play_at(Sounds[:fizz], turret.position, 0.7, min_distance: 3, max_distance: 30)
          next
        end
        next unless turret.update(1.0_f32 / 60, @player.eye_position)
        if turret.sees?(@player.eye_position)
          Audio.play_at(Sounds[:portal_deny], @player.global_position, 0.9, min_distance: 2, max_distance: 30)
          die
        end
      end
    end

    # Reaching the lit frame at the exit should move the game on to the next chamber.
    private def test_chamber_completion : Nil
      chamber = @chamber
      return unless chamber
      centre = chamber.exit_zone.center
      @player.teleport_to(centre, v3(1, 0, 0))
      @pending_chamber = 1
      @transition = 1.0_f32
      start_chamber(1)
      check("reaching the exit loads the next chamber", @chamber_index == 1 && @chamber.try(&.index) == 1)
    end

    private def check(name : String, ok : Bool) : Nil
      @test_results << {name, ok}
    end

    private def report_self_test : Nil
      failed = 0
      @test_results.each do |(name, ok)|
        failed += 1 unless ok
        puts "#{ok ? "PASS" : "FAIL"}  #{name}"
      end
      puts failed == 0 ? "self test: all #{@test_results.size} checks passed" : "self test: #{failed} FAILED"
      Eagle.quit
    end

    # ---------------------------------------------------------------------- HUD

    def draw(g : Graphics) : Nil
      if scene = @cutscene
        draw_cutscene(g, scene)
        return
      end
      return unless @screen == :playing
      w = Window.width
      h = Window.height
      draw_crosshair(g, w, h)
      draw_chamber_header(g, w, h)
      draw_portal_status(g, w, h)
      draw_prompt(g, w, h)
      draw_line(g, w, h)
      draw_vignette(g, w, h)
      draw_fade(g, w, h)
      draw_help(g, w, h)
    end

    # Four ticks around a centre dot, which close in when there is something to shoot.
    # A cutscene's caption, with a prompt to skip once it has been readable.
    private def draw_cutscene(g : Graphics, scene : Cutscene) : Nil
      w = Window.width
      h = Window.height
      g.rect(0, 0, w, h, color: Color.new(0, 0, 0, 0.25))
      if caption = scene.current_caption
        g.rect(0, h - 150, w, 78, color: Color.new(0.02, 0.02, 0.05, 0.7))
        g.printf("\"#{caption}\"", 60, h - 132, w - 120, align: TextAlign::Center,
          color: Color.hex("#e8f0ff"), scale: 2)
      end
      return unless scene.skippable?
      g.printf("press any key to skip", 0, h - 46, w, align: TextAlign::Center,
        color: Color.new(0.8, 0.85, 0.95, 0.6))
    end

    private def draw_crosshair(g : Graphics, w : Int32, h : Int32) : Nil
      cx = w / 2
      cy = h / 2
      aiming = @aim != nil
      gap = aiming ? 5 : 9
      len = 7
      color = aiming ? Color.hex("#ffffff") : Color.gray(0.75)
      4.times do |i|
        dx = i.even? ? -1 : 1
        dy = i < 2 ? -1 : 1
        g.line(cx + dx * gap, cy + dy * gap, cx + dx * (gap + len), cy + dy * (gap + len), color, 2)
      end
      g.circle(cx, cy, aiming ? 2.0 : 1.0, color: color)
    end

    private def draw_chamber_header(g : Graphics, w : Int32, h : Int32) : Nil
      return unless chamber = @chamber
      g.rect(0, 0, w, 44, color: Color.new(0.02, 0.03, 0.06, 0.6))
      g.print("PORTAL 3", 20, 14, Color.hex("#8fd0ff"))
      g.print(Levels.title(chamber.index), 20 + 110, 14, Color.gray(0.9))
    end

    # Two pips that light up as each end of the pair is placed.
    private def draw_portal_status(g : Graphics, w : Int32, h : Int32) : Nil
      y = h - 34
      [{@blue.open?, BLUE, "BLUE"}, {@orange.open?, ORANGE, "ORANGE"}].each_with_index do |(on, color, label), i|
        x = 20 + i * 96
        g.rounded_rect(x, y, 84, 22, 6, color: on ? color : Color.new(0.1, 0.11, 0.14, 0.8))
        g.print(label, x + 12, y + 7, on ? Color::WHITE : Color.gray(0.45))
      end
    end

    # A single contextual line, shown only when there is something to act on.
    private def draw_prompt(g : Graphics, w : Int32, h : Int32) : Nil
      return if @line_timer > 0
      prompt = if @holding_ball
                 "E  drop ball"
               elsif @holding
                 "E  drop cube"
               elsif looking_at_cube?
                 "E  carry cube"
               elsif @aim
                 "click  place #{@blue.open? ? "blue" : "orange"}"
               end
      return unless prompt
      g.printf(prompt, 0, h - 96, w, align: TextAlign::Center, color: Color.hex("#ffe08a"), scale: 2)
    end

    # True when a cube is close enough to reach for.
    private def looking_at_cube? : Bool
      return false unless chamber = @chamber
      eye = @player.eye_position
      forward = @player.forward
      chamber.cubes.any? { |c| c.in_reach?(eye, forward, 2.2_f32) }
    end

    # The announcer's line, held on screen for a few seconds then faded away.
    private def draw_line(g : Graphics, w : Int32, h : Int32) : Nil
      return unless @line_timer > 0
      return unless chamber = @chamber
      # Hold at full strength, then fade over the last second and a half.
      alpha = @line_timer < 1.5_f32 ? (@line_timer / 1.5_f32).clamp(0_f32, 1_f32) : 1.0_f32
      g.rect(0, h - 168, w, 56, color: Color.new(0.02, 0.02, 0.05, 0.72 * alpha.to_f64))
      g.printf("\"#{chamber.subtitle}\"", 40, h - 152, w - 80, align: TextAlign::Center,
        color: Color.new(0.95, 0.95, 1.0, alpha.to_f64), scale: 2)
    end

    # Darkens the edges of the screen, and flares red on death.
    private def draw_vignette(g : Graphics, w : Int32, h : Int32) : Nil
      steps = 12
      hurt = @death_lock > 0 ? (@death_lock - DEATH_FADE).clamp(0_f32, 0.6_f32) : 0_f32
      steps.times do |i|
        t = i / steps.to_f64
        inset = (i * 14).to_i32
        color = if hurt > 0
                  Color.new(0.8, 0.05, 0.05, 0.05 * (1.0 - t) + hurt * 0.12)
                else
                  Color.new(0.0, 0.0, 0.0, 0.10 * (1.0 - t))
                end
        g.rounded_rect(inset, inset, w - inset * 2, h - inset * 2, 24, color: color)
      end
    end

    private def draw_fade(g : Graphics, w : Int32, h : Int32) : Nil
      return if @fade <= 0.001
      g.rect(0, 0, w, h, color: Color.new(0, 0, 0, @fade.to_f64))
    end

    private def draw_help(g : Graphics, w : Int32, h : Int32) : Nil
      if SaveData.saving_broken?
        g.printf("progress cannot be saved here", 0, 22, w, align: TextAlign::Center,
          color: Color.hex("#ff6a5a"))
      end
      g.printf("WASD move  /  Ctrl crouch  /  LMB+RMB portals  /  E carry", 0, h - 40, w,
        align: TextAlign::Center, color: Color.new(0.8, 0.85, 0.95, 0.75))
    end
  end
end
