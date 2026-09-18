require "./sim"

include Eagle

# Joyride is a compact open-world driving game. The same seed always produces the same
# unbounded road network, city blocks, farms and countryside. Only the chunks around the
# player exist in the scene tree; simulation data is generated on demand and old chunks
# are evicted as the car travels.
class JoyrideGame < App
  STREAM_RADIUS =  2
  TRAFFIC_COUNT = 10
  PED_LIMIT     = 28

  @world = Joyride::World.new((ENV["EAGLE_WORLD_SEED"]? || "2026").to_i64)
  @player = Joyride::Car.new(v2(48, 48))
  @camera = Camera3D.new(position: v3(0, 8, 12), fov: 66)
  @chunks = {} of {Int32, Int32} => Node3D
  @traffic = [] of Joyride::TrafficCar
  @traffic_nodes = [] of Node3D
  @police = [] of Joyride::Car
  @police_nodes = [] of Node3D
  @police_pilots = [] of Joyride::Pilot
  @pedestrians = [] of Joyride::Pedestrian
  @pedestrian_nodes = [] of Node3D
  @mission : Joyride::Mission? = nil
  @wanted = Joyride::Wanted.new
  @rng = Joyride::Rng.new(0xEA61E_u64)
  @score = 0
  @message = "Find the glowing mission marker"
  @message_time = 5_f32
  @last_chunk = {Int32::MIN, Int32::MIN}
  @player_node = Node3D.new("player")
  @target_node = Node3D.new("mission")

  def load : Nil
    Input.map "accelerate", Key::W, Key::Up, Input.axis(GamepadAxis::TriggerRight, 1)
    Input.map "brake", Key::S, Key::Down, Input.axis(GamepadAxis::TriggerLeft, 1)
    Input.map "steer_left", Key::A, Key::Left, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "steer_right", Key::D, Key::Right, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "handbrake", Key::Space, GamepadButton::A

    env = Scene3D.environment
    env.ambient = Color.new(0.3, 0.32, 0.35)
    env.fog(150, 290, Color.hex("#b9cfe1"))
    env.sky_colors(Color.hex("#70a9e0"), Color.hex("#d8e7ef"), Color.hex("#819260"))
    root = SceneTree.root
    root.add(DirectionalLight3D.new(v3(-0.45, -1, -0.3), Color.hex("#fff1d0"), 1.1))

    start = @world.node(0, 0)
    dir = @world.arms(0, 0).first?.try { |a| (a.points[1] - a.points[0]).normalized } || v2(0, -1)
    @player = Joyride::Car.new(start, Joyride.heading_of(dir))
    build_car(@player_node, Color.hex("#f0b323"), police: false)
    root.add(@player_node)
    root.add(@camera)
    build_target
    root.add(@target_node)
    stream_world(force: true)
    spawn_traffic
    new_mission
  end

  def update(dt : Float32) : Nil
    dt = Math.min(dt, 0.05_f32)
    drive_player(dt)
    update_traffic(dt)
    update_police(dt)
    update_pedestrians(dt)
    update_mission(dt)
    stream_world
    update_camera(dt)
    sync_nodes
    @message_time -= dt if @message_time > 0
    Eagle.quit if Input.pressed?(Key::Escape)
    new_mission if Input.pressed?(Key::M)
  end

  private def drive_player(dt : Float32) : Nil
    @player.clear_inputs
    @player.throttle = Input.strength("accelerate")
    @player.brake = Input.strength("brake")
    @player.steer_input = Input.strength("steer_right") - Input.strength("steer_left")
    @player.handbrake = Input.down?("handbrake")
    impact = @player.step(dt, @world)
    @player.y = @world.ground_height(@player.pos)
    if impact > 9 && @wanted.crime!
      notify("Property damage! Police alerted")
    end
  end

  private def update_traffic(dt : Float32) : Nil
    @traffic.each { |t| t.update(dt, @world, @player, @traffic) }
    @traffic.each do |t|
      hit = Joyride::Car.collide(@player, t.car)
      if hit > 8
        t.wreck! if hit > 15
        notify("Traffic collision") if @wanted.crime!
      end
    end
    # Recycle traffic that fell far behind, keeping the population bounded forever.
    @traffic.each_with_index do |t, i|
      next if t.position.distance(@player.pos) < Joyride::CHUNK * 3.5
      t.wanderer.path.clear
      cur = @world.nearest_node_chunk(@player.pos + Joyride.forward(@player.heading) * (70 + i * 5)) || Joyride::World.chunk_of(@player.pos)
      @traffic[i] = Joyride::TrafficCar.new(@world, cur, nil, @rng.next_u64, i)
    end
  end

  private def update_police(dt : Float32) : Nil
    seen = @police.any? { |p| p.pos.distance(@player.pos) < 60 }
    notify("Wanted level dropped") if @wanted.update(dt, seen)
    while @police.size < @wanted.police_count
      behind = @player.pos - @player.forward * (35 + @police.size * 8)
      road, dir = @world.nearest_road_point(behind) || {@player.pos - @player.forward * 25, @player.forward}
      car = Joyride::Car.new(road, Joyride.heading_of(dir), Joyride::POLICE_SPEC)
      node = Node3D.new("police")
      build_car(node, Color.hex("#172c52"), police: true)
      SceneTree.root.add(node)
      @police << car; @police_nodes << node; @police_pilots << Joyride::Pilot.new
    end
    while @police.size > @wanted.police_count
      @police.pop; @police_pilots.pop; @police_nodes.pop.free
    end
    empty_path = Joyride::RoutePath.new
    @police.each_with_index do |car, i|
      pilot = @police_pilots[i]
      pilot.target_speed = 38_f32
      pilot.drive(car, empty_path, dt, @player.pos)
      car.step(dt, @world)
      if Joyride::Car.collide(car, @player) > 6
        @player.vel *= 0.8_f32
      end
    end
  end

  private def update_pedestrians(dt : Float32) : Nil
    cars = [@player] + @traffic.map(&.car) + @police
    @pedestrians.each do |p|
      if p.update(dt, cars)
        notify("Pedestrian hit! Wanted level raised") if @wanted.crime!(2)
      end
    end
  end

  private def update_mission(dt : Float32) : Nil
    mission = @mission
    return unless mission
    if event = mission.update(dt, @player.pos, @player.speed)
      case event
      when :checkpoint then notify(mission.kind.delivery? ? "Package collected" : "Checkpoint!")
      when :complete
        @score += mission.reward
        notify("Mission complete  +$#{mission.reward}")
      when :failed then notify("Mission failed")
      end
    end
    new_mission if mission.done? && Input.pressed?(Key::Enter)
    if target = mission.target
      @target_node.visible = true
      @target_node.position = v3(target.pos.x, 0.15, target.pos.y)
      @target_node.rotate_y(dt)
    else
      @target_node.visible = false
    end
  end

  private def new_mission : Nil
    kind = @rng.chance(0.5) ? Joyride::Mission::Kind::Delivery : Joyride::Mission::Kind::Race
    @mission = Joyride::Mission.generate(@world, @player.pos, kind, @rng)
    notify(@mission.not_nil!.title)
  end

  private def update_camera(dt : Float32) : Nil
    f = Joyride.forward(@player.heading)
    focus = v3(@player.pos.x, 1.1 + @player.y, @player.pos.y)
    desired = focus + v3(-f.x * 11, 6.5, -f.y * 11)
    @camera.position = Mathf.damp(@camera.position, desired, 5, dt)
    @camera.look_at(focus + v3(f.x * 5, 0.4, f.y * 5))
  end

  private def sync_nodes : Nil
    place_car(@player_node, @player)
    @traffic.each_with_index { |t, i| place_car(@traffic_nodes[i], t.car) }
    @police.each_with_index { |p, i| place_car(@police_nodes[i], p) }
    @pedestrians.each_with_index do |p, i|
      n = @pedestrian_nodes[i]
      n.position = v3(p.pos.x, p.down? ? 0.25 : 0.9, p.pos.y)
      n.set_euler(p.down? ? Math::PI / 2 : 0, p.heading, 0)
    end
  end

  private def place_car(n : Node3D, car : Joyride::Car) : Nil
    n.position = v3(car.pos.x, 0.45 + car.y, car.pos.y)
    n.set_euler(0, car.heading, -car.slip.clamp(0_f32, 8_f32) * 0.01)
  end

  private def stream_world(force = false) : Nil
    cx, cz = Joyride::World.chunk_of(@player.pos)
    return if !force && @last_chunk == {cx, cz}
    @last_chunk = {cx, cz}
    wanted = Set({Int32, Int32}).new
    (-STREAM_RADIUS..STREAM_RADIUS).each do |x|
      (-STREAM_RADIUS..STREAM_RADIUS).each do |z|
        key = {cx + x, cz + z}; wanted << key
        unless @chunks.has_key?(key)
          node = render_chunk(@world.layout(*key))
          @chunks[key] = node
          SceneTree.root.add(node)
        end
      end
    end
    @chunks.keys.reject { |k| wanted.includes?(k) }.each { |k| @chunks.delete(k).not_nil!.free }
    @world.evict(cx, cz, STREAM_RADIUS + 1)
    rebuild_pedestrians(cx, cz)
  end

  private def render_chunk(lay : Joyride::ChunkLayout) : Node3D
    n = Node3D.new("chunk #{lay.cx},#{lay.cz}")
    n.add(mesh_box(lay.center, Joyride::CHUNK, 0.05, Joyride::CHUNK, lay.ground))
    lay.patches.each do |p|
      n.add(mesh_box(v2((p.x0 + p.x1) / 2, (p.z0 + p.z1) / 2), p.x1 - p.x0, 0.04, p.z1 - p.z0, p.color, 0.04))
    end
    lay.arms.each do |arm|
      arm.points.each_cons_pair do |a, b|
        add_segment(n, a, b, arm.half_width * 2, Color.hex(arm.street? ? "#42464d" : "#55585a"), 0.08)
        # dashed center line, deliberately sparse to keep the web draw count reasonable
        mid = (a + b) / 2
        d = b - a
        add_segment(n, mid - d.normalized * Math.min(2, d.length / 3), mid + d.normalized * Math.min(2, d.length / 3), 0.16, Color.hex("#e7dca4"), 0.13)
      end
    end
    lay.slabs.each { |s| n.add(mesh_box(v2((s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2), s.x1 - s.x0, Joyride::CURB_H, s.z1 - s.z0, Color.hex("#a6a39b"), Joyride::CURB_H / 2)) }
    lay.buildings.each do |b|
      n.add(mesh_box(b.center, b.width, b.height, b.depth, b.color, b.height / 2))
      roof = mesh_box(b.center, b.width + 0.25, 0.25, b.depth + 0.25, b.roof, b.height + 0.13)
      n.add(roof)
    end
    lay.props.each { |p| add_prop(n, p) }
    n
  end

  private def mesh_box(p : Vec2, w, h, d, color : Color, y = -0.02) : MeshInstance3D
    MeshInstance3D.new(Mesh.box(w, h, d), Material.new(color, specular: 0.08), position: v3(p.x, y, p.y))
  end

  private def add_segment(parent : Node3D, a : Vec2, b : Vec2, width : Number, color : Color, y : Number) : Nil
    d = b - a
    return if d.length < 0.05
    m = mesh_box((a + b) / 2, width, 0.04, d.length + 0.15, color, y)
    m.set_euler(0, Joyride.heading_of(d), 0)
    parent.add(m)
  end

  private def add_prop(parent : Node3D, p : Joyride::Prop) : Nil
    case p.kind
    when .tree?, .pine?
      trunk = MeshInstance3D.new(Mesh.cylinder(0.22 * p.scale, 2.3 * p.scale, 8), Material.new(Color.hex("#69452d")), position: v3(p.pos.x, 1.15 * p.scale, p.pos.y))
      crown_mesh = p.kind.pine? ? Mesh.cone(1.2 * p.scale, 3.2 * p.scale, 10) : Mesh.sphere(1.25 * p.scale, 10, 7)
      crown = MeshInstance3D.new(crown_mesh, Material.new(p.color), position: v3(p.pos.x, 3 * p.scale, p.pos.y))
      parent.add(trunk, crown)
    when .hill?
      m = MeshInstance3D.new(Mesh.sphere(1, 12, 7), Material.new(p.color), position: v3(p.pos.x, -p.scale * 0.55, p.pos.y))
      m.scale = v3(p.scale, p.scale * 0.35, p.scale)
      parent.add(m)
    when .lamp?
      parent.add(MeshInstance3D.new(Mesh.cylinder(0.08, 3.5, 8), Material.new(Color.hex("#30343a")), position: v3(p.pos.x, 1.75, p.pos.y)))
    else
      size = p.kind.rock? ? p.scale : 0.8_f32
      parent.add(MeshInstance3D.new(Mesh.box(size, size, size), Material.new(p.color == Color::WHITE ? Color.hex("#a08d70") : p.color), position: v3(p.pos.x, size / 2, p.pos.y)))
    end
  end

  private def spawn_traffic : Nil
    origin = Joyride::World.chunk_of(@player.pos)
    chunks = [] of {Int32, Int32}
    seen = Set{origin}
    frontier = Deque({Int32, Int32}).new
    @world.neighbors(*origin).each { |c| frontier << c; seen << c }
    while (cur = frontier.shift?) && chunks.size < TRAFFIC_COUNT
      chunks << cur
      @world.neighbors(*cur).each do |c|
        next if seen.includes?(c)
        seen << c; frontier << c
      end
    end
    chunks << origin if chunks.empty?
    TRAFFIC_COUNT.times do |i|
      cur = chunks[i % chunks.size]
      t = Joyride::TrafficCar.new(@world, cur, nil, @rng.next_u64, i)
      node = Node3D.new("traffic")
      build_car(node, Color.hsv(i * 47, 0.55, 0.8), police: false)
      SceneTree.root.add(node)
      @traffic << t; @traffic_nodes << node
    end
  end

  private def rebuild_pedestrians(cx : Int32, cz : Int32) : Nil
    @pedestrian_nodes.each(&.free)
    @pedestrian_nodes.clear; @pedestrians.clear
    (-1..1).each do |ox|
      (-1..1).each do |oz|
        lay = @world.layout(cx + ox, cz + oz)
        lay.walkways.first(4).each do |(a, b)|
          break if @pedestrians.size >= PED_LIMIT
          p = Joyride::Pedestrian.new(a, b, @rng.float, Color.hsv(@rng.range(0, 360), 0.6, 0.9), Color.hex("#27334a"), @rng.range(1.1, 1.8))
          node = Node3D.new("pedestrian")
          node.add(MeshInstance3D.new(Mesh.cylinder(0.22, 1.1, 8), Material.new(p.shirt), position: v3(0, 0, 0)))
          node.add(MeshInstance3D.new(Mesh.sphere(0.2, 8, 6), Material.new(Color.hex("#d8a47f")), position: v3(0, 0.72, 0)))
          SceneTree.root.add(node)
          @pedestrians << p; @pedestrian_nodes << node
        end
      end
    end
  end

  private def build_car(n : Node3D, color : Color, police : Bool) : Nil
    n.add(MeshInstance3D.new(Mesh.box(1.9, 0.55, 4.2), Material.new(color, shininess: 48), position: v3(0, 0, 0)))
    n.add(MeshInstance3D.new(Mesh.box(1.65, 0.55, 1.9), Material.new(Color.hex("#9ec5df"), shininess: 80), position: v3(0, 0.5, 0.25)))
    if police
      n.add(MeshInstance3D.new(Mesh.box(1.25, 0.12, 0.28), Material.unlit(Color.hex("#e43d42")), position: v3(0, 0.86, 0.2)))
    end
  end

  private def build_target : Nil
    mat = Material.new(Color.new(1, 0.75, 0.08, 0.5), unlit: true, transparent: true)
    @target_node.add(MeshInstance3D.new(Mesh.cylinder(4, 0.2, 28), mat))
    @target_node.add(MeshInstance3D.new(Mesh.torus(4, 0.16, 28, 8), Material.unlit(Color.hex("#ffd54a")), position: v3(0, 0.35, 0)))
  end

  private def notify(text : String) : Nil
    @message = text; @message_time = 3_f32
  end

  def draw(g : Graphics) : Nil
    g.rect(0, 0, Window.width, 62, color: Color.new(0.02, 0.03, 0.05, 0.78))
    speed = (@player.forward_speed.abs * 3.6).round.to_i
    zone = @world.zone(*Joyride::World.chunk_of(@player.pos)).to_s
    wanted = @wanted.level > 0 ? "WANTED #{"*" * @wanted.level}" : "WANTED clear"
    g.print("#{speed} km/h    $#{@score}    #{zone}    #{wanted}", 18, 12, Color::WHITE, scale: 1.25)
    if mission = @mission
      timer = mission.time_left.try { |t| "  #{t.ceil.to_i}s" } || ""
      g.print("#{mission.title}#{timer}", 18, 39, Color.hex("#ffd54a"))
      if mission.done?
        g.print("Enter: next mission", Window.width - 190, 39, Color::WHITE)
      end
    end
    draw_minimap(g)
    if @message_time > 0
      g.rounded_rect(Window.width / 2 - 190, Window.height - 58, 380, 38, 8, color: Color.new(0, 0, 0, 0.72))
      g.print(@message, Window.width / 2, Window.height - 47, Color::WHITE, align: TextAlign::Center)
    end
    g.print("WASD/arrows drive   Space handbrake   M new mission   Esc quit", 16, Window.height - 22, Color.new(1, 1, 1, 0.7))
  end

  private def draw_minimap(g : Graphics) : Nil
    size = 150_f32; x = Window.width - size - 14; y = 74_f32; scale = 0.35_f32
    g.rect(x, y, size, size, color: Color.new(0.02, 0.03, 0.04, 0.75))
    center = v2(x + size / 2, y + size / 2)
    @chunks.each_key do |(cx, cz)|
      @world.arms(cx, cz).each do |a|
        a.points.each_cons_pair do |p, q|
          pa = center + (p - @player.pos) * scale
          pb = center + (q - @player.pos) * scale
          g.line(pa, pb, Color.new(0.75, 0.75, 0.7, 0.5), 1)
        end
      end
    end
    if target = @mission.try(&.target)
      p = center + (target.pos - @player.pos) * scale
      g.circle(p, 4, color: Color.hex("#ffd54a")) if p.x.in?(x..x + size) && p.y.in?(y..y + size)
    end
    f = Joyride.forward(@player.heading)
    g.line(center, center + f * 9, Color::WHITE, 3)
    g.circle(center, 4, color: Color.hex("#f0b323"))
  end
end

Eagle.run(JoyrideGame, title: "Eagle Joyride", width: 1100, height: 700, msaa: 2)
