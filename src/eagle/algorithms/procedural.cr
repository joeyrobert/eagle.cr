module Eagle
  # Map generators and sampling helpers used to build levels and scatter props.
  # Pass an `Rng` so a seed reproduces the same layout.
  #
  # ```
  # rng = Rng.new(7)
  # trees = Procedural.poisson_disk(320, 180, 16, rng)
  # rooms = Procedural.bsp_rooms(64, 48, rng)
  # cave = Procedural.cave(40, 24, rng)
  # program = Procedural.lsystem("F", {'F' => "F[+F]F[-F]F"}, 3)
  # ```
  module Procedural
    # Bridson Poisson-disk sampling in a rectangle.
    def self.poisson_disk(width : Number, height : Number, minimum_distance : Number,
                          rng = Rng.new, attempts = 30) : Array(Vec2)
      width = width.to_f32; height = height.to_f32; distance = minimum_distance.to_f32
      raise ArgumentError.new("dimensions and distance must be positive") if width <= 0 || height <= 0 || distance <= 0
      raise ArgumentError.new("attempts must be positive") if attempts <= 0
      cell_size = distance / Math.sqrt(2.0)
      columns = (width / cell_size).ceil.to_i
      rows = (height / cell_size).ceil.to_i
      grid = Array(Int32).new(columns * rows, -1)
      first = Vec2.new(rng.float(0, width), rng.float(0, height))
      points = [first]
      active = [0]
      grid[(first.y / cell_size).to_i * columns + (first.x / cell_size).to_i] = 0
      until active.empty?
        active_index = rng.below(active.size)
        source = points[active[active_index]]
        accepted = false
        attempts.times do
          candidate = source + Vec2.from_angle(rng.angle, rng.float(distance, distance * 2))
          next unless candidate.x >= 0 && candidate.y >= 0 && candidate.x < width && candidate.y < height
          gx = (candidate.x / cell_size).to_i; gy = (candidate.y / cell_size).to_i
          valid = true
          (Math.max(0, gy - 2)..Math.min(rows - 1, gy + 2)).each do |y|
            (Math.max(0, gx - 2)..Math.min(columns - 1, gx + 2)).each do |x|
              index = grid[y * columns + x]
              valid = false if index >= 0 && points[index].distance_squared(candidate) < distance * distance
            end
          end
          next unless valid
          grid[gy * columns + gx] = points.size
          points << candidate
          active << points.size - 1
          accepted = true
          break
        end
        active.delete_at(active_index) unless accepted
      end
      points
    end

    # Short alias for `poisson_disk`.
    def self.poisson(width : Number, height : Number, minimum_distance : Number,
                     rng = Rng.new, attempts = 30) : Array(Vec2)
      poisson_disk(width, height, minimum_distance, rng, attempts)
    end

    # Leaf rooms from recursive binary-space partitioning. Rooms have a one-cell margin.
    def self.bsp_rooms(width : Int, height : Int, rng = Rng.new, minimum_size = 6, depth = 4) : Array(Rect)
      raise ArgumentError.new("dimensions must be at least 3") if width < 3 || height < 3
      raise ArgumentError.new("minimum_size must be at least 2") if minimum_size < 2
      raise ArgumentError.new("depth cannot be negative") if depth < 0
      leaves = [{1, 1, width.to_i32 - 2, height.to_i32 - 2}]
      depth.times do
        next_leaves = [] of {Int32, Int32, Int32, Int32}
        leaves.each do |(x, y, w, h)|
          split_vertical = w > h || (w == h && rng.bool)
          if split_vertical && w >= minimum_size * 2
            cut = rng.int(minimum_size, w - minimum_size)
            next_leaves << {x, y, cut, h} << {x + cut, y, w - cut, h}
          elsif h >= minimum_size * 2
            cut = rng.int(minimum_size, h - minimum_size)
            next_leaves << {x, y, w, cut} << {x, y + cut, w, h - cut}
          else
            next_leaves << {x, y, w, h}
          end
        end
        leaves = next_leaves
      end
      leaves.map do |(x, y, w, h)|
        inset_x = rng.int(1, Math.max(1, w // 4)); inset_y = rng.int(1, Math.max(1, h // 4))
        Rect.new(x + inset_x, y + inset_y, Math.max(1, w - inset_x - 1), Math.max(1, h - inset_y - 1))
      end
    end

    # Cellular-automata cave. `true` means wall; borders always remain walls.
    def self.cellular_cave(width : Int, height : Int, rng = Rng.new, fill = 0.45, iterations = 5) : Array(Bool)
      width = width.to_i32; height = height.to_i32
      raise ArgumentError.new("dimensions must be at least 3") if width < 3 || height < 3
      raise ArgumentError.new("fill must be between 0 and 1") unless fill.in?(0..1)
      raise ArgumentError.new("iterations cannot be negative") if iterations < 0
      cells = Array(Bool).new(width * height) do |index|
        x = index % width; y = index // width
        x == 0 || y == 0 || x == width - 1 || y == height - 1 || rng.chance?(fill)
      end
      iterations.times do
        previous = cells
        cells = Array(Bool).new(width * height) do |index|
          x = index % width; y = index // width
          if x == 0 || y == 0 || x == width - 1 || y == height - 1
            true
          else
            walls = 0
            (-1..1).each { |dy| (-1..1).each { |dx| walls += 1 if (dx != 0 || dy != 0) && previous[(y + dy) * width + x + dx] } }
            walls >= 5
          end
        end
      end
      cells
    end

    # Short alias for `cellular_cave`.
    def self.cave(width : Int, height : Int, rng = Rng.new, fill = 0.45, iterations = 5) : Array(Bool)
      cellular_cave(width, height, rng, fill, iterations)
    end

    # Perfect recursive-backtracker maze. `true` cells are open passages.
    def self.maze(width : Int, height : Int, rng = Rng.new) : Array(Bool)
      width = width.to_i32; height = height.to_i32
      raise ArgumentError.new("dimensions must be at least 3") if width < 3 || height < 3
      open = Array(Bool).new(width * height, false)
      stack = [{1, 1}]
      open[width + 1] = true
      until stack.empty?
        x, y = stack.last
        candidates = [{0, -1}, {1, 0}, {0, 1}, {-1, 0}].map { |(dx, dy)| {x + dx * 2, y + dy * 2, dx, dy} }
          .select { |(nx, ny, _, _)| nx > 0 && ny > 0 && nx < width - 1 && ny < height - 1 && !open[ny * width + nx] }
        if candidates.empty?
          stack.pop
        else
          nx, ny, dx, dy = rng.pick(candidates)
          open[(y + dy) * width + x + dx] = true
          open[ny * width + nx] = true
          stack << {nx, ny}
        end
      end
      open
    end

    # Expands a deterministic context-free L-system.
    def self.lsystem(axiom : String, rules : Hash(Char, String), iterations : Int) : String
      current = axiom
      iterations.times do
        String.build do |io|
          current.each_char { |char| io << (rules[char]? || char) }
        end.tap { |next_value| current = next_value }
      end
      current
    end

    # Turtle interpretation of F/G draw, +/- turn and [] branch commands.
    def self.lsystem_segments(program : String, angle : Number, step : Number = 1,
                              start = Vec2::ZERO, heading : Number = -Math::PI / 2) : Array({Vec2, Vec2})
      position = start
      direction = heading.to_f64
      stack = [] of {Vec2, Float64}
      segments = [] of {Vec2, Vec2}
      program.each_char do |command|
        case command
        when 'F', 'G'
          next_position = position + Vec2.from_angle(direction, step)
          segments << {position, next_position}
          position = next_position
        when '+' then direction += angle
        when '-' then direction -= angle
        when '[' then stack << {position, direction}
        when ']'
          position, direction = stack.pop? || raise ArgumentError.new("unbalanced L-system brackets")
        end
      end
      raise ArgumentError.new("unbalanced L-system brackets") unless stack.empty?
      segments
    end
  end
end
