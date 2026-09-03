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
- [x] Audio mixer (Float32, main-thread queue), WAV codec, synth tones, Sound/Voice (pitch/pan/loop/fade), buses, streams, AudioPlayer & AudioPlayer2D nodes
- [x] Physics2D: circle/box/polygon, SAT with clipped manifolds, manifold-level Jacobi impulse solver with Baumgarte bias, spatial hash, raycast, point/rect/shape queries, layers/masks, sensors, contact signals; StaticBody2D/RigidBody2D/KinematicBody2D(CharacterBody2D)/Area2D/CollisionShape2D/RayCast2D; move_and_slide with substeps + floor snap
- [x] Particles2D (rate/burst/one-shot, gravity, damping, scale & colour over life, emission shapes, blend modes)
- [x] Specs for all of the above; physics example verified visually

## Phase 3 — Fonts & UI
- [x] TrueType parser (cmap 0/4/6/12, glyf simple+composite, hmtx, kern, name, TTC) + font-rs style signed-area rasteriser, glyph atlases, `Font.load(path, size)`
- [x] UI: Control (anchors, margins, focus, hover, mouse/keyboard), Panel, Label, Button (toggle/icon), CheckBox, Slider, ProgressBar, TextInput, ImageControl, VBox/HBox/GridContainer/Spacer, Theme (dark/light)
- [x] Specs; UI example verified with Arial TTF
- [!] CFF/OpenType outlines unsupported (glyf only). No GPOS kerning.

## Phase 4 — 3D
- [x] Mesh (P/N/UV/Color), primitives (quad, plane, box, sphere, cylinder, cone, capsule, torus, grid, axes), OBJ import/export, normals, flat shading, append/transform
- [x] Material (Blinn-Phong + metallic tint, unlit, textures, transparency, wireframe, custom shaders/uniforms), Camera3D (perspective/ortho, rays, projection, fly controls), Directional/Point/Spot lights, procedural sky, fog, PCF shadow map (directional)
- [x] Node3D, MeshInstance3D, Scene3D collector, Renderer3D (sorted opaque/transparent passes)
- [x] Specs incl. pixel checks for lighting and cast shadows; fly-through example verified
- [ ] Physics3D basics (AABB/sphere/raycast helpers exist in math; a simple world is TODO)

## Phase 5 — Games & polish
- [ ] 2D games: Chess, Breakout, Asteroids, Platformer, Snake
- [ ] 3D: feature fly-through, simple 3D game
- [ ] CLI: `eagle new`, `eagle run`, `eagle view` (image/model/font viewer)
- [ ] Windows/Linux link flags, docs, website

## Log
- 2026-09-18: project started; Phase 0 and Phase 1 landed (99 specs green). Smoke and sandbox2d screenshots verified visually.
- 2026-09-18: decided `Eagle.run(AppClass)` constructs the app after init so GPU resources can live in ivars.
- 2026-09-18: Phases 2–4 landed (152 specs). Findings: Crystal class vars are per-subclass (focus tracking moved to a module); `getter? x` + `signal x` clash in the parser (signal ivars are now `@_sig_*`); sequential contact impulses need manifold-level Jacobi to avoid drift; GL errors are sticky so the spec harness checks after every render; render targets are stored top-row-first by convention.
