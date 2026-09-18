module Eagle
  # Point quadtree for broad-phase queries in a bounded 2D world. Insert points, then
  # ask which values sit in a rectangle or a circle. Use it for "units near the player"
  # without scanning every entity.
  #
  # ```
  # tree = Quadtree(String).new(Rect.new(0, 0, 200, 200))
  # tree.insert("orc", v2(40, 60))
  # tree.insert("chest", v2(150, 20))
  # tree.query_circle(v2(40, 60), 30) # => ["orc"]
  # ```
  class Quadtree(T)
    record Entry(T), value : T, position : Vec2

    getter bounds : Rect
    getter size : Int32

    def initialize(@bounds : Rect, @capacity = 8, @max_depth = 8, @depth = 0)
      raise ArgumentError.new("capacity must be positive") if @capacity <= 0
      @entries = [] of Entry(T)
      @children = nil.as(Array(Quadtree(T))?)
      @size = 0
    end

    # Inserts *value* at *position*. Returns false when the point is outside the tree.
    def insert(value : T, position : Vec2) : Bool
      return false unless @bounds.contains?(position)
      @size += 1
      insert_entry(Entry(T).new(value, position))
      true
    end

    def clear : Nil
      @entries.clear
      @children = nil
      @size = 0
    end

    # Every value whose position sits inside *area*.
    def query(area : Rect) : Array(T)
      found = [] of T
      query(area, found)
      found
    end

    def query(area : Rect, found : Array(T)) : Nil
      return unless @bounds.intersects?(area)
      @entries.each { |entry| found << entry.value if area.contains?(entry.position) }
      @children.try(&.each { |child| child.query(area, found) })
    end

    def query_circle(center : Vec2, radius : Number) : Array(T)
      found = [] of T
      radius_f = radius.to_f32
      query_circle(center, radius_f * radius_f, Rect.centered(center, Vec2.new(radius_f * 2)), found)
      found
    end

    # Recursive overload used internally; exposed so child nodes can share the result buffer.
    def query_circle(center : Vec2, radius_sq : Float32, area : Rect, found : Array(T)) : Nil
      return unless @bounds.intersects?(area)
      @entries.each { |entry| found << entry.value if entry.position.distance_squared(center) <= radius_sq }
      @children.try(&.each { |child| child.query_circle(center, radius_sq, area, found) })
    end

    private def insert_entry(entry : Entry(T)) : Nil
      if children = @children
        if child = children.find { |candidate| candidate.bounds.contains?(entry.position) }
          child.insert(entry.value, entry.position)
          return
        end
      end
      @entries << entry
      subdivide if @entries.size > @capacity && @depth < @max_depth
    end

    private def subdivide : Nil
      return if @children
      half = @bounds.size / 2
      x = @bounds.x
      y = @bounds.y
      @children = [
        Quadtree(T).new(Rect.new(x, y, half.x, half.y), @capacity, @max_depth, @depth + 1),
        Quadtree(T).new(Rect.new(x + half.x, y, half.x, half.y), @capacity, @max_depth, @depth + 1),
        Quadtree(T).new(Rect.new(x, y + half.y, half.x, half.y), @capacity, @max_depth, @depth + 1),
        Quadtree(T).new(Rect.new(x + half.x, y + half.y, half.x, half.y), @capacity, @max_depth, @depth + 1),
      ]
      old = @entries
      @entries = [] of Entry(T)
      old.each { |entry| insert_entry(entry) }
    end
  end

  # Unbounded uniform spatial hash for dynamic 2D point objects. Prefer this over a
  # quadtree when objects move every frame: `move` is a remove plus an insert.
  #
  # ```
  # hash = SpatialHash(Int32).new(32)
  # hash.insert(1, v2(10, 10))
  # hash.query(v2(12, 8), 20) # => [1]
  # hash.move(1, v2(80, 10))
  # ```
  class SpatialHash(T)
    record Entry(T), value : T, position : Vec2
    getter cell_size : Float32

    def initialize(cell_size : Number)
      @cell_size = cell_size.to_f32
      raise ArgumentError.new("cell size must be positive") unless @cell_size > 0
      @cells = Hash({Int32, Int32}, Array(Entry(T))).new { |hash, key| hash[key] = [] of Entry(T) }
    end

    def insert(value : T, position : Vec2) : Nil
      @cells[cell(position)] << Entry(T).new(value, position)
    end

    def clear : Nil
      @cells.clear
    end

    def remove(value : T) : Bool
      @cells.each_value do |entries|
        if index = entries.index { |entry| entry.value == value }
          entries.delete_at(index)
          return true
        end
      end
      false
    end

    def move(value : T, position : Vec2) : Nil
      remove(value); insert(value, position)
    end

    def query(center : Vec2, radius : Number) : Array(T)
      radius_f = radius.to_f32
      min = cell(center - Vec2.new(radius_f))
      max = cell(center + Vec2.new(radius_f))
      radius_sq = radius_f * radius_f
      found = [] of T
      (min[1]..max[1]).each do |y|
        (min[0]..max[0]).each do |x|
          (@cells[{x, y}]? || [] of Entry(T)).each do |entry|
            found << entry.value if entry.position.distance_squared(center) <= radius_sq
          end
        end
      end
      found
    end

    private def cell(position : Vec2) : {Int32, Int32}
      {(position.x / @cell_size).floor.to_i, (position.y / @cell_size).floor.to_i}
    end
  end

  # Unbounded uniform 3D spatial grid for proximity queries.
  class SpatialHash3D(T)
    record Entry(T), value : T, position : Vec3
    getter cell_size : Float32

    def initialize(cell_size : Number)
      @cell_size = cell_size.to_f32
      raise ArgumentError.new("cell size must be positive") unless @cell_size > 0
      @cells = Hash({Int32, Int32, Int32}, Array(Entry(T))).new { |hash, key| hash[key] = [] of Entry(T) }
    end

    def insert(value : T, position : Vec3) : Nil
      @cells[cell(position)] << Entry(T).new(value, position)
    end

    def clear : Nil
      @cells.clear
    end

    def remove(value : T) : Bool
      @cells.each_value do |entries|
        if index = entries.index { |entry| entry.value == value }
          entries.delete_at(index)
          return true
        end
      end
      false
    end

    def move(value : T, position : Vec3) : Nil
      remove(value); insert(value, position)
    end

    def query(center : Vec3, radius : Number) : Array(T)
      radius_f = radius.to_f32
      min = cell(center - Vec3.new(radius_f))
      max = cell(center + Vec3.new(radius_f))
      radius_sq = radius_f * radius_f
      found = [] of T
      (min[2]..max[2]).each do |z|
        (min[1]..max[1]).each do |y|
          (min[0]..max[0]).each do |x|
            (@cells[{x, y, z}]? || [] of Entry(T)).each do |entry|
              found << entry.value if entry.position.distance_squared(center) <= radius_sq
            end
          end
        end
      end
      found
    end

    private def cell(position : Vec3) : {Int32, Int32, Int32}
      {(position.x / @cell_size).floor.to_i, (position.y / @cell_size).floor.to_i,
       (position.z / @cell_size).floor.to_i}
    end
  end
end
