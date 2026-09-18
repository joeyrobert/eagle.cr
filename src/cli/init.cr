require "option_parser"

# `eagle init`: the project setup wizard. Parsing, prompting and file generation live
# here (not in cli.cr) so specs can drive them without launching the CLI.
module Eagle::CLI
  class InitError < Exception; end

  # Every choice `eagle init` makes. `nil` means "not decided yet": prompt for it, or use the default.
  class InitOptions
    TEMPLATES = {"2d-game" => "2D game: a sprite you move around", "3d-game" => "3D game: a cube on a lit, shadowed floor",
                 "ui-app" => "UI app: panel, buttons and a slider", "empty" => "Empty: a window that prints hello"}
    ALIASES = {"2d" => "2d-game", "3d" => "3d-game", "ui" => "ui-app", "blank" => "empty"}

    property name : String? = nil
    property dir : String? = nil
    property template : String? = nil
    property width : Int32? = nil
    property height : Int32? = nil
    property pixel_art : Bool? = nil
    property web : Bool? = nil
    property git : Bool? = nil
    property ci : Bool? = nil
    property local : String? = nil
    property? yes = false
    property? help = false

    # Maps "2d", "3d-game", "UI" etc. to a canonical template name.
    def self.template_name(t : String) : String
      t = t.strip.downcase
      t = ALIASES[t]? || t
      raise InitError.new("unknown template #{t}; choose one of #{TEMPLATES.keys.join(", ")}") unless TEMPLATES.has_key?(t)
      t
    end

    # Parses "960x540" into {960, 540}.
    def self.parse_size(s : String) : {Int32, Int32}
      m = s.strip.match(/\A(\d+)\s*[xX*]\s*(\d+)\z/) || raise InitError.new("window size must look like 960x540, got #{s}")
      w, h = m[1].to_i, m[2].to_i
      raise InitError.new("window size #{s} is out of range") unless (64..8192).includes?(w) && (64..8192).includes?(h)
      {w, h}
    end

    # Checks a project name is usable as a directory, shard and Crystal module name.
    def self.validate_name(n : String) : String
      raise InitError.new("project name #{n.inspect} must start with a letter and use only letters, digits, - and _") unless n.matches?(/\A[A-Za-z][A-Za-z0-9_-]*\z/)
      n
    end

    # Fills every undecided choice with its default.
    def resolve_defaults : self
      @template ||= "2d-game"
      @width ||= 960
      @height ||= 540
      @pixel_art = false if @pixel_art.nil?
      @web = true if @web.nil?
      @git = true if @git.nil?
      @ci = @local.nil? if @ci.nil? # CI can't see a local path dependency
      self
    end

    def name! : String; @name || raise InitError.new("missing project name"); end
    def template! : String; @template.not_nil!; end
    def width! : Int32; @width.not_nil!; end
    def height! : Int32; @height.not_nil!; end
    def pixel_art? : Bool; !!@pixel_art; end
    def web? : Bool; !!@web; end
    def git? : Bool; !!@git; end
    def ci? : Bool; !!@ci; end

    # Directory the project is written to: `dir` if given, otherwise ./NAME.
    def target_dir : String; @dir || name!; end
    # The shard and executable name: lowercase.
    def shard_name : String; name!.downcase; end
    # File name for the game's library file under src/.
    def file_name : String; shard_name.gsub('-', '_'); end
    # Crystal module name: "my-game" becomes "MyGame".
    def module_name : String; name!.split(/[-_]/).reject(&.empty?).map { |w| w[0].upcase + w[1..] }.join; end
    # Window title: "my-game" becomes "My Game".
    def title : String; name!.split(/[-_]/).reject(&.empty?).map(&.capitalize).join(" "); end
  end

  module Init
    extend self

    USAGE = <<-TXT
      Usage: eagle init [NAME|.] [options]

      Creates a new Eagle game project. Asks questions when run in a terminal;
      pass --yes (or any flags) to script it. NAME defaults to the current
      folder's name when you pass "." (initialise the current folder).

      TXT

    # Parses `eagle init` arguments. Raises `InitError` on bad input.
    def parse(args : Array(String)) : InitOptions
      o = InitOptions.new
      errors = [] of String
      parser(o, errors).parse(args.dup)
      raise InitError.new(errors.first) unless errors.empty?
      o
    end

    # Help text for `eagle init --help`.
    def help : String
      parser(InitOptions.new, [] of String).to_s
    end

    private def parser(o : InitOptions, errors : Array(String)) : OptionParser
      OptionParser.new do |p|
        p.banner = USAGE
        p.on("-t TEMPLATE", "--template TEMPLATE", "2d-game (2d), 3d-game (3d), ui-app (ui) or empty") { |t| o.template = InitOptions.template_name(t) }
        p.on("-s SIZE", "--size SIZE", "window size, e.g. 1280x720 (default 960x540)") { |s| o.width, o.height = InitOptions.parse_size(s) }
        p.on("--pixel-art", "crisp nearest-neighbour texture filtering") { o.pixel_art = true }
        p.on("--no-pixel-art", "smooth (linear) texture filtering (default)") { o.pixel_art = false }
        p.on("--web", "embed assets so `eagle export web` works (default)") { o.web = true }
        p.on("--no-web", "load assets from disk; skip web setup") { o.web = false }
        p.on("--git", "run git init (default)") { o.git = true }
        p.on("--no-git", "don't run git init") { o.git = false }
        p.on("--ci", "add a GitHub Actions workflow (default unless --local)") { o.ci = true }
        p.on("--no-ci", "no GitHub Actions workflow") { o.ci = false }
        p.on("--local PATH", "depend on an Eagle checkout at PATH instead of github: joeyrobert/eagle.cr") { |path| o.local = File.expand_path(path) }
        p.on("-y", "--yes", "accept defaults for everything not given as a flag; never prompt") { o.yes = true }
        p.on("-h", "--help", "show this help") { o.help = true }
        p.unknown_args do |rest, _|
          if flag = rest.find(&.starts_with?("-"))
            errors << "unknown option #{flag}"
            next
          end
          errors << "unexpected arguments: #{rest[1..].join(" ")}" if rest.size > 1
          if n = rest[0]?
            if n == "."
              o.dir = "."
              o.name = File.basename(Dir.current)
            else
              o.name = n
            end
          end
        end
        p.invalid_option { |flag| errors << "unknown option #{flag}" }
        p.missing_option { |flag| errors << "#{flag} needs a value" }
      end
    end

    # Asks for every undecided choice on *input*/*output*, then fills the rest with defaults.
    def prompt(o : InitOptions, input : IO, output : IO) : InitOptions
      o.name ||= ask(input, output, "Project name", "mygame") { |v| InitOptions.validate_name(v) }
      unless o.template
        output.puts "Templates:"
        InitOptions::TEMPLATES.each_with_index { |(k, v), i| output.puts "  #{i + 1}) #{k.ljust(8)} #{v}" }
        o.template = ask(input, output, "Template", "2d-game") do |v|
          (i = v.to_i?) && (1..InitOptions::TEMPLATES.size).includes?(i) ? InitOptions::TEMPLATES.keys[i - 1] : InitOptions.template_name(v)
        end
      end
      unless o.width
        o.width, o.height = ask(input, output, "Window size", "960x540") { |v| InitOptions.parse_size(v) }
      end
      o.pixel_art = confirm(input, output, "Pixel-art filtering (crisp, unsmoothed textures)?", false) if o.pixel_art.nil?
      o.web = confirm(input, output, "Set up web export (embed assets into the build)?", true) if o.web.nil?
      o.git = confirm(input, output, "Initialise a git repository?", true) if o.git.nil?
      o.ci = confirm(input, output, "Add a GitHub Actions CI workflow?", o.local.nil?) if o.ci.nil?
      o.resolve_defaults
    end

    private def ask(input : IO, output : IO, question : String, default : String, & : String -> T) : T forall T
      loop do
        output.print "#{question} [#{default}]: "
        output.flush
        line = input.gets
        v = line.nil? || line.strip.empty? ? default : line.strip
        begin
          return yield v
        rescue e : InitError
          raise e if line.nil? # end of input: don't loop forever
          output.puts "  #{e.message}"
        end
      end
    end

    private def confirm(input : IO, output : IO, question : String, default : Bool) : Bool
      ask(input, output, question, default ? "Y/n" : "y/N") do |v|
        case v.downcase
        when "y/n" then default
        when "y", "yes" then true
        when "n", "no" then false
        else raise InitError.new("answer y or n")
        end
      end
    end

    # The project's files as relative path => contents.
    def files(o : InitOptions) : Hash(String, String | Bytes)
      o.resolve_defaults
      f = {} of String => String | Bytes
      f["shard.yml"] = shard_yml(o)
      f["src/main.cr"] = main_cr(o)
      f["src/#{o.file_name}.cr"] = game_cr(o)
      f["spec/spec_helper.cr"] = "require \"spec\"\nrequire \"../src/#{o.file_name}\"\n"
      f["spec/#{o.file_name}_spec.cr"] = spec_cr(o)
      f["assets/icon.png"] = icon_png
      f[".gitignore"] = "/bin/\n/lib/\n/.shards/\n/dist/\n*.dwarf\n*.pdb\n.DS_Store\n"
      f["README.md"] = readme(o)
      f[".github/workflows/ci.yml"] = ci_yml(o) if o.ci?
      f
    end

    # Writes the project to disk. Refuses to overwrite any existing file.
    def generate(o : InitOptions) : String
      InitOptions.validate_name(o.name!)
      dir = o.target_dir
      all = files(o)
      clash = all.keys.select { |p| File.exists?(File.join(dir, p)) }
      raise InitError.new("#{dir} already has #{clash.join(", ")}; not overwriting") unless clash.empty?
      all.each do |path, data|
        full = File.join(dir, path)
        Dir.mkdir_p(File.dirname(full))
        File.write(full, data)
      end
      dir
    end

    def shard_yml(o : InitOptions) : String
      dep = o.local ? "path: #{o.local}" : "github: joeyrobert/eagle.cr"
      <<-YML
        name: #{o.shard_name}
        version: 0.1.0
        crystal: ">= 1.21.0"

        dependencies:
          eagle:
            #{dep}

        targets:
          #{o.shard_name}:
            main: src/main.cr

        YML
    end

    def main_cr(o : InitOptions) : String
      String.build do |s|
        s << "require \"./#{o.file_name}\"\n\n"
        if o.web?
          s << "# Bake assets/ into the executable: web builds can't read the disk, and desktop builds ship as one file.\n"
          s << "Eagle.embed_assets(\"assets\")\n"
        end
        s << "Texture.default_filter = GPU::Filter::Nearest # pixel art: keep pixels crisp when scaled\n" if o.pixel_art?
        s << "\n" if o.web? || o.pixel_art?
        s << "Eagle.run(#{o.module_name}::Game, title: #{o.title.inspect}, width: #{o.width!}, height: #{o.height!})\n"
      end
    end

    # The game code, kept out of main.cr so specs can require it without opening a window.
    def game_cr(o : InitOptions) : String
      m = o.module_name
      case o.template!
      when "2d-game"
        <<-CR
          require "eagle"
          include Eagle

          module #{m}
            SPEED = 250

            # Moves *pos* along *dir* for *dt* seconds, staying inside *bounds*. Pure logic, so it is easy to spec.
            def self.step(pos : Vec2, dir : Vec2, dt : Float32, bounds : Vec2) : Vec2
              p = pos + dir * SPEED * dt
              v2(p.x.clamp(0_f32, bounds.x), p.y.clamp(0_f32, bounds.y))
            end

            class Game < App
              @player = Sprite2D.new(Texture.load("res://icon.png"), Window.center)

              def load
                Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
                Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
                Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
                Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
                SceneTree.root.add(@player)
              end

              def update(dt : Float32)
                @player.position = #{m}.step(@player.position, Input.vector("left", "right", "up", "down"), dt, Window.size)
                Eagle.quit if Input.pressed?(Key::Escape)
              end

              def draw(g : Graphics)
                g.print("#{o.title}: move with WASD or the arrow keys  fps \#{Clock.fps.round}", 10, 10)
              end
            end
          end

          CR
      when "3d-game"
        <<-CR
          require "eagle"
          include Eagle

          module #{m}
            SPEED = 4
            ARENA = 9 # half-width of the floor, in meters

            # Moves *pos* on the floor plane along *input* (x = right, y = down) for *dt* seconds, staying on the floor.
            def self.step(pos : Vec3, input : Vec2, dt : Float32) : Vec3
              p = pos + v3(input.x, 0, input.y) * SPEED * dt
              v3(p.x.clamp(-ARENA.to_f32, ARENA.to_f32), p.y, p.z.clamp(-ARENA.to_f32, ARENA.to_f32))
            end

            class Game < App
              @cam = Camera3D.new(position: v3(0, 6, 10))
              @player = MeshInstance3D.new(Mesh.cube, Material.new(Color.hex("#f4b400"), shininess: 48, specular: 0.4), position: v3(0, 0.5, 0))

              def load
                Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
                Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
                Input.map "up", Key::W, Key::Up, Input.axis(GamepadAxis::LeftY, -1)
                Input.map "down", Key::S, Key::Down, Input.axis(GamepadAxis::LeftY, 1)
                Scene3D.environment.shadows = true
                floor = MeshInstance3D.new(Mesh.plane(ARENA * 2, ARENA * 2), Material.new(Color.hex("#5b6b7a"), specular: 0.05))
                SceneTree.root.add(floor, @player, DirectionalLight3D.new(v3(-0.5, -1, -0.3)), @cam)
              end

              def update(dt : Float32)
                @player.position = #{m}.step(@player.position, Input.vector("left", "right", "up", "down"), dt)
                @player.rotation = Quat.from_axis_angle(Vec3::UP, Clock.elapsed)
                @cam.position = @player.position + v3(0, 6, 10)
                @cam.look_at(@player.position)
                Eagle.quit if Input.pressed?(Key::Escape)
              end

              def draw(g : Graphics)
                g.print("#{o.title}: move with WASD or the arrow keys  fps \#{Clock.fps.round}", 10, 10)
              end
            end
          end

          CR
      when "ui-app"
        <<-CR
          require "eagle"
          include Eagle

          module #{m}
            # The status line for *clicks* button presses. Pure logic, so it is easy to spec.
            def self.status(clicks : Int32) : String
              clicks == 0 ? "Not clicked yet" : "Clicked \#{clicks} time\#{clicks == 1 ? "" : "s"}"
            end

            class Game < App
              @clicks = 0
              @status = Label.new(#{m}.status(0))

              def load
                layer = CanvasLayer.new
                panel = Panel.new(size: v2(360, 0))
                panel.anchor = Anchor::Center
                panel.fit_content = true
                box = VBox.new(size: v2(340, 0))
                box.position = v2(10, 10)
                box.fit_content = true
                box.add(Label.new("#{o.title}", align: TextAlign::Center))
                box.add(ImageControl.new(Texture.load("res://icon.png")))
                box.add(Button.new("Click me") { @clicks += 1; @status.text = #{m}.status(@clicks) })
                volume = Label.new("Volume 50%")
                slider = Slider.new(0, 100, 50, step: 1)
                slider.on_value_changed { |v| volume.text = "Volume \#{v.to_i}%" }
                box.add(volume, slider, @status)
                panel.add(box)
                layer.add(panel)
                SceneTree.root.add(layer)
              end

              def update(dt : Float32)
                Eagle.quit if Input.pressed?(Key::Escape)
              end
            end
          end

          CR
      else
        <<-CR
          require "eagle"
          include Eagle

          module #{m}
            TITLE = #{o.title.inspect}

            class Game < App
              def load
              end

              def update(dt : Float32)
              end

              def draw(g : Graphics)
                g.print("Hello from \#{TITLE}!", 10, 10)
              end
            end
          end

          CR
      end
    end

    def spec_cr(o : InitOptions) : String
      m = o.module_name
      body = case o.template!
             when "2d-game"
               <<-CR
                   it "moves the player and keeps it on screen" do
                     #{m}.step(v2(100, 100), v2(1, 0), 1_f32, v2(960, 540)).should eq v2(100 + #{m}::SPEED, 100)
                     #{m}.step(v2(10, 10), v2(-1, -1), 1_f32, v2(960, 540)).should eq v2(0, 0)
                   end
                 CR
             when "3d-game"
               <<-CR
                   it "moves the player on the floor and keeps it in the arena" do
                     #{m}.step(v3(0, 0.5, 0), v2(0, 1), 0.5_f32).should eq v3(0, 0.5, #{m}::SPEED * 0.5)
                     #{m}.step(v3(0, 0.5, 0), v2(1, 0), 100_f32).x.should eq #{m}::ARENA
                   end
                 CR
             when "ui-app"
               <<-CR
                   it "describes the click count" do
                     #{m}.status(0).should eq "Not clicked yet"
                     #{m}.status(1).should eq "Clicked 1 time"
                     #{m}.status(3).should eq "Clicked 3 times"
                   end
                 CR
             else
               <<-CR
                   it "has a title" do
                     #{m}::TITLE.should eq #{o.title.inspect}
                   end
                 CR
             end
      "require \"./spec_helper\"\n\ndescribe #{m} do\n#{body}\nend\n"
    end

    # A 64x64 placeholder sprite, encoded with Eagle's own PNG writer.
    def icon_png : Bytes
      img = Image.new(64, 64)
      img.blit(Image.circle(64, Color.hex("#f4b400")), 0, 0)
      img.blit(Image.circle(16, Color.hex("#1b1f27")), 36, 16, blend: true)
      Codecs::PNG.encode(img)
    end

    def readme(o : InitOptions) : String
      n = o.shard_name
      web = o.web? ? <<-MD
        ### Web

        `src/main.cr` calls `Eagle.embed_assets("assets")`, so the same code runs in the browser:

        ```sh
        eagle export web            # dist/web/#{n}/: index.html + eagle.js + #{n}.wasm
        cd dist/web/#{n} && python3 -m http.server
        ```

        Web builds need `lld` (`brew install lld`, `apt install lld`).
        MD
      : <<-MD
        ### Assets

        Assets load from `assets/` at runtime (`res://icon.png`). Ship the `assets/` folder
        next to the executable, or add `Eagle.embed_assets("assets")` to `src/main.cr` to bake
        them in (required for `eagle export web`).
        MD
      <<-MD
        # #{o.title}

        A game made with [Eagle](https://github.com/joeyrobert/eagle.cr).

        ## Setup

        Install Crystal (>= 1.21) and SDL2 (`brew install crystal sdl2`,
        `apt install libsdl2-dev`), then:

        ```sh
        shards install
        ```

        ## Commands

        | Command | What it does |
        |---------|--------------|
        | `eagle run` | build and run in debug mode |
        | `eagle build` | release executable in `bin/#{n}` |
        | `crystal spec` | run the specs in `spec/` |
        | `eagle export exe` | release build into `dist/#{n}/` |
        | `eagle export web` | WebAssembly bundle into `dist/web/#{n}/` |
        | `eagle export app` | macOS app bundle `dist/#{n}.app` |

        Without the eagle CLI, plain Crystal works too:

        ```sh
        crystal run src/main.cr                         # run
        crystal build src/main.cr --release -o bin/#{n}  # release build
        shards build --release                          # same, via the shard.yml target
        ```

        Automated runs (CI, screenshots): `EAGLE_FRAMES=60 EAGLE_SCREENSHOT=shot.png EAGLE_HEADLESS=1 bin/#{n}`.

        #{web}

        ## Layout

        * `src/main.cr`: entry point; opens the window
        * `src/#{o.file_name}.cr`: the game
        * `spec/`: specs (`crystal spec`)
        * `assets/`: images, sounds, fonts (loaded with `res://` paths)

        MD
    end

    def ci_yml(o : InitOptions) : String
      <<-YML
        # Builds the game and runs its specs on every push and pull request.
        name: CI
        on:
          push:
          pull_request:

        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: crystal-lang/install-crystal@v1
                with:
                  crystal: latest
              - name: Install SDL2
                run: sudo apt-get update && sudo apt-get install -y libsdl2-dev
              - name: Install shards
                run: shards install
              - name: Specs
                run: crystal spec
              - name: Release build
                run: shards build --release

        YML
    end
  end
end
