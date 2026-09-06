# Eagle guide

## The loop

`Eagle.run(MyApp)` opens the window, creates the GPU device, constructs your
`App`, calls `load`, then every frame:

1. polls events → `Input` state, `App#input`, `Node#input` (children first)
2. runs zero or more **fixed** steps (`Config#fixed_fps`, default 60):
   physics world step → `Node#physics_process` → `App#fixed_update`
3. `Node#process` → tweens → `App#update(dt)`
4. mixes audio
5. clears, renders 3D (if a `Camera3D` is current), draws the 2D scene tree
   (with the current `Camera2D`), then `App#draw(g)`

`Clock.delta`, `Clock.elapsed`, `Clock.fps`, `Clock.scale` (slow motion) are
available anywhere.

## Two styles, one engine

**Immediate (LÖVE-style)** — draw everything yourself in `draw`:

```crystal
def draw(g : Graphics)
  g.circle(400, 300, 40, color: Color::RED)
  g.draw(texture, 100, 100, rotation: Clock.elapsed, ox: 16, oy: 16)
  g.print("score #{@score}", 10, 10)
end
```

**Scene tree (Godot-style)** — build nodes and let them run:

```crystal
class Player < Sprite2D
  signal died
  def ready; texture = Texture.load("res://player.png"); end
  def process(dt : Float32)
    position += Input.vector("left", "right", "up", "down") * 200 * dt
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

Images: PNG (all bit depths, palettes, interlace), QOI, BMP — decode *and*
encode (`Image#save`). Audio: WAV (PCM 8/16/24/32, float). Models: OBJ.

## Input

```crystal
Input.map "jump", Key::Space, GamepadButton::A
Input.map "left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
Input.pressed?("jump")          # this frame
Input.down?(Key::LShift)        # held
Input.axis("left", "right")     # -1..1 (analog on sticks)
Input.vector("left", "right", "up", "down")
Input.mouse, Input.mouse_delta, Input.wheel, Input.gamepad.try(&.rumble)
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
enemy.on_hit { |d| ... }        # or enemy.hit.connect { }
enemy.emit_hit(3)               # or enemy.hit.emit(3)
enemy.died.once { ... }
```

## Physics 2D

```crystal
ground = StaticBody2D.new(position: v2(400, 580)).box(800, 40)
ball = RigidBody2D.new(position: v2(400, 0)).circle(16)
ball.restitution = 0.6
ball.on_body_entered { |other| ... }
player = KinematicBody2D.new(position: v2(100, 100)).box(24, 40)
# each physics_process:
player.velocity += v2(0, 1400 * dt)
player.move_and_slide(dt)
player.on_floor?
Physics2D.world.raycast(from, dir, 100)
```

Units are pixels and seconds; default gravity 980 px/s². Layers/masks are bit
sets on `body.layer` / `body.mask`. `Area2D` is a sensor. `debug = true` on
any body draws its shapes.

## UI

```crystal
hud = CanvasLayer.new
panel = Panel.new(size: v2(300, 0)).tap(&.anchor = Anchor::Center).tap(&.fit_content = true)
box = VBox.new(size: v2(280, 0)).tap(&.position = v2(10, 10)).tap(&.fit_content = true)
box.add(Label.new("Settings"), Slider.new(0, 100, 50), CheckBox.new("Music", true), Button.new("OK") { close })
panel.add(box); hud.add(panel); SceneTree.root.add(hud)
Theme.default.font = Font.load("res://Inter.ttf", 18)
```

Controls receive mouse/keyboard events, manage focus (`Control.focused`), and
inherit `Theme` from ancestors. Containers (`VBox`, `HBox`, `GridContainer`)
size children by `effective_min_size` and `size_flags`.

## 3D

```crystal
root.add(Camera3D.new(position: v3(0, 3, 8)).tap(&.look_at(Vec3::ZERO)))
root.add(DirectionalLight3D.new(v3(-0.5, -1, -0.3)))
root.add(MeshInstance3D.new(Mesh.cube, Material.new(Color::RED), position: v3(0, 0.5, 0)))
Scene3D.environment.fog(20, 80)
Scene3D.environment.shadows = true
cam.screen_to_ray(Input.mouse).intersect_aabb(mesh_instance.global_bounds)
```

Shaders use the GLSL 330 / 300 es common subset; `Material#shader` accepts a
custom `Shader` using the standard uniforms (`u_model`, `u_view`,
`u_projection`, lights…).

## Automated runs

`EAGLE_FRAMES=60 EAGLE_SCREENSHOT=shot.png ./game` runs 60 frames, saves the
frame and exits. `EAGLE_HEADLESS=1` hides the window. `Eagle.init`/`Eagle.step`/
`Eagle.shutdown` drive the loop manually in tests. `EAGLE_GL_DEBUG=1` checks
for GL errors after every 3D stage.

## Backends

`Platform::Base` (window/input/audio/gamepads) and `GPU::Device` (rendering)
are abstract; `Platform::SDL` + `GPU::GL33` are the desktop implementations.
A WebGL2/WebAudio backend for `wasm32` is designed for but not yet implemented —
shaders and formats are already restricted to the WebGL2 subset.
