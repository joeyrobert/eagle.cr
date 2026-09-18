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

## Phase 0: Foundations
- [x] Repo, shard.yml, plan docs
- [x] Math: Vec2/3/4, Mat3/4, Quat, Rect, AABB, Ray, Color, Transform2D, Mathf (+ specs)
- [x] SDL2 + GL bindings, GL loader via proc addresses, Platform abstraction, GPU::Device abstraction, GL33 backend
- [x] PNG/QOI/BMP decode/encode (+ specs), Image class, screenshot to PNG
- [x] Frame-limited runs for automated verification (`EAGLE_FRAMES`, `EAGLE_SCREENSHOT`, `EAGLE_HEADLESS`, `EAGLE_SIZE`)

## Phase 1: 2D
- [x] Shader (3 creation styles), Texture/TextureRegion, Canvas, Graphics batch (sprites, rects, circles, ellipses, arcs, lines with mitres, polygons incl. concave, text)
- [x] Built-in 5x7 bitmap font, `print`/`printf`, wrapping, alignment
- [x] Camera2D (node), CanvasLayer, transform stack, scissor, blend modes
- [x] Input: keyboard, mouse, gamepad, action map with analog strengths
- [x] Node tree, `signal` macro (`Emitter`), SceneTree (groups, deferred, scene change, pause modes)
- [x] Node2D, Sprite2D, AnimatedSprite2D, Label, Timer, Polygon2D, Line2D, TileMap, Tween/Ease
- [x] Examples: smoke, sandbox2d

## Phase 2: Audio, physics, particles
- [x] Audio mixer (Float32, main-thread queue), WAV codec, synth tones, Sound/Voice (pitch/pan/loop/fade), buses, streams, AudioPlayer & AudioPlayer2D nodes
- [x] Physics2D: circle/box/polygon, SAT with clipped manifolds, manifold-level Jacobi impulse solver with Baumgarte bias, spatial hash, raycast, point/rect/shape queries, layers/masks, sensors, contact signals; StaticBody2D/RigidBody2D/KinematicBody2D(CharacterBody2D)/Area2D/CollisionShape2D/RayCast2D; move_and_slide with substeps + floor snap
- [x] Particles2D (rate/burst/one-shot, gravity, damping, scale & colour over life, emission shapes, blend modes)
- [x] Specs for all of the above; physics example verified visually

## Phase 3: Fonts & UI
- [x] TrueType parser (cmap 0/4/6/12, glyf simple+composite, hmtx, kern, name, TTC) + font-rs style signed-area rasteriser, glyph atlases, `Font.load(path, size)`
- [x] UI: Control (anchors, margins, focus, hover, mouse/keyboard), Panel, Label, Button (toggle/icon), CheckBox, Slider, ProgressBar, TextInput, ImageControl, VBox/HBox/GridContainer/Spacer, Theme (dark/light)
- [x] Specs; UI example verified with Arial TTF
- [!] CFF/OpenType outlines unsupported (glyf only). No GPOS kerning.

## Phase 4: 3D
- [x] Mesh (P/N/UV/Color), primitives (quad, plane, box, sphere, cylinder, cone, capsule, torus, grid, axes), OBJ import/export, normals, flat shading, append/transform
- [x] Material (Blinn-Phong + metallic tint, unlit, textures, transparency, wireframe, custom shaders/uniforms), Camera3D (perspective/ortho, rays, projection, fly controls), Directional/Point/Spot lights, procedural sky, fog, PCF shadow map (directional)
- [x] Node3D, MeshInstance3D, Scene3D collector, Renderer3D (sorted opaque/transparent passes)
- [x] Specs incl. pixel checks for lighting and cast shadows; fly-through example verified
- [ ] Physics3D basics (AABB/sphere/raycast helpers exist in math; a simple world is TODO)

## Phase 5: Games & polish
- [x] 2D games: Chess (full rules, perft-verified move generator, alpha-beta AI), Checkers (1/2 players, forced captures, multi-jumps, kings, AI), Breakout, Asteroids, Platformer, Snake, all self-contained (procedural assets & sounds)
- [x] 3D: feature fly-through (`flythrough3d`), Coin Rush (`coinrush3d`), streamed open-world driving (`joyride`), and first-person shooter (`fps` / Neon Bastion)
- [x] CLI: `eagle new/run/build/view/examples`; viewers for PNG/QOI/BMP, OBJ, TTF, WAV, GLSL (hot reload)
- [x] README + docs/guide.md
- [ ] Windows/Linux: link flags are in place (`@[Link("SDL2")]`) but untested on those platforms
- [ ] Website
- [ ] WebAssembly/WebGL2 backend (architecture ready; see 000-vision)

## Known gaps / next steps
- Physics3D: spheres + oriented boxes only (no capsules/meshes/joints); no sleeping.
- Audio: WAV + Ogg Vorbis (Crystal decoder, bit-exact vs ffmpeg on libvorbis streams; ffmpeg's *experimental* built-in encoder's coupled stereo decodes with a wrong angle channel, likely an encoder quirk, unresolved); no MP3; no reverb/effects; 3D audio is panning + ITD + head shadow (no HRTF or occlusion).
- Fonts: TrueType `glyf` only (no CFF/OpenType, no GPOS kerning, no colour emoji).
- 3D: no skeletal animation, no cubemaps/IBL/PBR, single directional shadow cascade, no post-processing stack.
- UI: no scroll containers, drop-downs, or rich text.
- No scene serialisation / editor; no networking.
- 2D text switches textures per glyph run (many draw calls with TTF); an atlas-with-white-pixel optimisation would fix it.
- Windows/Linux: objects cross-compile but no full link/run test on those OSes.
- Web: no file system, clipboard or threads; wireframe is emulated with edge lines; text input uses keydown (no IME); audio starts after the first click (browser policy).

## Phase 6: Completeness pass (2026-09-18)
- [x] Event injection (`Eagle.inject`) + `Script` scheduler; loop-driven integration specs; Tab focus navigation; interactions demo
- [x] Cross-compile check (Windows MSVC, Linux x86_64/aarch64 objects build)
- [x] Physics3D world + nodes + specs + example
- [x] Ogg Vorbis decoder (floor 1, residues 0/1/2, coupling, FFT-based IMDCT) validated against ffmpeg
- [x] Roguelike example (procedural dungeon, shadowcasting FOV, AI, items; unit-tested core)
- [x] WebAssembly/WebGL2 backend: stdlib shims (event loop, threads, monitor, timezone), `web/eagle.js` (WASI polyfill, WebGL2 object tables, WebAudio queue, input/gamepads), `Platform::Web`, wasm GL bindings from the same function table, pure-Crystal zlib (no libz), wasm-ld wrapper for exports; all 16 examples run in headless Chrome
- [x] Exports: `eagle export exe|web|app`, compile-time asset embedding (`Eagle.embed_assets`)
- [x] Marketing site + docs site (`script/build-site.sh` → `site/`): screenshots, code tabs, API groups, playable examples with source, guide/architecture/roadmap pages, `crystal docs` API reference
- [x] Site redesign (eagle palette, Crystal syntax highlighting via the compiler's lexer, themed API reference) published to GitHub Pages from `gh-pages` (`script/publish-site.sh`)
- [x] Usage docs on every public type: overview, when to use it, and an example; 125 doc examples type-checked by `script/check_doc_examples.cr`

## Log
- 2026-09-18: Neon Bastion FPS example (`examples/fps`): mouse look via `Window.relative_mouse` (click-to-capture for pointer lock; browsers need a gesture), pulse rifle + scattergun, procedural arena, grunt (keep distance and shoot on sight) and charger (rush melee) AI, Waves and Deathmatch, spatial stereo through `Audio.play_at` / `AudioPlayer3D` (shots, footsteps, enemy hums, deaths). Simulation is in `game.cr` with headless specs. Native builds lock the mouse on load so `EAGLE_FRAMES` can screenshot without a click.
- 2026-09-18: 3D spatial audio (`AudioPlayer3D`, `AudioListener3D`, `Audio.listener`, `Audio.play_at`, `Spatial3D`, `Attenuation`) and the `spatial_audio3d` example. Per voice: inverse/linear/exponential distance models with min/max/rolloff, equal-power pan in listener space (limited to `PAN_WIDTH` 0.8 so the far ear is never silent; a hard equal-power pan zeroed the far ear and hid the ITD entirely), up to 0.66 ms interaural delay through a 64-sample fractional delay line, one-pole head-shadow low-pass on the far ear and on sources behind, optional doppler. All parameters ramp linearly across each mixed buffer; the non-spatial path is untouched. Findings: `AudioPlayer3D` must seed its previous position in `enter_tree`, or the first frame reports zero velocity; `nodes.cr` had to require `audio_player` after `node3d`; stereo sources are downmixed to mono before spatializing. Not done: HRTF, occlusion/obstruction by geometry, reverb zones, cone (directional) sources.
- 2026-09-18: API docs pass. Findings: `Voice`/`AudioPlayback` setters only took `Float32`, so `voice.pitch = 0.8 + x` didn't compile (added `Number` setters); `CanvasLayer#layer` is not used for ordering (documented; order is tree order + `z_index`); the guide's Sprite2D example assigned locals instead of `self.position`; the full spec suite crashes intermittently inside a GL call (seen at the pre-docs commit too, roughly 1 run in 8), unresolved.
- 2026-09-18: project started; Phase 0 and Phase 1 landed (99 specs green). Smoke and sandbox2d screenshots verified visually.
- 2026-09-18: decided `Eagle.run(AppClass)` constructs the app after init so GPU resources can live in ivars.
- 2026-09-18: Phase 5 landed: 6 2D games + 2 3D programs, CLI, docs (167 specs). Findings: sphere/cylinder-cap winding was inverted (spec now checks winding for every primitive); `eagle view` doubles as a regression tool.
- 2026-09-18: Phases 2–4 landed (152 specs). Findings: Crystal class vars are per-subclass (focus tracking moved to a module); `getter? x` + `signal x` clash in the parser (signal ivars are now `@_sig_*`); sequential contact impulses need manifold-level Jacobi to avoid drift; GL errors are sticky so the spec harness checks after every render; render targets are stored top-row-first by convention.
