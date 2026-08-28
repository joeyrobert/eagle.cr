# Roadmap & progress log

Status legend: [ ] todo · [~] in progress · [x] done · [!] blocked/notes

Requirements gathered from the project owner (2026-09-18):
* 2D + 3D, Crystal-native, library + engine + viewer, compiles to one executable.
* Windows support (later), controllers, Godot-style object model, asset
  management, sound, GPU acceleration, particles, shaders.
* **Modular backends** so WebAssembly/WebGL is possible (graphics, audio,
  controllers are plug-and-play). See `000-vision-and-architecture.md`.
* **Well tested**: every user-facing feature and module has specs; GPU specs
  render into canvases and assert pixels.
* **No name clashes** with the Crystal stdlib (`include Eagle` must be safe):
  hence `Eagle::Emitter` (not `Signal`), `Eagle::Clock` (not `Time`), no
  `Eagle::Log` constant.
* **UI/font framework** as part of the engine (Control nodes, layout, theme,
  TrueType fonts).
* Examples: **5 complete 2D games** (chess is one of them) and **2 3D
  examples** (a feature fly-through/test and a small 3D game). Validate all.

## Phase 0 — Foundations
- [x] Repo, shard.yml, plan docs
- [x] Math: Vec2/3/4, Mat3/4, Quat, Rect, AABB, Ray, Color, Transform2D, Mathf (+ specs)
- [x] SDL2 + GL bindings, GL loader via proc addresses, Platform abstraction, GPU::Device abstraction, GL33 backend
- [x] PNG/QOI/BMP decode/encode (+ specs), Image class, screenshot to PNG
- [x] Frame-limited runs for automated verification (`EAGLE_FRAMES`, `EAGLE_SCREENSHOT`, `EAGLE_HEADLESS`, `EAGLE_SIZE`)

## Phase 1 — 2D
- [x] Shader (3 creation styles), Texture/TextureRegion, Canvas, Graphics batch (sprites, rects, circles, ellipses, arcs, lines with mitres, polygons incl. concave, text)
- [x] Built-in 5x7 bitmap font, `print`/`printf`, wrapping, alignment
- [x] Camera2D (node), CanvasLayer, transform stack, scissor, blend modes
- [x] Input: keyboard, mouse, gamepad, action map with analog strengths
- [x] Node tree, `signal` macro (`Emitter`), SceneTree (groups, deferred, scene change, pause modes)
- [x] Node2D, Sprite2D, AnimatedSprite2D, Label, Timer, Polygon2D, Line2D, TileMap, Tween/Ease
- [x] Examples: smoke, sandbox2d

## Phase 2 — Audio, physics, particles
- [ ] Audio mixer (Float32, main-thread queue), WAV codec, synth tones, Sound/Voice, AudioPlayer & AudioPlayer2D nodes
- [ ] Physics2D: circle/box/polygon, SAT, impulse solver, spatial hash, raycast, queries; StaticBody2D/RigidBody2D/KinematicBody2D/Area2D/CollisionShape2D; move_and_slide
- [ ] Particles2D
- [ ] Specs for all of the above

## Phase 3 — Fonts & UI
- [ ] TrueType parser + rasteriser (cmap, glyf, hmtx, kern), glyph atlas, `Font.load`
- [ ] UI: Control base (anchors, margins, focus, mouse/keyboard), Panel, Button, Label, CheckBox, Slider, ProgressBar, TextInput, VBox/HBox/Grid containers, Theme
- [ ] Specs

## Phase 4 — 3D
- [ ] Mesh (interleaved P/N/UV/Color/Tangent), primitives (cube, sphere, plane, cylinder, capsule, torus), OBJ loader
- [ ] Material (unlit/Blinn-Phong/PBR-lite), Camera3D, DirectionalLight/PointLight/SpotLight, fog, skybox, shadow map
- [ ] Node3D, MeshInstance3D, Camera3D node, Light nodes, Renderer3D, Physics3D basics (AABB/sphere/raycast)
- [ ] Specs (render to canvas and check pixels)

## Phase 5 — Games & polish
- [ ] 2D games: Chess, Breakout, Asteroids, Platformer, Snake
- [ ] 3D: feature fly-through, simple 3D game
- [ ] CLI: `eagle new`, `eagle run`, `eagle view` (image/model/font viewer)
- [ ] Windows/Linux link flags, docs, website

## Log
- 2026-09-18: project started; Phase 0 and Phase 1 landed (99 specs green). Smoke and sandbox2d screenshots verified visually.
- 2026-09-18: decided `Eagle.run(AppClass)` constructs the app after init so GPU resources can live in ivars.
