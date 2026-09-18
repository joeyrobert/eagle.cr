require "./eagle/version"
require "./eagle/math/math"
require "./eagle/core/error"
require "./eagle/core/log"
require "./eagle/core/clock"
require "./eagle/core/signal"
require "./eagle/core/events"
require "./eagle/input/keys"
require "./eagle/input/input"
require "./eagle/platform/wasm_shim"
require "./eagle/platform/base"
{% if flag?(:wasm32) %}
  require "./eagle/platform/web"
{% else %}
  require "./eagle/platform/sdl"
{% end %}
require "./eagle/gpu/device"
require "./eagle/gpu/gl33"
require "./eagle/assets/image"
require "./eagle/assets/codecs/codecs"
require "./eagle/assets/assets"
require "./eagle/graphics/texture"
require "./eagle/graphics/shader"
require "./eagle/graphics/canvas"
require "./eagle/graphics/font"
require "./eagle/graphics/truetype"
require "./eagle/graphics/graphics"
require "./eagle/graphics3d/mesh"
require "./eagle/graphics3d/material"
require "./eagle/graphics3d/renderer3d"
require "./eagle/audio/audio"
require "./eagle/physics/physics2d"
require "./eagle/physics/physics3d"
require "./eagle/core/tween"
require "./eagle/core/script"
require "./eagle/core/node"
require "./eagle/core/scene_tree"
require "./eagle/core/window"
require "./eagle/nodes/nodes"
require "./eagle/ui/ui"
require "./eagle/core/engine"

# Eagle is a 2D and 3D game engine written in Crystal. This page is the API reference;
# each type explains what it's for and shows how to use it.
#
# ## Where to start
#
# * `App` and `Eagle.run` open a window and run your game loop.
# * `Graphics` draws shapes, sprites and text immediately, in the style of LÖVE.
# * `Node`, `Node2D` and `SceneTree` build a Godot-style scene of objects that update and draw themselves.
# * `Input` reads keys, mouse and gamepads, and maps them to named actions.
#
# ## By topic
#
# * **2D:** `Sprite2D`, `AnimatedSprite2D`, `Camera2D`, `TileMap`, `Particles2D`, `Polygon2D`, `CanvasLayer`
# * **3D:** `Node3D`, `MeshInstance3D`, `Camera3D`, `DirectionalLight3D`, `Mesh`, `Material`, `Scene3D`
# * **Physics:** `RigidBody2D`, `KinematicBody2D`, `Area2D`, `Physics2D`, and their 3D versions
# * **UI:** `Control`, `Button`, `Label`, `Slider`, `TextInput`, `VBox`, `Theme`
# * **Audio:** `Sound`, `Voice`, `AudioPlayer`, `AudioPlayer3D`, `AudioListener3D`, `Audio`
# * **Assets:** `Assets`, `Texture`, `Image`, `Font`, `Shader`
# * **Timing:** `Clock`, `Timer`, `Tween`
# * **Math:** `Vec2`, `Vec3`, `Rect`, `Color`, `Mathf`, `Transform2D`, `Quat`
#
# ## A complete game
#
# ```
# class Game < App
#   @player = Sprite2D.new(Texture.new(Image.circle(24, Color::YELLOW)), Vec2.new(480, 270))
#   @score = 0
#
#   def load : Nil
#     Input.map "left", Key::A, Key::Left
#     Input.map "right", Key::D, Key::Right
#     SceneTree.root.add(@player)
#   end
#
#   def update(dt : Float32) : Nil
#     @player.x += Input.axis("left", "right") * 300 * dt
#     @score += 1 if Input.pressed?(Key::Space)
#   end
#
#   def draw(g : Graphics) : Nil
#     g.print("score #{@score}", 10, 10, scale: 2)
#   end
# end
#
# Eagle.run(Game, title: "My Game", width: 960, height: 540)
# ```
module Eagle
end
