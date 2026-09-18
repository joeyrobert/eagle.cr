module Eagle
  # Scene-wide 3D settings: sky, ambient light, fog and shadows. The active one is
  # `Scene3D.environment`.
  #
  # ```
  # env = Scene3D.environment
  # env.fog(15, 60, Color.gray(0.7))                # fade to gray between 15 and 60 units
  # env.sky = false
  # env.background = Color::BLACK                   # space
  # env.shadow_distance = 25                        # sharper shadows over a smaller area
  # ```
  class Environment
    # Light that reaches everything, even in shadow. Raise it if shadows look too black.
    property ambient : Color = Color.new(0.25, 0.27, 0.32)
    # Sky color overhead.
    property sky_top : Color = Color.hex("#3b6fd6")
    # Sky color at the horizon.
    property sky_horizon : Color = Color.hex("#b9d4f5")
    # Color below the horizon.
    property sky_bottom : Color = Color.hex("#3a3a44")
    # Draw the gradient sky. When off, `background` is used.
    property? sky = true
    # Flat background color when the sky is off.
    property background : Color = Color.hex("#202430")
    # Color distant things fade toward.
    property fog_color : Color = Color.hex("#b9d4f5")
    # Distance where fog begins.
    property fog_start : Float32 = 0_f32
    # Distance where fog is total. Fog is off when this is not greater than `fog_start`.
    property fog_end : Float32 = 0_f32 # <= start disables fog
    # Master switch for shadows.
    property? shadows = true
    # Shadow map resolution in pixels. Higher is sharper and slower.
    property shadow_size : Int32 = 2048
    # How far from the camera shadows are drawn. Smaller values give sharper shadows.
    property shadow_distance : Float32 = 40_f32
    # Offset that stops surfaces from shadowing themselves ("shadow acne"). Raise it slightly if
    # you see stripes, and lower it if shadows detach from objects.
    property shadow_bias : Float32 = 0.002_f32

    # Turns on fog between *start* and *finish*, optionally changing its color. Returns self.
    def fog(start : Number, finish : Number, color : Color? = nil) : self
      @fog_start = start.to_f32; @fog_end = finish.to_f32
      @fog_color = color if color
      self
    end

    # Sets the three sky colors at once. Returns self.
    def sky_colors(top : Color, horizon : Color, bottom : Color) : self
      @sky_top = top; @sky_horizon = horizon; @sky_bottom = bottom
      self
    end
  end

  # A light as the renderer sees it. The light nodes produce these each frame.
  struct LightData
    # Directional, point or spot.
    enum Kind
      Directional = 0
      Point = 1
      Spot = 2
    end
    getter kind : Kind
    getter position : Vec3
    getter direction : Vec3
    getter color : Color
    getter intensity : Float32
    getter range : Float32
    getter spot_inner : Float32
    getter spot_outer : Float32
    getter? shadows : Bool
    def initialize(@kind, @position, @direction, @color, @intensity, @range = 10_f32, @spot_inner = 0.5_f32, @spot_outer = 0.6_f32, @shadows = false); end

    # A directional light.
    def self.directional(direction : Vec3, color : Color = Color::WHITE, intensity : Number = 1, shadows : Bool = true) : LightData
      new(Kind::Directional, Vec3::ZERO, direction.normalized, color, intensity.to_f32, shadows: shadows)
    end

    # A point light.
    def self.point(position : Vec3, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10) : LightData
      new(Kind::Point, position, Vec3::DOWN, color, intensity.to_f32, range.to_f32)
    end

    # A spot light.
    def self.spot(position : Vec3, direction : Vec3, color : Color = Color::WHITE, intensity : Number = 1, range : Number = 10, angle : Number = 0.6, softness : Number = 0.1) : LightData
      new(Kind::Spot, position, direction.normalized, color, intensity.to_f32, range.to_f32, Math.cos(angle.to_f32 - softness.to_f32).to_f32, Math.cos(angle).to_f32)
    end
  end

  # One thing to draw: a mesh, a material and a world transform.
  struct DrawItem
    getter mesh : Mesh
    getter material : Material
    getter transform : Mat4
    def initialize(@mesh, @material, @transform); end
  end

  # The camera parameters the renderer needs.
  struct CameraView
    getter view : Mat4
    getter projection : Mat4
    getter position : Vec3
    def initialize(@view, @projection, @position); end
  end

  # The forward renderer: shadow pass, sky, opaque meshes, then transparent meshes.
  #
  # The scene tree drives it through `Scene3D.render`. Call `render` directly to draw meshes
  # without nodes, for tools and special effects.
  class Renderer3D
    # The settings used when rendering.
    property environment : Environment
    # Draw calls in the last render.
    getter stats_draw_calls = 0
    @depth_shader : Shader
    @sky_shader : Shader
    @sky_geom : UInt32
    @shadow_target : GPU::RenderTargetHandle? = nil
    @shadow_texture : Texture? = nil
    @light_matrix = Mat4.identity
    @draw_calls = 0
    # Set EAGLE_GL_DEBUG=1 to check for GL errors after every stage/draw.
    @@debug : Bool = ENV["EAGLE_GL_DEBUG"]? == "1"

    # The shadow map from the last render, for debugging.
    def shadow_texture : Texture?; @shadow_texture; end
    # The light-space matrix used for shadows.
    def light_matrix : Mat4; @light_matrix; end

    private def dbg(where : String)
      GPU.device.check_errors(where) if @@debug
    end

    # Creates a renderer.
    def initialize(@environment : Environment = Environment.new)
      @depth_shader = Shader.new(Shaders3D::DEPTH_VERTEX, Shaders3D::DEPTH_FRAGMENT, Shader::ATTRIBS_3D)
      @sky_shader = Shader.new(Shaders3D::SKY_VERTEX, Shaders3D::SKY_FRAGMENT, Shader::ATTRIBS_2D)
      layout = GPU::VertexLayout.new.float("a_position", 2).float("a_uv", 2).float("a_color", 4)
      @sky_geom = GPU.device.create_geometry(layout)
      verts = Slice(Float32).new(4 * 8, 0_f32)
      quad = [{-1, -1}, {1, -1}, {1, 1}, {-1, 1}]
      quad.each_with_index { |(x, y), i| verts[i * 8] = x.to_f32; verts[i * 8 + 1] = y.to_f32; verts[i * 8 + 7] = 1_f32 }
      GPU.device.upload_vertices(@sky_geom, verts, GPU::Usage::Static)
      GPU.device.upload_indices(@sky_geom, Slice[0_u32, 1_u32, 2_u32, 0_u32, 2_u32, 3_u32], GPU::Usage::Static)
    end

    # Frees GPU resources.
    def dispose : Nil
      @depth_shader.dispose
      @sky_shader.dispose
      GPU.device.delete_geometry(@sky_geom) if GPU.ready?
      @shadow_target.try { |t| GPU.device.delete_render_target(t) if GPU.ready? }
      @shadow_target = nil
    end

    # Renders *items* lit by *lights* from *camera* into the current target. Set *flip_y* when
    # rendering into a `Canvas`, and *clear* to clear color and depth first.
    def render(camera : CameraView, items : Array(DrawItem), lights : Array(LightData), target_size : Vec2, flip_y : Bool = false, clear : Bool = true) : Nil
      @draw_calls = 0
      dev = GPU.device
      Eagle.graphics.flush if Eagle.initialized?
      projection = camera.projection
      projection = Mat4.scale(Vec3.new(1, -1, 1)) * projection if flip_y
      shadow_light = lights.find { |l| l.kind.directional? && l.shadows? } if @environment.shadows?
      shadow_ok = false
      if sl = shadow_light
        caller_target = dev.current_target
        shadow_ok = render_shadows(sl, items, camera)
        dev.bind_render_target(caller_target)
        dbg("shadow pass")
      end

      dev.front_face_ccw(!flip_y)
      dbg("pre-clear")
      if clear
        dev.clear(@environment.sky? ? nil : @environment.background, depth: true)
      end
      dbg("clear")
      dev.depth_test(true, true, GPU::DepthFunc::LessEqual)
      draw_sky(camera, projection, lights) if @environment.sky? && clear
      dbg("sky")
      dev.blend_mode(GPU::BlendMode::None)

      opaque = items.reject { |i| i.material.transparent? }
      transparent = items.select { |i| i.material.transparent? }
      cam_pos = camera.position
      opaque.sort_by! { |i| {i.material.priority, i.material.effective_shader.id, (i.transform.translation - cam_pos).length_squared} }
      transparent.sort_by! { |i| {i.material.priority, -(i.transform.translation - cam_pos).length_squared} }

      current_shader : Shader? = nil
      setup = ->(sh : Shader) do
        sh.use
        sh["u_view"] = camera.view
        sh["u_projection"] = projection
        sh["u_camera_pos"] = cam_pos
        amb = @environment.ambient
        sh["u_ambient"] = Vec3.new(amb.r, amb.g, amb.b)
        sh["u_fog_color"] = Vec3.new(@environment.fog_color.r, @environment.fog_color.g, @environment.fog_color.b)
        sh["u_fog_range"] = Vec2.new(@environment.fog_start, @environment.fog_end)
        upload_lights(sh, lights)
        sh["u_shadows"] = shadow_ok ? 1 : 0
        sh["u_light_matrix"] = @light_matrix
        sh["u_shadow_bias"] = @environment.shadow_bias
        sh["u_shadow_texel"] = 1_f32 / @environment.shadow_size
        if (st = @shadow_texture) && shadow_ok
          sh.set_texture("u_shadow_map", st, 1)
        else
          sh.set_texture("u_shadow_map", Texture.white, 1)
        end
      end

      draw_item = ->(item : DrawItem) do
        sh = item.material.effective_shader
        if sh != current_shader
          setup.call(sh)
          current_shader = sh
        end
        m = item.material
        m.apply(sh)
        sh["u_model"] = item.transform
        sh["u_normal_matrix"] = item.transform.to_mat3.inverse.transposed
        dev.cull(m.double_sided? ? GPU::CullMode::None : GPU::CullMode::Back)
        dev.wireframe(m.wireframe?)
        item.mesh.draw
        dev.wireframe(false) if m.wireframe?
        @draw_calls += 1
        dbg("draw #{item.mesh.name}")
      end

      opaque.each { |i| draw_item.call(i) }
      unless transparent.empty?
        dev.depth_test(true, false, GPU::DepthFunc::LessEqual)
        transparent.each do |i|
          dev.blend_mode(i.material.blend)
          draw_item.call(i)
        end
      end

      # restore 2D-friendly state
      dev.depth_test(false)
      dev.cull(GPU::CullMode::None)
      dev.front_face_ccw(true)
      dev.blend_mode(GPU::BlendMode::Alpha)
      @stats_draw_calls = @draw_calls
    end

    private def upload_lights(sh : Shader, lights : Array(LightData))
      n = Math.min(lights.size, Shaders3D::MAX_LIGHTS)
      sh["u_light_count"] = n
      return if n == 0
      types = Array(Int32).new(n) { |i| lights[i].kind.value }
      pos = Array(Vec3).new(n) { |i| lights[i].position }
      dir = Array(Vec3).new(n) { |i| lights[i].direction }
      col = Array(Vec3).new(n) { |i| l = lights[i]; Vec3.new(l.color.r, l.color.g, l.color.b) * l.intensity }
      range = Array(Float32).new(n) { |i| lights[i].range }
      spot = Array(Vec2).new(n) { |i| Vec2.new(lights[i].spot_inner, lights[i].spot_outer) }
      sh["u_light_type"] = types
      sh["u_light_pos"] = pos
      sh["u_light_dir"] = dir
      sh["u_light_color"] = col
      sh["u_light_range"] = range
      sh["u_light_spot"] = spot
    end

    private def draw_sky(camera : CameraView, projection : Mat4, lights : Array(LightData))
      dev = GPU.device
      dev.depth_test(true, false, GPU::DepthFunc::LessEqual)
      dev.cull(GPU::CullMode::None)
      @sky_shader.use
      dbg("sky: use")
      # remove translation from the view for direction reconstruction
      v = camera.view
      rot = Mat4.identity
      3.times { |c| 3.times { |r| rot[c, r] = v[c, r] } }
      @sky_shader["u_inv_view_proj"] = (projection * rot).inverse
      e = @environment
      @sky_shader["u_sky_top"] = Vec3.new(e.sky_top.r, e.sky_top.g, e.sky_top.b)
      @sky_shader["u_sky_horizon"] = Vec3.new(e.sky_horizon.r, e.sky_horizon.g, e.sky_horizon.b)
      @sky_shader["u_sky_bottom"] = Vec3.new(e.sky_bottom.r, e.sky_bottom.g, e.sky_bottom.b)
      sun = lights.find(&.kind.directional?)
      @sky_shader["u_sun_dir"] = sun ? sun.direction : Vec3.new(0, -1, 0)
      @sky_shader["u_sun_color"] = sun ? Vec3.new(sun.color.r, sun.color.g, sun.color.b) * Math.min(sun.intensity, 1.5_f32) : Vec3::ZERO
      dbg("sky: uniforms")
      dev.draw(@sky_geom, GPU::Primitive::Triangles, 6, 0, indexed: true)
      dbg("sky: draw")
      @draw_calls += 1
      dev.depth_test(true, true, GPU::DepthFunc::LessEqual)
    end

    private def render_shadows(light : LightData, items : Array(DrawItem), camera : CameraView) : Bool
      dev = GPU.device
      size = @environment.shadow_size
      if (t = @shadow_target).nil? || t.width != size
        @shadow_target.try { |old| dev.delete_render_target(old) }
        t = dev.create_depth_target(size, size)
        @shadow_target = t
        @shadow_texture = Texture.wrap_handle(t.depth, size, size, GPU::Filter::Nearest)
      end
      # Fit an ortho box around the camera's focus area.
      dist = @environment.shadow_distance
      focus = camera.position + camera.view.inverse.transform_dir(Vec3::FORWARD) * (dist * 0.5)
      # snap to texel grid to reduce shimmer
      texel = dist * 2 / size
      light_view = Mat4.look_at(focus - light.direction * dist * 2, focus, light.direction.y.abs > 0.99 ? Vec3::BACK : Vec3::UP)
      lp = light_view.transform_point(focus)
      snapped = Vec3.new((lp.x / texel).round * texel, (lp.y / texel).round * texel, lp.z)
      light_view = Mat4.translation(snapped - lp) * light_view
      light_proj = Mat4.orthographic(-dist, dist, -dist, dist, 0.1, dist * 4)
      @light_matrix = light_proj * light_view
      dev.bind_render_target(t)
      dev.clear(nil, depth: true)
      dev.depth_test(true, true, GPU::DepthFunc::Less)
      dev.cull(GPU::CullMode::Front) # closed meshes: no self-shadow acne
      dev.blend_mode(GPU::BlendMode::None)
      @depth_shader.use
      @depth_shader["u_light_matrix"] = @light_matrix
      items.each do |item|
        next unless item.material.cast_shadows? && !item.material.transparent?
        @depth_shader["u_model"] = item.transform
        item.mesh.draw
        @draw_calls += 1
      end
      dev.cull(GPU::CullMode::None)
      true
    end

    # Same as `stats_draw_calls`.
    def draw_calls : Int32; @stats_draw_calls; end
  end
end
