require "../../src/eagle"

# Minimal smoke test: draws shapes, sprites and text. Run with
#   EAGLE_FRAMES=5 EAGLE_SCREENSHOT=smoke.png crystal run examples/smoke/main.cr
class Smoke < Eagle::App
  @tex : Eagle::Texture? = nil

  def load
    @tex = Eagle::Texture.new(Eagle::Image.checkerboard(64, 64, 8, Eagle::Color::YELLOW, Eagle::Color::MAGENTA))
  end

  def draw(g : Eagle::Graphics)
    g.rect(20, 20, 200, 120, color: Eagle::Color::RED)
    g.rect_line(20, 20, 200, 120, color: Eagle::Color::WHITE)
    g.circle(400, 100, 60, color: Eagle::Color::GREEN)
    g.circle(400, 100, 60, Eagle::DrawMode::Line, color: Eagle::Color::BLACK)
    g.line(0, 300, 640, 340, Eagle::Color::CYAN, 4)
    g.polygon([v2(500, 250), v2(600, 280), v2(560, 350), v2(520, 320), v2(480, 340)], color: Eagle::Color::ORANGE)
    g.draw(@tex.not_nil!, 250, 200, rotation: Eagle::Clock.elapsed * 0.5, sx: 2, ox: 32, oy: 32)
    g.print("Hello, Eagle! FPS #{Eagle::Clock.fps.round}", 20, 400, Eagle::Color::WHITE)
    g.print("draw calls: #{g.draw_calls}", 20, 430, Eagle::Color::GRAY)
  end
end

Eagle.run(Smoke.new, title: "Eagle smoke", width: 640, height: 480)
