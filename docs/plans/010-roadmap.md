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
- [x] 3D: feature fly-through (`flythrough3d`), Coin Rush (`coinrush3d`), streamed open-world driving (`joyride`), first-person shooter (`fps` / Neon Bastion), and voxel island maker (`voxel`)
- [x] CLI: `eagle new/run/build/view/examples`; viewers for PNG/QOI/BMP, OBJ, TTF, WAV, GLSL (hot reload)
- [x] README + docs/guide.md
- [ ] Windows/Linux: link flags are in place (`@[Link("SDL2")]`) but untested on those platforms
- [ ] Website
- [ ] WebAssembly/WebGL2 backend (architecture ready; see 000-vision)

## Known gaps / next steps
- Physics3D: mesh colliders are static only (no dynamic concave bodies, no mesh-vs-mesh); joints have no limits, motors or springs; sleeping is off by default and jointed bodies never sleep.
- Audio: WAV + Ogg Vorbis (Crystal decoder, bit-exact vs ffmpeg on libvorbis streams; ffmpeg's *experimental* built-in encoder's coupled stereo decodes with a wrong angle channel, likely an encoder quirk, unresolved); no MP3; no reverb/effects; 3D audio is panning + ITD + head shadow (no HRTF or occlusion).
- Fonts: TrueType `glyf` only (no CFF/OpenType, no GPOS kerning, no colour emoji).
- 3D: no skeletal animation, no cubemaps/IBL/PBR, single directional shadow cascade, no post-processing stack.
- Touch: web/browser path only; no native iOS/Android backends (they can feed `TouchEvent`), no pressure-based or multi-finger-swipe gestures, no floating joystick.
- UI: rich text is a small markup subset (bold, color, links, wrapping), with no italics, inline images or per-glyph fonts; drop-downs have no type-to-search; scroll containers hold one child and have no kinetic (touch) scrolling.
- No scene serialisation / editor; no networking.
- Windows/Linux: objects cross-compile but no full link/run test on those OSes.
- Web: no file system or threads; wireframe is emulated with edge lines; audio starts after the first click (browser policy).

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
- 2026-09-18: Web IME text input and clipboard (issue #30). New `Clipboard.text`/`text=` (SDL clipboard natively, browser clipboard on the web, in-memory fallback without a platform), `CompositionEvent` (SDL_TEXTEDITING natively, composition events on the web) and `ClipboardEvent` (browser paste/copy/cut). `TextInput` shows underlined preedit at the caret, handles copy/cut/paste (whole field; there is no selection yet, password fields never copy) and reports its caret to `Input.text_input_area` (SDL_SetTextInputRect natively, positions the hidden field on the web). Web backend: a hidden textarea takes focus while text input is on, so IMEs, mobile on-screen keyboards and clipboard events work; typed text now comes from `input` events (mobile keyboards send no usable keydown), Ctrl/Cmd+C/X/V are left to the browser instead of being forwarded as keys, and strings cross the wasm boundary through a new string event. Writes use `navigator.clipboard.writeText` with an `execCommand` fallback; reads only see what was copied or pasted inside the page. `script/web-input-check.sh` drives composition and paste/copy/cut events in headless Chrome over the DevTools protocol (the virtual-time budget stalls rAF, so it uses real time). Not tested: real IMEs and real phone keyboards (only synthetic events). Known limits: the first tap on a field focuses the hidden element outside the gesture, which iOS Safari may not honor for the keyboard; no text selection.
- 2026-09-18: Batched text with shapes (#29): font atlases now hold a white texel (`Texture#white_uv`) and `Graphics` shapes sample it when the current texture has one, so shapes and text share a batch. A spec scene of 4 rows of rect, text, line and circle went from 9 draw calls to 2; the rendered pixels are byte-identical (SHA1 of the canvas matched before and after for the pixel font and a TTF). Whitespace glyphs no longer emit empty quads.
- 2026-09-18: Touch support (#47). `TouchEvent` (per-finger began/moved/ended/cancelled with stable ids, pressure), `Touch.fingers` polling, `TouchDragEvent` with `Touch.drag_threshold`, opt-in `GestureRecognizer` node (tap, double tap, long press, swipe, pinch, rotate as signals), `VirtualJoystick`/`VirtualButton` driving actions through `Input.set_virtual`, `Script.touch_*`/`pinch`/`twist` helpers, and the `touch` example. Mouse emulation stays on by default: the engine turns an unhandled touch (first finger only) into left-mouse events flagged `from_touch?`, so existing games and UI (Button, Slider) work unchanged and never see a touch and a synthesized mouse event twice; a node claims a finger with `handled = true`. Web backend: all touches, browser identifiers remapped to small stable slots, `touchcancel` plus tab-hide/blur cancel every finger, logical (CSS px) coordinates like the mouse so hidpi is correct, and the canvas gets `touch-action: none`, no text selection/callout/tap highlight and `preventDefault` on touch events (page scroll, pull to refresh, double tap zoom). Findings: `Clock.advance` clamps a step to `max_delta`, so time-based gesture specs must advance in small steps; a `Script.tap` would shadow `Object#tap`, so it is `touch_tap`; closures in `Script` helpers must not capture locals that are reassigned later. Not done: kinetic scrolling for `ScrollContainer` (PR #49 not merged yet), native touch backends.
- 2026-09-18: Physics3D capsules, static triangle-mesh colliders and joints (issue #27). `Capsule` (sphere/capsule/box/mesh contacts, raycast), `MeshCollider` (grid-accelerated triangle lookup, sphere/capsule/box contacts, raycast; `from_mesh`/`from_triangles`), `DistanceJoint`/`BallJoint`/`HingeJoint`/`FixedJoint` solved with the contact rows (`World#distance_joint` etc.), opt-in sleeping (`World#sleep_threshold`), node helpers `capsule` and `mesh`, and a capsule spawn in the physics3d example. Findings: the box-vs-triangle SAT used interval overlap, which is zero for a flat triangle, so it must use push distance; the solver's impulse helper reset the sleep timer every step, so nothing ever slept until it only woke sleeping bodies.
- 2026-09-18: Fixed the intermittent GL crash in the full spec run (#26). Crystal's monitor moves the main fiber to a new thread after a blocking syscall over 10ms (file reads in the audio specs), leaving GL and the Cocoa event loop on the old thread; `Fiber.syscall` now runs in place in the SDL platform so the fiber stays put. Regression spec forces the case; `Scene3D.reset` added to the 3D specs' `before_each` after an order-dependent shadow failure.
- 2026-09-18: Voxel island maker (`examples/voxel`): seeded noise island, greedy-meshed `Mesh` with vertex colours, Minecraft-style DDA break/place, colour hotbar + `E` palette, AABB walking. Simulation in `world.cr` with headless specs. Native builds lock the mouse on load so `EAGLE_FRAMES` can screenshot without a click.
- 2026-09-18: Neon Bastion FPS example (`examples/fps`): mouse look via `Window.relative_mouse` (click-to-capture for pointer lock; browsers need a gesture), pulse rifle + scattergun, procedural arena, grunt (keep distance and shoot on sight) and charger (rush melee) AI, Waves and Deathmatch, spatial stereo through `Audio.play_at` / `AudioPlayer3D` (shots, footsteps, enemy hums, deaths). Simulation is in `game.cr` with headless specs. Native builds lock the mouse on load so `EAGLE_FRAMES` can screenshot without a click.
- 2026-09-18: Common game algorithms library (`Rng`, `Noise`, `Grid`, `Pathfinding`, `Procedural`, `Geometry`, `Quadtree`/`SpatialHash`, `Steering`, state machines, behavior trees, minimax) with specs and the `algorithms` example. Roguelike FOV now calls `Grid.field_of_view`.
- 2026-09-18: 3D spatial audio (`AudioPlayer3D`, `AudioListener3D`, `Audio.listener`, `Audio.play_at`, `Spatial3D`, `Attenuation`) and the `spatial_audio3d` example. Per voice: inverse/linear/exponential distance models with min/max/rolloff, equal-power pan in listener space (limited to `PAN_WIDTH` 0.8 so the far ear is never silent; a hard equal-power pan zeroed the far ear and hid the ITD entirely), up to 0.66 ms interaural delay through a 64-sample fractional delay line, one-pole head-shadow low-pass on the far ear and on sources behind, optional doppler. All parameters ramp linearly across each mixed buffer; the non-spatial path is untouched. Findings: `AudioPlayer3D` must seed its previous position in `enter_tree`, or the first frame reports zero velocity; `nodes.cr` had to require `audio_player` after `node3d`; stereo sources are downmixed to mono before spatializing. Not done: HRTF, occlusion/obstruction by geometry, reverb zones, cone (directional) sources.
- 2026-09-18: API docs pass. Findings: `Voice`/`AudioPlayback` setters only took `Float32`, so `voice.pitch = 0.8 + x` didn't compile (added `Number` setters); `CanvasLayer#layer` is not used for ordering (documented; order is tree order + `z_index`); the guide's Sprite2D example assigned locals instead of `self.position`; the full spec suite crashes intermittently inside a GL call (seen at the pre-docs commit too, roughly 1 run in 8), unresolved.
- 2026-09-18: UI widgets (issue #28): `ScrollContainer` (one child, wheel and draggable vertical/horizontal bars, track paging, `ensure_visible`, `scrolled` signal; children are scissor-clipped and clicks outside the viewport are not delivered), `OptionButton` (alias `DropDown`; popup is an overlay added to the nearest `CanvasLayer` or the root at high `z_index` so it is never clipped or covered, closes on outside click, Escape or focus loss, keyboard navigation) and `RichTextLabel` (alias `RichText`; `**bold**` / `[b]`, `[color=#hex]`, `[url=meta]` with `meta_clicked`, newlines and word wrap; bold is drawn as a one-pixel double strike). Headless specs in `spec/ui`, shown in `examples/ui`. Findings: Crystal treated `@overlay` as nilable when `self` was passed to a helper object inside `initialize`, so the popup parts are now built lazily; `Button` ignores a `size:` inside boxes (the box uses `min_size`), which matters when sizing scroll content in specs.
- 2026-09-18: project started; Phase 0 and Phase 1 landed (99 specs green). Smoke and sandbox2d screenshots verified visually.
- 2026-09-18: decided `Eagle.run(AppClass)` constructs the app after init so GPU resources can live in ivars.
- 2026-09-18: Phase 5 landed: 6 2D games + 2 3D programs, CLI, docs (167 specs). Findings: sphere/cylinder-cap winding was inverted (spec now checks winding for every primitive); `eagle view` doubles as a regression tool.
- 2026-09-18: Phases 2–4 landed (152 specs). Findings: Crystal class vars are per-subclass (focus tracking moved to a module); `getter? x` + `signal x` clash in the parser (signal ivars are now `@_sig_*`); sequential contact impulses need manifold-level Jacobi to avoid drift; GL errors are sticky so the spec harness checks after every render; render targets are stored top-row-first by convention.
