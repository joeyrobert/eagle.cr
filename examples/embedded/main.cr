require "../../src/eagle"
include Eagle

# All assets live inside the executable: `Eagle.embed_assets` bakes the
# `assets/` folder in at compile time, so this game ships as one file.
Eagle.embed_assets("examples/embedded/assets")

class EmbeddedDemo < App
  @tex : Texture? = nil
  @fx : Shader? = nil

  def load
    @tex = Texture.load("res://tile.png", GPU::Filter::Nearest, GPU::Wrap::Repeat)
    @fx = Shader.load("res://shader.glsl")
    Sound.load("res://blip.wav").play
  end

  def draw(g : Graphics)
    g.with_shader(@fx) { g.draw_tiled(@tex.not_nil!, Rect.new(40, 60, Window.width - 80, Window.height - 120), v2(Clock.elapsed * 30, 0)) }
    g.print("embedded assets: #{Assets.embedded_paths.join(", ")}", 10, 10)
    g.print("no files are read from disk — try moving the executable anywhere", 10, Window.height - 26, Color::GRAY)
  end
end

Eagle.run(EmbeddedDemo, title: "Eagle embedded assets", width: 640, height: 400)
