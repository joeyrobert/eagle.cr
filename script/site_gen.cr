# Generates the marketing + docs site into site/ (run via script/build-site.sh).
require "html"
require "crystal/syntax_highlighter/html"

ROOT    = File.expand_path("..", __DIR__)
SITE    = File.join(ROOT, "site")
VERSION = File.read(File.join(ROOT, "src/eagle/version.cr")).match(/VERSION = "([^"]+)"/).not_nil![1]

EXAMPLES = {
  "chess"        => {"Chess", "Full rules with castling, en passant, promotion; perft-verified move generator and an alpha-beta AI.", "Click a piece, then a square. U undo · R restart · N toggle AI · 1-4 AI depth"},
  "checkers"     => {"Checkers", "One or two players, forced captures, multi-jumps, kings and a quiescence-searching AI.", "Pick a mode, then click pieces. U undo · R restart · M menu"},
  "breakout"     => {"Breakout", "Paddle, ball, bricks with hit points, particles, camera shake and synthesized sounds.", "Mouse or arrows move · Space launches"},
  "asteroids"    => {"Asteroids", "Vector ship, splitting rocks, wrap-around space and thruster particles.", "A/D rotate · W thrust · Space fire"},
  "platformer"   => {"Platformer", "ASCII level to TileMap + colliders, coyote time, jump buffering, enemies you can stomp, coins and a goal.", "Arrows/WASD move · Space jump · R restart"},
  "snake"        => {"Snake", "Grid logic with a unit-tested core and speed that ramps as you eat.", "Arrows/WASD · Space restarts"},
  "roguelike"    => {"Roguelike", "Procedural dungeons, shadowcasting field of view, monsters that chase, items, five levels.", "Arrows/WASD/hjkl move · Space wait · Enter descends on > · R restart"},
  "coinrush3d"   => {"Coin Rush (3D)", "Roll a ball around a lit, shadowed arena collecting coins before the timer runs out.", "WASD move · Space jump · right-drag orbits the camera"},
  "flythrough3d" => {"3D fly-through", "Every 3D feature: primitives, textures, lights, shadows, fog, transparency, wireframe, picking.", "WASD/QE move · right-drag look · F wireframe · click to pick"},
  "spatial_audio3d" => {"Spatial audio (3D)", "Looping sound sources you can fly around: panning, distance models, interaural delay, head shadow and doppler.", "WASD/QE move · right-drag look · click fires a shot · 1-3 distance model · M mute"},
  "physics"      => {"2D physics", "Rigid bodies, stacking, ramps, sensors and additive particle bursts.", "Click to spawn bodies"},
  "physics3d"    => {"3D physics", "Spheres and boxes with SAT contacts, stacking pyramid, kinematic ramp.", "Click fires spheres · Space throws a box · R resets"},
  "ui"           => {"UI toolkit", "Panels, buttons, sliders, checkboxes, text input, grids and themes.", "Click around; Tab cycles focus"},
  "interactions" => {"Interactions", "Every input pattern with a live event log: clicks, drags, wheel zoom, text, gamepads, signals, timers.", "Try everything; the log on the right narrates"},
  "sandbox2d"    => {"2D sandbox", "Scene tree, tile map, following camera with shake, tweens and a HUD layer.", "WASD moves the player"},
  "embedded"     => {"Embedded assets", "A game whose PNG, WAV and shader are baked into the binary at compile time.", "Nothing to press. It runs with no files at all"},
  "smoke"        => {"Smoke test", "Shapes, sprites, lines and text: the first thing Eagle ever rendered.", ""},
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
  flush = -> { unless para.empty?
    out << "<p>" << md_inline(para.join(" ")) << "</p>\n"; para.clear
  end }
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
      out << code_block(code.join("\n"), lang)
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

# Highlights Crystal with the compiler's own lexer; shell gets comments and prompts; anything else is escaped.
def highlight(code : String, lang : String) : String
  case lang
  when "crystal", "cr", ""
    Crystal::SyntaxHighlighter::HTML.highlight!(code)
  when "sh", "shell", "bash", "console"
    code.lines.map do |line|
      if (m = line.match(/^(\s*)(#.*)$/))
        "#{m[1]}<span class=\"c\">#{HTML.escape(m[2])}</span>"
      elsif (m = line.match(/^(.*?)(\s+#\s.*)$/))
        "#{HTML.escape(m[1])}<span class=\"c\">#{HTML.escape(m[2])}</span>"
      else
        HTML.escape(line)
      end
    end.join("\n")
  else
    HTML.escape(code)
  end
end

def code_block(code : String, lang : String = "crystal") : String
  "<pre class=\"code\"><code class=\"lang-#{lang}\">#{highlight(code, lang)}</code></pre>\n"
end

FONTS = %(<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;1,6..72,400;1,6..72,500&display=swap">)
REPO  = "https://github.com/joeyrobert/eagle.cr"

def page(title : String, body : String, depth : Int32 = 0, active : String = "") : String
  rel = "../" * depth
  nav = [{"Play", "play/index.html", "play"}, {"Guide", "docs/guide.html", "guide"}, {"API", "docs/api/index.html", "api"}, {"GitHub", REPO, "gh"}]
  links = nav.map { |(n, h, k)| "<a href=\"#{h.starts_with?("http") ? h : rel + h}\"#{k == active ? " class=\"active\"" : ""}>#{n}</a>" }.join
  <<-HTML
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <title>#{HTML.escape(title)}</title>
  <meta name="description" content="Eagle is a 2D and 3D game engine written in Crystal.">
  #{FONTS}
  <link rel="stylesheet" href="#{rel}assets/site.css">
  <link rel="icon" href="#{rel}assets/favicon.svg"></head>
  <body><header class="top"><div class="wrap"><a class="brand" href="#{rel}index.html"><img src="#{rel}assets/favicon.svg" alt=""><span>Eagle</span><span class="ver">v#{VERSION}</span></a><nav>#{links}</nav></div></header>
  <main class="wrap">#{body}</main>
  <footer><div class="wrap"><span>Eagle is free software under the LGPL v3.</span><span>Written in Crystal. <a href="#{REPO}">Source on GitHub</a></span></div></footer>
  </body></html>
  HTML
end

CSS = <<-CSS
:root{
  --paper:#f4efe6;--paper2:#ebe4d7;--ink:#1e1711;--ink2:#5e5249;--rule:#d6cbbb;--gold:#c98a12;--link:#8a5200;
  --code-bg:#1d1611;--code-ink:#efe5d4;
  --serif:"Newsreader",Georgia,"Times New Roman",serif;--sans:"IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;--mono:"IBM Plex Mono",ui-monospace,Menlo,Consolas,monospace;
  color-scheme:light;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--paper:#15100c;--paper2:#1f1813;--ink:#eee6d9;--ink2:#a89a8a;--rule:#3a2f26;--gold:#e3a537;--link:#f0b452;--code-bg:#0e0a07;color-scheme:dark}}
:root[data-theme="dark"]{--paper:#15100c;--paper2:#1f1813;--ink:#eee6d9;--ink2:#a89a8a;--rule:#3a2f26;--gold:#e3a537;--link:#f0b452;--code-bg:#0e0a07;color-scheme:dark}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.6 var(--sans)}
.wrap{max-width:1120px;margin:0 auto;padding:0 24px}
a{color:var(--link);text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px}
a:hover{color:var(--ink);text-decoration-color:var(--gold)}
img{max-width:100%}
header.top{border-bottom:2px solid var(--ink)}
header.top .wrap{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-top:18px;padding-bottom:16px;flex-wrap:wrap}
.brand{display:flex;align-items:baseline;gap:10px;color:var(--ink);text-decoration:none}
.brand img{width:30px;height:30px;align-self:center;border-radius:6px}
.brand span:first-of-type{font:500 28px/1 var(--serif);letter-spacing:-.01em}
.ver{font:400 12px var(--mono);color:var(--ink2)}
nav{display:flex;gap:26px}
nav a{color:var(--ink);text-decoration:none;font-weight:500;font-size:15px;padding:4px 0;border-bottom:2px solid transparent}
nav a:hover{color:var(--ink);border-bottom-color:var(--rule)}
nav a.active{border-bottom-color:var(--gold)}
h1,h2{font-family:var(--serif);font-weight:500;letter-spacing:-.015em}
h3{font-weight:600}
.hero{display:grid;grid-template-columns:1.05fr 1fr;gap:56px;align-items:center;padding:64px 0 24px}
.hero>*{min-width:0}
main{overflow-wrap:break-word}
.hero h1{font-size:66px;line-height:1.02;margin:0 0 22px}
.hero h1 em{color:var(--link);font-style:italic}
.lead{font-size:20px;line-height:1.55;color:var(--ink2);margin:0 0 28px;max-width:34em}
.actions{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:28px}
.btn{display:inline-block;padding:11px 18px;border-radius:3px;font-weight:600;font-size:15px;text-decoration:none;background:var(--ink);color:var(--paper);border:1.5px solid var(--ink)}
.btn:hover{background:var(--gold);border-color:var(--gold);color:#1e1711}
.btn.alt{background:transparent;color:var(--ink)}
.btn.alt:hover{border-color:var(--gold);color:var(--ink)}
.plate{margin:0}
.plate img{display:block;width:100%;border:1.5px solid var(--ink);box-shadow:10px 10px 0 var(--gold)}
.plate figcaption{font:13px/1.5 var(--mono);color:var(--ink2);margin-top:18px}
section.block{margin-top:88px}
h2.section{font-size:40px;line-height:1.1;margin:0 0 28px;padding-top:16px;border-top:2px solid var(--ink)}
h2.section small{display:block;font:400 16px/1.5 var(--sans);color:var(--ink2);letter-spacing:0;margin-top:8px}
.features{display:grid;grid-template-columns:1fr 1fr;column-gap:56px}
.feat{border-top:1px solid var(--rule);padding:18px 0 22px}
.feat h3{font-size:18px;margin:0 0 6px}
.feat p{margin:0;color:var(--ink2);font-size:16px}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:36px 28px}
.shots figure{margin:0}
.shots img{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;border:1.5px solid var(--ink);transition:box-shadow .15s,transform .15s}
.shots a:hover img{box-shadow:6px 6px 0 var(--gold);transform:translate(-3px,-3px)}
.shots figcaption{margin-top:12px;font-size:15px;color:var(--ink2)}
.shots figcaption b{display:block;color:var(--ink);font-size:16px}
.shots figcaption b a{color:inherit;text-decoration:none}
pre{margin:0 0 20px;padding:18px 20px;border-radius:4px;background:var(--code-bg);color:var(--code-ink);overflow:auto;font:13.5px/1.65 var(--mono)}
code{font-family:var(--mono);font-size:.88em;background:var(--paper2);padding:.12em .38em;border-radius:3px}
pre code{background:none;padding:0;font-size:inherit;color:inherit}
pre .k{color:#e8a93a}pre .t{color:#9dc4d6}pre .s{color:#bccc8c}pre .n{color:#e7916a}pre .i{color:#e7916a}pre .c{color:#857667;font-style:italic}pre .m{color:#f4e9d6}pre .o{color:#c7b59f}
.install{font-size:13px;margin:0}
.install .p{color:#857667;user-select:none}
.tabs{display:flex;gap:26px;flex-wrap:wrap;border-bottom:1px solid var(--rule);margin-bottom:18px}
.tabs button{background:none;border:0;border-bottom:2px solid transparent;margin-bottom:-1px;padding:10px 0;font:600 15px var(--sans);color:var(--ink2);cursor:pointer}
.tabs button:hover{color:var(--ink)}
.tabs button.on{color:var(--ink);border-bottom-color:var(--gold)}
.tabpane{display:none}.tabpane.on{display:block}
.api{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:28px 32px;margin-bottom:28px}
.api h3{font:500 12px var(--mono);text-transform:uppercase;letter-spacing:.09em;color:var(--ink2);margin:0 0 8px;padding-bottom:6px;border-bottom:1px solid var(--rule)}
.api ul{list-style:none;margin:0;padding:0;font-size:15px;line-height:1.95}
.api a{color:var(--ink);text-decoration:none;font-family:var(--mono);font-size:14px}
.api a:hover{color:var(--link);text-decoration:underline}
table{border-collapse:collapse;width:100%;margin:16px 0 24px;font-size:15px;border-top:2px solid var(--ink)}
th,td{border-bottom:1px solid var(--rule);padding:9px 12px 9px 0;text-align:left;vertical-align:top}
th{font-weight:600}
.doc{max-width:760px;padding:48px 0 24px}
.doc h1{font-size:52px;line-height:1.05;margin:0 0 24px}
.doc h2{font-size:32px;margin:52px 0 14px;padding-top:14px;border-top:1px solid var(--rule)}
.doc h3{font-size:19px;margin:32px 0 8px}
.doc li{margin-bottom:4px}
blockquote{margin:20px 0;padding-left:18px;border-left:3px solid var(--gold);color:var(--ink2)}
hr{border:0;border-top:1px solid var(--rule);margin:36px 0}
.page-head{padding:48px 0 8px}
.page-head h1{font-size:52px;line-height:1.05;margin:0 0 14px}
.play{padding:40px 0 8px}
.play h1{font-size:44px;margin:0 0 8px}
.play .lead{margin-bottom:24px}
.stage{display:inline-block;max-width:100%}
.stage canvas{display:block;max-width:100%;border:1.5px solid var(--ink);box-shadow:10px 10px 0 var(--gold);background:#000}
.controls{font:13px/1.6 var(--mono);color:var(--ink2);margin:22px 0 0}
details{margin-top:40px;border-top:1px solid var(--rule);padding-top:14px}
summary{cursor:pointer;font-weight:600}
summary code{font-weight:400}
details h3{font:500 13px var(--mono);color:var(--ink2);margin:24px 0 8px}
footer{margin-top:96px}
footer .wrap{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;border-top:2px solid var(--ink);padding-top:18px;padding-bottom:48px;font-size:14px;color:var(--ink2)}
@media (max-width:860px){
  .wrap{padding:0 16px}
  .hero{grid-template-columns:1fr;gap:40px;padding-top:40px}
  .hero h1{font-size:46px}
  .features{grid-template-columns:1fr}
  h2.section{font-size:32px}
  .doc h1,.page-head h1{font-size:40px}
  nav{gap:18px}
  .shots{grid-template-columns:1fr}
}
CSS

# Appended to crystal docs' stylesheet so the API reference matches the site.
API_CSS = <<-CSS
:root{--paper:#f4efe6;--paper2:#ebe4d7;--ink:#1e1711;--ink2:#5e5249;--rule:#d6cbbb;--gold:#c98a12;--link:#8a5200;--side:#1e1711;--side-ink:#e9dfcf;--side-dim:#a89a8a;--code-bg:#1d1611}
@media (prefers-color-scheme:dark){:root{--paper:#15100c;--paper2:#1f1813;--ink:#eee6d9;--ink2:#a89a8a;--rule:#3a2f26;--gold:#e3a537;--link:#f0b452;--side:#0e0a07;--code-bg:#0e0a07}}
html,body{background:var(--paper)}
body{color:var(--ink);font-family:"IBM Plex Sans",system-ui,sans-serif;font-size:16px;line-height:1.6}
a,a:visited,.main-content a:visited{color:var(--link)}
h1,h2,h3,h4,h5,h6{color:var(--ink)}
h1,h2{font-family:"Newsreader",Georgia,serif;font-weight:500;letter-spacing:-.01em}
h2{border-bottom:0;border-top:1px solid var(--rule);padding:14px 0 0}
h1.type-name{color:var(--ink);background:none;border:0;border-bottom:2px solid var(--ink);border-radius:0;padding:0 0 12px;font-size:40px}
.kind{color:var(--link);font-family:"IBM Plex Mono",monospace;font-size:45%;text-transform:uppercase;letter-spacing:.08em;vertical-align:middle}
.sidebar{background:var(--side);color:var(--side-ink);box-shadow:none;border-right:2px solid var(--gold)}
.sidebar .current>a,.sidebar a:hover{color:var(--gold)}
.sidebar input{background:#2a211a;color:var(--side-ink);border-radius:3px}
.project-name{font-family:"Newsreader",Georgia,serif;font-weight:500;font-size:1.7rem}
.site-link{display:block;margin-top:10px;font-size:13px;color:var(--side-dim)!important;text-decoration:underline;text-underline-offset:3px}
.superclass-hierarchy .superclass a,.superclass-hierarchy .superclass a:visited,.other-type a,.other-type a:visited,.entry-summary .signature,.entry-summary a:visited{background:var(--paper2);color:var(--ink);border:1px solid var(--rule);border-radius:3px}
.superclass-hierarchy .superclass a:hover,.other-type a:hover,.entry-summary .signature:hover{background:var(--paper2);border-color:var(--gold)}
.entry-detail .signature{background:var(--paper2);color:var(--ink);border:1px solid var(--rule);border-left:3px solid var(--gold);border-radius:3px;font-family:"IBM Plex Mono",monospace;font-size:14px}
.entry-detail:target .signature{background:var(--paper2);border-color:var(--gold)}
.entry-detail .signature .method-permalink{color:var(--link)}
.methods-inherited a,.methods-inherited a:visited,.methods-inherited .tooltip *{color:var(--link)}
.methods-inherited .tooltip>span{background:var(--paper2)}
code{font-family:"IBM Plex Mono",ui-monospace,Menlo,monospace}
:not(pre)>code{background:var(--paper2);color:var(--ink)}
pre{background:var(--code-bg);color:#efe5d4;border:0;border-radius:4px;font-size:13.5px;line-height:1.65}
pre .k{color:#e8a93a}pre .t{color:#9dc4d6}pre .s{color:#bccc8c}pre .n{color:#e7916a}pre .i{color:#e7916a}pre .c{color:#857667;font-style:italic}pre .m{color:#f4e9d6}pre .o{color:#c7b59f}
.entry-detail .signature .k,.entry-summary .signature .k{color:var(--link)}.signature .t{color:#2e5a70}.signature .n{color:#a4532c}
@media (prefers-color-scheme:dark){.signature .t{color:#9dc4d6}.signature .n{color:#e7916a}}
span.flag.purple{background:var(--paper2);color:var(--ink);border-color:var(--gold)}
table{display:table;white-space:normal;background:transparent;border:0;padding:0;text-align:left;border-collapse:collapse;width:100%;max-width:62em;margin:16px 0 28px;border-top:2px solid var(--ink);font-size:15px;line-height:1.55}
th{letter-spacing:0}
th,td{border-bottom:1px solid var(--rule);padding:9px 14px 9px 0;text-align:left;vertical-align:top}
th{font-weight:600}td:first-child{font-weight:600;white-space:nowrap}
.main-content img{max-width:100%;border:1.5px solid var(--ink)}
CSS

FAVICON = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#1E1711"/><path d="M6 64 C8 44 14 26 28 18.5 C37 14 47 14.5 53 19.5 L47 30.5 C41 30.5 37 34.5 35 41 L31 64 Z" fill="#F4EFE6"/><path d="M49.5 18 C56 18.5 61.5 23.5 60.5 32 C60 35.5 58.5 38 56 39.5 C56.5 35 55 32 51.5 31 L44.5 31.5 C46.5 27 47.5 22 49.5 18 Z" fill="#E3A537"/><path d="M34.5 23 L49 19.5 L48 22.5 Z" fill="#1E1711"/><circle cx="42" cy="24.6" r="2.3" fill="#1E1711"/></svg>\n)

CODE_SAMPLES = {
  "Hello, sprite" => <<-CR,
  require "eagle"
  include Eagle

  class Game < App
    @player = Sprite2D.new(Texture.load("res://player.png"), Window.center)
    @score = 0

    def load : Nil
      Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
      Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
      SceneTree.root.add(@player)
    end

    def update(dt : Float32) : Nil
      @player.x += Input.axis("left", "right") * 250 * dt
      @score += 1 if Input.pressed?(Key::Space)
    end

    def draw(g : Graphics) : Nil
      g.print("score \#{@score}", 10, 10, scale: 2)
    end
  end

  Eagle.run(Game, title: "My Game", width: 960, height: 540)
  CR
  "Scene tree & signals" => <<-CR,
  class Bullet < Area2D
  end

  class Enemy < Area2D
    signal died(points : Int32)

    def initialize(position : Vec2)
      super("Enemy", position)
      circle(12)
      add(Sprite2D.new(Texture.new(Image.circle(24, Color::RED))))
      on_body_entered { |other| hit if other.is_a?(Bullet) }
    end

    def hit : Nil
      emit_died(100)
      Tween.value(Color::WHITE, Color::TRANSPARENT, 0.2) { |c| self.modulate = c }
        .on_complete { queue_free }
    end
  end

  score = 0
  boom = Sound.tone(90, 0.3, Sound::Wave::Noise)
  enemy = Enemy.new(v2(300, 200))
  enemy.on_died { |points| score += points; boom.play }
  SceneTree.root.add(enemy)
  CR
  "2D physics" => <<-CR,
  class Player < KinematicBody2D
    def physics_process(dt : Float32) : Nil
      self.velocity += v2(0, 1400 * dt) # gravity
      self.velocity = v2(Input.axis("left", "right") * 220, velocity.y)
      self.velocity = v2(velocity.x, -520) if Input.pressed?("jump") && on_floor?
      move_and_slide(dt)
    end
  end

  ground = StaticBody2D.new(position: v2(400, 580)).box(800, 40)
  ball = RigidBody2D.new(position: v2(400, 0)).circle(16)
  ball.restitution = 0.6
  bounce = Sound.tone(440, 0.08)
  ball.on_body_entered { |other| bounce.play }
  player = Player.new(position: v2(100, 100)).box(24, 40)
  SceneTree.root.add(ground, ball, player)

  if hit = Physics2D.world.raycast(player.position, v2(1, 0), 200)
    puts "wall \#{hit.distance} px ahead"
  end
  CR
  "3D scene" => <<-CR,
  root = SceneTree.root
  cam = Camera3D.new(position: v3(0, 3, 8))
  cam.look_at(Vec3::ZERO)
  root.add(cam)
  root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.3))) # casts PCF shadows

  grass = Texture.new(Image.checkerboard(64, 64, 8, Color.hex("#4a7a3a"), Color.hex("#3d6630")), wrap: GPU::Wrap::Repeat)
  root.add(MeshInstance3D.new(Mesh.plane(40, 40, uv_scale: 10), Material.new(texture: grass)))
  crate = MeshInstance3D.new(Mesh.cube, Material.new(Color::ORANGE, shininess: 48), position: v3(0, 0.5, 0))
  root.add(crate)

  Scene3D.environment.fog(20, 80)
  Scene3D.environment.sky_colors(Color.hex("#3b6fd6"), Color.hex("#b9d4f5"), Color.hex("#3a3a44"))

  # picking: turn the crate red while the mouse is over it
  if (box = crate.global_bounds) && cam.mouse_ray.intersect_aabb(box)
    crate.material.albedo = Color::RED
  end
  CR
  "UI" => <<-CR,
  hud = CanvasLayer.new
  panel = Panel.new(size: v2(320, 0))
  panel.anchor = Anchor::Center
  panel.fit_content = true

  box = VBox.new(size: v2(300, 0))
  box.position = v2(10, 10)
  box.fit_content = true
  box.add(Label.new("Settings"),
    Slider.new(0, 100, 50).tap { |s| s.on_value_changed { |v| Audio.volume = v / 100 } },
    CheckBox.new("Fullscreen").tap { |c| c.on_toggled { |on| Window.fullscreen = on } },
    TextInput.new("", "player name").tap { |t| t.on_submitted { |name| puts "hi \#{name}" } },
    Button.new("Start") { SceneTree.change_scene(Node2D.new("Level")) })

  panel.add(box)
  hud.add(panel)
  SceneTree.root.add(hud)
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

  canvas = Canvas.new(320, 180) # low-res render target
  g.with_canvas(canvas) do
    g.circle(160, 90, 40, color: Color::YELLOW)
    g.print("pixel perfect", 110, 150)
  end
  glow["u_strength"] = 0.3
  g.with_shader(glow) { g.draw(canvas, Window.rect) }
  CR
}

API_GROUPS = {
  "Core"           => %w(Eagle::App Eagle::Config Eagle::Clock Eagle::Node Eagle::Node2D Eagle::Node3D Eagle::SceneTree Eagle::Emitter Eagle::Tween Eagle::Ease Eagle::Script Eagle::Window Eagle::Input),
  "2D"             => %w(Eagle::Graphics Eagle::Texture Eagle::TextureRegion Eagle::Canvas Eagle::Shader Eagle::Font Eagle::TrueTypeFont Eagle::Camera2D Eagle::Sprite2D Eagle::AnimatedSprite2D Eagle::TileMap Eagle::Particles2D Eagle::Polygon2D Eagle::Line2D Eagle::CanvasLayer Eagle::Timer),
  "Physics"        => %w(Eagle::Physics2D::World Eagle::Physics2D::Body Eagle::RigidBody2D Eagle::StaticBody2D Eagle::KinematicBody2D Eagle::Area2D Eagle::RayCast2D Eagle::Physics3D::World Eagle::RigidBody3D Eagle::KinematicBody3D Eagle::Area3D),
  "3D"             => %w(Eagle::Mesh Eagle::Material Eagle::Renderer3D Eagle::Environment Eagle::Camera3D Eagle::MeshInstance3D Eagle::DirectionalLight3D Eagle::PointLight3D Eagle::SpotLight3D Eagle::Scene3D),
  "UI"             => %w(Eagle::Control Eagle::Panel Eagle::Label Eagle::Button Eagle::CheckBox Eagle::Slider Eagle::ProgressBar Eagle::TextInput Eagle::VBox Eagle::HBox Eagle::GridContainer Eagle::Theme),
  "Audio & assets" => %w(Eagle::Audio Eagle::Sound Eagle::Voice Eagle::AudioPlayer Eagle::AudioPlayer2D Eagle::AudioPlayer3D Eagle::AudioListener3D Eagle::Assets Eagle::Image Eagle::Codecs::PNG Eagle::Codecs::Vorbis Eagle::Codecs::Zlib),
  "Math"           => %w(Eagle::Vec2 Eagle::Vec3 Eagle::Vec4 Eagle::Mat4 Eagle::Quat Eagle::Rect Eagle::AABB Eagle::Ray Eagle::Color Eagle::Transform2D Eagle::Mathf),
}

def api_href(name : String) : String
  "docs/api/#{name.gsub("::", "/")}.html"
end

# ---- build ---------------------------------------------------------------------
SHOTS_SRC = File.join(ROOT, "docs/screenshots")
Dir.mkdir_p(File.join(SITE, "assets/screenshots"))
Dir.mkdir_p(File.join(SITE, "docs"))
Dir.mkdir_p(File.join(SITE, "play"))
File.write(File.join(SITE, "assets/site.css"), CSS)
File.write(File.join(SITE, "assets/favicon.svg"), FAVICON)
Dir.glob(File.join(SHOTS_SRC, "*.png")).each { |f| File.copy(f, File.join(SITE, "assets/screenshots", File.basename(f))) }
has_shot = ->(n : String) { File.exists?(File.join(SHOTS_SRC, "#{n}.png")) }

# crystal docs has no Markdown tables, so README tables arrive as a paragraph of pipes.
def pipe_table(src : String) : String?
  rows = src.lines.map(&.strip).reject(&.empty?)
  return nil unless rows.size > 1 && rows.all? { |r| r.starts_with?("|") && r.ends_with?("|") }
  body = rows.reject { |r| r =~ /^\|[\s|:-]+\|$/ }.map_with_index do |r, i|
    tag = i == 0 ? "th" : "td"
    cells = r[1..-2].split("|").map { |c| c.strip.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" } }
    "<tr>" + cells.map { |c| "<#{tag}>#{c}</#{tag}>" }.join + "</tr>"
  end
  "<table>#{body.join}</table>"
end

# theme the crystal docs output, if present
api_root = File.join(SITE, "docs/api")
if Dir.exists?(api_root)
  css_path = File.join(api_root, "css/style.css")
  css = File.read(css_path)
  marker = "/* eagle theme */"
  File.write(css_path, css.split(marker).first + marker + "\n" + API_CSS)
  Dir.glob(File.join(api_root, "**/*.html")).each do |f|
    html = File.read(f)
    next if html.includes?("class=\"site-link\"")
    up = "../" * (Path[f].relative_to(api_root).parts.size - 1)
    site = "#{up}../../"
    html = html.sub("</head>", "#{FONTS}<link rel=\"icon\" href=\"#{site}assets/favicon.svg\">\n</head>")
    html = html.sub(/(<h1 class="project-name">.*?<\/h1>)/m) { "#{$1}<a class=\"site-link\" href=\"#{site}index.html\">Back to the Eagle site</a>" }
    html = html.gsub(/<p>(\|.*?)<\/p>/m) { |whole| pipe_table($1) || whole }
    html = html.gsub(%(src="docs/screenshots/), %(src="#{site}assets/screenshots/))
    File.write(f, html)
  end
end

def api_link(name : String, rel : String) : String?
  return nil unless File.exists?(File.join(SITE, api_href(name)))
  "<li><a href=\"#{rel}#{api_href(name)}\">#{name.lchop("Eagle::")}</a></li>"
end

# marketing page
shots = %w(flythrough3d coinrush3d chess platformer physics3d roguelike ui interactions asteroids breakout physics checkers).select { |n| has_shot.call(n) }
gallery = shots.map do |n|
  t, d, _ = EXAMPLES[n]
  "<figure><a href=\"play/#{n}/index.html\"><img src=\"assets/screenshots/#{n}.png\" alt=\"#{t} screenshot\" loading=\"lazy\"></a><figcaption><b><a href=\"play/#{n}/index.html\">#{t}</a></b>#{d}</figcaption></figure>"
end.join
tabs = CODE_SAMPLES.keys.map_with_index { |k, i| "<button class=\"#{i == 0 ? "on" : ""}\" data-tab=\"#{i}\">#{k}</button>" }.join
panes = CODE_SAMPLES.values.map_with_index { |code, i| "<div class=\"tabpane #{i == 0 ? "on" : ""}\" data-pane=\"#{i}\">#{code_block(code)}</div>" }.join
api = API_GROUPS.map { |group, names| "<div><h3>#{group}</h3><ul>#{names.compact_map { |n| api_link(n, "") }.join}</ul></div>" }.join
features = [
  {"Crystal all the way down", "PNG, QOI, BMP, WAV and Ogg Vorbis codecs, zlib, a TrueType rasteriser, the audio mixer, physics, particles, UI and the 3D renderer are all Crystal. SDL2 and OpenGL sit underneath, and nothing else."},
  {"Two ways to draw", "Write a LÖVE-style <code>load</code>, <code>update</code>, <code>draw</code> loop with immediate-mode calls, or build a Godot-style node tree with signals. Mixing the two is fine."},
  {"2D and 3D", "Batched sprites, cameras, tile maps and particles. Meshes, materials, directional, point and spot lights, PCF shadows, fog and a procedural sky."},
  {"Physics that stacks", "2D SAT with clipped manifolds, 3D spheres and oriented boxes, kinematic characters with <code>move_and_slide</code>, raycasts and sensors."},
  {"Runs in the browser", "One command compiles a game to WebAssembly and WebGL2. Same code, same rendering, assets embedded in the binary."},
  {"Ships as one file", "<code>eagle export exe</code> bakes assets into a single executable. <code>eagle export web</code> makes a static bundle, and there is a macOS <code>.app</code> target too."},
  {"Tested end to end", "More than 200 specs, including GPU pixel tests, perft-verified chess, bit-exact Vorbis decoding and integration specs that drive the real frame loop with injected input."},
  {"Tools included", "The <code>eagle</code> CLI scaffolds projects and opens viewers for images, OBJ, TTF, WAV and hot-reloading GLSL. Frame-limited screenshot runs make CI easy."},
]
feature_cards = features.map { |(t, d)| "<div class=\"feat\"><h3>#{t}</h3><p>#{d}</p></div>" }.join
install = [
  "brew install sdl2",
  "git clone https://github.com/joeyrobert/eagle.cr && cd eagle.cr",
  "shards build && bin/eagle examples asteroids",
].map { |l| "<span class=\"p\">$ </span>#{HTML.escape(l)}" }.join("\n")
hero_img = has_shot.call("flythrough3d") ? %(<figure class="plate"><a href="play/flythrough3d/index.html"><img src="assets/screenshots/flythrough3d.png" alt="The 3D fly-through example"></a><figcaption>Fig. 1. The 3D fly-through example: shadows, fog, transparency and picking, running in WebGL2.</figcaption></figure>) : ""
home = <<-HTML
<section class="hero"><div>
<h1>Games in <em>Crystal</em>, top to bottom.</h1>
<p class="lead">Eagle is a 2D and 3D game engine written entirely in Crystal. It has a scene tree, signals, physics, audio, UI and a WebAssembly target, and your game compiles to a single executable.</p>
<div class="actions"><a class="btn" href="play/index.html">Play the examples</a><a class="btn alt" href="docs/guide.html">Read the guide</a></div>
<pre class="install"><code>#{install}</code></pre>
</div>#{hero_img}</section>
<section class="block"><h2 class="section">Inside the engine<small>Everything here is implemented in Crystal and covered by specs.</small></h2>
<div class="features">#{feature_cards}</div></section>
<section class="block"><h2 class="section">Examples<small>Each one is a complete program that also runs in your browser. Click a screenshot to play it.</small></h2>
<div class="shots">#{gallery}</div></section>
<section class="block"><h2 class="section">A taste of the API<small>Simple things stay short, and the harder things are still possible.</small></h2>
<div class="tabs">#{tabs}</div>#{panes}</section>
<section class="block"><h2 class="section">API reference<small>Generated from the source by <code>crystal docs</code>. Each type explains what it is for and shows how to use it.</small></h2>
<div class="api">#{api}</div>
<div class="actions"><a class="btn" href="docs/api/index.html">Browse the full API</a><a class="btn alt" href="docs/guide.html">Guide</a><a class="btn alt" href="docs/architecture.html">Architecture</a></div></section>
<script>
document.querySelectorAll('.tabs button').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.tabs button').forEach(x=>x.classList.remove('on'));document.querySelectorAll('.tabpane').forEach(x=>x.classList.remove('on'));b.classList.add('on');document.querySelector('.tabpane[data-pane="'+b.dataset.tab+'"]').classList.add('on');}));
</script>
HTML
File.write(File.join(SITE, "index.html"), page("Eagle, a game engine for Crystal", home, 0, "home"))

# docs pages from markdown
docs = {"guide" => {"Guide", "docs/guide.md"}, "architecture" => {"Architecture", "docs/plans/000-vision-and-architecture.md"}, "roadmap" => {"Roadmap", "docs/plans/010-roadmap.md"}, "readme" => {"README", "README.md"}}
docs.each do |name, (title, path)|
  md = File.read(File.join(ROOT, path)).gsub(/^!\[[^\]]*\]\([^)]*\)\n\n?/m, "")
  body = "<article class=\"doc\">" + markdown(md) + "</article>"
  File.write(File.join(SITE, "docs/#{name}.html"), page("#{title} · Eagle", body, 1, name == "guide" ? "guide" : ""))
end
doc_index = <<-HTML
<article class="doc"><h1>Documentation</h1>
<table>
<tr><td><a href="guide.html">Guide</a></td><td>The game loop, drawing styles, assets, input, signals, physics, UI, 3D, automation and backends.</td></tr>
<tr><td><a href="api/index.html">API reference</a></td><td>Every public type and method, with usage notes and examples, generated from source.</td></tr>
<tr><td><a href="../play/index.html">Playable examples</a></td><td>All of the example games compiled to WebAssembly, with their source.</td></tr>
<tr><td><a href="architecture.html">Architecture</a></td><td>Layers, backends and the key design decisions.</td></tr>
<tr><td><a href="roadmap.html">Roadmap</a></td><td>What is done and what is known to be missing.</td></tr>
<tr><td><a href="readme.html">README</a></td><td>Install, build and run.</td></tr>
</table></article>
HTML
File.write(File.join(SITE, "docs/index.html"), page("Docs · Eagle", doc_index, 1, "guide"))

# play pages
built = EXAMPLES.keys.select { |n| File.exists?(File.join(ROOT, "dist/web/#{n}/#{n}.wasm")) }
cards = EXAMPLES.select { |n, _| built.includes?(n) }.map do |n, (t, d, _)|
  shot = has_shot.call(n) ? "<a href=\"#{n}/index.html\"><img src=\"../assets/screenshots/#{n}.png\" alt=\"#{t} screenshot\" loading=\"lazy\"></a>" : ""
  "<figure>#{shot}<figcaption><b><a href=\"#{n}/index.html\">#{t}</a></b>#{d}</figcaption></figure>"
end.join
play_index = <<-HTML
<div class="page-head"><h1>Playable examples</h1><p class="lead">Every example is compiled to WebAssembly and WebGL2 from the same Crystal source that runs natively. Click a canvas to focus it. Sound starts after your first click.</p></div>
<div class="shots">#{cards}</div>
HTML
File.write(File.join(SITE, "play/index.html"), page("Play · Eagle", play_index, 1, "play"))
built.each do |n|
  t, d, controls = EXAMPLES[n]
  dir = File.join(SITE, "play", n)
  Dir.mkdir_p(dir)
  File.copy(File.join(ROOT, "dist/web/#{n}/#{n}.wasm"), File.join(dir, "#{n}.wasm"))
  File.copy(File.join(ROOT, "web/eagle.js"), File.join(dir, "eagle.js"))
  src = File.read(File.join(ROOT, "examples/#{n}/main.cr"))
  extra = Dir.glob(File.join(ROOT, "examples/#{n}/*.cr")).reject { |f| f.ends_with?("main.cr") }.sort.map { |f| "<h3>examples/#{n}/#{File.basename(f)}</h3>#{code_block(File.read(f))}" }.join
  body = <<-HTML
  <div class="play"><h1>#{t}</h1><p class="lead">#{d}</p>
  <div class="stage"><canvas id="eagle"></canvas></div>
  #{controls.empty? ? "" : "<p class=\"controls\">#{controls}</p>"}
  <details><summary>Source: <code>examples/#{n}/main.cr</code></summary><h3>examples/#{n}/main.cr</h3>#{code_block(src)}#{extra}</details></div>
  <script type="module">import { runEagle } from "./eagle.js"; runEagle("./#{n}.wasm", document.getElementById("eagle"), { antialias: true });</script>
  HTML
  File.write(File.join(dir, "index.html"), page("#{t} · Eagle", body, 2, "play"))
end
puts "site generated: #{built.size} playable examples, #{docs.size} doc pages"
