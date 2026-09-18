require "../../src/eagle"
include Eagle

# Playable tour of Eagle's common game algorithms. Number keys and Tab switch
# scenes: A* pathfinding, fBm terrain, Poisson-disk sampling, flocking and
# shadowcasting field of view. No external assets.
class AlgorithmsDemo < App
  enum Scene
    Path
    Noise
    Poisson
    Flock
    Fov
  end

  TAB_H = 36_f32
  BG    = Color.hex("#16141c")

  @scene = Scene::Path
  @cycle = 0_f32
  @auto = false
  @rng = Rng.new(2026)

  @path_grid = CostGrid.new(1, 1)
  @path_start = {1, 1}
  @path_goal = {3, 3}
  @path = [] of Grid::Point
  @path_walk = 0_f32
  @mud = Set(Grid::Point).new

  @noise = Noise.new(11)
  @noise_z = 0_f32

  @points = [] of Vec2

  @boids_pos = [] of Vec2
  @boids_vel = [] of Vec2

  @fov_open = [] of Bool
  @fov_w = 1
  @fov_h = 1
  @fov_origin = {1, 1}
  @fov_visible = Set(Grid::Point).new
  @fov_explored = Set(Grid::Point).new
  @fov_pace = 0_f32
  @fov_cool = 0_f32

  def load : Nil
    @auto = ENV.has_key?("EAGLE_FRAMES") || ENV["EAGLE_DEMO"]? == "1"
    Input.map "left", Key::A, Key::Left
    Input.map "right", Key::D, Key::Right
    Input.map "up", Key::W, Key::Up
    Input.map "down", Key::S, Key::Down
    Input.map "next", Key::Tab, Key::RightBracket
    enter_scene
  end

  def update(dt : Float32) : Nil
    dt = Math.min(dt, 0.05_f32)
    if @auto
      @cycle += dt
      if @cycle >= 0.28
        @cycle = 0
        @scene = Scene.from_value((@scene.value + 1) % Scene.values.size)
        enter_scene
      end
    else
      Scene.values.each do |scene|
        select_scene(scene) if Input.pressed?(Key.from_value(Key::Num1.value + scene.value))
      end
      if Input.pressed?("next")
        select_scene(Scene.from_value((@scene.value + 1) % Scene.values.size))
      end
      if Input.mouse_pressed? && Input.mouse.y < TAB_H
        i = (Input.mouse.x / (Window.width / Scene.values.size)).to_i.clamp(0, Scene.values.size - 1)
        select_scene(Scene.from_value(i))
      end
    end

    case @scene
    when .path?    then update_path(dt)
    when .noise?   then @noise_z += dt * 0.35
    when .poisson? then update_poisson
    when .flock?   then update_flock(dt)
    when .fov?     then update_fov(dt)
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics) : Nil
    g.clear(BG)
    draw_tabs(g)
    case @scene
    when .path?    then draw_path(g)
    when .noise?   then draw_noise(g)
    when .poisson? then draw_poisson(g)
    when .flock?   then draw_flock(g)
    when .fov?     then draw_fov(g)
    end
    g.print(help_text, 12, Window.height - 22, Color.new(1, 1, 1, 0.65))
  end

  private def select_scene(scene : Scene) : Nil
    return if scene == @scene
    @scene = scene
    enter_scene
  end

  private def enter_scene : Nil
    case @scene
    when .path?    then setup_path
    when .poisson? then setup_poisson
    when .flock?   then setup_flock
    when .fov?     then setup_fov
    else
    end
  end

  private def setup_path : Nil
    width, height = 41, 25
    maze = Procedural.maze(width, height, Rng.new(9))
    grid = CostGrid.new(width, height)
    mud = Set(Grid::Point).new
    rng = Rng.new(3)
    height.times do |y|
      width.times do |x|
        if maze[y * width + x]
          if rng.chance?(0.08)
            grid[x, y] = 4
            mud << {x, y}
          end
        else
          grid.block(x, y)
        end
      end
    end
    @path_grid = grid
    @mud = mud
    @path_start = {1, 1}
    @path_goal = farthest_open({1, 1})
    @path_walk = 0
    rebuild_path
  end

  private def farthest_open(from : Grid::Point) : Grid::Point
    best = from
    best_d = 0
    @path_grid.height.times do |y|
      @path_grid.width.times do |x|
        next unless @path_grid.passable?(x, y)
        d = (x - from[0]).abs + (y - from[1]).abs
        if d > best_d
          best_d = d
          best = {x, y}
        end
      end
    end
    best
  end

  private def rebuild_path : Nil
    result = Pathfinding.a_star(@path_grid, @path_start, @path_goal, diagonal: true)
    @path = result.path
    @path_walk = 0
  end

  private def cell_size : Float32
    Math.min((Window.width - 24) / @path_grid.width, (Window.height - TAB_H - 48) / @path_grid.height).to_f32
  end

  private def grid_origin : Vec2
    size = cell_size
    v2((Window.width - @path_grid.width * size) / 2,
      TAB_H + 8 + (Window.height - TAB_H - 40 - @path_grid.height * size) / 2)
  end

  private def cell_at(mouse : Vec2) : Grid::Point?
    size = cell_size
    origin = grid_origin
    x = ((mouse.x - origin.x) / size).floor.to_i
    y = ((mouse.y - origin.y) / size).floor.to_i
    @path_grid.in_bounds?(x, y) ? {x, y} : nil
  end

  private def update_path(dt : Float32) : Nil
    if Input.mouse_pressed? && Input.mouse.y >= TAB_H
      if cell = cell_at(Input.mouse)
        if @path_grid.passable?(cell[0], cell[1])
          @path_goal = cell
          rebuild_path
        end
      end
    end
    return if @path.size < 2
    @path_walk += dt * 8
    while @path_walk >= 1 && @path.size >= 2
      @path_walk -= 1
      @path_start = @path[1]
      @path.shift
    end
    if @path.size <= 1
      @path_goal = farthest_open(@path_start)
      @path_goal = {1, 1} if @path_goal == @path_start
      rebuild_path
    end
  end

  private def draw_path(g : Graphics) : Nil
    size = cell_size
    origin = grid_origin
    @path_grid.height.times do |y|
      @path_grid.width.times do |x|
        px = origin.x + x * size
        py = origin.y + y * size
        color = if !@path_grid.passable?(x, y)
                  Color.hex("#2a2733")
                elsif @mud.includes?({x, y})
                  Color.hex("#5c4328")
                else
                  Color.hex("#3d4658")
                end
        g.rect(px, py, size - 1, size - 1, color: color)
      end
    end
    @path.each_cons_pair do |a, b|
      g.line(origin + v2(a[0] + 0.5, a[1] + 0.5) * size, origin + v2(b[0] + 0.5, b[1] + 0.5) * size,
        Color.hex("#e3a537"), 2)
    end
    start = origin + v2(@path_start[0] + 0.5, @path_start[1] + 0.5) * size
    goal = origin + v2(@path_goal[0] + 0.5, @path_goal[1] + 0.5) * size
    g.circle(start, size * 0.32, color: Color.hex("#7bed9f"))
    g.circle(goal, size * 0.32, color: Color.hex("#ff5d73"))
    g.print("click a floor tile to set the goal   mud is slower", origin.x, origin.y - 16, Color.new(1, 1, 1, 0.7))
  end

  private def draw_noise(g : Graphics) : Nil
    cols = 80
    rows = 42
    cw = Window.width / cols
    ch = (Window.height - TAB_H - 28) / rows
    rows.times do |y|
      cols.times do |x|
        h = @noise.fbm(x * 0.08, y * 0.08 + @noise_z, octaves: 4)
        color = if h < -0.15
                  Color.hex("#1d4e89").lerp(Color.hex("#3d7ea6"), (h + 0.5).clamp(0, 1))
                elsif h < 0.05
                  Color.hex("#c9b896")
                elsif h < 0.35
                  Color.hex("#3f7d4e").lerp(Color.hex("#7daf6a"), (h - 0.05) / 0.3)
                elsif h < 0.55
                  Color.hex("#6b6e70")
                else
                  Color.hex("#e8eef5")
                end
        g.rect(x * cw, TAB_H + y * ch, cw + 0.5, ch + 0.5, color: color)
      end
    end
    g.print("simplex fBm   seed 11", 12, TAB_H + 8, Color.new(0, 0, 0, 0.55))
  end

  private def setup_poisson : Nil
    @points = Procedural.poisson_disk(Window.width - 40, Window.height - TAB_H - 60, 22, Rng.new(5))
  end

  private def update_poisson : Nil
    setup_poisson if Input.pressed?(Key::R)
  end

  private def draw_poisson(g : Graphics) : Nil
    origin = v2(20, TAB_H + 28)
    g.print("#{@points.size} points, minimum distance 22   R reseeds", origin.x, TAB_H + 8, Color.new(1, 1, 1, 0.7))
    @points.each do |point|
      p = origin + point
      g.circle(p, 11, color: Color.hex("#2f6f44"))
      g.circle(p, 5, color: Color.hex("#7daf6a"))
    end
  end

  private def setup_flock : Nil
    rng = Rng.new(21)
    @boids_pos = Array.new(48) { rng.in_rect(Rect.new(40, TAB_H + 40, Window.width - 80, Window.height - TAB_H - 80)) }
    @boids_vel = Array.new(48) { rng.direction * rng.float(40, 90) }
  end

  private def update_flock(dt : Float32) : Nil
    radius = 46_f32
    max_speed = 110_f32
    hash = SpatialHash(Int32).new(radius)
    @boids_pos.each_with_index { |pos, i| hash.insert(i, pos) }
    @boids_pos.each_with_index do |pos, i|
      nearby_p = [] of Vec2
      nearby_v = [] of Vec2
      hash.query(pos, radius).each do |j|
        next if i == j
        nearby_p << @boids_pos[j]
        nearby_v << @boids_vel[j]
      end
      force = Steering.flock(pos, @boids_vel[i], nearby_p, nearby_v, radius).limit(220)
      force += Steering.seek(pos, Input.mouse, max_speed) * 0.35 if Input.mouse.y > TAB_H
      vel = (@boids_vel[i] + force * dt).limit(max_speed)
      pos = pos + vel * dt
      pos = v2(pos.x < 0 ? Window.width : (pos.x > Window.width ? 0 : pos.x),
        pos.y < TAB_H ? Window.height : (pos.y > Window.height ? TAB_H : pos.y))
      @boids_pos[i] = pos
      @boids_vel[i] = vel
    end
  end

  private def draw_flock(g : Graphics) : Nil
    g.print("mouse attracts   wrapping world", 12, TAB_H + 8, Color.new(1, 1, 1, 0.7))
    @boids_pos.each_with_index do |pos, i|
      dir = @boids_vel[i].normalized
      tip = pos + dir * 10
      left = pos - dir * 6 + dir.perpendicular * 5
      right = pos - dir * 6 - dir.perpendicular * 5
      g.polygon([tip, left, right], color: Color.hsv(i * 17, 0.55, 0.95))
    end
  end

  private def setup_fov : Nil
    @fov_w, @fov_h = 45, 27
    maze = Procedural.maze(@fov_w, @fov_h, Rng.new(14))
    @fov_open = maze
    @fov_origin = {1, 1}
    @fov_explored.clear
    recompute_fov
  end

  private def recompute_fov : Nil
    @fov_visible = Grid.field_of_view(@fov_origin, 9) do |x, y|
      !x.in?(0...@fov_w) || !y.in?(0...@fov_h) || !@fov_open[y * @fov_w + x]
    end
    @fov_visible.each { |cell| @fov_explored << cell }
  end

  private def update_fov(dt : Float32) : Nil
    @fov_cool -= dt
    move = Input.vector("left", "right", "up", "down")
    if @fov_cool <= 0 && move.length_squared > 0.25
      dx = Mathf.sign(move.x)
      dy = dx != 0 ? 0 : Mathf.sign(move.y)
      nx = @fov_origin[0] + dx
      ny = @fov_origin[1] + dy
      if nx.in?(0...@fov_w) && ny.in?(0...@fov_h) && @fov_open[ny * @fov_w + nx]
        @fov_origin = {nx, ny}
        recompute_fov
        @fov_cool = 0.12
      end
    end
    if @auto
      @fov_pace += dt
      if @fov_pace > 0.1
        @fov_pace = 0
        choices = Grid::CARDINAL.map { |(dx, dy)| {@fov_origin[0] + dx, @fov_origin[1] + dy} }
          .select { |n| n[0].in?(0...@fov_w) && n[1].in?(0...@fov_h) && @fov_open[n[1] * @fov_w + n[0]] }
        if cell = @rng.pick?(choices)
          @fov_origin = cell
          recompute_fov
        end
      end
    elsif Input.mouse_pressed? && Input.mouse.y >= TAB_H
      size = Math.min((Window.width - 24) / @fov_w, (Window.height - TAB_H - 48) / @fov_h)
      origin = v2((Window.width - @fov_w * size) / 2, TAB_H + 20)
      x = ((Input.mouse.x - origin.x) / size).floor.to_i
      y = ((Input.mouse.y - origin.y) / size).floor.to_i
      if x.in?(0...@fov_w) && y.in?(0...@fov_h) && @fov_open[y * @fov_w + x]
        @fov_origin = {x, y}
        recompute_fov
      end
    end
  end

  private def draw_fov(g : Graphics) : Nil
    size = Math.min((Window.width - 24) / @fov_w, (Window.height - TAB_H - 48) / @fov_h)
    origin = v2((Window.width - @fov_w * size) / 2, TAB_H + 20)
    @fov_h.times do |y|
      @fov_w.times do |x|
        cell = {x, y}
        open = @fov_open[y * @fov_w + x]
        color = if @fov_visible.includes?(cell)
                  open ? Color.hex("#d7c9a3") : Color.hex("#6b6560")
                elsif @fov_explored.includes?(cell)
                  open ? Color.hex("#3c3a48") : Color.hex("#24222c")
                else
                  Color.hex("#0c0b10")
                end
        g.rect(origin.x + x * size, origin.y + y * size, size - 1, size - 1, color: color)
      end
    end
    px = origin.x + (@fov_origin[0] + 0.5) * size
    py = origin.y + (@fov_origin[1] + 0.5) * size
    g.circle(px, py, size * 0.32, color: Color.hex("#e3a537"))
    g.print("WASD move   click to teleport", origin.x, TAB_H + 6, Color.new(1, 1, 1, 0.7))
  end

  private def draw_tabs(g : Graphics) : Nil
    n = Scene.values.size
    w = Window.width / n
    Scene.values.each_with_index do |scene, i|
      on = scene == @scene
      g.rect(i * w, 0, w, TAB_H, color: on ? Color.hex("#2b241c") : Color.hex("#1c1a22"))
      g.rect(i * w, TAB_H - 3, w, 3, color: on ? Color.hex("#e3a537") : Color.hex("#2a2733"))
      g.print("#{i + 1}  #{scene_name(scene)}", i * w + w / 2, 10, on ? Color.hex("#f4efe6") : Color.hex("#8a8278"),
        align: TextAlign::Center)
    end
  end

  private def scene_name(scene : Scene) : String
    case scene
    in .path?    then "A* path"
    in .noise?   then "Noise"
    in .poisson? then "Poisson"
    in .flock?   then "Flocking"
    in .fov?     then "FOV"
    end
  end

  private def help_text : String
    "1-5 or Tab switch scenes   Esc quits"
  end
end

Eagle.run(AlgorithmsDemo, title: "Eagle Algorithms", width: 960, height: 600)
