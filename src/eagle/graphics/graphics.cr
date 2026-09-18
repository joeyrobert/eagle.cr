module Eagle
  # Whether a shape is filled or drawn as an outline.
  enum DrawMode
    # Filled shapes.
    Fill
    # Outlines, using `Graphics#line_width`.
    Line
  end

  # Horizontal alignment for `Graphics#print` and `Graphics#printf`. With `Center` and `Right`,
  # the x you pass is the center or right edge of the text.
  enum TextAlign
    # Align the left edge to x.
    Left
    # Center the text on x.
    Center
    # Align the right edge to x.
    Right
  end

  # The 2D drawing context: shapes, sprites, text, transforms, cameras and render targets.
  #
  # You get one as `g` in `App#draw` and `Node#draw`. Every call is batched, so drawing
  # thousands of sprites costs only a few GPU draw calls. Coordinates are in logical points,
  # with `(0, 0)` at the top-left and y growing downward.
  #
  # ```
  # class Game < App
  #   @ship = Texture.new(Image.circle(32, Color::WHITE))
  #
  #   def draw(g : Graphics) : Nil
  #     g.clear(Color.hex("#1d1611"))
  #
  #     g.rect(20, 20, 200, 120, color: Color::GRAY)              # filled box
  #     g.rect(20, 20, 200, 120, DrawMode::Line, Color::WHITE)     # outline
  #     g.circle(Window.center, 40, color: Color::ORANGE)
  #     g.line(v2(0, 0), Input.mouse, Color::CYAN, width: 3)
  #
  #     g.draw(@ship, 300, 200, rotation: Clock.elapsed, ox: 16, oy: 16) # spin around its center
  #
  #     g.push do # everything in here is rotated around (500, 300)
  #       g.translate(500, 300)
  #       g.rotate(0.3)
  #       g.rect(-25, -25, 50, 50)
  #     end
  #
  #     g.print("Score 1200", 10, 10, scale: 2)
  #     g.printf("Centered and wrapped text", 0, 400, Window.width, align: TextAlign::Center)
  #   end
  # end
  # ```
  #
  # State such as `color`, `line_width`, `blend`, `shader` and `font` persists until you
  # change it, and resets at the start of each frame. The `with_*` methods set something
  # for one block and restore it afterwards, which is the tidy way to make temporary changes.
  class Graphics
    # Vertices per batch. A batch is flushed to the GPU when it fills up.
    MAX_VERTICES = 65532
    # Floats per 2D vertex: position, UV and color.
    VERTEX_FLOATS = 8 # x y u v r g b a

    # Draw calls issued so far this frame. Show it in a debug overlay to check batching.
    getter stats_draw_calls = 0
    # Vertices submitted so far this frame.
    getter stats_vertices = 0
    # Default color for shapes, text and texture tint. Most methods also take a `color:` argument.
    property color : Color = Color::WHITE
    # Default thickness, in points, for lines, polylines and outlines.
    property line_width : Float32 = 1_f32
    # Fixed segment count for circles. `nil` picks a count from the radius, so small circles stay cheap
    # and big ones stay round.
    property circle_segments : Int32? = nil
    # Font used by `print` when you don't pass one. Starts as `Font.default`, the built-in pixel font.
    property font : Font
    # The current transform applied to everything drawn.
    getter transform : Transform2D = Transform2D::IDENTITY
    # The current blend mode.
    getter blend : GPU::BlendMode = GPU::BlendMode::Alpha
    # The custom shader in use, or `nil` for the default.
    getter shader : Shader?
    # The canvas being drawn into, or `nil` for the screen.
    getter canvas : Canvas?
    # The 2D camera in use, or `nil` for screen space.
    getter camera : Camera2D?
    # The current clip rectangle, or `nil` when clipping is off.
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

    # Creates a drawing context. The engine makes one for you; see `Eagle.graphics`.
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

    # Frees GPU buffers. The engine calls it on shutdown.
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

    # Size of what you are drawing into: the window, or the canvas inside `with_canvas`.
    def target_size : Vec2; @target_size; end

    # Draws into *canvas* instead of the screen for the duration of the block. The canvas is
    # cleared to *clear* first; pass `nil` to keep what it already has. The transform starts
    # fresh inside the block.
    #
    # ```
    # canvas = Canvas.new(320, 180)
    # g.with_canvas(canvas) do
    #   g.circle(160, 90, 40, color: Color::YELLOW)
    # end
    # g.draw(canvas, 0, 0, sx: 4) # upscale the low-res image to fill a 1280x720 window
    # ```
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

    # Clears the whole target to *color*. On the screen this replaces `Config#clear_color` for this frame.
    def clear(color : Color = Color::BLACK) : Nil
      flush
      GPU.device.clear(color, depth: true, stencil: true)
    end

    # --- state ---------------------------------------------------------------
    # Sets how new pixels combine with what's already drawn. `Additive` makes glows and fire,
    # `Multiply` darkens, and `Alpha` is the normal default.
    def blend=(mode : GPU::BlendMode)
      return if mode == @blend
      flush
      @blend = mode
      GPU.device.blend_mode(mode)
    end

    # Uses a blend mode for the block, then restores the previous one.
    #
    # ```
    # g.with_blend(GPU::BlendMode::Additive) { g.circle(200, 200, 30, color: Color::ORANGE.alpha(0.5)) }
    # ```
    def with_blend(mode : GPU::BlendMode, &) : Nil
      prev = @blend
      self.blend = mode
      yield
      self.blend = prev
    end

    # Uses a custom shader for everything drawn afterwards. `nil` restores the default.
    # Eagle sets `u_projection`, `u_texture`, `u_time` and `u_resolution` for you. See `Shader.effect`.
    def shader=(s : Shader?)
      return if s == @shader
      flush
      @shader = s
    end

    # Uses a shader for the block, then restores the previous one.
    def with_shader(s : Shader?, &) : Nil
      prev = @shader
      self.shader = s
      yield
      self.shader = prev
    end

    # Uses a default color for the block, then restores the previous one.
    def with_color(c : Color, &) : Nil
      prev = @color
      @color = c
      yield
      @color = prev
    end

    # Clips drawing to a rectangle in target coordinates, for example to keep a scrolling list
    # inside its panel. `nil` turns clipping off.
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

    # Clips drawing to a rectangle for the block.
    def with_scissor(r : Rect?, &) : Nil
      prev = @scissor_rect
      self.scissor = r
      yield
      self.scissor = prev
    end

    # Draws in world space through *cam*, or back in screen space with `nil`. The engine already
    # uses `Camera2D.current` for the scene tree, so you need this only for manual drawing.
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

    # Draws through a camera for the block, then restores the previous camera and transform.
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
    # Saves the current transform. Pair it with `pop`.
    def push : Nil; @stack << @transform; end
    # Restores the transform saved by the last `push`.
    def pop : Nil; @transform = @stack.pop? || Transform2D::IDENTITY; end
    # Saves the transform, runs the block, and restores it. Transforms inside the block stay local to it.
    def push(&) : Nil; push; yield; pop; end
    # Moves the origin by *x*, *y*.
    def translate(x : Number, y : Number) : Nil; @transform = @transform * Transform2D.translation(Vec2.new(x, y)); end
    # Moves the origin by *v*.
    def translate(v : Vec2) : Nil; translate(v.x, v.y); end
    # Rotates subsequent drawing by *rad* radians around the current origin.
    def rotate(rad : Number) : Nil; @transform = @transform * Transform2D.rotation(rad); end
    # Scales subsequent drawing uniformly.
    def scale(s : Number) : Nil; scale(s, s); end
    # Scales subsequent drawing by *x* and *y*. A negative value mirrors.
    def scale(x : Number, y : Number) : Nil; @transform = @transform * Transform2D.scale(Vec2.new(x, y)); end
    # Replaces the current transform.
    def transform=(t : Transform2D); @transform = t; end
    # Multiplies the current transform by *t*.
    def apply(t : Transform2D) : Nil; @transform = @transform * t; end
    # Resets the transform to the camera's view, or to identity without a camera.
    def origin : Nil; @transform = @camera.try(&.view) || Transform2D::IDENTITY; end
    # Applies *t* for the block.
    def with_transform(t : Transform2D, &) : Nil; push; apply(t); yield; pop; end

    # --- sprites -------------------------------------------------------------
    # Draws a texture or region with its top-left at *x*, *y*. *rotation* is in radians,
    # *sx*/*sy* scale it, and *ox*/*oy* set the pivot in texture pixels, which is the point
    # that lands on *x*, *y* and that rotation turns around.
    #
    # ```
    # tex = Texture.new(Image.circle(32, Color::WHITE))
    # g.draw(tex, 100, 100)                                     # top-left at (100, 100)
    # g.draw(tex, 200, 100, rotation: 0.5, ox: 16, oy: 16)       # rotate around its center
    # g.draw(tex, 300, 100, sx: -1, ox: 32)                     # mirrored horizontally
    # g.draw(tex, 400, 100, color: Color::RED.alpha(0.5))       # tinted and translucent
    # ```
    def draw(d : Drawable, x : Number = 0, y : Number = 0, rotation : Number = 0, sx : Number = 1, sy : Number = sx, ox : Number = 0, oy : Number = 0, color : Color = @color) : Nil
      tex, u0, v0, u1, v1, w, h = unpack(d)
      quad(tex, x.to_f32, y.to_f32, w * sx, h * sy, rotation.to_f32, ox * sx, oy * sy, u0, v0, u1, v1, color)
    end

    # Draws a texture or region using vectors for position, scale and pivot.
    def draw(d : Drawable, position : Vec2, rotation : Number = 0, scale : Vec2 = Vec2::ONE, origin : Vec2 = Vec2::ZERO, color : Color = @color) : Nil
      draw(d, position.x, position.y, rotation, scale.x, scale.y, origin.x, origin.y, color)
    end

    # Draws a texture or region stretched to fill *dest*.
    def draw(d : Drawable, dest : Rect, color : Color = @color, rotation : Number = 0) : Nil
      tex, u0, v0, u1, v1, w, h = unpack(d)
      if rotation == 0
        quad(tex, dest.x, dest.y, dest.w, dest.h, 0_f32, 0_f32, 0_f32, u0, v0, u1, v1, color)
      else
        quad(tex, dest.center.x, dest.center.y, dest.w, dest.h, rotation.to_f32, dest.w / 2, dest.h / 2, u0, v0, u1, v1, color)
      end
    end

    # Draws a texture or region centered on *x*, *y*.
    def draw_centered(d : Drawable, x : Number, y : Number, rotation : Number = 0, sx : Number = 1, sy : Number = sx, color : Color = @color) : Nil
      _, _, _, _, _, w, h = unpack(d)
      draw(d, x, y, rotation, sx, sy, w / 2, h / 2, color)
    end

    # Draws a texture or region centered on *p*.
    def draw_centered(d : Drawable, p : Vec2, rotation : Number = 0, sx : Number = 1, sy : Number = sx, color : Color = @color) : Nil
      draw_centered(d, p.x, p.y, rotation, sx, sy, color)
    end

    # Draws a canvas like a texture.
    def draw(c : Canvas, x : Number = 0, y : Number = 0, rotation : Number = 0, sx : Number = 1, sy : Number = sx, ox : Number = 0, oy : Number = 0, color : Color = @color) : Nil
      draw(c.texture, x, y, rotation, sx, sy, ox, oy, color)
    end

    # Draws a canvas stretched to fill *dest*.
    def draw(c : Canvas, dest : Rect, color : Color = @color) : Nil
      draw(c.texture, dest, color)
    end

    # Fills *dest* by repeating a texture, for backgrounds and floors. The texture must use
    # `GPU::Wrap::Repeat`. *offset* scrolls the pattern, which is an easy parallax effect.
    #
    # ```
    # floor = Texture.new(Image.checkerboard(32, 32), wrap: GPU::Wrap::Repeat)
    # g.draw_tiled(floor, Window.rect, offset: v2(Clock.elapsed * 20, 0))
    # ```
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
    # Draws a rectangle, filled by default. Pass `DrawMode::Line` for an outline.
    def rect(x : Number, y : Number, w : Number, h : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      if mode.fill?
        quad(Texture.white, x.to_f32, y.to_f32, w.to_f32, h.to_f32, 0_f32, 0_f32, 0_f32, 0_f32, 0_f32, 1_f32, 1_f32, color)
      else
        polyline([Vec2.new(x, y), Vec2.new(x + w, y), Vec2.new(x + w, y + h), Vec2.new(x, y + h)], color, closed: true)
      end
    end

    # Draws a `Rect`, filled by default.
    def rect(r : Rect, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      rect(r.x, r.y, r.w, r.h, mode, color)
    end

    # Draws a rectangle outline.
    def rect_line(x : Number, y : Number, w : Number, h : Number, color : Color = @color) : Nil
      rect(x, y, w, h, DrawMode::Line, color)
    end

    # Draws the outline of a `Rect`.
    def rect_line(r : Rect, color : Color = @color) : Nil; rect(r, DrawMode::Line, color); end

    # Draws a rectangle with rounded corners of *radius*, handy for buttons and panels.
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

    # Draws a circle, filled by default.
    def circle(x : Number, y : Number, radius : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color, segments : Int32? = nil) : Nil
      n = segments || @circle_segments || Math.max(12, Math.min(96, (radius * 1.2).to_i))
      pts = Array(Vec2).new(n) { |i| a = Math::PI * 2 * i / n; Vec2.new(x + Math.cos(a) * radius, y + Math.sin(a) * radius) }
      if mode.fill?
        fan(Vec2.new(x, y), pts, color)
      else
        polyline(pts, color, closed: true)
      end
    end

    # Draws a circle at *center*.
    def circle(center : Vec2, radius : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      circle(center.x, center.y, radius, mode, color)
    end

    # Draws a circle outline.
    def circle_line(x : Number, y : Number, radius : Number, color : Color = @color) : Nil
      circle(x, y, radius, DrawMode::Line, color)
    end

    # Draws an ellipse with radii *rx* and *ry*.
    def ellipse(x : Number, y : Number, rx : Number, ry : Number, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      n = Math.max(12, Math.min(96, (Math.max(rx, ry) * 1.2).to_i))
      pts = Array(Vec2).new(n) { |i| a = Math::PI * 2 * i / n; Vec2.new(x + Math.cos(a) * rx, y + Math.sin(a) * ry) }
      mode.fill? ? fan(Vec2.new(x, y), pts, color) : polyline(pts, color, closed: true)
    end

    # Draws a pie slice (filled) or an arc (line) from angle *a0* to *a1* in radians.
    # Angle 0 points right and angles grow clockwise, which suits cooldown timers.
    #
    # ```
    # cooldown = 0.25
    # g.arc(50, 50, 20, -Math::PI / 2, -Math::PI / 2 + Mathf::TAU * cooldown, color: Color::WHITE.alpha(0.6))
    # ```
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

    # Draws a line of *width* points.
    def line(x1 : Number, y1 : Number, x2 : Number, y2 : Number, color : Color = @color, width : Number = @line_width) : Nil
      a = Vec2.new(x1, y1); b = Vec2.new(x2, y2)
      d = b - a
      len = d.length
      return if len == 0
      n = d.perpendicular / len * (width / 2)
      tri_quad(Texture.white, a + n, b + n, b - n, a - n, color)
    end

    # Draws a line between two points.
    def line(a : Vec2, b : Vec2, color : Color = @color, width : Number = @line_width) : Nil
      line(a.x, a.y, b.x, b.y, color, width)
    end

    # Draws connected line segments with mitred joins. Set *closed* to join the last point to the first.
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

    # Draws a polygon. Filled polygons may be concave, as long as the edges don't cross.
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

    # Draws a triangle.
    def triangle(a : Vec2, b : Vec2, c : Vec2, mode : DrawMode = DrawMode::Fill, color : Color = @color) : Nil
      polygon([a, b, c], mode, color)
    end

    # Draws a square dot of *size* points.
    def point(x : Number, y : Number, color : Color = @color, size : Number = 1) : Nil
      rect(x - size / 2, y - size / 2, size, size, DrawMode::Fill, color)
    end

    # Draws many dots in one go, such as stars or particles.
    def points(pts : Array(Vec2), color : Color = @color, size : Number = 1) : Nil
      pts.each { |p| point(p.x, p.y, color, size) }
    end

    # --- text ----------------------------------------------------------------
    # Draws text with its top-left corner at *x*, *y*. Newlines start new lines.
    # With `align: TextAlign::Center`, *x* is the center of each line instead.
    #
    # ```
    # g.print("GAME OVER", Window.center.x, 200, Color::RED, scale: 3, align: TextAlign::Center)
    # g.print("line one\nline two", 10, 10)
    # ```
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

    # Draws text at *pos*.
    def print(text : String, pos : Vec2, color : Color = @color, font : Font = @font, scale : Number = 1, align : TextAlign = TextAlign::Left) : Nil
      print(text, pos.x, pos.y, color, font, scale, align)
    end

    # Draws text word-wrapped to fit *width*, aligned inside that width.
    def printf(text : String, x : Number, y : Number, width : Number, align : TextAlign = TextAlign::Left, color : Color = @color, font : Font = @font, scale : Number = 1) : Nil
      lines = font.wrap(text, (width / scale).to_f32)
      ax = case align
           in TextAlign::Left then x
           in TextAlign::Center then x + width / 2
           in TextAlign::Right then x + width
           end
      print(lines.join("\n"), ax, y, color, font, scale, align)
    end

    # The width and height *text* would take up, for centering or sizing backgrounds.
    def text_size(text : String, font : Font = @font, scale : Number = 1) : Vec2
      font.measure(text) * scale
    end

    # --- low level -----------------------------------------------------------
    # Pushes a textured quad with explicit corners and UVs, for custom effects like skewed sprites.
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

    # Pushes arbitrary textured triangles with per-vertex colors. Use it for custom meshes,
    # trails and deformable sprites.
    def triangles(tex : Texture, positions : Array(Vec2), uvs : Array(Vec2), colors : Array(Color), indices : Array(Int32)) : Nil
      set_texture(tex)
      ensure_space(positions.size, indices.size)
      base = @vcount
      positions.each_with_index { |p, i| push_vertex(p, uvs[i].x, uvs[i].y, colors[i]) }
      indices.each { |i| push_index(base + i) }
    end

    # Sends pending geometry to the GPU now. Eagle does this when needed; call it yourself
    # only when mixing in raw GPU calls.
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

    # Same as `stats_draw_calls`.
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

  # Polygon helpers used by the renderer and physics.
  module Geometry
    # Splits a simple polygon, convex or concave, into triangles by ear clipping. Returns
    # indices into *pts*, three per triangle.
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

    # True when *p* lies inside the triangle *a*, *b*, *c*.
    def self.point_in_triangle?(p : Vec2, a : Vec2, b : Vec2, c : Vec2) : Bool
      d1 = (p - a).cross(b - a); d2 = (p - b).cross(c - b); d3 = (p - c).cross(a - c)
      has_neg = d1 < 0 || d2 < 0 || d3 < 0
      has_pos = d1 > 0 || d2 > 0 || d3 > 0
      !(has_neg && has_pos)
    end
  end
end
