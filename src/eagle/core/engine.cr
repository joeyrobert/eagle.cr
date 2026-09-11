module Eagle
  # Engine configuration. Every field has a sensible default.
  class Config
    property title : String = "Eagle"
    property width : Int32 = 1280
    property height : Int32 = 720
    property resizable : Bool = true
    property fullscreen : Bool = false
    property vsync : Bool = true
    property msaa : Int32 = 0
    property highdpi : Bool = true
    # Fixed timestep rate for physics_process (Hz).
    property fixed_fps : Int32 = 60
    # Cap for the variable-rate loop when vsync is off (0 = uncapped).
    property max_fps : Int32 = 0
    property clear_color : Color = Color.rgb(24, 26, 32)
    # Root for `res://` paths. nil = auto-detect (see Assets).
    property assets_dir : String? = nil
    property audio : Bool = true
    property hidden : Bool = false

    def initialize(**opts)
      {% for ivar in @type.instance_vars %}
        if v = opts[{{ivar.symbolize}}]?
          @{{ivar}} = v.as({{ivar.type}})
        end
      {% end %}
    end
  end

  # Subclass (or use the block helpers) to make a game. All hooks are optional.
  #
  #   class Game < Eagle::App
  #     def load; end
  #     def update(dt : Float32); end
  #     def draw(g : Graphics); end
  #   end
  #   Eagle.run(Game.new, title: "Hi")
  class App
    @load_blocks = [] of ->
    @update_blocks = [] of Float32 ->
    @fixed_blocks = [] of Float32 ->
    @draw_blocks = [] of Graphics ->
    @input_blocks = [] of Event ->

    # Override to tweak configuration before the window opens.
    def configure(config : Config) : Nil; end
    # Called once after the window and GPU are ready.
    def load : Nil; end
    # Variable timestep, once per frame.
    def update(dt : Float32) : Nil; end
    # Fixed timestep (Config#fixed_fps), zero or more times per frame.
    def fixed_update(dt : Float32) : Nil; end
    # 2D drawing. The scene tree is drawn before this.
    def draw(g : Graphics) : Nil; end
    # Raw input events, before the scene tree sees them.
    def input(event : Event) : Nil; end
    def resize(width : Int32, height : Int32) : Nil; end
    # Return false to veto quitting.
    def quit? : Bool; true; end
    def unload : Nil; end

    def on_load(&block : ->) : self; @load_blocks << block; self; end
    def on_update(&block : Float32 ->) : self; @update_blocks << block; self; end
    def on_fixed_update(&block : Float32 ->) : self; @fixed_blocks << block; self; end
    def on_draw(&block : Graphics ->) : self; @draw_blocks << block; self; end
    def on_input(&block : Event ->) : self; @input_blocks << block; self; end

    # :nodoc:
    def _load; load; @load_blocks.each(&.call); end
    # :nodoc:
    def _update(dt); update(dt); @update_blocks.each(&.call(dt)); end
    # :nodoc:
    def _fixed_update(dt); fixed_update(dt); @fixed_blocks.each(&.call(dt)); end
    # :nodoc:
    def _draw(g); draw(g); @draw_blocks.each(&.call(g)); end
    # :nodoc:
    def _input(e); input(e); @input_blocks.each(&.call(e)); end
  end

  @@platform : Platform::Base? = nil
  @@app : App? = nil
  @@config = Config.new
  @@running = false
  @@quit_requested = false
  @@graphics : Graphics? = nil
  @@last_time = 0.0
  @@frame_limit : Int64? = nil
  @@screenshot_path : String? = nil
  @@initialized = false
  @@frame_hooks = [] of ->

  def self.platform : Platform::Base
    @@platform || raise Error.new("Eagle is not initialised. Call Eagle.run or Eagle.init.")
  end

  def self.platform? : Platform::Base?; @@platform; end
  def self.config : Config; @@config; end
  def self.app : App; @@app || raise Error.new("No app running"); end
  def self.running? : Bool; @@running; end
  def self.initialized? : Bool; @@initialized; end
  def self.graphics : Graphics; @@graphics || raise Error.new("Graphics not ready"); end
  # 2D immediate-mode drawing context (same object as passed to `draw`).
  def self.g : Graphics; graphics; end

  # Run a game. `Eagle.run(MyGame.new, title: "x")` or `Eagle.run(title: "x") { |app| ... }`.
  def self.run(app : App = App.new, **opts) : Nil
    init(app, **opts)
    begin
      main_loop
    ensure
      shutdown
    end
  end

  def self.run(**opts, &block : App ->) : Nil
    app = App.new
    block.call(app)
    run(app, **opts)
  end

  # Pass the App class to have it constructed *after* the window and GPU exist,
  # so instance-variable initialisers may create textures etc.
  def self.run(app_class : App.class, **opts) : Nil
    init(app_class, **opts)
    begin
      main_loop
    ensure
      shutdown
    end
  end

  def self.init(app_class : App.class, **opts) : Nil
    init(App.new, **opts) { app_class.new }
  end

  # Open the window and GPU without entering the loop (tests, tools). Pair with `shutdown`.
  def self.init(app : App = App.new, **opts, &factory : -> App) : Nil
    init(app, **opts) # opens everything with a placeholder app
    real = factory.call
    @@app = real
    real._load
    SceneTree.root.ready_tree
  end

  def self.init(app : App = App.new, **opts) : Nil
    return if @@initialized
    setup_logging
    @@config = Config.new(**opts)
    @@app = app
    app.configure(@@config)
    apply_env(@@config)

    pf = Platform::SDL.new
    @@platform = pf
    wc = Platform::WindowConfig.new
    wc.title = @@config.title; wc.width = @@config.width; wc.height = @@config.height
    wc.resizable = @@config.resizable; wc.fullscreen = @@config.fullscreen; wc.vsync = @@config.vsync
    wc.msaa = @@config.msaa; wc.hidden = @@config.hidden; wc.highdpi = @@config.highdpi
    pf.open(wc)
    Window.refresh(pf)

    dev = GPU::GL33.new { |name| pf.gl_proc(name) }
    dev.default_framebuffer_size = pf.drawable_size
    GPU.device = dev

    Clock.reset
    Clock.fixed_delta = 1.0 / @@config.fixed_fps
    Assets.root = @@config.assets_dir if @@config.assets_dir
    @@graphics = Graphics.new
    Audio.init(pf) if @@config.audio
    SceneTree.reset
    @@initialized = true
    @@running = true
    @@quit_requested = false
    @@last_time = pf.now
    app._load
    SceneTree.root.ready_tree
  end

  private def self.apply_env(c : Config) : Nil
    if f = ENV["EAGLE_FRAMES"]?
      @@frame_limit = f.to_i64
    end
    @@screenshot_path = ENV["EAGLE_SCREENSHOT"]?
    c.hidden = true if ENV["EAGLE_HEADLESS"]? == "1"
    if size = ENV["EAGLE_SIZE"]?
      w, h = size.split("x").map(&.to_i)
      c.width = w; c.height = h
    end
    c.highdpi = false if ENV["EAGLE_HIGHDPI"]? == "0"
  end

  def self.quit : Nil
    @@quit_requested = true
  end

  # :nodoc: register a per-frame hook (used by subsystems)
  def self.each_frame(&block : ->) : Nil
    @@frame_hooks << block
  end

  private def self.main_loop : Nil
    while @@running
      step
    end
  end

  # Advance exactly one frame. Public so tests and tools can drive the loop.
  def self.step : Nil
    pf = platform
    app = self.app
    now = pf.now
    Clock.advance(now - @@last_time)
    @@last_time = now

    Input.begin_frame
    pf.poll_events { |ev| handle_event(ev) }
    Script.tick
    unless @@injected.empty?
      queued = @@injected
      @@injected = [] of Event
      queued.each { |ev| handle_event(ev) }
    end
    Input.end_poll

    Clock.each_fixed_step do |fdt|
      Physics2D.world.step(fdt) if Physics2D.active?
      Physics3D.world.step(fdt) if Physics3D.active?
      SceneTree.root.physics_process_tree(fdt)
      app._fixed_update(fdt)
    end
    SceneTree.root.process_tree(Clock.delta)
    Tween.update_all(Clock.delta)
    app._update(Clock.delta)
    SceneTree.flush_deferred
    Audio.update
    @@frame_hooks.each(&.call)

    g = graphics
    GPU.device.bind_render_target(nil)
    GPU.device.clear(@@config.clear_color, depth: true, stencil: true)
    g.begin_frame
    if Camera3D.current
      Scene3D.render
      GPU.device.bind_render_target(nil)
    end
    g.camera = Camera2D.current
    SceneTree.root.draw_tree(g)
    g.camera = nil
    app._draw(g)
    g.end_frame

    if (limit = @@frame_limit) && Clock.frame >= limit
      if path = @@screenshot_path
        screenshot(path)
        Eagle.log.info { "Screenshot written to #{path}" }
      end
      @@quit_requested = true
    end

    pf.swap

    if (max = @@config.max_fps) > 0 && !@@config.vsync
      target = 1.0 / max
      spent = pf.now - now
      pf.sleep(target - spent) if spent < target
    end

    if @@quit_requested
      @@running = false
    end
  end

  @@injected = [] of Event

  # Queue synthetic events for the next frame (tests, demos, replays, accessibility tools).
  # They flow through exactly the same path as real input: Input state, App#input, the node tree.
  def self.inject(*events : Event) : Nil
    events.each { |e| @@injected << e }
  end

  # Route one event through Input, the App and the scene tree.
  def self.handle_event(ev : Event) : Nil
    pf = platform
    app = self.app
    Input.handle(ev)
    case ev
    when QuitEvent
      @@quit_requested = true if app.quit?
    when WindowEvent
      case ev.kind
      when .resized?
        Window.refresh(pf)
        GPU.device.as(GPU::GL33).default_framebuffer_size = pf.drawable_size
        app.resize(Window.width, Window.height)
        SceneTree.root.each_descendant { |n| n.resized(Window.width, Window.height) }
      when .focus_gained? then Window.focused = true
      when .focus_lost? then Window.focused = false
      end
    end
    app._input(ev)
    SceneTree.dispatch_input(ev)
    Control.handle_focus_navigation(ev) unless ev.handled?
  end

  # Capture the current back buffer (call after drawing, before swap), or the
  # last presented frame during a normal frame. Returns the image; saves if `path`.
  def self.screenshot(path : String? = nil) : Image
    w, h = platform.drawable_size
    GPU.device.bind_render_target(nil)
    GL.finish
    bytes = GPU.device.read_pixels(0, 0, w, h)
    img = Image.new(w, h, bytes)
    # Opaque output: the default framebuffer alpha is meaningless.
    i = 3
    while i < bytes.size
      bytes[i] = 255_u8
      i += 4
    end
    img.save(path) if path
    img
  end

  def self.shutdown : Nil
    return unless @@initialized
    @@app.try(&.unload)
    SceneTree.reset
    Scene3D.reset
    Control.reset_focus
    Material.reset_shared
    Audio.shutdown
    @@graphics.try(&.dispose)
    @@graphics = nil
    Assets.clear
    GPU.device = nil
    @@platform.try(&.close)
    @@platform = nil
    @@initialized = false
    @@running = false
    @@frame_hooks.clear
    @@frame_limit = nil
    @@injected.clear
    Script.clear
  end
end
