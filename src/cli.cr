require "option_parser"
require "./eagle"

# The `eagle` command: scaffold projects, run them, and view assets.
module Eagle::CLI
  extend self

  USAGE = <<-TXT
    eagle — Crystal-native game engine

    Usage:
      eagle new NAME            create a new game project in ./NAME
      eagle run [FILE]          build & run a game (default: src/main.cr)
      eagle build [FILE]        build a release executable into ./bin
      eagle view FILE           view an image (.png .qoi .bmp), model (.obj), font (.ttf), sound (.wav) or shader (.glsl)
      eagle examples            list bundled examples
      eagle examples NAME       run a bundled example
      eagle version

    Environment for automated runs: EAGLE_FRAMES=n EAGLE_SCREENSHOT=out.png EAGLE_HEADLESS=1 EAGLE_SIZE=WxH
    TXT

  def run(args : Array(String))
    case args[0]?
    when "new" then new_project(args[1]? || abort("eagle new NAME"))
    when "run" then run_project(args[1]? || "src/main.cr", release: false)
    when "build" then run_project(args[1]? || "src/main.cr", release: true, build_only: true)
    when "view" then view(args[1]? || abort("eagle view FILE"))
    when "examples" then examples(args[1]?)
    when "version", "-v", "--version" then puts "eagle #{Eagle::VERSION}"
    else puts USAGE
    end
  end

  def new_project(name : String)
    abort "#{name} already exists" if Dir.exists?(name)
    Dir.mkdir_p("#{name}/src")
    Dir.mkdir_p("#{name}/assets")
    engine_path = File.expand_path("..", __DIR__)
    File.write("#{name}/shard.yml", <<-YML)
      name: #{name}
      version: 0.1.0
      crystal: ">= 1.21.0"
      dependencies:
        eagle:
          path: #{engine_path}
      targets:
        #{name}:
          main: src/main.cr
      YML
    File.write("#{name}/src/main.cr", <<-CR)
      require "eagle"
      include Eagle

      class Game < App
        @player = Sprite2D.new(Texture.new(Image.circle(32, Color.hex("#ffcc00"))), Window.center)

        def load
          Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
          Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
          Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
          Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
          SceneTree.root.add(@player)
        end

        def update(dt : Float32)
          @player.position += Input.vector("left", "right", "up", "down") * 250 * dt
          Eagle.quit if Input.pressed?(Key::Escape)
        end

        def draw(g : Graphics)
          g.print("#{name} — move with WASD  fps \#{Clock.fps.round}", 10, 10)
        end
      end

      Eagle.run(Game, title: "#{name}", width: 960, height: 540)
      CR
    File.write("#{name}/.gitignore", "/bin/\n/lib/\n/.shards/\n")
    puts "Created #{name}/. Next:\n  cd #{name}\n  shards install\n  eagle run"
  end

  def run_project(file : String, release : Bool, build_only : Bool = false)
    abort "#{file} not found" unless File.exists?(file)
    Dir.mkdir_p("bin")
    out_bin = "bin/#{File.basename(file, ".cr")}"
    out_bin = "bin/#{File.basename(Dir.current)}" if File.basename(file) == "main.cr"
    cmd = ["crystal", "build", file, "-o", out_bin]
    cmd << "--release" if release
    puts "$ #{cmd.join(" ")}"
    status = Process.run(cmd[0], cmd[1..], output: STDOUT, error: STDERR)
    abort "build failed" unless status.success?
    return puts("built #{out_bin}") if build_only
    Process.run(out_bin, output: STDOUT, error: STDERR, input: STDIN)
  end

  def examples(name : String?)
    root = File.expand_path("../examples", __DIR__)
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
    Eagle.run(app, title: "eagle view — #{File.basename(path)}", width: 1000, height: 700)
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
      g.print("AVAW Ta fi ﬁ — kerning & ligature test", 10, y + 10, Color.gray(0.8), @fonts[3])
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
