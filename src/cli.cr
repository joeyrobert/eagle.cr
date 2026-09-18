require "option_parser"
require "./eagle"
require "./cli/init"

# The `eagle` command: scaffold projects, run them, and view assets.
module Eagle::CLI
  extend self

  USAGE = <<-TXT
    eagle: Crystal-native game engine

    Usage:
      eagle init [NAME] [options]  set up a new game project (wizard; --yes for defaults)
      eagle new NAME [options]     same as eagle init NAME --yes
      eagle run [FILE]             build & run a game (default: src/main.cr)
      eagle build [FILE]           build a release executable into ./bin
      eagle export exe [FILE]      release build into dist/<name>/
      eagle export web [FILE]      WebAssembly bundle into dist/web/<name>/
      eagle export app [FILE]      macOS .app bundle into dist/<name>.app
      eagle view FILE              view an image, model, font, sound or shader
      eagle examples [NAME]        list bundled examples, or run one
      eagle version                print the version
      eagle help [COMMAND]         show help for a command

    Environment for automated runs: EAGLE_FRAMES=n EAGLE_SCREENSHOT=out.png EAGLE_HEADLESS=1 EAGLE_SIZE=WxH
    TXT

  HELP = {
    "run" => <<-TXT,
      Usage: eagle run [FILE]

      Compiles FILE (default src/main.cr) in debug mode into bin/ and runs it.
      Runs `shards install` first if shard.yml has dependencies but lib/ doesn't exist.
      Plain Crystal equivalent: crystal run src/main.cr
      TXT
    "build" => <<-TXT,
      Usage: eagle build [FILE]

      Compiles FILE (default src/main.cr) with --release into bin/<project>.
      Plain Crystal equivalent: crystal build src/main.cr --release -o bin/<project>
      (or shards build --release, which builds the targets in shard.yml).
      TXT
    "export" => <<-TXT,
      Usage: eagle export exe|web|app [FILE]

        exe  release build into dist/<name>/<name>. Use Eagle.embed_assets("assets")
             for a single self-contained file, or ship assets/ next to it.
        web  WebAssembly bundle into dist/web/<name>/ (index.html, eagle.js, <name>.wasm).
             Needs lld (brew install lld, apt install lld) and embedded assets.
             Serve the folder over HTTP, e.g. python3 -m http.server.
        app  macOS .app bundle into dist/<name>.app (macOS only).

      <name> is the project folder's name when FILE is main.cr, else FILE's base name.
      TXT
    "view" => <<-TXT,
      Usage: eagle view FILE

      Opens a viewer for .png .qoi .bmp images, .obj models, .ttf fonts, .wav sounds
      and .glsl shaders (hot reloads on save).
      TXT
    "examples" => <<-TXT,
      Usage: eagle examples [NAME]

      Lists the bundled examples, or builds and runs one.
      TXT
    "version" => "Usage: eagle version\n\nPrints the eagle version.",
  }

  def run(args : Array(String))
    cmd = args[0]?
    return puts(help_for(args[1]?)) if cmd.in?("help", "-h", "--help")
    return puts(help_for(cmd)) if cmd && args[1..].any?(&.in?("-h", "--help"))
    case cmd
    when "init" then init(args[1..])
    when "new" then init(args[1..] + ["--yes"], require_name: true)
    when "run" then run_project(args[1]? || "src/main.cr", release: false)
    when "build" then run_project(args[1]? || "src/main.cr", release: true, build_only: true)
    when "view" then view(args[1]? || abort("eagle view FILE"))
    when "examples" then examples(args[1]?)
    when "export" then export(args[1]? || abort(HELP["export"]), args[2]? || "src/main.cr")
    when "version", "-v", "--version" then puts "eagle #{Eagle::VERSION}"
    when nil then puts USAGE
    else abort "unknown command #{cmd}\n\n#{USAGE}"
    end
  end

  def help_for(cmd : String?) : String
    return USAGE if cmd.nil?
    return Init.help if cmd.in?("init", "new")
    HELP[cmd]? || "unknown command #{cmd}\n\n#{USAGE}"
  end

  def init(args : Array(String), require_name = false)
    o = Init.parse(args)
    return puts(Init.help) if o.help?
    abort "usage: eagle new NAME [options]" if require_name && o.name.nil?
    if !o.yes? && STDIN.tty?
      Init.prompt(o, STDIN, STDOUT)
    else
      abort "usage: eagle init NAME [options] (or run it in a terminal to be asked)" if o.name.nil?
      o.resolve_defaults
    end
    dir = Init.generate(o)
    if o.git? && !Dir.exists?(File.join(dir, ".git"))
      begin
        Process.run("git", ["init", "-q", dir])
      rescue File::NotFoundError
        STDERR.puts "git not found; skipped git init"
      end
    end
    puts "Created #{o.template} project #{o.name} in #{dir == "." ? "the current folder" : "#{dir}/"}. Next:"
    puts "  cd #{dir}" unless dir == "."
    puts "  shards install"
    puts "  eagle run"
  rescue e : InitError
    abort "eagle init: #{e.message}"
  end

  # Where the engine source lives (examples, web build script): EAGLE_ROOT, the project's lib/eagle,
  # the checkout this binary was built from, or EAGLE_HOME/src next to an installed binary.
  def engine_root : String
    exe_dir = Process.executable_path.try { |p| File.dirname(p) } || "."
    candidates = [ENV["EAGLE_ROOT"]?, "lib/eagle", File.expand_path("..", __DIR__), File.join(exe_dir, "..", "src")]
    candidates.compact.map { |c| File.expand_path(c) }.find { |c| File.exists?(File.join(c, "src", "eagle.cr")) } ||
      abort("can't find the Eagle source: set EAGLE_ROOT to an eagle.cr checkout, or run shards install in your project")
  end

  def eagle_home : String
    ENV["EAGLE_HOME"]? || File.join(Path.home, ".eagle")
  end

  def run_project(file : String, release : Bool, build_only : Bool = false)
    abort "#{file} not found" unless File.exists?(file)
    if File.exists?("shard.yml") && !Dir.exists?("lib") && File.read("shard.yml").includes?("dependencies:")
      run_cmd(["shards", "install"])
    end
    Dir.mkdir_p("bin")
    out_bin = "bin/#{File.basename(file, ".cr")}"
    out_bin = "bin/#{File.basename(Dir.current)}" if File.basename(file) == "main.cr"
    {% if flag?(:win32) %} out_bin += ".exe" {% end %}
    cmd = ["crystal", "build", file, "-o", out_bin]
    cmd << "--release" if release
    run_cmd(cmd)
    return puts("built #{out_bin}") if build_only
    Process.run(out_bin, output: STDOUT, error: STDERR, input: STDIN)
  end

  def export(mode : String, file : String)
    abort "#{file} not found" unless File.exists?(file)
    name = File.basename(file) == "main.cr" ? File.basename(File.dirname(File.expand_path(file))) : File.basename(file, ".cr")
    case mode
    when "exe"
      out_dir = "dist/#{name}"
      Dir.mkdir_p(out_dir)
      exe = "#{out_dir}/#{name}"
      {% if flag?(:win32) %} exe += ".exe" {% end %}
      run_cmd(["crystal", "build", file, "--release", "-o", exe])
      puts "exported #{exe} (#{File.size(exe) // 1024} KB). Assets: embed with Eagle.embed_assets or ship an assets/ folder next to it."
    when "web"
      root = engine_root
      env = {} of String => String
      unless ENV["EAGLE_WASM_TOOLCHAIN"]? || Dir.exists?(File.join(root, ".wasm-toolchain"))
        env["EAGLE_WASM_TOOLCHAIN"] = File.join(eagle_home, "wasm-toolchain") # shared download cache across projects
      end
      run_cmd(["sh", File.join(root, "script", "build-web.sh"), file, "dist/web/#{name}"], env)
      puts "exported dist/web/#{name}/. Serve the folder over HTTP (e.g. python3 -m http.server)."
    when "app"
      {% if flag?(:darwin) %}
        app = "dist/#{name}.app/Contents/MacOS"
        Dir.mkdir_p(app)
        run_cmd(["crystal", "build", file, "--release", "-o", "#{app}/#{name}"])
        File.write("dist/#{name}.app/Contents/Info.plist", <<-PLIST)
          <?xml version="1.0" encoding="UTF-8"?>
          <plist version="1.0"><dict>
            <key>CFBundleName</key><string>#{name}</string>
            <key>CFBundleExecutable</key><string>#{name}</string>
            <key>CFBundleIdentifier</key><string>cr.eagle.#{name}</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>NSHighResolutionCapable</key><true/>
          </dict></plist>
          PLIST
        puts "exported dist/#{name}.app"
      {% else %}
        abort "app bundles are only produced on macOS"
      {% end %}
    else
      abort "unknown export mode #{mode} (exe, web, app)"
    end
  end

  private def run_cmd(cmd : Array(String), env : Hash(String, String)? = nil)
    cmd = cmd + windows_link_flags if cmd[0] == "crystal"
    puts "$ #{cmd.join(" ")}"
    status = Process.run(cmd[0], cmd[1..], env: env, output: STDOUT, error: STDERR)
    abort "command failed" unless status.success?
  end

  # On Windows the installer ships SDL2.lib in EAGLE_HOME/lib; point the MSVC linker at it.
  private def windows_link_flags : Array(String)
    {% if flag?(:win32) %}
      libdir = File.join(File.dirname(Process.executable_path || "."), "..", "lib")
      return ["--link-flags", "/LIBPATH:#{File.expand_path(libdir)}"] if File.exists?(File.join(libdir, "SDL2.lib"))
    {% end %}
    [] of String
  end

  def examples(name : String?)
    root = File.join(engine_root, "examples")
    names = Dir.children(root).select { |d| File.exists?(File.join(root, d, "main.cr")) }.sort
    if name.nil?
      puts "Examples (eagle examples NAME):"
      names.each { |n| puts "  #{n}" }
      return
    end
    abort "unknown example #{name}; try: #{names.join(", ")}" unless names.includes?(name)
    run_project(File.join(root, name, "main.cr"), release: false)
  end

  # ---- viewer ---------------------------------------------------------------
  def view(path : String)
    abort "#{path} not found" unless File.exists?(path)
    ext = File.extname(path).downcase
    app = case ext
          when ".png", ".qoi", ".bmp" then ImageViewer.new(path)
          when ".obj" then ModelViewer.new(path)
          when ".ttf", ".ttc" then FontViewer.new(path)
          when ".wav" then SoundViewer.new(path)
          when ".glsl" then ShaderViewer.new(path)
          else abort "don't know how to view #{ext}"
          end
    Eagle.run(app, title: "eagle view: #{File.basename(path)}", width: 1000, height: 700)
  end

  class ImageViewer < App
    @path : String
    @tex : Texture? = nil
    @zoom = 1_f32
    @pan = Vec2::ZERO
    @nearest = true

    def initialize(@path); end

    def load
      @tex = Texture.new(Image.load(@path), GPU::Filter::Nearest)
      fit
    end

    def fit
      t = @tex.not_nil!
      @zoom = (Math.min(Window.width / t.width.to_f32, Window.height / t.height.to_f32).clamp(0.05_f32, 8_f32) * 0.9_f32)
      @pan = Vec2::ZERO
    end

    def update(dt : Float32)
      @zoom = (@zoom * (1 + Input.wheel.y * 0.1)).clamp(0.05_f32, 64_f32)
      @pan += Input.mouse_delta if Input.mouse_down?
      fit if Input.pressed?(Key::F)
      if Input.pressed?(Key::N)
        @nearest = !@nearest
        @tex.not_nil!.filter = @nearest ? GPU::Filter::Nearest : GPU::Filter::Linear
      end
      Eagle.quit if Input.pressed?(Key::Escape)
    end

    def draw(g : Graphics)
      t = @tex.not_nil!
      w = t.width * @zoom; h = t.height * @zoom
      pos = Window.center - v2(w, h) / 2 + @pan
      g.draw(Texture.new(Image.checkerboard(16, 16, 8, Color.gray(0.3), Color.gray(0.25)), wrap: GPU::Wrap::Repeat), Rect.new(pos, v2(w, h))) if false
      g.rect(pos.x, pos.y, w, h, color: Color.gray(0.2))
      g.draw(t, pos.x, pos.y, sx: @zoom)
      g.print("#{File.basename(@path)}  #{t.width}x#{t.height}  zoom #{(@zoom * 100).round}%   wheel zoom, drag pan, F fit, N filter", 10, 10)
    end
  end

  class ModelViewer < App
    @path : String
    @node : MeshInstance3D? = nil
    @cam = Camera3D.new(position: v3(0, 1, 4))
    @yaw = 0.6_f32
    @pitch = 0.4_f32
    @dist = 4_f32
    @wire = false

    def initialize(@path); end

    def load
      mesh = Codecs::OBJ.decode(File.read(@path), @path)
      b = mesh.bounds
      size = b.size.length
      mesh.transform!(Mat4.translation(-b.center))
      @dist = size * 1.2
      @node = MeshInstance3D.new(mesh, Material.new(Color.hex("#d0d4dc"), shininess: 48, specular: 0.4))
      SceneTree.root.add(@node.not_nil!, DirectionalLight3D.new(v3(-0.5, -1, -0.4)), @cam)
      SceneTree.root.add(MeshInstance3D.new(Mesh.grid(size * 2, 20), Material.unlit(Color.gray(0.35)), position: v3(0, -b.size.y / 2, 0)))
      @cam.far = size * 20
    end

    def update(dt : Float32)
      if Input.mouse_down?
        @yaw -= Input.mouse_delta.x * 0.01
        @pitch = (@pitch + Input.mouse_delta.y * 0.01).clamp(-1.5_f32, 1.5_f32)
      end
      @dist *= (1 - Input.wheel.y * 0.1)
      if Input.pressed?(Key::W)
        @wire = !@wire
        @node.not_nil!.material.wireframe = @wire
      end
      @cam.position = Quat.from_axis_angle(Vec3::UP, @yaw) * Quat.from_axis_angle(Vec3::RIGHT, -@pitch) * v3(0, 0, @dist)
      @cam.look_at(Vec3::ZERO)
      Eagle.quit if Input.pressed?(Key::Escape)
    end

    def draw(g : Graphics)
      m = @node.not_nil!.mesh.not_nil!
      g.print("#{File.basename(@path)}  #{m.vertex_count} verts  #{m.triangle_count} tris   drag orbit, wheel zoom, W wireframe", 10, 10)
    end
  end

  class FontViewer < App
    @path : String
    @fonts = [] of Font

    def initialize(@path); end

    def load
      data = File.read(@path).to_slice
      [12, 18, 24, 36, 56].each { |s| @fonts << TrueTypeFont.new(data, s) }
    end

    def draw(g : Graphics)
      f0 = @fonts[0].as(TrueTypeFont)
      g.print("#{File.basename(@path)}  family: #{f0.family_name}  glyphs: #{f0.ttf.glyph_count}  kern pairs: #{f0.ttf.kern_pairs}", 10, 10)
      y = 40_f32
      @fonts.each do |f|
        g.print("The quick brown fox jumps over the lazy dog 0123456789 (#{f.as(TrueTypeFont).size.to_i}px)", 10, y, Color::WHITE, f)
        y += f.height + 10
      end
      g.print("AVAW Ta fi ﬁ: kerning & ligature test", 10, y + 10, Color.gray(0.8), @fonts[3])
      Eagle.quit if Input.pressed?(Key::Escape)
    end
  end

  class SoundViewer < App
    @path : String
    @sound : Sound? = nil
    @voice : Voice? = nil

    def initialize(@path); end

    def load
      @sound = Sound.load(@path)
      @voice = @sound.not_nil!.play
    end

    def update(dt : Float32)
      @voice = @sound.not_nil!.play if Input.pressed?(Key::Space)
      Eagle.quit if Input.pressed?(Key::Escape)
    end

    def draw(g : Graphics)
      s = @sound.not_nil!
      b = s.buffer
      g.print("#{File.basename(@path)}  #{b.sample_rate} Hz  #{b.channels} ch  #{b.duration.round(2)} s   space replay", 10, 10)
      # waveform
      w = Window.width - 40; h = 300; cy = Window.height / 2
      pts = Array(Vec2).new(w) do |x|
        i = (x.to_f64 / w * b.frames).to_i
        Vec2.new(20 + x, cy - b.at(i, 0) * h / 2)
      end
      g.polyline(pts, Color.hex("#4fd1c5"))
      if v = @voice
        px = 20 + v.position / b.duration * w
        g.line(px, cy - h / 2, px, cy + h / 2, Color::YELLOW)
      end
    end
  end

  class ShaderViewer < App
    @path : String
    @shader : Shader? = nil
    @error = ""
    @mtime : ::Time? = nil

    def initialize(@path); end

    def load; reload; end

    def reload
      begin
        @shader = Shader.parse(File.read(@path))
        @error = ""
      rescue e
        @error = e.message || "error"
      end
      @mtime = File.info(@path).modification_time
    end

    def update(dt : Float32)
      reload if File.info(@path).modification_time != @mtime # hot reload
      Eagle.quit if Input.pressed?(Key::Escape)
    end

    def draw(g : Graphics)
      if (sh = @shader) && @error.empty?
        sh["u_mouse"] = Input.mouse if sh.has_uniform?("u_mouse")
        g.with_shader(sh) { g.rect(0, 0, Window.width, Window.height) }
      end
      g.print("#{File.basename(@path)}  (edit the file to hot-reload)", 10, 10)
      g.printf(@error, 10, 40, Window.width - 20, color: Color::RED) unless @error.empty?
    end
  end
end

Eagle::CLI.run(ARGV)
