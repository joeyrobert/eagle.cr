module Eagle
  # Settings for the window and the engine loop. Every field has a sensible default.
  #
  # You rarely build a `Config` yourself. Pass the fields as named arguments to
  # `Eagle.run`, or override `App#configure` to compute them:
  #
  # ```
  # class Game < App
  #   def configure(config : Config) : Nil
  #     config.msaa = 4
  #     config.fixed_fps = 120 # finer physics steps
  #   end
  # end
  #
  # Eagle.run(Game, title: "Space Rocks", width: 1280, height: 720, vsync: true)
  # ```
  #
  # A few environment variables override the config, which is handy for CI and screenshots:
  #
  # * `EAGLE_FRAMES=60` quits after 60 frames.
  # * `EAGLE_SCREENSHOT=out.png` saves the last frame before quitting.
  # * `EAGLE_HEADLESS=1` hides the window.
  # * `EAGLE_SIZE=800x600` overrides the window size.
  class Config
    # Window title.
    property title : String = "Eagle"
    # Initial window width in logical pixels.
    property width : Int32 = 1280
    # Initial window height in logical pixels.
    property height : Int32 = 720
    # Whether the player can resize the window. `App#resize` and `Node#resized` fire when they do.
    property resizable : Bool = true
    # Start fullscreen. Toggle later with `Window.fullscreen=`.
    property fullscreen : Bool = false
    # Sync presentation to the display's refresh rate. Leave it on unless you are measuring performance.
    property vsync : Bool = true
    # Multisample anti-aliasing samples (0, 2, 4 or 8). Smooths 3D edges and shape outlines.
    property msaa : Int32 = 0
    # Render at full resolution on Retina and other high-DPI screens.
    property highdpi : Bool = true
    # How many times per second `physics_process` and `App#fixed_update` run, independent of the frame rate.
    property fixed_fps : Int32 = 60
    # Frame-rate cap used when vsync is off. 0 means uncapped.
    property max_fps : Int32 = 0
    # Background color the screen is cleared to at the start of every frame.
    property clear_color : Color = Color.rgb(24, 26, 32)
    # Folder that `res://` paths resolve against. `nil` auto-detects it; see `Assets`.
    property assets_dir : String? = nil
    # Set to false to skip opening an audio device, for tools and servers.
    property audio : Bool = true
    # Open the window hidden, for tests and offscreen rendering.
    property hidden : Bool = false

    # Builds a config from named arguments that match the property names.
    def initialize(**opts)
      {% for ivar in @type.instance_vars %}
        if v = opts[{{ivar.symbolize}}]?
          @{{ivar}} = v.as({{ivar.type}})
        end
      {% end %}
    end
  end

  # The base class for a game. Subclass it, override the hooks you need, and hand it to `Eagle.run`.
  #
  # Every hook is optional. Eagle calls them in this order each frame:
  #
  # 1. `input` for each new event (key presses, clicks, window events)
  # 2. `fixed_update` zero or more times, at `Config#fixed_fps`
  # 3. `update` once, with the time since the last frame
  # 4. `draw`, after the scene tree has drawn itself
  #
  # `load` runs once, when the window and GPU are ready. Create textures, sounds and
  # nodes there, or pass the class (not an instance) to `Eagle.run` so instance-variable
  # initializers can create them too.
  #
  # ```
  # class Game < App
  #   @pos = Vec2.new(100, 100)
  #   @tex : Texture? = nil
  #
  #   def load : Nil
  #     @tex = Texture.new(Image.circle(16, Color::YELLOW))
  #     Input.map "left", Key::A, Key::Left
  #     Input.map "right", Key::D, Key::Right
  #   end
  #
  #   def update(dt : Float32) : Nil
  #     @pos += v2(Input.axis("left", "right") * 200 * dt, 0)
  #     Eagle.quit if Input.pressed?(Key::Escape)
  #   end
  #
  #   def draw(g : Graphics) : Nil
  #     @tex.try { |t| g.draw(t, @pos) }
  #     g.print("fps #{Clock.fps.round}", 10, 10)
  #   end
  # end
  #
  # Eagle.run(Game, title: "My Game", width: 960, height: 540)
  # ```
  #
  # You can mix this immediate-mode style with the scene tree: add nodes to
  # `SceneTree.root` in `load` and they update and draw themselves before your `draw`.
  #
  # For tiny programs, skip the subclass and use the block helpers:
  #
  # ```
  # Eagle.run(title: "Blocks") do |app|
  #   app.on_draw { |g| g.circle(Window.center, 50) }
  # end
  # ```
  class App
    @load_blocks = [] of ->
    @update_blocks = [] of Float32 ->
    @fixed_blocks = [] of Float32 ->
    @draw_blocks = [] of Graphics ->
    @input_blocks = [] of Event ->

    # Adjust the configuration before the window opens. Runs before `load`.
    def configure(config : Config) : Nil; end
    # Called once after the window, GPU and audio are ready. Load assets and build your scene here.
    def load : Nil; end
    # Called once per frame. *dt* is the time since the last frame in seconds, already scaled by `Clock.scale`.
    # Put movement, game rules and animation here, multiplying speeds by *dt*.
    def update(dt : Float32) : Nil; end
    # Called at a fixed rate (`Config#fixed_fps`), zero or more times per frame. *dt* is always
    # the same value. Put physics and anything that must be deterministic here.
    def fixed_update(dt : Float32) : Nil; end
    # Called once per frame after the scene tree is drawn, so anything you draw here appears on top.
    # *g* is the immediate-mode drawing context.
    def draw(g : Graphics) : Nil; end
    # Receives every raw event before the scene tree sees it. Set `event.handled = true` to stop
    # nodes from receiving it. For "is this key held?" checks, use `Input` instead.
    def input(event : Event) : Nil; end
    # Called when the window size changes, with the new size in logical pixels.
    def resize(width : Int32, height : Int32) : Nil; end
    # Called when the player closes the window. Return false to keep running, for example to
    # show an "unsaved changes" prompt.
    def quit? : Bool; true; end
    # Called once during shutdown. Save settings or high scores here.
    def unload : Nil; end

    # Adds a block that runs after `load`. Returns self so calls can be chained.
    def on_load(&block : ->) : self; @load_blocks << block; self; end
    # Adds a block that runs after `update` every frame.
    def on_update(&block : Float32 ->) : self; @update_blocks << block; self; end
    # Adds a block that runs after each `fixed_update`.
    def on_fixed_update(&block : Float32 ->) : self; @fixed_blocks << block; self; end
    # Adds a block that runs after `draw`.
    def on_draw(&block : Graphics ->) : self; @draw_blocks << block; self; end
    # Adds a block that runs after `input` for each event.
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

  # The platform backend (SDL on desktop, the browser on the web). Raises if Eagle isn't running.
  # You rarely need it; `Window`, `Input` and `Audio` wrap it.
  def self.platform : Platform::Base
    @@platform || raise Error.new("Eagle is not initialised. Call Eagle.run or Eagle.init.")
  end

  # The platform backend, or `nil` before `Eagle.run`.
  def self.platform? : Platform::Base?; @@platform; end
  # The active configuration.
  def self.config : Config; @@config; end
  # The running app. Raises if nothing is running.
  def self.app : App; @@app || raise Error.new("No app running"); end
  # True while the main loop is running.
  def self.running? : Bool; @@running; end
  # True after the window and GPU are open.
  def self.initialized? : Bool; @@initialized; end
  # The 2D drawing context, the same object passed to `App#draw`.
  def self.graphics : Graphics; @@graphics || raise Error.new("Graphics not ready"); end
  # Short alias for `graphics`.
  def self.g : Graphics; graphics; end

  # Opens the window, calls `App#load`, runs the main loop until quit, then shuts down.
  # Named arguments set `Config` fields.
  #
  # ```
  # class Game < App
  # end
  #
  # Eagle.run(Game.new, title: "Hi", width: 800, height: 600)
  # ```
  #
  # On the web the browser drives frames, so this returns right away.
  def self.run(app : App = App.new, **opts) : Nil
    init(app, **opts)
    {% if flag?(:wasm32) %}
      # The browser drives frames through `eagle_frame`; returning here hands control back to JS.
      return
    {% else %}
      begin
        main_loop
      ensure
        shutdown
      end
    {% end %}
  end

  # Creates a plain `App`, lets the block attach hooks with `App#on_draw` and friends, then runs it.
  def self.run(**opts, &block : App ->) : Nil
    app = App.new
    block.call(app)
    run(app, **opts)
  end

  # Runs a game given its class. The app is constructed after the window and GPU exist,
  # so instance-variable initializers can create textures, fonts and sounds. This is
  # the recommended form.
  #
  # ```
  # class Game < App
  #   @logo = Texture.new(Image.circle(32, Color::WHITE)) # safe: the GPU is ready
  # end
  #
  # Eagle.run(Game, title: "Hi")
  # ```
  def self.run(app_class : App.class, **opts) : Nil
    init(app_class, **opts)
    {% if flag?(:wasm32) %}
      return
    {% else %}
      begin
        main_loop
      ensure
        shutdown
      end
    {% end %}
  end

  # Opens the window and GPU and constructs *app_class*, without entering the loop.
  # Drive frames with `step` and finish with `shutdown`.
  def self.init(app_class : App.class, **opts) : Nil
    init(App.new, **opts) { app_class.new }
  end

  # Opens everything with a placeholder, then builds the real app with *factory*.
  def self.init(app : App = App.new, **opts, &factory : -> App) : Nil
    init(app, **opts) # opens everything with a placeholder app
    real = factory.call
    @@app = real
    real._load
    SceneTree.root.ready_tree
  end

  # Opens the window and GPU and calls `App#load`, without entering the loop.
  # Use it in tests and tools, then call `step` to advance frames and `shutdown` when done.
  #
  # ```
  # Eagle.init(title: "test", hidden: true)
  # 3.times { Eagle.step }
  # image = Eagle.screenshot
  # Eagle.shutdown
  # ```
  def self.init(app : App = App.new, **opts) : Nil
    return if @@initialized
    setup_logging
    @@config = Config.new(**opts)
    @@app = app
    app.configure(@@config)
    apply_env(@@config)

    pf = {% if flag?(:wasm32) %} Platform::Web.new {% else %} Platform::SDL.new {% end %}
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

  # Asks the loop to stop after the current frame. `App#unload` runs during shutdown.
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

  # Runs exactly one frame: input, fixed updates, update, tweens, audio and drawing.
  # `run` calls this in a loop. Call it yourself after `init` to drive the engine from tests;
  # pass *dt* (seconds) to advance the clock by a fixed amount instead of wall-clock time.
  def self.step(dt : Number? = nil) : Nil
    pf = platform
    app = self.app
    now = pf.now
    Clock.advance(dt ? dt.to_f64 : now - @@last_time)
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
      {% if flag?(:wasm32) %} shutdown {% end %}
    end
  end

  @@injected = [] of Event

  # Queues synthetic events for the next frame. They go through the same path as real
  # input, so `Input`, `App#input` and nodes all see them. Use it for tests, demos and replays.
  #
  # ```
  # Eagle.inject(KeyEvent.new(Key::Space, pressed: true))
  # ```
  def self.inject(*events : Event) : Nil
    events.each { |e| @@injected << e }
  end

  # Routes one event through `Input`, the app and the scene tree right away. Most code should use `inject`.
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
    return unless ev.is_a?(TouchEvent)
    Touch.take_derived.each do |d|
      app._input(d)
      SceneTree.dispatch_input(d)
    end
    Touch.mouse_events(ev).each { |m| handle_event(m) } if Touch.emulate_mouse? && !ev.handled?
  end

  # Reads the current frame back from the GPU and returns it as an `Image`. Saves a PNG if you give a path.
  #
  # ```
  # Eagle.screenshot("shot.png") if Input.pressed?(Key::F12)
  # ```
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

  # Closes the window and frees GPU, audio and asset resources. `run` calls it for you.
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
