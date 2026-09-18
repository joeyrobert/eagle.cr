# Eagle: Vision & Architecture

Eagle is a Crystal-native game engine. Goals, in priority order:

1. **Easy things are easy, hard things are possible.** A working game is a few
   dozen lines. Everything is still reachable (raw GL, shaders, custom nodes).
2. **Crystal all the way down.** Only two native dependencies: SDL2 (window,
   input, gamepad, audio device) and the platform's OpenGL. Image decoding,
   audio mixing, fonts, physics, scene tree, particles, asset caching are
   Crystal.
3. **Library + engine + viewer.** `require "eagle"` in any shard, or use the
   `eagle` CLI to scaffold/run/view. Games compile to a single executable.
4. **Fast feedback loop.** Deterministic frame stepping, screenshots to PNG,
   headless-ish runs (`EAGLE_FRAMES=60 EAGLE_SCREENSHOT=out.png`) so tests and
   agents can verify rendering without a human.

## Inspirations

* **LÖVE**: immediate-mode `love.graphics` style API, callbacks `load/update/draw`.
* **Godot**: node/scene tree, signals, `_ready/_process/_physics_process`,
  Node2D/Node3D families, input action map, `res://` asset paths, one-file shaders.

## Layers

```
 ┌──────────────────────────────────────────────────────────────┐
 │ Games / Examples / CLI viewer                                │
 ├──────────────────────────────────────────────────────────────┤
 │ Nodes: Node2D Sprite2D Camera2D Label Area2D RigidBody2D …    │
 │        Node3D MeshInstance3D Camera3D Light3D Particles …     │
 ├──────────────────────────────────────────────────────────────┤
 │ Systems: SceneTree · Signals · Input (actions, gamepad)      │
 │          Assets (cache, res://) · Audio mixer · Physics2D/3D  │
 │          Particles · Fonts (bitmap + TTF) · Tween · Timer     │
 ├──────────────────────────────────────────────────────────────┤
 │ Graphics: Graphics2D (batched) · Renderer3D · Shader ·        │
 │           Texture · Mesh · Material · RenderTarget · Camera   │
 ├──────────────────────────────────────────────────────────────┤
 │ Platform: Window · Time · Events  (SDL2)   GL 3.3 core loader │
 ├──────────────────────────────────────────────────────────────┤
 │ Math: Vec2/3/4 Mat3/4 Quat Rect Color Transform2D             │
 └──────────────────────────────────────────────────────────────┘
```

## Key decisions

* **GL 3.3 core via function-pointer loader** (`SDL_GL_GetProcAddress`). Works
  on macOS (4.1 core max), Linux, Windows without a loader library. Backend is
  behind `Eagle::GL`; a Vulkan/Metal backend is possible later but not planned.
* **Audio**: SDL opens the device; Eagle mixes Float32 stereo in Crystal on the
  main thread each frame and pushes with `SDL_QueueAudio`. No foreign-thread
  callbacks into Crystal (GC-safe). Latency ~ 2 frames.
* **Images**: Crystal PNG decoder/encoder (zlib from stdlib), plus BMP/TGA/QOI.
* **Fonts**: an embedded bitmap font so `print` works with zero assets, and a
  Crystal TrueType parser + rasterizer for real fonts.
* **Scene tree**: `Node` with lifecycle hooks; signals via a `signal` macro
  (`signal hit(damage : Int32)` → `on_hit { |d| }` / `emit_hit(d)`).
* **Determinism**: fixed-timestep `physics_process`, variable `process`.
* **Assets**: `res://` root resolved from the executable dir, the project dir, or
  `EAGLE_ASSETS`. Cached by path; hot reload later.

## Directory layout

```
src/eagle.cr              library entry
src/eagle/lib/            C bindings (sdl2, gl)
src/eagle/math/
src/eagle/core/           engine loop, window, time, events, log, signals, node tree
src/eagle/graphics/       gl objects, 2D batcher, 3D renderer, fonts
src/eagle/assets/         loader/cache and codecs (png, wav, obj, ttf)
src/eagle/audio/
src/eagle/physics/
src/eagle/particles/
src/eagle/nodes/          Godot-style nodes
src/cli.cr                `eagle` CLI (new/run/view)
examples/                 runnable examples & games
spec/                     unit specs (no window needed)
docs/plans/               plans and progress logs (this folder)
```

## Roadmap (phases)

See `010-roadmap.md`, updated as work lands.

## Modular backends (added 2026-09-18 after user request for WASM/WebGL)

Everything platform-specific sits behind small abstract classes so backends are
plug-and-play:

| Abstraction              | Default impl (desktop) | Planned                    |
|--------------------------|------------------------|----------------------------|
| `Eagle::Platform::Base`  | `Platform::SDL`        | `Platform::Web` (JS glue)  |
| `Eagle::GPU::Device`     | `GPU::GL33`            | `GPU::WebGL2`              |
| `Eagle::Audio::Device`   | `Audio::SDLDevice`     | `Audio::WebAudioDevice`    |
| `Eagle::Input::Source`   | SDL events             | DOM events                 |

Rules that keep WebGL2 reachable:

* Shaders are written **once** in the GLSL 300 es / GL 3.3 common subset. The
  backend prepends the `#version` line and precision qualifiers. No geometry
  shaders, no compute, no `gl_VertexID` tricks, no bindless. UBO-free by default
  (plain uniforms) so GLES 3.0 and WebGL2 both work.
* Vertex formats and texture formats are limited to the WebGL2 set
  (RGBA8, RGB8, R8, depth24, float32 attributes).
* The renderer never calls `LibGL` directly; it calls `GPU::Device`.
* Engine code never calls SDL directly; it calls `Platform`.
* Audio is mixed in Crystal into Float32 frames; the device just consumes them.

Crystal's `wasm32-unknown-wasi` target is experimental; the web backend is a
later phase and requires a JS shim for WebGL2/WebAudio/DOM input. The
architecture above is what makes it possible without an engine rewrite.
