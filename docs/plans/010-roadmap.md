# Roadmap & progress log

Status legend: [ ] todo · [~] in progress · [x] done · [!] blocked/notes

## Phase 0 — Foundations
- [x] Repo, shard.yml, plan docs
- [ ] Math: Vec2/3/4, Mat3/4, Quat, Rect, Color, Transform2D (+ specs)
- [ ] SDL2 + GL bindings, GL loader, Window, clear, swap
- [ ] PNG decode/encode (+ specs), screenshot to PNG
- [ ] Frame-limited runs for automated verification

## Phase 1 — 2D
- [ ] Shader, Texture, VertexBuffer, Graphics2D batch (sprites, rects, circles, lines, polygons)
- [ ] Built-in bitmap font, `print`
- [ ] Camera2D, RenderTarget (canvas)
- [ ] Input: keyboard, mouse, action map
- [ ] Node tree, signals, SceneTree, Node2D, Sprite2D, AnimatedSprite2D, Label, Timer, Tween
- [ ] Example: 2D sandbox

## Phase 2 — Audio, physics, particles
- [ ] Audio mixer, WAV loader, procedural tones, AudioPlayer node
- [ ] Physics2D: circle/AABB/polygon, bodies, impulse solver, spatial hash, raycast; Area2D/RigidBody2D/StaticBody2D/KinematicBody2D nodes
- [ ] Particles2D
- [ ] Examples: breakout, physics playground

## Phase 3 — 3D
- [ ] Mesh, Material, Camera3D, lights, primitives, OBJ loader, Node3D/MeshInstance3D
- [ ] Skybox, fog, basic shadow map
- [ ] Example: 3D scene

## Phase 4 — Polish
- [ ] TTF fonts (Crystal parser + rasterizer)
- [ ] Gamepad (SDL_GameController), rumble
- [ ] CLI: `eagle new`, `eagle run`, `eagle view`
- [ ] Windows/Linux link flags, docs, website

## Log
- 2026-09-18: project started.
