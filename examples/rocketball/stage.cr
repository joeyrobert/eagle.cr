require "../../src/eagle"
require "./match"
require "./settings"

module EagleRocketBall
  include Eagle

  def self.mix(a : Color, b : Color, t : Number) : Color
    t = t.to_f32
    Color.new(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  end

  def self.glass(c : Color, alpha : Number, emissive : Color = Color::BLACK) : Material
    m = Material.new(Color.new(c.r, c.g, c.b, alpha.to_f32), specular: 0.7, shininess: 90, emissive: emissive, transparent: true)
    m.double_sided = true
    m.cast_shadows = false
    m
  end

  def self.glow(c : Color, additive : Bool = false, alpha : Number = 1) : Material
    m = Material.unlit(Color.new(c.r, c.g, c.b, alpha.to_f32))
    m.cast_shadows = false
    if additive
      m.transparent = true
      m.blend = GPU::BlendMode::Additive
    end
    m
  end

  # The pitch, walls, goals, stands and boost pads: everything that is scenery rather than a car.
  class Stage
    getter goal_lights = [] of PointLight3D
    getter ball_light : PointLight3D
    @pads = [] of {Pad, MeshInstance3D, MeshInstance3D?, Material}
    @goal_flash = [0_f32, 0_f32]
    @goal_colors = [Color::WHITE, Color::WHITE]
    # Team-colored goal parts, per team: the material, how strongly it glows and its alpha.
    @goal_mats = [[] of {Material, Float32, Float32}, [] of {Material, Float32, Float32}]

    def initialize(@root : Node)
      @ball_light = PointLight3D.new(v3(0, 4, 0), Color.hex("#9fd0ff"), 1.4, 20)
      build
    end

    def self.floor_image : Image
      w = 512
      h = 768
      img = Image.new(w, h)
      ppu = w / (HALF_W * 2)
      dark = Color.hex("#1c5a3a")
      light = Color.hex("#22683f")
      h.times do |py|
        band = ((py / ppu) / 7).to_i.even?
        img.fill_rect(0, py, w, 1, band ? dark : light)
      end
      line = Color.new(0.92, 0.97, 1, 0.85)
      px = ->(x : Float32) { ((x + HALF_W) * ppu).round.to_i }
      pz = ->(z : Float32) { ((z + HALF_L) * ppu).round.to_i }
      rect = ->(x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32) do
        t = 3
        img.fill_rect(px.call(x0), pz.call(z0), px.call(x1) - px.call(x0), t, line)
        img.fill_rect(px.call(x0), pz.call(z1) - t, px.call(x1) - px.call(x0), t, line)
        img.fill_rect(px.call(x0), pz.call(z0), t, pz.call(z1) - pz.call(z0), line)
        img.fill_rect(px.call(x1) - t, pz.call(z0), t, pz.call(z1) - pz.call(z0), line)
      end
      rect.call(-HALF_W + 0.6_f32, -HALF_L + 0.6_f32, HALF_W - 0.6_f32, HALF_L - 0.6_f32)
      img.fill_rect(px.call(-HALF_W + 0.6_f32), pz.call(0_f32) - 1, px.call(HALF_W - 0.6_f32) - px.call(-HALF_W + 0.6_f32), 3, line)
      rect.call(-14_f32, -HALF_L + 0.6_f32, 14_f32, -HALF_L + 12)
      rect.call(-14_f32, HALF_L - 12, 14_f32, HALF_L - 0.6_f32)
      rect.call(-GOAL_HALF_W, -HALF_L + 0.6_f32, GOAL_HALF_W, -HALF_L + 5)
      rect.call(-GOAL_HALF_W, HALF_L - 5, GOAL_HALF_W, HALF_L - 0.6_f32)
      720.times do |i|
        a = i * Math::TAU / 720
        img.fill_rect(px.call((Math.cos(a) * 8).to_f32) - 1, pz.call((Math.sin(a) * 8).to_f32) - 1, 3, 3, line)
      end
      img.fill_rect(px.call(0_f32) - 4, pz.call(0_f32) - 4, 9, 9, line)
      img
    end

    def self.crowd_image : Image
      rng = Random.new(5)
      img = Image.new(128, 32, Color.hex("#0b0e18"))
      128.times do |x|
        32.times do |y|
          next unless rng.rand < 0.42
          img[x, y] = Color.hsv(rng.rand * 360, rng.rand * 0.5 + 0.15, 0.4 + rng.rand * 0.5)
        end
      end
      img
    end

    def self.net_image : Image
      img = Image.new(32, 32)
      c = Color.new(1, 1, 1, 0.5)
      32.times do |i|
        img[i, 0] = c
        img[i, 1] = c
        img[0, i] = c
        img[1, i] = c
      end
      img
    end

    private def add(node : Node) : Nil
      @root.add(node)
    end

    private def build : Nil
      env = Scene3D.environment
      env.sky_colors(Color.hex("#03040c"), Color.hex("#14213f"), Color.hex("#05060e"))
      env.fog(90, 230, Color.hex("#0a1226"))
      env.ambient = Color.new(0.2, 0.23, 0.32)
      env.shadows = true
      env.shadow_distance = 75
      floor = Texture.new(Stage.floor_image, mipmaps: true)
      add MeshInstance3D.new(Mesh.plane(HALF_W * 2, HALF_L * 2, 1), Material.new(texture: floor, specular: 0.15, shininess: 24))
      add MeshInstance3D.new(Mesh.plane(400, 400, 1), Material.new(Color.hex("#0b0f1a"), specular: 0), position: v3(0, -0.06, 0))
      build_walls
      build_goals
      build_stands
      build_lights
      build_pads
    end

    private def build_walls : Nil
      glass = EagleRocketBall.glass(Color.hex("#7fc2ff"), 0.13)
      rim = EagleRocketBall.glow(Color.hex("#59d6ff"))
      kick = Material.new(Color.hex("#1e2740"), shininess: 60, specular: 0.5)
      [-1, 1].each do |s|
        add MeshInstance3D.new(Mesh.box(0.3, HEIGHT, HALF_L * 2), glass, position: v3(s * (HALF_W + 0.15), HEIGHT / 2, 0))
        add MeshInstance3D.new(Mesh.box(0.7, 1.4, HALF_L * 2), kick, position: v3(s * (HALF_W + 0.35), 0.7, 0))
        add MeshInstance3D.new(Mesh.box(0.45, 0.3, HALF_L * 2), rim, position: v3(s * (HALF_W + 0.2), HEIGHT, 0))
        side = HALF_W - GOAL_HALF_W
        [-1, 1].each do |sx|
          add MeshInstance3D.new(Mesh.box(side, HEIGHT, 0.3), glass, position: v3(sx * (GOAL_HALF_W + side / 2), HEIGHT / 2, s * (HALF_L + 0.15)))
          add MeshInstance3D.new(Mesh.box(side, 1.4, 0.7), kick, position: v3(sx * (GOAL_HALF_W + side / 2), 0.7, s * (HALF_L + 0.35)))
          add MeshInstance3D.new(Mesh.box(side, 0.3, 0.45), rim, position: v3(sx * (GOAL_HALF_W + side / 2), HEIGHT, s * (HALF_L + 0.2)))
        end
        above = HEIGHT - GOAL_HEIGHT
        add MeshInstance3D.new(Mesh.box(GOAL_HALF_W * 2, above, 0.3), glass, position: v3(0, GOAL_HEIGHT + above / 2, s * (HALF_L + 0.15)))
        add MeshInstance3D.new(Mesh.box(GOAL_HALF_W * 2, 0.3, 0.45), rim, position: v3(0, HEIGHT, s * (HALF_L + 0.2)))
      end
      len = CORNER * Math.sqrt(2).to_f32
      [-1, 1].each do |sx|
        [-1, 1].each do |sz|
          center = v3(sx * (HALF_W - CORNER / 2), 0, sz * (HALF_L - CORNER / 2))
          turn = Quat.from_axis_angle(Vec3::UP, Math.atan2(sz, sx))
          pane = MeshInstance3D.new(Mesh.box(len, HEIGHT, 0.3), glass, position: center + v3(0, HEIGHT / 2, 0))
          pane.rotation = turn
          add pane
          kickboard = MeshInstance3D.new(Mesh.box(len, 1.4, 0.7), kick, position: center + v3(0, 0.7, 0))
          kickboard.rotation = turn
          add kickboard
          strip = MeshInstance3D.new(Mesh.box(len, 0.3, 0.45), rim, position: center + v3(0, HEIGHT, 0))
          strip.rotation = turn
          add strip
        end
      end
    end

    private def build_goals : Nil
      net = Texture.new(Stage.net_image, wrap: GPU::Wrap::Repeat)
      @goal_colors = [Settings.team_color(0), Settings.team_color(1)]
      {-1, 1}.each do |s|
        color = @goal_colors[s > 0 ? 0 : 1]
        team = s > 0 ? 0 : 1
        post = Material.new(Color.hex("#e9eef8"), emissive: color * 0.6, shininess: 80, specular: 0.8)
        @goal_mats[team] << {post, 0.6_f32, 1_f32}
        z = s * HALF_L
        {-1, 1}.each do |sx|
          add MeshInstance3D.new(Mesh.cylinder(0.35, GOAL_HEIGHT, 12), post, position: v3(sx * GOAL_HALF_W, GOAL_HEIGHT / 2, z))
          add MeshInstance3D.new(Mesh.cylinder(0.25, GOAL_HEIGHT, 10), post, position: v3(sx * GOAL_HALF_W, GOAL_HEIGHT / 2, z + s * GOAL_DEPTH))
        end
        bar = MeshInstance3D.new(Mesh.cylinder(0.35, GOAL_HALF_W * 2, 12), post, position: v3(0, GOAL_HEIGHT, z))
        bar.rotate_z(Math::PI / 2)
        add bar
        net_mat = EagleRocketBall.glass(color, 0.32, color * 0.25)
        net_mat.texture = net
        @goal_mats[team] << {net_mat, 0.25_f32, 0.32_f32}
        net_mat.uv_scale = v2(GOAL_HALF_W * 2 / 1.4, GOAL_HEIGHT / 1.4)
        add MeshInstance3D.new(Mesh.box(GOAL_HALF_W * 2, GOAL_HEIGHT, 0.12), net_mat, position: v3(0, GOAL_HEIGHT / 2, z + s * GOAL_DEPTH))
        side_mat = EagleRocketBall.glass(color, 0.28, color * 0.2)
        side_mat.texture = net
        @goal_mats[team] << {side_mat, 0.2_f32, 0.28_f32}
        side_mat.uv_scale = v2(GOAL_DEPTH / 1.4, GOAL_HEIGHT / 1.4)
        {-1, 1}.each do |sx|
          add MeshInstance3D.new(Mesh.box(0.12, GOAL_HEIGHT, GOAL_DEPTH), side_mat, position: v3(sx * GOAL_HALF_W, GOAL_HEIGHT / 2, z + s * GOAL_DEPTH / 2))
        end
        add MeshInstance3D.new(Mesh.box(GOAL_HALF_W * 2, 0.12, GOAL_DEPTH), side_mat, position: v3(0, GOAL_HEIGHT, z + s * GOAL_DEPTH / 2))
        add MeshInstance3D.new(Mesh.plane(GOAL_HALF_W * 2, GOAL_DEPTH, 1), Material.new(mix_dark(color), specular: 0.2), position: v3(0, 0.01, z + s * GOAL_DEPTH / 2))
        light = PointLight3D.new(v3(0, GOAL_HEIGHT - 1.2, z + s * GOAL_DEPTH * 0.6), color, 0.9, 26)
        @goal_lights << light
        add light
      end
    end

    private def mix_dark(c : Color) : Color
      EagleRocketBall.mix(Color.hex("#0a1018"), c, 0.35)
    end

    private def build_stands : Nil
      crowd = Texture.new(Stage.crowd_image, wrap: GPU::Wrap::Repeat)
      base = Material.unlit(Color.new(0.75, 0.75, 0.85, 1), crowd)
      base.uv_scale = v2(18, 1)
      body = Material.new(Color.hex("#0d1220"), specular: 0.1)
      3.times do |k|
        h = 3.5_f32 + k * 3.5_f32
        [-1, 1].each do |s|
          x = s * (HALF_W + 4 + k * 5.5_f32)
          add MeshInstance3D.new(Mesh.box(5.5, h, HALF_L * 2 + 14 + k * 8), body, position: v3(x, h / 2, 0))
          add MeshInstance3D.new(Mesh.box(5.3, 0.4, HALF_L * 2 + 14 + k * 8), base, position: v3(x, h + 0.2, 0))
        end
      end
      2.times do |k|
        h = 3_f32 + k * 3.5_f32
        [-1, 1].each do |s|
          z = s * (HALF_L + GOAL_DEPTH + 5 + k * 5.5_f32)
          add MeshInstance3D.new(Mesh.box(HALF_W * 2 + 14, h, 5.5), body, position: v3(0, h / 2, z))
          add MeshInstance3D.new(Mesh.box(HALF_W * 2 + 13, 0.4, 5.3), base, position: v3(0, h + 0.2, z))
        end
      end
    end

    private def build_lights : Nil
      add DirectionalLight3D.new(v3(-0.25, -1, -0.18), Color.hex("#a9bcff"), 0.55)
      tower = Material.new(Color.hex("#1b2236"))
      lamp = EagleRocketBall.glow(Color.hex("#fff4d8"))
      [-1, 1].each do |sx|
        [-1, 1].each do |sz|
          add MeshInstance3D.new(Mesh.cylinder(0.5, 30, 8), tower, position: v3(sx * (HALF_W + 17), 15, sz * (HALF_L + 12)))
          add MeshInstance3D.new(Mesh.box(4, 1.6, 1), lamp, position: v3(sx * (HALF_W + 17), 30.5, sz * (HALF_L + 12)))
          add PointLight3D.new(v3(sx * 15, 22, sz * 24), Color.hex("#fff1d6"), 0.8, 62)
        end
      end
      add @ball_light
    end

    private def build_pads : Nil
      # The pad list belongs to the match, so pads are attached later with `bind_pads`.
    end

    # Creates a visual for each of the match's boost pads.
    def bind_pads(pads : Array(Pad)) : Nil
      @pads.each { |(_, base, orb, _)| base.free; orb.try(&.free) }
      @pads.clear
      pads.each do |pad|
        mat = Material.unlit(Color.hex("#ffb02e"))
        mat.cast_shadows = false
        if pad.big?
          base = MeshInstance3D.new(Mesh.cylinder(2.3, 0.14, 24), mat, position: pad.pos + v3(0, 0.02, 0))
          orb = MeshInstance3D.new(Mesh.sphere(0.85, 14, 10), mat, position: pad.pos + v3(0, 1.7, 0))
          add base
          add orb
          @pads << {pad, base, orb, mat}
        else
          base = MeshInstance3D.new(Mesh.cylinder(1.05, 0.08, 18), mat, position: pad.pos + v3(0, 0.0, 0))
          add base
          @pads << {pad, base, nil, mat}
        end
      end
    end

    # Repaints the goals after the players pick new team colors.
    def recolor : Nil
      2.times do |team|
        c = Settings.team_color(team)
        @goal_mats[team].each do |(mat, glow, alpha)|
          mat.albedo = alpha < 1 ? Color.new(c.r, c.g, c.b, alpha) : Color.hex("#e9eef8")
          mat.emissive = c * glow
        end
        @goal_lights[1 - team].color = c
      end
    end

    def flash_goal(team : Int32) : Nil
      # Light 0 is the goal at -Z (orange's), light 1 the goal at +Z (blue's); a team scores in the other team's goal.
      @goal_flash[team] = 1
    end

    def update(dt : Float32, ball_pos : Vec3, ball_color : Color, time : Float32) : Nil
      @ball_light.position = ball_pos + v3(0, 1.5, 0)
      @ball_light.color = ball_color
      @goal_lights.each_with_index do |light, i|
        @goal_flash[i] = Math.max(0_f32, @goal_flash[i] - dt * 0.5_f32)
        light.intensity = 0.9_f32 + @goal_flash[i] * (3.5_f32 + Math.sin(time * 20) * 1.2_f32)
      end
      @pads.each do |(pad, base, orb, mat)|
        if pad.active?
          mat.albedo = pad.big? ? Color.hex("#ffc94d") : Color.hex("#ffb02e")
          orb.try { |o| o.visible = true; o.position = pad.pos + v3(0, 1.7 + Math.sin(time * 2.4 + pad.pos.x) * 0.25, 0); o.rotate_y(dt * 2) }
        else
          mat.albedo = Color.hex("#38290f")
          orb.try(&.visible = false)
        end
      end
    end
  end

  # A car drawn from boxes, with wheels that turn, a boost flame and a team color.
  class CarView
    getter root = Node3D.new
    @wheels = [] of Node3D
    @flame : MeshInstance3D
    @flame_mat : Material
    @body_mat : Material
    @spin = 0_f32
    @flicker = 0_f32

    def initialize(@team : Int32, color : Color, parent : Node)
      @body_mat = Material.new(color, shininess: 90, specular: 0.8, metallic: 0.25)
      glassy = Material.new(Color.hex("#0f1626"), shininess: 120, specular: 1)
      dark = Material.new(Color.hex("#12141b"), shininess: 20, specular: 0.2)
      accent = EagleRocketBall.glow(EagleRocketBall.mix(color, Color::WHITE, 0.7))
      @root.add MeshInstance3D.new(Mesh.box(2.0, 0.6, 4.3), @body_mat, position: v3(0, -0.12, 0))
      @root.add MeshInstance3D.new(Mesh.box(1.5, 0.44, 1.9), glassy, position: v3(0, 0.4, 0.35))
      @root.add MeshInstance3D.new(Mesh.box(1.9, 0.07, 0.55), @body_mat, position: v3(0, 0.55, 1.95))
      {-1, 1}.each do |s|
        @root.add MeshInstance3D.new(Mesh.box(0.1, 0.32, 0.1), dark, position: v3(s * 0.6, 0.36, 1.9))
        @root.add MeshInstance3D.new(Mesh.box(0.45, 0.13, 0.06), EagleRocketBall.glow(Color.hex("#fff6dc")), position: v3(s * 0.62, -0.03, -2.17))
        @root.add MeshInstance3D.new(Mesh.box(0.4, 0.1, 0.06), EagleRocketBall.glow(Color.hex("#ff2a3a")), position: v3(s * 0.62, 0.0, 2.17))
        {-1, 1}.each do |sz|
          wheel = Node3D.new
          wheel.position = v3(s * 1.02, -0.22, sz * 1.4)
          tire = MeshInstance3D.new(Mesh.cylinder(0.4, 0.4, 14), dark)
          tire.rotation = Quat.from_axis_angle(Vec3::BACK, Math::PI / 2)
          wheel.add tire
          hub = MeshInstance3D.new(Mesh.cylinder(0.22, 0.44, 8), EagleRocketBall.glow(Color.hex("#c9d2e6")))
          hub.rotation = Quat.from_axis_angle(Vec3::BACK, Math::PI / 2)
          wheel.add hub
          @root.add wheel
          @wheels << wheel
        end
      end
      @root.add MeshInstance3D.new(Mesh.box(0.5, 0.02, 1.7), accent, position: v3(0, 0.19, -1.15))
      @flame_mat = EagleRocketBall.glow(EagleRocketBall.mix(color, Color.hex("#ffd9a0"), 0.55), true, 0.9)
      @flame = MeshInstance3D.new(Mesh.cone(0.42, 2.6, 12), @flame_mat, position: v3(0, -0.05, 3.5))
      @flame.rotation = Quat.from_axis_angle(Vec3::RIGHT, Math::PI / 2)
      @root.add @flame
      parent.add @root
    end

    def color=(c : Color) : Nil
      @body_mat.albedo = c
    end

    def free : Nil
      @root.free
    end

    # Moves the view to a car pose. *forward_speed* turns the wheels.
    def sync(dt : Float32, pos : Vec3, orient : Quat, boosting : Bool, visible : Bool, forward_speed : Float32) : Nil
      @root.visible = visible
      return unless visible
      @root.position = pos
      @root.rotation = orient
      @spin += forward_speed * dt / 0.4_f32
      @wheels.each { |w| w.rotation = Quat.from_axis_angle(Vec3::RIGHT, @spin) }
      @flicker += dt * 40
      len = boosting ? 0.75_f32 + Math.sin(@flicker).abs * 0.35_f32 : 0.001_f32
      @flame.scale = v3(boosting ? 1 : 0.001, len, boosting ? 1 : 0.001)
      @flame.position = v3(0, -0.05, 2.15 + 1.3 * len)
    end
  end

  # A pool of small glowing spheres for sparks, boost trails and explosions.
  class Fx
    class Particle
      property node : MeshInstance3D
      property mat : Material
      property vel = Vec3::ZERO
      property life = 0_f32
      property max_life = 1_f32
      property size = 1_f32
      property gravity = 0_f32

      def initialize(@node : MeshInstance3D, @mat : Material); end
    end

    @pool = [] of Particle
    @next = 0

    def initialize(parent : Node, count : Int32 = 160)
      mesh = Mesh.sphere(0.5, 8, 5)
      count.times do
        mat = EagleRocketBall.glow(Color::WHITE, true, 1)
        node = MeshInstance3D.new(mesh, mat)
        node.scale = 0.0001_f32
        parent.add node
        @pool << Particle.new(node, mat)
      end
    end

    def emit(pos : Vec3, vel : Vec3, color : Color, size : Number, life : Number, gravity : Number = 0) : Nil
      p = @pool[@next]
      @next = (@next + 1) % @pool.size
      p.node.position = pos
      p.vel = vel
      p.mat.albedo = Color.new(color.r, color.g, color.b, 0.9)
      p.life = life.to_f32
      p.max_life = life.to_f32
      p.size = size.to_f32
      p.gravity = gravity.to_f32
    end

    def burst(pos : Vec3, color : Color, count : Int32, speed : Number, size : Number = 0.5, life : Number = 0.9, rng : Random = Random.new) : Nil
      count.times do
        d = v3(rng.rand * 2 - 1, rng.rand * 1.4 - 0.2, rng.rand * 2 - 1)
        d = d.normalized if d.length > 0.001
        emit(pos, d * (speed.to_f32 * (0.4_f32 + rng.rand.to_f32 * 0.6_f32)), EagleRocketBall.mix(color, Color::WHITE, rng.rand * 0.5), size.to_f32 * (0.5_f32 + rng.rand.to_f32), life.to_f32 * (0.6_f32 + rng.rand.to_f32 * 0.5_f32), 14)
      end
    end

    def update(dt : Float32) : Nil
      @pool.each do |p|
        if p.life > 0
          p.life -= dt
          p.vel = Vec3.new(p.vel.x, p.vel.y - p.gravity * dt, p.vel.z)
          p.node.position += p.vel * dt
          f = (p.life / p.max_life).clamp(0_f32, 1_f32)
          p.node.scale = p.life > 0 ? p.size * f : 0.0001_f32
        end
      end
    end
  end
end
