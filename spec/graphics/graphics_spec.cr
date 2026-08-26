require "../gpu_spec_helper"

describe Eagle::Graphics do
  gpu_it "clears a canvas to a color" do
    img = GPUSpec.render(8, 8, Color::RED) { }
    img[0, 0].should eq Color::RED
    img[7, 7].should eq Color::RED
  end

  gpu_it "fills rectangles with the top-left origin, y down" do
    img = GPUSpec.render(16, 16) { |g| g.rect(0, 0, 8, 4, color: Color::GREEN) }
    img[0, 0].should eq Color::GREEN
    img[7, 3].should eq Color::GREEN
    img[8, 0].should eq Color::BLACK
    img[0, 4].should eq Color::BLACK
    img[15, 15].should eq Color::BLACK
  end

  gpu_it "draws circles" do
    img = GPUSpec.render(32, 32) { |g| g.circle(16, 16, 10, color: Color::BLUE) }
    img[16, 16].should eq Color::BLUE
    img[16, 7].should eq Color::BLUE
    img[1, 1].should eq Color::BLACK
    img[16, 3].should eq Color::BLACK
  end

  gpu_it "draws lines with width" do
    img = GPUSpec.render(32, 32) { |g| g.line(0, 16, 32, 16, Color::WHITE, 4) }
    img[16, 16].should eq Color::WHITE
    img[16, 14].should eq Color::WHITE
    img[16, 10].should eq Color::BLACK
    img[16, 22].should eq Color::BLACK
  end

  gpu_it "draws concave polygons" do
    # an L shape
    pts = [v2(0, 0), v2(20, 0), v2(20, 10), v2(10, 10), v2(10, 20), v2(0, 20)]
    img = GPUSpec.render(24, 24) { |g| g.polygon(pts, color: Color::YELLOW) }
    img[5, 5].should eq Color::YELLOW
    img[15, 5].should eq Color::YELLOW
    img[5, 15].should eq Color::YELLOW
    img[15, 15].should eq Color::BLACK
  end

  gpu_it "draws textures and regions with scale and rotation" do
    src = Image.new(4, 4, Color::TRANSPARENT)
    src.fill_rect(0, 0, 2, 4, Color::RED)
    src.fill_rect(2, 0, 2, 4, Color::BLUE)
    tex = Texture.new(src, GPU::Filter::Nearest)
    img = GPUSpec.render(16, 16) { |g| g.draw(tex, 0, 0, sx: 4) }
    img[2, 2].should eq Color::RED
    img[13, 13].should eq Color::BLUE
    # region: only the blue half
    img2 = GPUSpec.render(16, 16) { |g| g.draw(tex.region(2, 0, 2, 4), 0, 0, sx: 4) }
    img2[2, 2].should eq Color::BLUE
    img2[7, 7].should eq Color::BLUE
    img2[10, 10].should eq Color::BLACK
    # rotate 180 around the centre swaps halves
    img3 = GPUSpec.render(16, 16) { |g| g.draw(tex, 8, 8, rotation: Math::PI, sx: 4, ox: 2, oy: 2) }
    img3[2, 2].should eq Color::BLUE
    img3[13, 13].should eq Color::RED
    tex.dispose
  end

  gpu_it "applies the tint color and alpha blending" do
    img = GPUSpec.render(4, 4) do |g|
      g.color = Color.new(1, 1, 1, 0.5)
      g.rect(0, 0, 4, 4)
    end
    img[1, 1].r.should be_close(0.5, 0.02)
    img[1, 1].g.should be_close(0.5, 0.02)
  end

  gpu_it "supports additive blending" do
    img = GPUSpec.render(4, 4) do |g|
      g.rect(0, 0, 4, 4, color: Color.new(0.5, 0, 0))
      g.with_blend(GPU::BlendMode::Additive) { g.rect(0, 0, 4, 4, color: Color.new(0.25, 0.5, 0)) }
    end
    img[1, 1].r.should be_close(0.75, 0.02)
    img[1, 1].g.should be_close(0.5, 0.02)
  end

  gpu_it "uses the transform stack" do
    img = GPUSpec.render(16, 16) do |g|
      g.push do
        g.translate(8, 8)
        g.scale(2)
        g.rect(0, 0, 2, 2, color: Color::CYAN)
      end
      g.rect(0, 0, 2, 2, color: Color::MAGENTA)
    end
    img[9, 9].should eq Color::CYAN
    img[11, 11].should eq Color::CYAN
    img[12, 12].should eq Color::BLACK
    img[0, 0].should eq Color::MAGENTA
  end

  gpu_it "clips with scissor" do
    img = GPUSpec.render(16, 16) do |g|
      g.with_scissor(Rect.new(4, 4, 4, 4)) { g.rect(0, 0, 16, 16, color: Color::WHITE) }
    end
    img[5, 5].should eq Color::WHITE
    img[2, 2].should eq Color::BLACK
    img[10, 10].should eq Color::BLACK
  end

  gpu_it "renders text with the built-in font" do
    img = GPUSpec.render(64, 24) { |g| g.print("I", 0, 0, Color::WHITE) }
    # 'I' at 2x scale: a vertical bar around x = 4..5, y = 0..13
    img.average(0, 0, 12, 16).r.should be > 0.05
    img.average(40, 0, 20, 16).r.should eq 0
    w = Font.default.width("Hello")
    w.should eq 5 * 6 * 2
    Font.default.measure("a\nb").y.should eq 2 * 8 * 2
  end

  gpu_it "word-wraps text" do
    lines = Font.default.wrap("one two three four", 6 * 2 * 9)
    lines.should eq ["one two", "three", "four"]
  end

  gpu_it "batches draws into few draw calls" do
    g = Eagle.graphics
    g.begin_frame
    canvas = Canvas.new(8, 8)
    g.with_canvas(canvas) { 200.times { |i| g.rect(i, 0, 1, 1) } }
    g.end_frame
    g.draw_calls.should eq 1
    canvas.dispose
  end

  gpu_it "runs custom effect shaders" do
    sh = Shader.effect("vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 sc) { return vec4(0.0, 1.0, 0.0, 1.0); }")
    img = GPUSpec.render(4, 4) { |g| g.with_shader(sh) { g.rect(0, 0, 4, 4, color: Color::RED) } }
    img[1, 1].should eq Color::GREEN
    sh.dispose
  end

  gpu_it "sets shader uniforms" do
    sh = Shader.effect("uniform vec4 u_tint; vec4 effect(vec4 c, sampler2D t, vec2 uv, vec2 sc) { return u_tint; }")
    sh["u_tint"] = Color::BLUE
    img = GPUSpec.render(4, 4) { |g| g.with_shader(sh) { g.rect(0, 0, 4, 4) } }
    img[1, 1].should eq Color::BLUE
    sh.has_uniform?("u_tint").should be_true
    sh.has_uniform?("u_nope").should be_false
    sh.dispose
  end

  gpu_it "reports shader compile errors with line numbers" do
    ex = expect_raises(ShaderError) { Shader.effect("vec4 effect(vec4 c, sampler2D t, vec2 uv, vec2 sc) { return nope; }") }
    ex.message.not_nil!.should contain("--- source ---")
  end

  gpu_it "parses single-file shaders with sections" do
    src = <<-GLSL
      #vertex
      in vec2 a_position; in vec2 a_uv; in vec4 a_color;
      uniform mat4 u_projection; out vec4 v_color;
      void main() { v_color = a_color; gl_Position = u_projection * vec4(a_position, 0.0, 1.0); }
      #fragment
      in vec4 v_color; out vec4 frag;
      void main() { frag = vec4(1.0, 0.0, 1.0, 1.0); }
      GLSL
    sh = Shader.parse(src)
    img = GPUSpec.render(4, 4) { |g| g.with_shader(sh) { g.rect(0, 0, 4, 4) } }
    img[1, 1].should eq Color::MAGENTA
    sh.dispose
  end

  gpu_it "draws canvases into other canvases the right way up" do
    inner = Canvas.new(8, 8)
    g = Eagle.graphics
    g.begin_frame
    g.with_canvas(inner) { g.rect(0, 0, 8, 4, color: Color::RED) } # top half red
    outer = Canvas.new(8, 8)
    g.with_canvas(outer) { g.draw(inner, 0, 0) }
    g.end_frame
    img = outer.to_image
    img[4, 1].should eq Color::RED
    img[4, 6].should eq Color::TRANSPARENT
    inner.dispose; outer.dispose
  end

  gpu_it "applies a camera" do
    cam = Camera2D.new(position: v2(100, 100), zoom: 2)
    cam.viewport = v2(16, 16)
    img = GPUSpec.render(16, 16) do |g|
      g.with_camera(cam) { g.rect(100, 100, 2, 2, color: Color::WHITE) }
    end
    # world (100,100) is the viewport centre (8,8); 2x zoom → 4px square
    img[8, 8].should eq Color::WHITE
    img[11, 11].should eq Color::WHITE
    img[12, 12].should eq Color::BLACK
    img[7, 7].should eq Color::BLACK
    cam.screen_to_world(v2(8, 8)).approx?(v2(100, 100)).should be_true
    cam.world_to_screen(v2(100, 100)).approx?(v2(8, 8)).should be_true
  end
end

describe Eagle::Texture do
  gpu_it "splits frames" do
    tex = Texture.new(Image.new(8, 4))
    frames = tex.frames(4, 4)
    frames.size.should eq 2
    frames[1].u0.should eq 0.5
    tex.dispose
  end

  gpu_it "updates sub-regions" do
    tex = Texture.new(Image.new(4, 4, Color::BLACK), GPU::Filter::Nearest)
    tex.update(Image.new(2, 2, Color::RED), 2, 2)
    img = GPUSpec.render(4, 4) { |g| g.draw(tex, 0, 0) }
    img[3, 3].should eq Color::RED
    img[0, 0].should eq Color::BLACK
    tex.dispose
  end
end

describe Eagle::Geometry do
  it "triangulates concave polygons" do
    pts = [v2(0, 0), v2(20, 0), v2(20, 10), v2(10, 10), v2(10, 20), v2(0, 20)]
    tris = Geometry.triangulate(pts)
    tris.size.should eq (pts.size - 2) * 3
  end
end
