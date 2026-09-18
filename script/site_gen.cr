# Generates the marketing + docs site into site/ (run via script/build-site.sh).
require "html"

ROOT = File.expand_path("..", __DIR__)
SITE = File.join(ROOT, "site")
VERSION = File.read(File.join(ROOT, "src/eagle/version.cr")).match(/VERSION = "([^"]+)"/).not_nil![1]

EXAMPLES = {
  "chess" => {"Chess", "Full rules with castling, en passant, promotion; perft-verified move generator and an alpha-beta AI.", "Click a piece, then a square. U undo · R restart · N toggle AI · 1-4 AI depth"},
  "checkers" => {"Checkers", "One or two players, forced captures, multi-jumps, kings and a quiescence-searching AI.", "Pick a mode, then click pieces. U undo · R restart · M menu"},
  "breakout" => {"Breakout", "Paddle, ball, bricks with hit points, particles, camera shake and synthesized sounds.", "Mouse or arrows move · Space launches"},
  "asteroids" => {"Asteroids", "Vector ship, splitting rocks, wrap-around space and thruster particles.", "A/D rotate · W thrust · Space fire"},
  "platformer" => {"Platformer", "ASCII level to TileMap + colliders, coyote time, jump buffering, enemies you can stomp, coins and a goal.", "Arrows/WASD move · Space jump · R restart"},
  "snake" => {"Snake", "Grid logic with a unit-tested core and speed that ramps as you eat.", "Arrows/WASD · Space restarts"},
  "roguelike" => {"Roguelike", "Procedural dungeons, shadowcasting field of view, monsters that chase, items, five levels.", "Arrows/WASD/hjkl move · Space wait · Enter descends on > · R restart"},
  "coinrush3d" => {"Coin Rush (3D)", "Roll a ball around a lit, shadowed arena collecting coins before the timer runs out.", "WASD move · Space jump · right-drag orbits the camera"},
  "flythrough3d" => {"3D fly-through", "Every 3D feature: primitives, textures, lights, shadows, fog, transparency, wireframe, picking.", "WASD/QE move · right-drag look · F wireframe · click to pick"},
  "physics" => {"2D physics", "Rigid bodies, stacking, ramps, sensors and additive particle bursts.", "Click to spawn bodies"},
  "physics3d" => {"3D physics", "Spheres and boxes with SAT contacts, stacking pyramid, kinematic ramp.", "Click fires spheres · Space throws a box · R resets"},
  "ui" => {"UI toolkit", "Panels, buttons, sliders, checkboxes, text input, grids and themes.", "Click around; Tab cycles focus"},
  "interactions" => {"Interactions", "Every input pattern with a live event log: clicks, drags, wheel zoom, text, gamepads, signals, timers.", "Try everything; the log on the right narrates"},
  "sandbox2d" => {"2D sandbox", "Scene tree, tile map, following camera with shake, tweens and a HUD layer.", "WASD moves the player"},
  "embedded" => {"Embedded assets", "A game whose PNG, WAV and shader are baked into the binary at compile time.", "Nothing to press — it just works with no files"},
  "smoke" => {"Smoke test", "Shapes, sprites, lines and text: the first thing Eagle ever rendered.", ""},
}

def md_inline(s : String) : String
  s = HTML.escape(s)
  s = s.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }
  s = s.gsub(/\*\*([^*]+)\*\*/) { "<strong>#{$1}</strong>" }
  s = s.gsub(/(?<![\w*])\*([^*]+)\*(?!\w)/) { "<em>#{$1}</em>" }
  s = s.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "<a href=\"#{$2}\">#{$1}</a>" }
  s
end

# Minimal Markdown -> HTML (headings, fences, lists, tables, quotes, paragraphs).
def markdown(src : String) : String
  out = String::Builder.new
  lines = src.lines
  i = 0
  para = [] of String
  flush = ->{ unless para.empty?; out << "<p>" << md_inline(para.join(" ")) << "</p>\n"; para.clear; end }
  while i < lines.size
    line = lines[i]
    if line.starts_with?("```")
      flush.call
      lang = line[3..].strip
      code = [] of String
      i += 1
      while i < lines.size && !lines[i].starts_with?("```")
        code << lines[i]; i += 1
      end
      out << "<pre><code class=\"lang-#{lang}\">" << HTML.escape(code.join("\n")) << "</code></pre>\n"
    elsif (m = line.match(/^(\#{1,4})\s+(.*)/))
      flush.call
      level = m[1].size
      id = m[2].downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
      out << "<h#{level} id=\"#{id}\">" << md_inline(m[2]) << "</h#{level}>\n"
    elsif line.starts_with?("|")
      flush.call
      rows = [] of String
      while i < lines.size && lines[i].starts_with?("|")
        rows << lines[i]; i += 1
      end
      i -= 1
      out << "<table>"
      rows.each_with_index do |r, ri|
        next if r =~ /^\|\s*-/
        cells = r.strip.strip('|').split('|').map(&.strip)
        tag = ri == 0 ? "th" : "td"
        out << "<tr>" << cells.map { |c| "<#{tag}>#{md_inline(c)}</#{tag}>" }.join << "</tr>"
      end
      out << "</table>\n"
    elsif line =~ /^\s*[-*]\s+/ || line =~ /^\s*\d+\.\s+/
      flush.call
      ordered = line =~ /^\s*\d+\./
      out << (ordered ? "<ol>" : "<ul>")
      while i < lines.size && (lines[i] =~ /^\s*[-*]\s+/ || lines[i] =~ /^\s*\d+\.\s+/)
        out << "<li>" << md_inline(lines[i].sub(/^\s*([-*]|\d+\.)\s+/, "")) << "</li>"
        i += 1
      end
      i -= 1
      out << (ordered ? "</ol>\n" : "</ul>\n")
    elsif line.starts_with?(">")
      flush.call
      out << "<blockquote>" << md_inline(line.lchop(">").strip) << "</blockquote>\n"
    elsif line.strip == "---"
      flush.call
      out << "<hr>\n"
    elsif line.strip.empty?
      flush.call
    else
      para << line.strip
    end
    i += 1
  end
  flush.call
  out.to_s
end

def page(title : String, body : String, depth : Int32 = 0, active : String = "") : String
  rel = "../" * depth
  nav = [{"Home", "index.html", "home"}, {"Play", "play/index.html", "play"}, {"Guide", "docs/guide.html", "guide"}, {"API", "docs/api/index.html", "api"}, {"GitHub", "https://github.com/joeyrobert/eagle.cr", "gh"}]
  links = nav.map { |(n, h, k)| "<a href=\"#{h.starts_with?("http") ? h : rel + h}\"#{k == active ? " class=\"active\"" : ""}>#{n}</a>" }.join
  <<-HTML
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <title>#{HTML.escape(title)} · Eagle</title>
  <link rel="stylesheet" href="#{rel}assets/site.css">
  <link rel="icon" href="#{rel}assets/favicon.svg"></head>
  <body><header class="top"><a class="brand" href="#{rel}index.html"><img src="#{rel}assets/favicon.svg" alt=""> Eagle <span class="ver">v#{VERSION}</span></a><nav>#{links}</nav></header>
  <main>#{body}</main>
  <footer>Eagle is MIT licensed · built with Crystal · <a href="https://github.com/joeyrobert/eagle.cr">source on GitHub</a></footer>
  </body></html>
  HTML
end

CSS = <<-CSS
:root{--bg:#0f1117;--bg2:#161a24;--panel:#1c2130;--line:#2a3142;--text:#e6e8ef;--muted:#9aa3b5;--accent:#5e9cff;--accent2:#ffd166;--radius:14px}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
header.top{position:sticky;top:0;z-index:5;display:flex;align-items:center;justify-content:space-between;padding:12px 28px;background:rgba(15,17,23,.85);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;color:var(--text);font-size:18px}.brand img{width:28px;height:28px}.ver{color:var(--muted);font-weight:400;font-size:13px}
nav a{margin-left:22px;color:var(--muted);font-weight:500}nav a.active,nav a:hover{color:var(--text);text-decoration:none}
main{max-width:1120px;margin:0 auto;padding:32px 24px}
.hero{padding:70px 0 40px;display:grid;grid-template-columns:1.1fr 1fr;gap:40px;align-items:center}
.hero h1{font-size:52px;line-height:1.05;margin:0 0 18px;letter-spacing:-.02em}.hero h1 span{background:linear-gradient(90deg,#5e9cff,#9b6bff);-webkit-background-clip:text;background-clip:text;color:transparent}
.hero p.lead{font-size:20px;color:var(--muted);margin:0 0 26px}
.btn{display:inline-block;padding:12px 20px;border-radius:10px;font-weight:600;background:var(--accent);color:#fff;margin-right:12px}.btn.alt{background:var(--panel);border:1px solid var(--line);color:var(--text)}.btn:hover{text-decoration:none;filter:brightness(1.1)}
.hero img{width:100%;border-radius:var(--radius);border:1px solid var(--line);box-shadow:0 20px 60px rgba(0,0,0,.5)}
h2.section{font-size:30px;margin:60px 0 18px;letter-spacing:-.01em}h2.section small{display:block;font-size:16px;color:var(--muted);font-weight:400;margin-top:4px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:18px}.card h3{margin:0 0 8px;font-size:17px}.card p{margin:0;color:var(--muted);font-size:14px}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:14px}
.shots figure{margin:0;background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);overflow:hidden}.shots img{width:100%;display:block;aspect-ratio:16/10;object-fit:cover}.shots figcaption{padding:10px 14px;font-size:14px;color:var(--muted)}.shots figcaption b{color:var(--text)}
pre{background:#0b0d13;border:1px solid var(--line);border-radius:12px;padding:16px 18px;overflow:auto;font:13.5px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;background:#0b0d13;padding:1px 6px;border-radius:6px;font-size:.92em}pre code{padding:0;background:none}
.tabs{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px}.tabs button{background:var(--panel);border:1px solid var(--line);color:var(--muted);padding:8px 14px;border-radius:8px;cursor:pointer;font-weight:600}.tabs button.on{color:var(--text);border-color:var(--accent)}
.tabpane{display:none}.tabpane.on{display:block}
.api-list{columns:3;column-gap:24px;font-size:14px}.api-list li{break-inside:avoid;margin:0 0 4px}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:15px}th,td{border:1px solid var(--line);padding:8px 10px;text-align:left}th{background:var(--panel)}
.doc{max-width:860px}.doc h1{font-size:40px;letter-spacing:-.02em}.doc h2{margin-top:44px;border-bottom:1px solid var(--line);padding-bottom:6px}.doc h3{margin-top:28px}
.play-wrap{display:flex;flex-direction:column;align-items:center;gap:12px}.play-wrap canvas{max-width:100%;border-radius:10px;border:1px solid var(--line)}.controls{color:var(--muted);font-size:14px}
details{margin-top:24px}summary{cursor:pointer;font-weight:600}
footer{text-align:center;color:var(--muted);padding:40px 20px;border-top:1px solid var(--line);font-size:14px}
@media(max-width:800px){.hero{grid-template-columns:1fr;padding-top:30px}.hero h1{font-size:38px}.api-list{columns:1}nav a{margin-left:14px}}
CSS

FAVICON = <<-SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#5e9cff"/><stop offset="1" stop-color="#9b6bff"/></linearGradient></defs><rect width="64" height="64" rx="14" fill="url(#g)"/><path d="M14 40 L30 18 L38 30 L46 22 L52 40 L40 36 L30 46 Z" fill="#fff"/><circle cx="33" cy="26" r="2.4" fill="#0f1117"/></svg>
SVG

CODE_SAMPLES = {
  "Hello, sprite" => <<-CR,
  require "eagle"
  include Eagle

  class Game < App
    @player = Sprite2D.new(Texture.load("res://player.png"), Window.center)

    def load
      Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
      Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
      SceneTree.root.add(@player)
    end

    def update(dt : Float32)
      @player.x += Input.axis("left", "right") * 250 * dt
    end

    def draw(g : Graphics)
      g.print("score \#{@score}", 10, 10)
    end
  end

  Eagle.run(Game, title: "My Game", width: 960, height: 540)
  CR
  "Scene tree & signals" => <<-CR,
  class Enemy < Area2D
    signal died(points : Int32)

    def initialize(pos : Vec2)
      super("Enemy", pos)
      circle(12)
      add(AnimatedSprite2D.new.tap { |s| s.add_animation("idle", sheet.frames(32, 32), fps: 8) })
      on_body_entered { |other| hit if other.is_a?(Bullet) }
    end

    def hit
      emit_died(100)
      Tween.value(1.0, 0.0, 0.2) { |a| modulate = Color::WHITE.with_alpha(a) }.on_complete { queue_free }
    end
  end

  enemy = Enemy.new(v2(300, 200))
  enemy.on_died { |points| @score += points; Sounds.explode.play }
  SceneTree.root.add(enemy)
  CR
  "2D physics" => <<-CR,
  ground = StaticBody2D.new(position: v2(400, 580)).box(800, 40)
  ball   = RigidBody2D.new(position: v2(400, 0)).circle(16)
  ball.restitution = 0.6
  ball.on_body_entered { |other| Sounds.bounce.play }

  player = KinematicBody2D.new(position: v2(100, 100)).box(24, 40)

  def physics_process(dt : Float32)
    player.velocity += v2(0, 1400 * dt)                    # gravity
    player.velocity = v2(Input.axis("left", "right") * 220, player.velocity.y)
    player.velocity = v2(player.velocity.x, -520) if Input.pressed?("jump") && player.on_floor?
    player.move_and_slide(dt)
  end

  hit = Physics2D.world.raycast(player.position, v2(1, 0), 200)
  CR
  "3D scene" => <<-CR,
  root = SceneTree.root
  root.add(Camera3D.new(position: v3(0, 3, 8)).tap(&.look_at(Vec3::ZERO)))
  root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.3)))          # casts PCF shadows
  root.add(MeshInstance3D.new(Mesh.plane(40, 40), Material.new(texture: Texture.load("res://grass.png"))))
  crate = MeshInstance3D.new(Mesh.cube, Material.new(Color::ORANGE, shininess: 48), position: v3(0, 0.5, 0))
  root.add(crate)

  Scene3D.environment.fog(20, 80)
  Scene3D.environment.sky_colors(Color.hex("#3b6fd6"), Color.hex("#b9d4f5"), Color.hex("#3a3a44"))

  # picking
  if (hit = cam.mouse_ray.intersect_aabb(crate.global_bounds.not_nil!))
    crate.material.albedo = Color::RED
  end
  CR
  "UI" => <<-CR,
  hud = CanvasLayer.new
  panel = Panel.new(size: v2(320, 0)).tap { |p| p.anchor = Anchor::Center; p.fit_content = true }
  box = VBox.new(size: v2(300, 0)).tap { |b| b.position = v2(10, 10); b.fit_content = true }
  box.add(Label.new("Settings"),
          Slider.new(0, 100, 50).tap { |s| s.on_value_changed { |v| Audio.volume = v / 100 } },
          CheckBox.new("Fullscreen", false).tap { |c| c.on_toggled { |on| Window.fullscreen = on } },
          TextInput.new("", "player name").tap { |t| t.on_submitted { |name| save(name) } },
          Button.new("Start") { SceneTree.change_scene(Level.new) })
  panel.add(box); hud.add(panel); SceneTree.root.add(hud)
  Theme.default.font = Font.load("res://Inter.ttf", 18)
  CR
  "Shaders & canvases" => <<-CR,
  glow = Shader.effect(<<-GLSL)
    uniform float u_strength;
    vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen) {
      vec4 c = texture(tex, uv);
      float pulse = 0.5 + 0.5 * sin(u_time * 4.0);
      return c * color + c.a * pulse * u_strength;
    }
    GLSL

  canvas = Canvas.new(320, 180)              # low-res render target
  g.with_canvas(canvas) { draw_world(g) }
  g.with_shader(glow) { glow["u_strength"] = 0.3; g.draw(canvas, Rect.new(0, 0, Window.width, Window.height)) }
  CR
}

API_GROUPS = {
  "Core" => %w(Eagle::App Eagle::Config Eagle::Clock Eagle::Node Eagle::Node2D Eagle::Node3D Eagle::SceneTree Eagle::Emitter Eagle::Tween Eagle::Ease Eagle::Script Eagle::Window Eagle::Input),
  "2D" => %w(Eagle::Graphics Eagle::Texture Eagle::TextureRegion Eagle::Canvas Eagle::Shader Eagle::Font Eagle::TrueTypeFont Eagle::Camera2D Eagle::Sprite2D Eagle::AnimatedSprite2D Eagle::TileMap Eagle::Particles2D Eagle::Polygon2D Eagle::Line2D Eagle::CanvasLayer Eagle::Timer),
  "Physics" => %w(Eagle::Physics2D::World Eagle::Physics2D::Body Eagle::RigidBody2D Eagle::StaticBody2D Eagle::KinematicBody2D Eagle::Area2D Eagle::RayCast2D Eagle::Physics3D::World Eagle::RigidBody3D Eagle::KinematicBody3D Eagle::Area3D),
  "3D" => %w(Eagle::Mesh Eagle::Material Eagle::Renderer3D Eagle::Environment Eagle::Camera3D Eagle::MeshInstance3D Eagle::DirectionalLight3D Eagle::PointLight3D Eagle::SpotLight3D Eagle::Scene3D),
  "UI" => %w(Eagle::Control Eagle::Panel Eagle::Label Eagle::Button Eagle::CheckBox Eagle::Slider Eagle::ProgressBar Eagle::TextInput Eagle::VBox Eagle::HBox Eagle::GridContainer Eagle::Theme),
  "Audio & assets" => %w(Eagle::Audio Eagle::Sound Eagle::Voice Eagle::AudioPlayer Eagle::AudioPlayer2D Eagle::Assets Eagle::Image Eagle::Codecs::PNG Eagle::Codecs::Vorbis Eagle::Codecs::Zlib),
  "Math" => %w(Eagle::Vec2 Eagle::Vec3 Eagle::Vec4 Eagle::Mat4 Eagle::Quat Eagle::Rect Eagle::AABB Eagle::Ray Eagle::Color Eagle::Transform2D Eagle::Mathf),
}

def api_href(name : String) : String
  "docs/api/#{name.gsub("::", "/")}.html"
end

# ---- build ---------------------------------------------------------------------
Dir.mkdir_p(File.join(SITE, "assets/screenshots"))
Dir.mkdir_p(File.join(SITE, "docs"))
Dir.mkdir_p(File.join(SITE, "play"))
File.write(File.join(SITE, "assets/site.css"), CSS)
File.write(File.join(SITE, "assets/favicon.svg"), FAVICON)
Dir.glob(File.join(ROOT, "screenshots/*.png")).each do |f|
  next if File.basename(f).starts_with?("web_") || File.basename(f).starts_with?("view_") || File.basename(f).starts_with?("dbg")
  File.copy(f, File.join(SITE, "assets/screenshots", File.basename(f)))
end

# marketing page
shots = %w(flythrough3d coinrush3d chess platformer physics3d roguelike ui interactions asteroids breakout physics checkers).select { |n| File.exists?(File.join(SITE, "assets/screenshots/#{n}.png")) }
gallery = shots.map do |n|
  t, d, _ = EXAMPLES[n]
  "<figure><a href=\"play/#{n}/index.html\"><img src=\"assets/screenshots/#{n}.png\" alt=\"#{t}\"></a><figcaption><b>#{t}</b> — #{d}</figcaption></figure>"
end.join
tabs = CODE_SAMPLES.keys.map_with_index { |k, i| "<button class=\"#{i == 0 ? "on" : ""}\" data-tab=\"#{i}\">#{k}</button>" }.join
panes = CODE_SAMPLES.values.map_with_index { |code, i| "<div class=\"tabpane #{i == 0 ? "on" : ""}\" data-pane=\"#{i}\"><pre><code class=\"lang-crystal\">#{HTML.escape(code)}</code></pre></div>" }.join
api = API_GROUPS.map { |group, names| "<h3>#{group}</h3><ul class=\"api-list\">" + names.map { |n| "<li><a href=\"#{api_href(n)}\"><code>#{n}</code></a></li>" }.join + "</ul>" }.join
features = [
  {"Crystal all the way down", "PNG/QOI/BMP, WAV and Ogg Vorbis codecs, zlib, TrueType rasteriser, audio mixer, physics, particles, UI, 3D renderer — all Crystal. Only SDL2 and OpenGL underneath."},
  {"Easy things easy", "A LÖVE-style <code>load / update / draw</code> loop, immediate-mode drawing and a Godot-style node tree with signals. Pick either or mix."},
  {"2D and 3D", "Batched sprites, cameras, tile maps and particles; meshes, materials, lights, PCF shadows, fog and a procedural sky."},
  {"Physics that stacks", "2D SAT with clipped manifolds and 3D oriented boxes/spheres, kinematic characters with <code>move_and_slide</code>, raycasts and sensors."},
  {"Runs in the browser", "Compile to WebAssembly + WebGL2 with one command. Same code, same rendering, embedded assets."},
  {"Ships as one file", "<code>eagle export exe</code> bakes assets into a single executable; <code>eagle export web</code> makes a static bundle; macOS <code>.app</code> too."},
  {"Tested end to end", "220+ specs including GPU pixel tests, perft-verified chess, bit-exact Vorbis decoding, and integration specs that drive the real frame loop with injected input."},
  {"Tools included", "An <code>eagle</code> CLI with project scaffolding, viewers for images, OBJ, TTF, WAV and hot-reloading GLSL, screenshot/frame-limited runs for CI."},
]
feature_cards = features.map { |(t, d)| "<div class=\"card\"><h3>#{t}</h3><p>#{d}</p></div>" }.join
home = <<-HTML
<section class="hero"><div>
<h1>The <span>Crystal-native</span> game engine</h1>
<p class="lead">2D and 3D games in Crystal with a node tree, signals, physics, audio, UI and a WebAssembly target. A library, an engine and a viewer that compile to one executable.</p>
<a class="btn" href="play/index.html">Play the examples</a><a class="btn alt" href="docs/guide.html">Read the guide</a>
<p style="margin-top:22px"><code>brew install sdl2 && git clone https://github.com/joeyrobert/eagle.cr && cd eagle.cr && shards build && bin/eagle examples asteroids</code></p>
</div><div><a href="play/flythrough3d/index.html"><img src="assets/screenshots/flythrough3d.png" alt="Eagle 3D fly-through"></a></div></section>
<h2 class="section">What's in the box <small>Everything below is implemented in Crystal and covered by specs.</small></h2>
<div class="grid">#{feature_cards}</div>
<h2 class="section">Screenshots <small>Every one is a playable example; click to run it in your browser.</small></h2>
<div class="shots">#{gallery}</div>
<h2 class="section">Code <small>Easy things are easy, hard things are possible.</small></h2>
<div class="tabs">#{tabs}</div>#{panes}
<h2 class="section">API reference <small>Generated from the source with <code>crystal docs</code>; every public class and method.</small></h2>
#{api}
<p><a class="btn" href="docs/api/index.html">Browse the full API</a><a class="btn alt" href="docs/guide.html">Guide</a><a class="btn alt" href="docs/architecture.html">Architecture</a></p>
<script>
document.querySelectorAll('.tabs button').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.tabs button').forEach(x=>x.classList.remove('on'));document.querySelectorAll('.tabpane').forEach(x=>x.classList.remove('on'));b.classList.add('on');document.querySelector('.tabpane[data-pane="'+b.dataset.tab+'"]').classList.add('on');}));
</script>
HTML
File.write(File.join(SITE, "index.html"), page("Eagle — Crystal game engine", home, 0, "home"))

# docs pages from markdown
docs = {"guide" => File.join(ROOT, "docs/guide.md"), "architecture" => File.join(ROOT, "docs/plans/000-vision-and-architecture.md"), "roadmap" => File.join(ROOT, "docs/plans/010-roadmap.md"), "readme" => File.join(ROOT, "README.md")}
docs.each do |name, path|
  body = "<article class=\"doc\">" + markdown(File.read(path)) + "</article>"
  File.write(File.join(SITE, "docs/#{name}.html"), page(name.capitalize, body, 1, name == "guide" ? "guide" : ""))
end
doc_index = <<-HTML
<article class="doc"><h1>Documentation</h1>
<ul>
<li><a href="guide.html">Guide</a> — the loop, drawing styles, assets, input, signals, physics, UI, 3D, automation, backends.</li>
<li><a href="api/index.html">API reference</a> — every public type and method, generated from source.</li>
<li><a href="../play/index.html">Playable examples</a> — all example games compiled to WebAssembly, with source.</li>
<li><a href="architecture.html">Architecture</a> — layers, backends, key decisions.</li>
<li><a href="roadmap.html">Roadmap & findings</a> — what's done, what's known to be missing.</li>
<li><a href="readme.html">README</a></li>
</ul></article>
HTML
File.write(File.join(SITE, "docs/index.html"), page("Docs", doc_index, 1, "guide"))

# play pages
built = EXAMPLES.keys.select { |n| File.exists?(File.join(ROOT, "dist/web/#{n}/#{n}.wasm")) }
cards = EXAMPLES.select { |n, _| built.includes?(n) }.map do |n, (t, d, _)|
  shot = File.exists?(File.join(SITE, "assets/screenshots/#{n}.png")) ? "<img src=\"../assets/screenshots/#{n}.png\" alt=\"#{t}\">" : ""
  "<figure><a href=\"#{n}/index.html\">#{shot}</a><figcaption><b><a href=\"#{n}/index.html\">#{t}</a></b> — #{d}</figcaption></figure>"
end.join
File.write(File.join(SITE, "play/index.html"), page("Play", "<h1>Playable examples</h1><p class=\"lead\">Every example compiled to WebAssembly + WebGL2 from the same Crystal source that runs natively. Click a canvas to focus it; sound starts after the first click.</p><div class=\"shots\">#{cards}</div>", 1, "play"))
built.each do |n|
  t, d, controls = EXAMPLES[n]
  dir = File.join(SITE, "play", n)
  Dir.mkdir_p(dir)
  File.copy(File.join(ROOT, "dist/web/#{n}/#{n}.wasm"), File.join(dir, "#{n}.wasm"))
  File.copy(File.join(ROOT, "web/eagle.js"), File.join(dir, "eagle.js"))
  src = File.read(File.join(ROOT, "examples/#{n}/main.cr"))
  extra = Dir.glob(File.join(ROOT, "examples/#{n}/*.cr")).reject { |f| f.ends_with?("main.cr") }.map { |f| "<h3>#{File.basename(f)}</h3><pre><code>#{HTML.escape(File.read(f))}</code></pre>" }.join
  body = <<-HTML
  <div class="play-wrap"><h1>#{t}</h1><p class="lead">#{d}</p><canvas id="eagle"></canvas><p class="controls">#{controls}</p>
  <details><summary>Source — examples/#{n}/main.cr</summary><pre><code class="lang-crystal">#{HTML.escape(src)}</code></pre>#{extra}</details></div>
  <script type="module">import { runEagle } from "./eagle.js"; runEagle("./#{n}.wasm", document.getElementById("eagle"), { antialias: true });</script>
  HTML
  File.write(File.join(dir, "index.html"), page(t, body, 2, "play"))
end
puts "site generated: #{built.size} playable examples, #{docs.size} doc pages"
