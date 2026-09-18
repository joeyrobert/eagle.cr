# Eagle guide

## Setup

Eagle needs Crystal 1.21 or newer and SDL2. Install the `eagle` CLI with one line; the
installer checks the prerequisites and prints the command for anything missing
(`--with-deps` runs it for you):

```sh
# macOS and Linux
curl -fsSL https://raw.githubusercontent.com/joeyrobert/eagle.cr/main/install.sh | sh
```

```powershell
# Windows (PowerShell); or run eagle-setup.exe from the releases page
irm https://raw.githubusercontent.com/joeyrobert/eagle.cr/main/install.ps1 | iex
```

Then create a project and run it:

```sh
eagle init mygame   # pick a template (2d-game, 3d-game, ui-app, empty), window size, pixel art, web, git, CI
cd mygame
eagle run
crystal spec        # the generated sample spec
```

In scripts, pass the answers as flags: `eagle init mygame --template 3d --size 1280x720 --no-ci --yes`.
`eagle help init` lists them all. The game lives in `src/<name>.cr` and `src/main.cr` only
starts it, so specs can `require "../src/<name>"` without opening a window.

### Manual setup

Adding Eagle to an existing Crystal project needs no CLI:

1. Install SDL2: `brew install sdl2` (macOS), `sudo apt install libsdl2-dev` (Debian/Ubuntu),
   `sudo dnf install SDL2-devel` (Fedora), `sudo pacman -S sdl2` (Arch). On Windows, download
   `SDL2-devel-2.x.x-VC.zip` from the SDL releases on GitHub, build with
   `--link-flags "/LIBPATH:C:\path\to\SDL2\lib\x64"`, and ship `SDL2.dll` next to the executable.
2. Add Eagle to `shard.yml`, then run `shards install`:

   ```yaml
   dependencies:
     eagle:
       github: joeyrobert/eagle.cr
   ```

3. `require "eagle"` and hand an `App` to `Eagle.run`:

   ```crystal
   require "eagle"
   include Eagle

   class Game < App
     def draw(g : Graphics)
       g.print("Hello, Eagle!", 10, 10)
     end
   end

   Eagle.run(Game, title: "My Game", width: 960, height: 540)
   ```

4. `crystal run src/main.cr` runs it; `mkdir -p bin && crystal build src/main.cr --release -o bin/game` builds a
   release executable. `eagle run` and `eagle build` do the same, and work in any project
   that has `src/main.cr`.

## The loop

`Eagle.run(MyApp)` opens the window, creates the GPU device, constructs your
`App`, calls `load`, then every frame:

1. polls events → `Input` state, `App#input`, `Node#input` (children first)
2. runs zero or more **fixed** steps (`Config#fixed_fps`, default 60): physics world step → `Node#physics_process` → `App#fixed_update`
3. `Node#process` → tweens → `App#update(dt)`
4. mixes audio
5. clears, renders 3D (if a `Camera3D` is current), draws the 2D scene tree (with the current `Camera2D`), then `App#draw(g)`

`Clock.delta`, `Clock.elapsed`, `Clock.fps`, `Clock.scale` (slow motion) are
available anywhere.

## Two styles, one engine

**Immediate (LÖVE-style):** draw everything yourself in `draw`:

```crystal
class Game < App
  @texture = Texture.new(Image.circle(32, Color::WHITE))
  @score = 0

  def draw(g : Graphics) : Nil
    g.circle(400, 300, 40, color: Color::RED)
    g.draw(@texture, 100, 100, rotation: Clock.elapsed, ox: 16, oy: 16)
    g.print("score #{@score}", 10, 10)
  end
end
```

**Scene tree (Godot-style):** build nodes and let them run:

```crystal
class Player < Sprite2D
  signal died

  def ready : Nil
    self.texture = Texture.load("res://player.png")
  end

  def process(dt : Float32) : Nil
    self.position += Input.vector("left", "right", "up", "down") * 200 * dt
  end
end

SceneTree.root.add(Player.new)
```

Mix freely: nodes draw first, then `App#draw` on top (HUD).

## Assets

`Texture.load("res://x.png")`, `Sound.load`, `Font.load(path, size)`,
`Mesh.load("x.obj")`, `Shader.load("fx.glsl")`. `res://` resolves to
`EAGLE_ASSETS`, `Config#assets_dir`, `assets/` next to the executable, or
`assets/` in the working directory. Loaded assets are cached.

Images: PNG (all bit depths, palettes, interlace), QOI, BMP. Decode *and*
encode (`Image#save`). Audio: WAV (PCM 8/16/24/32, float). Models: OBJ.

## Input

```crystal
Input.map "jump", Key::Space, GamepadButton::A
Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
Input.pressed?("jump")          # this frame
Input.down?(Key::LShift)        # held
Input.axis("left", "right")     # -1..1 (analog on sticks)
Input.vector("left", "right", "up", "down")
Input.mouse                     # also mouse_delta and wheel
Input.gamepad.try(&.rumble)
```

Raw events (`KeyEvent`, `MouseButtonEvent`, `TextEvent`, `GamepadAxisEvent`, …)
arrive in `App#input` and `Node#input`; set `event.handled = true` to stop
propagation.

## Signals

```crystal
class Enemy < Node2D
  signal hit(damage : Int32)
  signal died
end

enemy = Enemy.new
enemy.on_hit { |d| puts "took #{d}" } # or enemy.hit.connect { |d| ... }
enemy.emit_hit(3)                      # or enemy.hit.emit(3)
enemy.died.once { puts "gone" }
```

## Physics 2D

```crystal
ground = StaticBody2D.new(position: v2(400, 580)).box(800, 40)
ball = RigidBody2D.new(position: v2(400, 0)).circle(16)
ball.restitution = 0.6
ball.on_body_entered { |other| puts "bounce" }

class Player < KinematicBody2D
  def physics_process(dt : Float32) : Nil
    self.velocity += v2(0, 1400 * dt)
    move_and_slide(dt)
    puts "grounded" if on_floor?
  end
end

player = Player.new(position: v2(100, 100)).box(24, 40)
SceneTree.root.add(ground, ball, player)
Physics2D.world.raycast(player.position, v2(1, 0), 100)
```

Units are pixels and seconds; default gravity 980 px/s². Layers/masks are bit
sets on `body.layer` / `body.mask`. `Area2D` is a sensor. `debug = true` on
any body draws its shapes.

## Algorithms

Seeded helpers for procedural content, grid games and lightweight AI. `Rng` is a
PCG32 generator that includes Crystal's `Random`, so `array.shuffle(rng)` works
and the same seed replays on native and wasm. `Noise` is Perlin, simplex, fBm
and Worley. `Grid` and `Pathfinding` cover Bresenham, shadowcasting FOV, A*,
Dijkstra and flow fields. `Procedural` builds Poisson-disk points, BSP rooms,
caves and mazes. `Geometry`, `Quadtree` / `SpatialHash`, `Steering` and the
behavior-tree types sit beside them.

```crystal
rng = Rng.new(2026)
dmg = rng.roll("2d6+1")

n = Noise.new(42)
height = n.fbm(12.5, 8.0)

grid = CostGrid.new(20, 12)
grid.block(5, 5)
path = Pathfinding.a_star(grid, {0, 0}, {19, 11})

seen = Grid.field_of_view({10, 8}, 8) { |x, y| !x.in?(0...20) || !y.in?(0...12) || !grid.passable?(x, y) }
trees = Procedural.poisson_disk(320, 180, 16, rng)
```

The `algorithms` example tabs through A*, noise terrain, Poisson-disk sampling,
flocking and shadowcasting FOV. The roguelike uses `Grid.field_of_view` for its
fog of war.

```sh
crystal run examples/algorithms/main.cr
# 1-5 or Tab switch scenes, click sets the A* goal, WASD moves in FOV
```

## UI

```crystal
hud = CanvasLayer.new
panel = Panel.new(size: v2(300, 0)).tap(&.anchor = Anchor::Center).tap(&.fit_content = true)
box = VBox.new(size: v2(280, 0)).tap(&.position = v2(10, 10)).tap(&.fit_content = true)
box.add(Label.new("Settings"), Slider.new(0, 100, 50), CheckBox.new("Music", true), Button.new("OK") { panel.visible = false })
panel.add(box); hud.add(panel); SceneTree.root.add(hud)
Theme.default.font = Font.load("res://Inter.ttf", 18)
```

Controls receive mouse/keyboard events, manage focus (`Control.focused`), and
inherit `Theme` from ancestors. Containers (`VBox`, `HBox`, `GridContainer`)
size children by `effective_min_size` and `size_flags`.

## 3D

```crystal
root = SceneTree.root
cam = Camera3D.new(position: v3(0, 3, 8)).tap(&.look_at(Vec3::ZERO))
cube = MeshInstance3D.new(Mesh.cube, Material.new(Color::RED), position: v3(0, 0.5, 0))
root.add(cam, DirectionalLight3D.new(v3(-0.5, -1, -0.3)), cube)
Scene3D.environment.fog(20, 80)
Scene3D.environment.shadows = true
if box = cube.global_bounds
  cam.screen_to_ray(Input.mouse).intersect_aabb(box) # distance to the cube under the mouse, or nil
end
```

Shaders use the GLSL 330 / 300 es common subset; `Material#shader` accepts a
custom `Shader` using the standard uniforms (`u_model`, `u_view`,
`u_projection`, lights…).

## 3D audio

```crystal
hum = Sound.tone(55, 2, Sound::Wave::Saw, volume: 0.3)
generator = AudioPlayer3D.new(hum, position: v3(4, 1, -6), loop: true, autoplay: true, max_distance: 30)
generator.attenuation = Attenuation::Linear # or Inverse (default), Exponential
SceneTree.root.add(generator)
bang = Sound.tone(80, 0.4, Sound::Wave::Noise)
Audio.play_at(bang, v3(10, 0, -20), pitch: 0.9 + rand * 0.2) # one-shot, no node
Audio.listener                                               # the current AudioListener3D, else Camera3D
```

3D voices are heard from the current `Camera3D`, or from an `AudioListener3D` when
one is current (third-person cameras, cutscenes). Each voice gets distance
attenuation (`min_distance`, `max_distance`, `rolloff`), equal-power panning, a
small interaural delay and a head-shadow low-pass so left/right and front/back
read on headphones, and optional doppler (`doppler = true`). Parameters glide
across each mixed buffer, so fast movers don't click.

### Streaming an open world

The `joyride` example keeps an effectively infinite world bounded in memory. Its seed maps
world coordinates to deterministic road edges, zones and chunk contents, so a chunk can be
discarded and later rebuilt exactly. The game keeps a five-by-five ring of rendered chunks
around the player and evicts old simulation layouts. Traffic follows the generated road
graph, pedestrians use generated sidewalks, and missions choose targets from that same graph.

```sh
crystal run examples/joyride/main.cr
# WASD/arrows drive, Space handbrake, M starts a new mission
```

The reusable, window-free generation and simulation are in `examples/joyride/world.cr` and
`examples/joyride/sim.cr`; `main.cr` is the 3D presentation layer. Set
`EAGLE_WORLD_SEED=42` to explore a different deterministic world.

### First-person shooter

The `fps` example (Neon Bastion) is a compact arena shooter: mouse look, a pulse rifle and
scattergun, grunt and charger AI, Waves and Deathmatch. Combat and the procedural arena live
in `examples/fps/game.cr` so they can be specced without a window; `main.cr` is the
first-person view, HUD and spatial audio. Click to capture the mouse (browsers require a
gesture for pointer lock); native builds lock it on launch.

```sh
crystal run examples/fps/main.cr
# WASD move, Shift sprint, click/RB fire, 1/2 weapons, F1 Waves, F2 Deathmatch
```

## Automated runs

`EAGLE_FRAMES=60 EAGLE_SCREENSHOT=shot.png ./game` runs 60 frames, saves the
frame and exits. `EAGLE_HEADLESS=1` hides the window. `Eagle.init`/`Eagle.step`/
`Eagle.shutdown` drive the loop manually in tests. `EAGLE_GL_DEBUG=1` checks
for GL errors after every 3D stage.

## Backends

`Platform::Base` (window/input/audio/gamepads) and `GPU::Device` (rendering)
are abstract. `Platform::SDL` + `GPU::GL33` are the desktop implementations.
`Platform::Web` targets `wasm32-wasi` and drives WebGL2, WebAudio and DOM input
through `web/eagle.js`. Shaders and formats stay within the WebGL2 subset so the
same code renders identically on both.

## Building and exporting

Run these in the project folder. FILE defaults to `src/main.cr`, and `<name>` is the
project folder's name (or FILE's base name when it isn't `main.cr`).

```sh
eagle run            # debug build into bin/<name>, then run it (runs shards install first if needed)
eagle build          # release build: bin/<name>
eagle export exe     # release build: dist/<name>/<name>
eagle export web     # dist/web/<name>/: index.html + eagle.js + <name>.wasm; serve over HTTP
eagle export app     # dist/<name>.app (macOS bundle)
```

The same without the CLI:

```sh
crystal run src/main.cr
mkdir -p bin && crystal build src/main.cr --release -o bin/mygame
shards build --release                                        # every target in shard.yml, into bin/
sh lib/eagle/script/build-web.sh src/main.cr dist/web/mygame  # the web build eagle export web runs
```

Assets load from `assets/` next to the executable or in the working directory. Add
`Eagle.embed_assets("assets")` to `src/main.cr` to bake them into the executable instead
(`eagle init` does this unless you pass `--no-web`); then `dist/<name>/<name>` is a single
file you can move anywhere. The web build needs embedded assets, since the browser can't
read your disk.

Web builds need `lld` (`brew install lld`, `apt install lld`); Crystal's wasm libraries are
downloaded on first use (`eagle export web` keeps them in `~/.eagle/wasm-toolchain` unless the
engine checkout has its own `.wasm-toolchain/`). Everything the desktop build does works in the browser except file-system
access (embed assets), threads, and clipboard. Preview with
`cd dist/web/<name> && python3 -m http.server`.

The same commands take a file, which is how the bundled examples are exported from an
Eagle checkout: `eagle export web examples/snake/main.cr` writes `dist/web/snake/`.

## Site

`script/build-site.sh` compiles every example to WebAssembly, generates the API reference with `crystal docs`, and writes the marketing + docs site to `site/`.
Screenshots shown on the site come from `docs/screenshots/`. `script/publish-site.sh` pushes the built `site/` to the `gh-pages` branch, which GitHub Pages serves at https://joeyrobert.github.io/eagle.cr/.
