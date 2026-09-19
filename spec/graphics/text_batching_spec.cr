require "../gpu_spec_helper"

BATCH_TTF = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Geneva.ttf", "/System/Library/Fonts/Monaco.ttf",
             "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
             "C:/Windows/Fonts/arial.ttf"].find { |p| File.exists?(p) }

# Draws shapes and text alternately, the pattern that used to flush on every switch.
private def interleaved(g : Graphics, font : Font)
  4.times do |i|
    y = 4 + i * 20
    g.rect(2, y, 90, 16, color: Color.new(0.2, 0.3, 0.6, 1.0))
    g.print("Batch #{i}", 4, y + 2, Color::WHITE, font)
    g.line(2, y + 18, 92, y + 18, Color::RED, 1)
    g.circle(80, y + 8, 5, color: Color.new(1.0, 0.8, 0.1, 0.6))
  end
end

# The same scene with every shape forced onto the separate 1x1 white texture.
private def unbatched(g : Graphics, font : Font)
  white = Texture.white
  4.times do |i|
    y = 4 + i * 20
    g.draw(white, 2, y, sx: 90, sy: 16, color: Color.new(0.2, 0.3, 0.6, 1.0))
    g.print("Batch #{i}", 4, y + 2, Color::WHITE, font)
    g.line(2, y + 18, 92, y + 18, Color::RED, 1)
    g.circle(80, y + 8, 5, color: Color.new(1.0, 0.8, 0.1, 0.6))
  end
end

private def pixels(img : Image) : Array(Color)
  (0...img.height).flat_map { |y| (0...img.width).map { |x| img[x, y] } }
end

describe "text batching" do
  # The first shape reuses whichever atlas an earlier example left bound, so the count is 1 or 2 depending on order.
  gpu_it "draws shapes and default-font text in at most two draw calls" do
    GPUSpec.render(100, 90) { |g| interleaved(g, Font.default) }
    batched = Eagle.graphics.stats_draw_calls
    GPUSpec.render(100, 90) { |g| unbatched(g, Font.default) }
    batched.should be <= 2
    Eagle.graphics.stats_draw_calls.should be > batched
  end

  gpu_it "draws shapes and TrueType text in at most two draw calls" do
    pending!("no system TTF found") unless BATCH_TTF
    font = TrueTypeFont.new(File.read(BATCH_TTF.not_nil!).to_slice, 14).preload
    GPUSpec.render(100, 90) { |g| interleaved(g, font) }
    batched = Eagle.graphics.stats_draw_calls
    GPUSpec.render(100, 90) { |g| unbatched(g, font) }
    batched.should be <= 2
    Eagle.graphics.stats_draw_calls.should be > batched
  end

  gpu_it "keeps pixels identical to drawing shapes on the white texture" do
    fonts = [Font.default] of Font
    fonts << TrueTypeFont.new(File.read(BATCH_TTF.not_nil!).to_slice, 14).preload if BATCH_TTF
    fonts.each do |font|
      a = GPUSpec.render(100, 90) { |g| interleaved(g, font) }
      b = GPUSpec.render(100, 90) { |g| unbatched(g, font) }
      pixels(a).should eq pixels(b)
    end
  end
end
