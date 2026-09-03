require "../gpu_spec_helper"

SYSTEM_TTF = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Geneva.ttf", "/System/Library/Fonts/Monaco.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf",
              "C:/Windows/Fonts/arial.ttf"].find { |p| File.exists?(p) }

describe Eagle::TrueType do
  it "parses tables, cmap and metrics" do
    pending!("no system TTF found") unless SYSTEM_TTF
    ttf = TrueType.load(SYSTEM_TTF.not_nil!)
    ttf.units_per_em.should be > 0
    ttf.glyph_count.should be > 50
    ttf.ascent.should be > 0
    ttf.descent.should be < 0
    ttf.has_glyph?('A').should be_true
    ttf.glyph_index('A').should_not eq 0
    ttf.glyph_index('B').should_not eq ttf.glyph_index('A')
    ttf.advance(ttf.glyph_index('W')).should be > ttf.advance(ttf.glyph_index('i'))
    ttf.advance(ttf.glyph_index(' ')).should be > 0
  end

  it "reads outlines and rasterises glyphs with anti-aliasing" do
    pending!("no system TTF found") unless SYSTEM_TTF
    ttf = TrueType.load(SYSTEM_TTF.not_nil!)
    o = ttf.outline(ttf.glyph_index('O'))
    o.contours.size.should eq 2 # outer + inner
    o.contours.each { |c| c.size.should be > 3 }
    bmp = ttf.rasterize(ttf.glyph_index('l'), 32_f32 / ttf.units_per_em)
    bmp.width.should be > 0
    bmp.height.should be > 15
    cov = bmp.coverage
    cov.max.should be_close(1, 0.02) # solid interior
    cov.min.should eq 0
    partial = cov.count { |v| v > 0.05 && v < 0.95 }
    partial.should be > 0 # anti-aliased edges
    # 'i' has two contours (dot + stem) in most fonts, 'O' shows a hole
    ob = ttf.rasterize(ttf.glyph_index('O'), 64_f32 / ttf.units_per_em)
    center = ob.coverage[(ob.height // 2) * ob.width + ob.width // 2]
    center.should be < 0.05
    edge = ob.coverage[(ob.height // 2) * ob.width + 2]
    edge.should be > 0.3
    space = ttf.rasterize(ttf.glyph_index(' '), 0.02_f32)
    space.width.should eq 0
  end
end

describe Eagle::TrueTypeFont do
  gpu_it "renders text through Graphics" do
    pending!("no system TTF found") unless SYSTEM_TTF
    font = TrueTypeFont.new(File.read(SYSTEM_TTF.not_nil!).to_slice, 24)
    font.line_height.should be > 20
    font.width("MMM").should be > font.width("iii")
    font.measure("a\nb").y.should eq font.line_height * 2
    img = GPUSpec.render(96, 40) { |g| g.print("Hi!", 2, 2, Color::WHITE, font) }
    img.average(0, 0, 60, 30).r.should be > 0.05
    img.average(80, 0, 16, 40).r.should eq 0
    font.glyph('H').not_nil!.region.width.should be > 5
    font.preload
  end
end
