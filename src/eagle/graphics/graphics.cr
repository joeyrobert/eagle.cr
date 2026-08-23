module Eagle
  enum DrawMode
    Fill
    Line
  end

  enum TextAlign
    Left
    Center
    Right
  end

  # Immediate-mode 2D drawing (LÖVE-style), batched into as few draw calls as
  # possible. Coordinates are in logical points with (0,0) top-left.
  class Graphics
    MAX_VERTICES = 65532
    VERTEX_FLOATS = 8 # x y u v r g b a

    getter stats_draw_calls = 0
    getter stats_vertices = 0
    # Current tint; multiplies everything drawn.
    property color : Color = Color::WHITE
    property line_width : Float32 = 1_f32
    # Anti-aliased circle segment count is derived from radius; override here.
    property circle_segments : Int32? = nil
    property font : Font
    getter transform : Transform2D = Transform2D::IDENTITY
    getter blend : GPU::BlendMode = GPU::BlendMode::Alpha
    getter shader : Shader?
    getter canvas : Canvas?
    getter camera : Camera2D?
    getter scissor_rect : Rect?

    @default_shader : Shader
    @stack = [] of Transform2D
    @geom : UInt32
    @verts : Slice(Float32)
    @indices : Slice(UInt32)
    @vcount = 0
    @icount = 0
    @texture : Texture
    @projection = Mat4.identity
    @frame_draw_calls = 0
    @frame_vertices = 0
    @target_size = Vec2::ZERO

    def initialize
      @default_shader = Shader.default_2d
      @shader = nil
      layout = GPU::VertexLayout.new.float("a_position", 2).float("a_uv", 2).float("a_color", 4)
      @geom = GPU.device.create_geometry(layout)
      @verts = Slice(Float32).new(MAX_VERTICES * VERTEX_FLOATS)
      @indices = Slice(UInt32).new(MAX_VERTICES * 3 // 2)
      @texture = Texture.white
      @font = Font.default
      @camera = nil
      @canvas = nil
      @scissor_rect = nil
    end

    def dispose : Nil
      GPU.device.delete_geometry(@geom) if GPU.ready?
      @default_shader.dispose
    end

    # --- frame ---------------------------------------------------------------
    # :nodoc:
    def begin_frame : Nil
      @frame_draw_calls = 0
      @frame_vertices = 0
      reset_state
      set_target(nil)
    end

    # :nodoc:
    def end_frame : Nil
      flush
      @stats_draw_calls = @frame_draw_calls
      @stats_vertices = @frame_vertices
      @camera = nil
    end

    private def reset_state
      @color = Color::WHITE
      @line_width = 1_f32
      @transform = Transform2D::IDENTITY
      @stack.clear
      @blend = GPU::BlendMode::Alpha
      @shader = nil
      @scissor_rect = nil
    end

    private def set_target(canvas : Canvas?)
      flush
      @canvas = canvas
      if c = canvas
        GPU.device.bind_render_target(c.handle)
        @target_size = c.size
        # Unflipped so canvas row 0 is the top when sampled as a texture.
        @projection = Mat4.orthographic(0, c.width, 0, c.height)
      else
        GPU.device.bind_render_target(nil)
        @target_size = Window.size
        @projection = Mat4.orthographic(0, Window.width, Window.height, 0)
      end
      GPU.device.scissor(nil, 0)
      GPU.device.depth_test(false)
      GPU.device.cull(GPU::CullMode::None)
      GPU.device.blend_mode(@blend)
    end

    def target_size : Vec2; @target_size; end

    # Draw into an off-screen canvas for the duration of the block.
    def with_canvas(canvas : Canvas, clear : Color? = Color::TRANSPARENT, &) : Nil
      prev = @canvas
      prev_t = @transform
      prev_stack = @stack.dup
      prev_scissor = @scissor_rect
      set_target(canvas)
      @transform = Transform2D::IDENTITY
      @stack.clear
      if c = clear
        GPU.device.clear(c, depth: canvas.depth?)
      end
      begin
        yield
      ensure
        flush
        set_target(prev)
        @transform = prev_t
        @stack = prev_stack
        self.scissor = prev_scissor
      end
    end

    # Clear the current target.
    def clear(color : Color = Color::BLACK) : Nil
      flush
      GPU.device.clear(color, depth: true, stencil: true)
    end

    # --- state ---------------------------------------------------------------
    def blend=(mode : GPU::BlendMode)
      return if mode == @blend
      flush
      @blend = mode
      GPU.device.blend_mode(mode)
    end

    def with_blend(mode : GPU::BlendMode, &) : Nil
      prev = @blend
      self.blend = mode
      yield
      self.blend = prev
    end

    # Set a custom shader (nil = default). Uniforms `u_projection`, `u_texture`,
    # `u_time`, `u_resolution` are provided.
    def shader=(s : Shader?)
      return if s == @shader
      flush
      @shader = s
    end

    def with_shader(s : Shader?, &) : Nil
      prev = @shader
      self.shader = s
      yield
      self.shader = prev
    end

    def with_color(c : Color, &) : Nil
      prev = @color
      @color = c
      yield
      @color = prev
    end

    # Clip drawing to a rectangle (in current target coordinates), nil to disable.
    def scissor=(r : Rect?)
      flush
      @scissor_rect = r
      if @canvas
        # canvas projection is unflipped, so y is already GL-style bottom-up.
        if rr = r
          GPU.device.scissor(Rect.new(rr.x, @target_size.y - rr.y - rr.h, rr.w, rr.h), @target_size.y.to_i)
        else
          GPU.device.scissor(nil, 0)
        end
      else
        s = Window.scale
        GPU.device.scissor(r.try(&.scale(s)), Window.pixel_height)
      end
    end

    def with_scissor(r : Rect?, &) : Nil
      prev = @scissor_rect
      self.scissor = r
      yield
      self.scissor = prev
    end

    # Use a camera for subsequent drawing (world space). `nil` returns to screen space.
    def camera=(cam : Camera2D?)
      flush
      @camera = cam
      if c = cam
        c.update(Clock.delta)
        @transform = c.view
      else
        @transform = Transform2D::IDENTITY
      end
    end

    def with_camera(cam : Camera2D?, &) : Nil
      prev_cam = @camera
      prev_t = @transform
      self.camera = cam
      yield
      flush
      @camera = prev_cam
      @transform = prev_t
    end

    # --- transform stack -----------------------------------------------------
    def push : Nil; @stack << @transform; end
    def pop : Nil; @transform = @stack.pop? || Transform2D::IDENTITY; end
    def push(&) : Nil; push; yield; pop; end
    def translate(x : Number, y : Number) : Nil; @transform = @transform * Transform2D.translation(Vec2.new(x, y)); end
    def translate(v : Vec2) : Nil; translate(v.x, v.y); end
    def rotate(rad : Number) : Nil; @transform = @transform * Transform2D.rotation(rad); end
    def scale(s : Number) : Nil; scale(s, s); end
    def scale(x : Number, y : Number) : Nil; @transform = @transform * Transform2D.scale(Vec2.new(x, y)); end
    def transform=(t : Transform2D); @transform = t; end
    def apply(t : Transform2D) : Nil; @transform = @transform * t; end
    def origin : Nil; @transform = @camera.try(&.view) || Transform2D::IDENTITY; end
    def with_transform(t : Transform2D, &) : Nil; push; apply(t); yield; pop; end

    # --- sprites -------------------------------------------------------------
    # Draw a texture/region at (x, y) with rotation (radians), scale and origin offset (in texture pixels).
    def draw(d : Drawable, x : Number = 0, y : Number = 0, rotation : Number = 0, sx : Number = 1, sy : Number = sx, ox : Number = 0, oy : Number = 0, color : Color = @color) : Nil
      tex, u0, v0, u1, v1, w, h = unpack(d)
      quad(tex, x.to_f32, y.to_f32, w * sx, h * sy, rotation.to_f32, ox * sx, oy * sy, u0, v0, u1, v1, color)
    end

    def draw(d : Drawable, position : Vec2, rotation : Number = 0, scale : Vec2 = Vec2::ONE, origin : Vec2 = Vec2::ZERO, color : Color = @color) : Nil
      draw(d, position.x, position.y, rotation, scale.x, scale.y, origin.x, origin.y, color)
    end

    # Draw stretched into `dest`.
    def draw(d : Drawable, dest : Rect, color : Color = @color, rotation : Number = 0) : Nil
      tex, u0, v0, u1, v1, w, h = unpack(d)
      if rotation == 0
        quad(tex, dest.x, dest.y, dest.w, dest.h, 0_f32, 0_f32, 0_f32, u0, v0, u1, v1, color)
      else
        quad(tex, dest.center.x, dest.center.y, dest.w, dest.h, rotation.to_f32, dest.w / 2, dest.h / 2, u0, v0, u1, v1, color)
      end
    end

    # Draw a texture centred at a point.
    def draw_centered(d : Drawable, x : Number, y : Number, rotation : Number = 0, sx : Number = 1, sy : Number = sx, color : Color = @color) : Nil
      _, _, _, _, _, w, h = unpack(d)
      draw(d, x, y, rotation, sx, sy, w / 2, h / 2, color)
    end

    def draw_centered(d : Drawable, p : Vec2, rotation : Number = 0, sx : Number = 1, sy : Number = sx, color : Color = @color) : Nil
      draw_centered(d, p.x, p.y, rotation, sx, sy, color)
    end

    # Draw a canvas (its texture is stored top-row-first, so no flip needed).
    def draw(c : Canvas, x : Number = 0, y : Number = 0, rotation : Number = 0, sx : Number = 1, sy : Number = sx, ox : Number = 0, oy : Number = 0, color : Color = @color) : Nil
      draw(c.texture, x, y, rotation, sx, sy, ox, oy, color)
    end

    def draw(c : Canvas, dest : Rect, color : Color = @color) : Nil
      draw(c.texture, dest, color)
    end

    # Tiled fill of a rectangle with a texture (requires Wrap::Repeat on the texture).
    def draw_tiled(tex : Texture, dest : Rect, offset : Vec2 = Vec2::ZERO, scale : Number = 1, color : Color = @color) : Nil
      u0 = offset.x / (tex.width * scale); v0 = offset.y / (tex.height * scale)
      u1 = u0 + dest.w / (tex.width * scale); v1 = v0 + dest.h / (tex.height * scale)
      quad(tex, dest.x, dest.y, dest.w, dest.h, 0_f32, 0_f32, 0_f32, u0.to_f32, v0.to_f32, u1.to_f32, v1.to_f32, color)
    end

    private def unpack(d : Drawable) : {Texture, Float32, Float32, Float32, Float32, Float32, Float32}
      case d
      in Texture then {d, 0_f32, 0_f32, 1_f32, 1_f32, d.width.to_f32, d.height.to_f32}
      in TextureRegion then {d.texture, d.u0, d.v0, d.u1, d.v1, d.width, d.height}
      end
    end

    # --- shapes --------------------------------------------------------------
    def rect(x : Number, y : Number, w : Number, h : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      if mode.fill?
        quad(Texture.white, x.to_f32, y.to_f32, w.to_f32, h.to_f32, 0_f32, 0_f32, 0_f32, 0_f32, 0_f32, 1_f32, 1_f32, color)
      else
        polyline([Vec2.new(x, y), Vec2.new(x + w, y), Vec2.new(x + w, y + h), Vec2.new(x, y + h)], color, closed: true)
      end
    end

    def rect(r : Rect, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      rect(r.x, r.y, r.w, r.h, mode, color)
    end

    def rect_line(x : Number, y : Number, w : Number, h : Number, color : Color = @color) : Nil
      rect(x, y, w, h, DrawMode::Line, color)
    end

    def rect_line(r : Rect, color : Color = @color) : Nil; rect(r, DrawMode::Line, color); end

    def rounded_rect(x : Number, y : Number, w : Number, h : Number, radius : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      r = Math.min(radius.to_f32, Math.min(w, h) / 2).to_f32
      pts = [] of Vec2
      segs = Math.max(2, (r / 3).ceil.to_i)
      corners = {
        {x + w - r, y + r, -Math::PI / 2},
        {x + w - r, y + h - r, 0.0},
        {x + r, y + h - r, Math::PI / 2},
        {x + r, y + r, Math::PI},
      }
      corners.each do |(cx, cy, start)|
        (0..segs).each do |i|
          a = start + (Math::PI / 2) * i / segs
          pts << Vec2.new(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
        end
      end
      polygon(pts, mode, color)
    end

    def circle(x : Number, y : Number, radius : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color, segments : Int32? = nil) : Nil
      n = segments || @circle_segments || Math.max(12, Math.min(96, (radius * 1.2).to_i))
      pts = Array(Vec2).new(n) { |i| a = Math::PI * 2 * i / n; Vec2.new(x + Math.cos(a) * radius, y + Math.sin(a) * radius) }
      if mode.fill?
        fan(Vec2.new(x, y), pts, color)
      else
        polyline(pts, color, closed: true)
      end
    end

    def circle(center : Vec2, radius : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      circle(center.x, center.y, radius, mode, color)
    end

    def circle_line(x : Number, y : Number, radius : Number, color : Color = @color) : Nil
      circle(x, y, radius, DrawMode::Line, color)
    end

    def ellipse(x : Number, y : Number, rx : Number, ry : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      n = Math.max(12, Math.min(96, (Math.max(rx, ry) * 1.2).to_i))
      pts = Array(Vec2).new(n) { |i| a = Math::PI * 2 * i / n; Vec2.new(x + Math.cos(a) * rx, y + Math.sin(a) * ry) }
      mode.fill? ? fan(Vec2.new(x, y), pts, color) : polyline(pts, color, closed: true)
    end

    # Pie slice / arc from `a0` to `a1` radians.
    def arc(x : Number, y : Number, radius : Number, a0 : Number, a1 : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      span = (a1 - a0).to_f32
      n = Math.max(2, (span.abs * Math.max(6, radius / 4)).to_i)
      pts = Array(Vec2).new(n + 1) { |i| a = a0 + span * i / n; Vec2.new(x + Math.cos(a) * radius, y + Math.sin(a) * radius) }
      if mode.fill?
        fan(Vec2.new(x, y), pts, color, closed: false)
      else
        polyline(pts, color)
      end
    end

    def line(x1 : Number, y1 : Number, x2 : Number, y2 : Number, color : Color = @color, width : Number = @line_width) : Nil
      a = Vec2.new(x1, y1); b = Vec2.new(x2, y2)
      d = b - a
      len = d.length
      return if len == 0
      n = d.perpendicular / len * (width / 2)
      tri_quad(Texture.white, a + n, b + n, b - n, a - n, color)
    end

    def line(a : Vec2, b : Vec2, color : Color = @color, width : Number = @line_width) : Nil
      line(a.x, a.y, b.x, b.y, color, width)
    end

    # Connected line segments with mitred joins.
    def polyline(points : Array(Vec2), color : Color = @color, width : Number = @line_width, closed : Bool = false) : Nil
      return if points.size < 2
      hw = width.to_f32 / 2
      pts = closed ? points + [points[0]] : points
      if pts.size == 2
        line(pts[0], pts[1], color, width)
        return
      end
      normals = Array(Vec2).new(pts.size - 1) { |i| (pts[i + 1] - pts[i]).normalized.perpendicular }
      offsets = Array(Vec2).new(pts.size)
      pts.size.times do |i|
        n0 = i == 0 ? (closed ? normals[-1] : normals[0]) : normals[i - 1]
        n1 = i == pts.size - 1 ? (closed ? normals[0] : normals[-1]) : normals[i]
        m = (n0 + n1)
        ml = m.length
        if ml < 1e-4
          offsets << n1 * hw
        else
          m = m / ml
          d = m.dot(n1)
          d = 0.5_f32 if d.abs < 0.5 # limit mitre length on sharp angles
          offsets << m * (hw / d)
        end
      end
      (pts.size - 1).times do |i|
        tri_quad(Texture.white, pts[i] + offsets[i], pts[i + 1] + offsets[i + 1], pts[i + 1] - offsets[i + 1], pts[i] - offsets[i], color)
      end
    end

    # Filled (convex or simple concave via ear clipping) or outlined polygon.
    def polygon(points : Array(Vec2), mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      return if points.size < 3
      if mode.line?
        polyline(points, color, closed: true)
        return
      end
      if convex?(points)
        fan(points[0], points[1..], color, closed: false)
      else
        tris = Geometry.triangulate(points)
        set_texture(Texture.white)
        ensure_space(points.size, tris.size)
        base = @vcount
        points.each { |p| push_vertex(p, 0_f32, 0_f32, color) }
        tris.each { |i| push_index(base + i) }
      end
    end

    def triangle(a : Vec2, b : Vec2, c : Vec2, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      polygon([a, b, c], mode, color)
    end

    def point(x : Number, y : Number, color : Color = @color, size : Number = 1) : Nil
      rect(x - size / 2, y - size / 2, size, size, DrawMode::Fill, color)
    end

    def points(pts : Array(Vec2), color : Color = @color, size : Number = 1) : Nil
      pts.each { |p| point(p.x, p.y, color, size) }
    end

    # --- text ----------------------------------------------------------------
    # Draw text at (x, y) = top-left of the first line.
    def print(text : String, x : Number = 0, y : Number = 0, color : Color = @color, font : Font = @font, scale : Number = 1, align : TextAlign = TextAlign::Left) : Nil
      s = font.scale * scale
      line_h = font.line_height * s
      cy = y.to_f32
      text.each_line(chomp: true) do |line|
        lw = font.width(line) * scale
        cx = case align
             in TextAlign::Left then x.to_f32
             in TextAlign::Center then x.to_f32 - lw / 2
             in TextAlign::Right then x.to_f32 - lw
             end
        prev : Char? = nil
        line.each_char do |ch|
          if g = font.glyph(ch)
            cx += font.kerning(prev, ch) * s if prev
            r = g.region
            quad(r.texture, cx + g.offset.x * s, cy + g.offset.y * s, r.width * s, r.height * s, 0_f32, 0_f32, 0_f32, r.u0, r.v0, r.u1, r.v1, color)
            cx += (g.advance + font.letter_spacing) * s
          end
          prev = ch
        end
        cy += line_h
      end
    end

    def print(text : String, pos : Vec2, color : Color = @color, font : Font = @font, scale : Number = 1, align : TextAlign = TextAlign::Left) : Nil
      print(text, pos.x, pos.y, color, font, scale, align)
    end

    # Word-wrapped text inside `width`.
    def printf(text : String, x : Number, y : Number, width : Number, align : TextAlign = TextAlign::Left, color : Color = @color, font : Font = @font, scale : Number = 1) : Nil
      lines = font.wrap(text, (width / scale).to_f32)
      ax = case align
           in TextAlign::Left then x
           in TextAlign::Center then x + width / 2
           in TextAlign::Right then x + width
           end
      print(lines.join("\n"), ax, y, color, font, scale, align)
    end

    def text_size(text : String, font : Font = @font, scale : Number = 1) : Vec2
      font.measure(text) * scale
    end

    # --- low level -----------------------------------------------------------
    # Push an arbitrary textured quad (corners in order, with UVs).
    def quad_raw(tex : Texture, p0 : Vec2, p1 : Vec2, p2 : Vec2, p3 : Vec2, uv0 : Vec2, uv1 : Vec2, uv2 : Vec2, uv3 : Vec2, color : Color = @color) : Nil
      set_texture(tex)
      ensure_space(4, 6)
      base = @vcount
      push_vertex(p0, uv0.x, uv0.y, color)
      push_vertex(p1, uv1.x, uv1.y, color)
      push_vertex(p2, uv2.x, uv2.y, color)
      push_vertex(p3, uv3.x, uv3.y, color)
      push_quad_indices(base)
    end

    # Push raw triangles (positions, uvs, colors, indices) — for meshes, particles.
    def triangles(tex : Texture, positions : Array(Vec2), uvs : Array(Vec2), colors : Array(Color), indices : Array(Int32)) : Nil
      set_texture(tex)
      ensure_space(positions.size, indices.size)
      base = @vcount
      positions.each_with_index { |p, i| push_vertex(p, uvs[i].x, uvs[i].y, colors[i]) }
      indices.each { |i| push_index(base + i) }
    end

    # Flush pending geometry to the GPU.
    def flush : Nil
      return if @icount == 0
      shader = @shader || @default_shader
      shader.use
      shader["u_projection"] = @projection
      shader["u_time"] = Clock.elapsed.to_f32
      shader["u_resolution"] = @target_size
      shader.set_texture("u_texture", @texture, 0)
      GPU.device.upload_vertices(@geom, @verts[0, @vcount * VERTEX_FLOATS], GPU::Usage::Stream)
      GPU.device.upload_indices(@geom, @indices[0, @icount], GPU::Usage::Stream)
      GPU.device.draw(@geom, GPU::Primitive::Triangles, @icount, 0, indexed: true)
      @frame_draw_calls += 1
      @frame_vertices += @vcount
      @vcount = 0
      @icount = 0
    end

    def draw_calls : Int32; @stats_draw_calls; end

    private def quad(tex : Texture, x : Number, y : Number, w : Number, h : Number, rot : Number, ox : Number, oy : Number, u0 : Float32, v0 : Float32, u1 : Float32, v1 : Float32, color : Color)
      x = x.to_f32; y = y.to_f32; w = w.to_f32; h = h.to_f32; rot = rot.to_f32; ox = ox.to_f32; oy = oy.to_f32
      if rot == 0
        p0 = @transform * Vec2.new(x - ox, y - oy)
        p1 = @transform * Vec2.new(x - ox + w, y - oy)
        p2 = @transform * Vec2.new(x - ox + w, y - oy + h)
        p3 = @transform * Vec2.new(x - ox, y - oy + h)
      else
        t = @transform * Transform2D.trs(Vec2.new(x, y), rot, Vec2::ONE, Vec2.new(ox, oy))
        p0 = t * Vec2.new(0, 0); p1 = t * Vec2.new(w, 0); p2 = t * Vec2.new(w, h); p3 = t * Vec2.new(0, h)
      end
      set_texture(tex)
      ensure_space(4, 6)
      base = @vcount
      push_raw(p0.x, p0.y, u0, v0, color)
      push_raw(p1.x, p1.y, u1, v0, color)
      push_raw(p2.x, p2.y, u1, v1, color)
      push_raw(p3.x, p3.y, u0, v1, color)
      push_quad_indices(base)
    end

    private def tri_quad(tex : Texture, a : Vec2, b : Vec2, c : Vec2, d : Vec2, color : Color)
      set_texture(tex)
      ensure_space(4, 6)
      base = @vcount
      push_vertex(a, 0_f32, 0_f32, color); push_vertex(b, 1_f32, 0_f32, color)
      push_vertex(c, 1_f32, 1_f32, color); push_vertex(d, 0_f32, 1_f32, color)
      push_quad_indices(base)
    end

    private def fan(center : Vec2, pts : Array(Vec2), color : Color, closed : Bool = true)
      set_texture(Texture.white)
      n = pts.size
      ensure_space(n + 1, n * 3)
      base = @vcount
      push_vertex(center, 0.5_f32, 0.5_f32, color)
      pts.each { |p| push_vertex(p, 0_f32, 0_f32, color) }
      segs = closed ? n : n - 1
      segs.times do |i|
        push_index(base); push_index(base + 1 + i); push_index(base + 1 + (i + 1) % n)
      end
    end

    private def convex?(pts : Array(Vec2)) : Bool
      sign = 0
      n = pts.size
      n.times do |i|
        c = (pts[(i + 1) % n] - pts[i]).cross(pts[(i + 2) % n] - pts[(i + 1) % n])
        next if c.abs < 1e-6
        s = c > 0 ? 1 : -1
        return false if sign != 0 && s != sign
        sign = s
      end
      true
    end

    @[AlwaysInline]
    private def set_texture(tex : Texture)
      if tex.id != @texture.id
        flush
        @texture = tex
      end
    end

    @[AlwaysInline]
    private def ensure_space(verts : Int32, idx : Int32)
      flush if @vcount + verts > MAX_VERTICES || @icount + idx > @indices.size
    end

    @[AlwaysInline]
    private def push_vertex(p : Vec2, u : Float32, v : Float32, c : Color)
      tp = @transform * p
      push_raw(tp.x, tp.y, u, v, c)
    end

    @[AlwaysInline]
    private def push_raw(x : Float32, y : Float32, u : Float32, v : Float32, c : Color)
      i = @vcount * VERTEX_FLOATS
      ptr = @verts.to_unsafe + i
      ptr[0] = x; ptr[1] = y; ptr[2] = u; ptr[3] = v
      ptr[4] = c.r; ptr[5] = c.g; ptr[6] = c.b; ptr[7] = c.a
      @vcount += 1
    end

    @[AlwaysInline]
    private def push_index(i : Int32)
      @indices[@icount] = i.to_u32
      @icount += 1
    end

    @[AlwaysInline]
    private def push_quad_indices(base : Int32)
      push_index(base); push_index(base + 1); push_index(base + 2)
      push_index(base); push_index(base + 2); push_index(base + 3)
    end
  end

  module Geometry
    # Ear-clipping triangulation of a simple polygon. Returns index triples.
    def self.triangulate(pts : Array(Vec2)) : Array(Int32)
      n = pts.size
      return [] of Int32 if n < 3
      # ensure consistent winding (positive area = clockwise in y-down)
      area = 0_f32
      n.times { |i| area += pts[i].cross(pts[(i + 1) % n]) }
      idx = (0...n).to_a
      idx.reverse! if area < 0
      out_tris = [] of Int32
      guard = 0
      while idx.size > 3 && guard < n * n
        guard += 1
        found = false
        idx.size.times do |i|
          a = idx[(i - 1) % idx.size]; b = idx[i]; c = idx[(i + 1) % idx.size]
          pa = pts[a]; pb = pts[b]; pc = pts[c]
          next if (pb - pa).cross(pc - pb) <= 0 # reflex
          inside = idx.any? do |k|
            next false if k == a || k == b || k == c
            point_in_triangle?(pts[k], pa, pb, pc)
          end
          next if inside
          out_tris << a << b << c
          idx.delete_at(i)
          found = true
          break
        end
        break unless found
      end
      out_tris << idx[0] << idx[1] << idx[2] if idx.size == 3
      out_tris
    end

    def self.point_in_triangle?(p : Vec2, a : Vec2, b : Vec2, c : Vec2) : Bool
      d1 = (p - a).cross(b - a); d2 = (p - b).cross(c - b); d3 = (p - c).cross(a - c)
      has_neg = d1 < 0 || d2 < 0 || d3 < 0
      has_pos = d1 > 0 || d2 > 0 || d3 > 0
      !(has_neg && has_pos)
    end
  end
end
