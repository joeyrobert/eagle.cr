module Eagle
  # Weighted finite grid used by A*, Dijkstra and flow-field searches. A cost must be
  # positive; `Float64::INFINITY` marks an impassable cell.
  #
  # ```
  # grid = CostGrid.new(8, 8)
  # grid.block(3, 3)
  # grid[4, 4] = 2 # mud, twice as expensive as the default cost of 1
  # path = Pathfinding.a_star(grid, {0, 0}, {7, 7}).path
  # ```
  class CostGrid
    getter width : Int32
    getter height : Int32
    getter costs : Array(Float64)

    # Creates a *width* by *height* grid filled with *default_cost*.
    def initialize(@width : Int32, @height : Int32, default_cost : Number = 1)
      raise ArgumentError.new("grid dimensions must be positive") if @width <= 0 || @height <= 0
      @costs = Array(Float64).new(@width * @height, default_cost.to_f64)
    end

    # True when `(x, y)` sits inside the grid.
    def in_bounds?(x : Int, y : Int) : Bool
      x >= 0 && y >= 0 && x < @width && y < @height
    end

    # Movement cost of a cell, or infinity when it is out of bounds.
    def [](x : Int, y : Int) : Float64
      in_bounds?(x, y) ? @costs[y * @width + x] : Float64::INFINITY
    end

    # Sets a positive movement cost. Use `block` for walls.
    def []=(x : Int, y : Int, cost : Number) : Nil
      raise IndexError.new unless in_bounds?(x, y)
      raise ArgumentError.new("cost must be positive") unless cost > 0
      @costs[y * @width + x] = cost.to_f64
    end

    # Marks a cell impassable.
    def block(x : Int, y : Int) : Nil
      @costs[y * @width + x] = Float64::INFINITY
    end

    # True when the cell can be entered.
    def passable?(x : Int, y : Int) : Bool
      self[x, y].finite?
    end
  end

  # Deterministic A*, Dijkstra and flow-field searches for grids and arbitrary graphs.
  #
  # Grid searches take a `CostGrid`. Graph searches take a hash of node to
  # `{neighbor, cost}` pairs. Flow fields precompute "step toward the goal" for every
  # reachable cell, which is cheaper than a fresh A* when many units share a destination.
  #
  # ```
  # grid = CostGrid.new(8, 8)
  # grid.block(3, 3)
  # result = Pathfinding.a_star(grid, {0, 0}, {7, 7})
  # result.found?           # true when a path exists
  # result.path             # includes start and goal
  # field = Pathfinding.flow_field(grid, {7, 7})
  # field.next_step({0, 0}) # the neighbour that decreases cost-to-go
  # ```
  module Pathfinding
    alias Point = Grid::Point

    # Result of a successful or failed search. `found?` is true when `path` is not empty.
    record Result(T), path : Array(T), cost : Float64, visited : Int32 do
      def found? : Bool
        !path.empty?
      end
    end

    # Finds a least-cost grid path, including start and goal. Diagonal motion costs
    # sqrt(2), and can be forbidden from squeezing between two blocked cells.
    def self.a_star(grid : CostGrid, start : Point, goal : Point, diagonal = false,
                    no_corner_cutting = true) : Result(Point)
      search_grid(grid, start, goal, diagonal, no_corner_cutting, true)
    end

    # Dijkstra is A* without a heuristic; useful when movement costs dominate distance.
    def self.dijkstra(grid : CostGrid, start : Point, goal : Point, diagonal = false) : Result(Point)
      search_grid(grid, start, goal, diagonal, true, false)
    end

    private def self.search_grid(grid, start, goal, diagonal, no_corner_cutting, heuristic)
      unless grid.passable?(start[0], start[1]) && grid.passable?(goal[0], goal[1])
        return Result(Point).new(Array(Point).new, Float64::INFINITY, 0)
      end
      frontier = [start]
      came_from = {} of Point => Point
      distance = {start => 0.0}
      visited = 0
      until frontier.empty?
        current_index = frontier.each_index.min_by do |i|
          point = frontier[i]
          distance[point] + (heuristic ? grid_heuristic(point, goal, diagonal) : 0.0)
        end
        current = frontier.delete_at(current_index)
        visited += 1
        break if current == goal
        cx, cy = current
        (diagonal ? Grid::OCTILE : Grid::CARDINAL).each do |(dx, dy)|
          nx = cx + dx
          ny = cy + dy
          next unless grid.passable?(nx, ny)
          if dx != 0 && dy != 0 && no_corner_cutting
            next unless grid.passable?(cx + dx, cy) && grid.passable?(cx, cy + dy)
          end
          candidate = {nx, ny}
          step = grid[nx, ny] * (dx != 0 && dy != 0 ? Math.sqrt(2.0) : 1.0)
          new_distance = distance[current] + step
          next if distance[candidate]?.try { |old| old <= new_distance }
          distance[candidate] = new_distance
          came_from[candidate] = current
          frontier << candidate unless frontier.includes?(candidate)
        end
      end
      build_result(start, goal, came_from, distance, visited)
    end

    private def self.grid_heuristic(a : Point, b : Point, diagonal : Bool) : Float64
      dx = (a[0] - b[0]).abs.to_f64
      dy = (a[1] - b[1]).abs.to_f64
      diagonal ? dx + dy + (Math.sqrt(2.0) - 2.0) * Math.min(dx, dy) : dx + dy
    end

    # Graph A*. Each adjacency entry is `{neighbor, nonnegative_cost}`.
    def self.a_star(graph : Hash(T, Array({T, Float64})), start : T, goal : T,
                    heuristic : Proc(T, T, Float64) = ->(_a : T, _b : T) { 0.0 }) : Result(T) forall T
      frontier = [start]
      came_from = {} of T => T
      distance = {start => 0.0}
      visited = 0
      until frontier.empty?
        index = frontier.each_index.min_by { |i| distance[frontier[i]] + heuristic.call(frontier[i], goal) }
        current = frontier.delete_at(index)
        visited += 1
        break if current == goal
        (graph[current]? || [] of {T, Float64}).each do |(neighbor, cost)|
          raise ArgumentError.new("edge costs cannot be negative") if cost < 0
          candidate = distance[current] + cost
          next if distance[neighbor]?.try { |old| old <= candidate }
          distance[neighbor] = candidate
          came_from[neighbor] = current
          frontier << neighbor unless frontier.includes?(neighbor)
        end
      end
      build_result(start, goal, came_from, distance, visited)
    end

    # Dijkstra on an arbitrary graph.
    def self.dijkstra(graph : Hash(T, Array({T, Float64})), start : T, goal : T) : Result(T) forall T
      a_star(graph, start, goal)
    end

    private def self.build_result(start : T, goal : T, came_from : Hash(T, T),
                                  distance : Hash(T, Float64), visited : Int32) : Result(T) forall T
      return Result(T).new([start], 0.0, visited) if start == goal
      return Result(T).new(Array(T).new, Float64::INFINITY, visited) unless distance.has_key?(goal)
      path = [goal]
      until path.last == start
        path << came_from[path.last]
      end
      path.reverse!
      Result(T).new(path, distance[goal], visited)
    end

    # Removes unnecessary waypoints wherever *clear* reports direct line of sight.
    def self.smooth(path : Array(T), &clear : T, T -> Bool) : Array(T) forall T
      return path.dup if path.size < 3
      result = [path.first]
      anchor = 0
      while anchor < path.size - 1
        furthest = path.size - 1
        while furthest > anchor + 1 && !clear.call(path[anchor], path[furthest])
          furthest -= 1
        end
        result << path[furthest]
        anchor = furthest
      end
      result
    end

    # Cost-to-go and best-next-cell maps for moving many units toward one destination.
    record FlowField, goal : Point, distances : Hash(Point, Float64), directions : Hash(Point, Point) do
      # The neighbour a unit at *from* should step into, or `nil`.
      def next_step(from : Point) : Point?
        directions[from]?
      end

      # True when a unit at *from* can reach the goal.
      def reachable?(from : Point) : Bool
        distances.has_key?(from)
      end
    end

    # Dijkstra search from *goal* over the whole grid, then a best-next-cell map.
    def self.flow_field(grid : CostGrid, goal : Point, diagonal = false) : FlowField
      distance = {goal => 0.0}
      frontier = [goal]
      until frontier.empty?
        index = frontier.each_index.min_by { |i| distance[frontier[i]] }
        current = frontier.delete_at(index)
        cx, cy = current
        (diagonal ? Grid::OCTILE : Grid::CARDINAL).each do |(dx, dy)|
          neighbor = {cx + dx, cy + dy}
          next unless grid.passable?(neighbor[0], neighbor[1])
          candidate = distance[current] + grid[cx, cy] * (dx != 0 && dy != 0 ? Math.sqrt(2.0) : 1.0)
          next if distance[neighbor]?.try { |old| old <= candidate }
          distance[neighbor] = candidate
          frontier << neighbor unless frontier.includes?(neighbor)
        end
      end
      directions = {} of Point => Point
      distance.each_key do |point|
        next if point == goal
        x, y = point
        choices = (diagonal ? Grid::OCTILE : Grid::CARDINAL).map { |(dx, dy)| {x + dx, y + dy} }
        if next_point = choices.select { |candidate| distance.has_key?(candidate) }.min_by? { |candidate| distance[candidate] }
          directions[point] = next_point
        end
      end
      FlowField.new(goal, distance, directions)
    end
  end
end
