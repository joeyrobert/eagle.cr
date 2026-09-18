# Eagle

A Crystal-native 2D/3D game engine: library, engine and viewer in one shard,
compiling to a single executable. Inspired by LÖVE (immediate-mode drawing,
`load/update/draw`) and Godot (scene tree, nodes, signals, action map).

Only two native dependencies: **SDL2** and the platform's **OpenGL 3.3**.
Everything else — PNG/QOI/BMP/WAV codecs, TrueType fonts, audio mixer,
physics, particles, UI, 3D renderer with shadows — is written in Crystal.

```crystal
require "eagle"
include Eagle

class Game < App
  @player = Sprite2D.new(Texture.new(Image.circle(32, Color::YELLOW)), Window.center)

  def load
    Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    SceneTree.root.add(@player)
  end

  def update(dt : Float32)
    @player.x += Input.axis("left", "right") * 250 * dt
  end

  def draw(g : Graphics)
    g.print("Hello, Eagle!", 10, 10)
  end
end

Eagle.run(Game, title: "My Game", width: 960, height: 540)
```

## Features

| Area | What you get |
|------|--------------|
| Core | `App` callbacks, fixed + variable timestep, `Clock`, logging, headless/screenshot runs for CI |
| Scene tree | `Node`, `Node2D`, `Node3D`, `SceneTree`, groups, deferred calls, pause modes, `signal` macro |
| 2D | Batched `Graphics` (sprites, shapes, thick lines, concave polygons, text), `Camera2D`, `CanvasLayer`, `Canvas` render targets, blend modes, scissor, custom shaders (LÖVE-style `effect`) |
| Nodes | `Sprite2D`, `AnimatedSprite2D`, `Label`, `Timer`, `TileMap`, `Polygon2D`, `Line2D`, `Particles2D`, `AudioPlayer(2D)` |
| Input | Keyboard, mouse, gamepads (SDL GameController), action map with analog strengths, text input |
| Audio | Float32 mixer, WAV + Ogg Vorbis (Crystal decoder), procedural tones, voices with pitch/pan/fade, buses, streams |
| Physics 2D | Circles/boxes/polygons, SAT, impulse solver, spatial hash, raycasts, layers, sensors, `RigidBody2D`, `StaticBody2D`, `KinematicBody2D` (`move_and_slide`), `Area2D`, `RayCast2D` |
| Physics 3D | Spheres and oriented boxes, SAT manifolds, impulse solver, raycasts, `RigidBody3D`, `StaticBody3D`, `KinematicBody3D`, `Area3D`, `RayCast3D` |
| Web | `wasm32-wasi` build with a WebGL2/WebAudio/DOM runtime (`web/eagle.js`); every example runs in the browser |
| Export | Single executable with compile-time embedded assets, web bundle, macOS app |
| Fonts | Built-in pixel font, TrueType parser + anti-aliased rasteriser, glyph atlases, kerning |
| UI | `Control`, `Panel`, `Label`, `Button`, `CheckBox`, `Slider`, `ProgressBar`, `TextInput`, `VBox`/`HBox`/`GridContainer`, themes, focus & keyboard navigation |
| 3D | `Mesh` primitives + OBJ, `Material` (Blinn-Phong, textures, transparency, wireframe, custom shaders), `Camera3D`, directional/point/spot lights, PCF shadow maps, procedural sky, fog |
| Tween | `Tween.to/value/after/sequence` with 17 easings |
| Tools | `eagle new/run/build/view/examples` CLI; viewers for images, OBJ, TTF, WAV, GLSL (hot reload) |

## Getting started

```sh
brew install sdl2            # macOS (Linux: libsdl2-dev; Windows: SDL2 dev libs on the lib path)
git clone https://github.com/joeyrobert/eagle.cr && cd eagle.cr
shards build                 # builds bin/eagle
bin/eagle examples           # list examples
bin/eagle examples asteroids # run one
bin/eagle new mygame && cd mygame && shards install && ../bin/eagle run
```

Add to an existing project's `shard.yml`:

```yaml
dependencies:
  eagle:
    github: joeyrobert/eagle.cr
```

## Examples

`examples/` contains complete, self-contained programs (no external assets):

* **Games (2D):** `chess` (full rules + alpha-beta AI), `checkers` (1 or 2 players, AI), `breakout`, `asteroids`, `platformer`, `snake`, `roguelike`
* **Games (3D):** `coinrush3d`
* **Feature tests:** `smoke`, `sandbox2d`, `physics`, `physics3d`, `ui`, `interactions`, `embedded`, `flythrough3d`

Every example supports `EAGLE_FRAMES=60 EAGLE_SCREENSHOT=out.png` for automated verification.

## Web and exports

```sh
bin/eagle export web examples/breakout/main.cr    # WebAssembly + WebGL2 bundle in dist/web/breakout/
bin/eagle export exe examples/breakout/main.cr    # single release executable (embed assets with Eagle.embed_assets)
bin/eagle export app examples/breakout/main.cr    # macOS .app
script/build-site.sh                              # marketing + docs site with every example playable in the browser
```

Web builds need `brew install lld`; Crystal's wasm libraries are fetched automatically.

## Testing

```sh
crystal spec                 # ~210 specs incl. GPU-backed pixel tests (hidden window)
EAGLE_NO_GPU=1 crystal spec  # skip GPU specs (CI without a display)
```

## Documentation

* `docs/guide.md` — concepts and API tour
* `docs/plans/` — architecture, roadmap, findings
* `crystal docs` — API reference

## License

MIT
