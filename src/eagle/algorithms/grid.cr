module Eagle
  # Integer-grid algorithms shared by tile maps, tactics games and roguelikes.
  #
  # Coordinates are `{x, y}` tuples. Pass an opacity callback for line of sight and
  # field of view; report cells outside your map as opaque so rays stop at the edge.
  #
  # ```
  # walls = Set{ {3, 2} }
  # seen = Grid.field_of_view({2, 2}, 8) { |x, y| walls.includes?({x, y}) || !x.in?(0...10) || !y.in?(0...10) }
  # Grid.line({0, 0}, {4, 2}) # every cell the line touches
  # ```
  module Grid
    alias Point = {Int32, Int32}

    # Four orthogonal neighbours: east, west, south, north.
    CARDINAL = [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]
    # Cardinal neighbours plus the four diagonals.
    OCTILE   = CARDINAL + [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

    # Every cell touched by the line from *from* to *to*, including both ends.
    def self.line(from : Point, to : Point) : Array(Point)
      x0, y0 = from
      x1, y1 = to
      dx = (x1 - x0).abs
      sx = x0 < x1 ? 1 : -1
      dy = -(y1 - y0).abs
      sy = y0 < y1 ? 1 : -1
      error = dx + dy
      cells = [] of Point
      loop do
        cells << {x0, y0}
        break if x0 == x1 && y0 == y1
        twice = 2 * error
        if twice >= dy
          error += dy
          x0 += sx
        end
        if twice <= dx
          error += dx
          y0 += sy
        end
      end
      cells
    end

    # Whether all cells between the endpoints are transparent. The endpoints can be
    # ignored independently, which is useful when an opaque wall is the target.
    def self.line_of_sight?(from : Point, to : Point, ignore_from = true, ignore_to = false,
                            &opaque : Int32, Int32 -> Bool) : Bool
      cells = line(from, to)
      cells.each_with_index do |(x, y), i|
        next if ignore_from && i == 0
        next if ignore_to && i == cells.size - 1
        return false if opaque.call(x, y)
      end
      true
    end

    # All cells reachable through cardinal neighbours. *limit* guards accidental
    # searches over unbounded procedural worlds.
    def self.flood_fill(start : Point, limit = 1_000_000, &passable : Int32, Int32 -> Bool) : Set(Point)
      found = Set(Point).new
      queue = Deque(Point).new
      queue << start if passable.call(start[0], start[1])
      while point = queue.shift?
        next if found.includes?(point)
        found << point
        break if found.size >= limit
        x, y = point
        CARDINAL.each do |(dx, dy)|
          candidate = {x + dx, y + dy}
          queue << candidate if !found.includes?(candidate) && passable.call(candidate[0], candidate[1])
        end
      end
      found
    end

    # Symmetric recursive-shadowcasting field of view. Opaque cells are visible but
    # hide cells behind them. Coordinates outside a map should be reported opaque.
    def self.field_of_view(origin : Point, radius : Int, &opaque : Int32, Int32 -> Bool) : Set(Point)
      visible = Set(Point).new
      visible << origin
      8.times { |octant| cast_light(origin, radius.to_i32, 1, 1.0, 0.0, octant, visible, opaque) }
      visible
    end

    private MULT = [
      [1, 0, 0, -1, -1, 0, 0, 1],
      [0, 1, -1, 0, 0, -1, 1, 0],
      [0, 1, 1, 0, 0, -1, -1, 0],
      [1, 0, 0, 1, -1, 0, 0, -1],
    ]

    private def self.cast_light(origin : Point, radius : Int32, row : Int32,
                                start_slope : Float64, end_slope : Float64, octant : Int32,
                                visible : Set(Point), opaque : Int32, Int32 -> Bool) : Nil
      return if start_slope < end_slope
      cx, cy = origin
      xx = MULT[0][octant]
      xy = MULT[1][octant]
      yx = MULT[2][octant]
      yy = MULT[3][octant]
      radius_sq = radius * radius
      (row..radius).each do |distance|
        dx = -distance - 1
        dy = -distance
        blocked = false
        next_start = start_slope
        while dx <= 0
          dx += 1
          x = cx + dx * xx + dy * xy
          y = cy + dx * yx + dy * yy
          left = (dx - 0.5) / (dy + 0.5)
          right = (dx + 0.5) / (dy - 0.5)
          next if start_slope < right
          break if end_slope > left
          visible << {x, y} if dx * dx + dy * dy <= radius_sq
          wall = opaque.call(x, y)
          if blocked
            if wall
              next_start = right
            else
              blocked = false
              start_slope = next_start
            end
          elsif wall && distance < radius
            blocked = true
            cast_light(origin, radius, distance + 1, start_slope, left, octant, visible, opaque)
            next_start = right
          end
        end
        break if blocked
      end
    end
  end

  # Axial hex-grid coordinate, using pointy-top `(q, r)` axes.
  #
  # `s` is the third cube coordinate (`-q - r`), so `q + r + s` is always 0.
  # Distance and neighbours follow the usual cube-hex rules.
  #
  # ```
  # hex = Hex.new(0, 0)
  # hex.neighbors.size              # => 6
  # hex.distance(Hex.new(2, -1))    # => 2
  # Hex.round(0.8, -0.2)            # => Hex.new(1, 0)
  # ```
  struct Hex
    getter q : Int32
    getter r : Int32

    # The six axial neighbour offsets, in counter-clockwise order from east.
    DIRECTIONS = [
      {1, 0}, {1, -1}, {0, -1}, {-1, 0}, {-1, 1}, {0, 1},
    ]

    def initialize(@q : Int32, @r : Int32); end

    # Cube coordinate `s = -q - r`.
    def s : Int32
      -@q - @r
    end

    def +(other : Hex) : Hex
      Hex.new(@q + other.q, @r + other.r)
    end

    def -(other : Hex) : Hex
      Hex.new(@q - other.q, @r - other.r)
    end

    def *(scale : Int) : Hex
      Hex.new(@q * scale, @r * scale)
    end

    # Cube distance, the number of steps to *other*.
    def distance(other : Hex) : Int32
      ((q - other.q).abs + (r - other.r).abs + (s - other.s).abs) // 2
    end

    # Neighbour in *direction* 0..5, wrapping.
    def neighbor(direction : Int) : Hex
      dq, dr = DIRECTIONS[direction % 6]
      Hex.new(@q + dq, @r + dr)
    end

    # The six adjacent hexes, in direction order.
    def neighbors : Array(Hex)
      (0...6).map { |direction| neighbor(direction) }
    end

    # Rounds fractional axial coordinates while preserving `q + r + s == 0`.
    def self.round(q : Number, r : Number) : Hex
      s = -q - r
      rq = q.round.to_i
      rr = r.round.to_i
      rs = s.round.to_i
      q_error = (rq - q).abs
      r_error = (rr - r).abs
      s_error = (rs - s).abs
      if q_error > r_error && q_error > s_error
        rq = -rr - rs
      elsif r_error > s_error
        rr = -rq - rs
      end
      Hex.new(rq, rr)
    end
  end
end
