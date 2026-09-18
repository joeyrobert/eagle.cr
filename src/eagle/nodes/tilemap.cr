module Eagle
  # A grid of tiles drawn from a tileset, for levels, backgrounds and dungeon maps.
  #
  # Each cell holds a tile id, an index into the tileset read left to right and top to
  # bottom, or -1 for empty. Drawing is culled to the camera, so large maps stay cheap.
  #
  # ```
  # tiles = Texture.new(Image.checkerboard(64, 16, 16))
  # map = TileMap.new(tiles, 16, 16)
  # map.load_layout(<<-MAP)
  #   0 0 0 0
  #   1 . . 1
  #   2 2 2 2
  #   MAP
  # map[1, 1] = 3                             # set one cell
  # cx, cy = map.world_to_cell(Input.mouse)   # which tile is under the mouse?
  # solid = map[cx, cy] >= 0
  # ```
  #
  # `TileMap` only draws. For collisions, add `StaticBody2D` boxes for solid cells, as the
  # platformer example does.
  class TileMap < Node2D
    # The texture tiles are cut from.
    getter tileset : Texture
    # Tile width in pixels.
    getter tile_width : Int32
    # Tile height in pixels.
    getter tile_height : Int32
    # Number of columns in use.
    getter width : Int32 = 0
    # Number of rows in use.
    getter height : Int32 = 0
    # Tint applied to every tile.
    property color : Color = Color::WHITE
    @cells = {} of {Int32, Int32} => Int32
    @regions : Array(TextureRegion)
    @columns : Int32

    # Creates a map from a tileset cut into *tile_width* x *tile_height* tiles, with *spacing*
    # pixels between tiles in the texture.
    def initialize(@tileset : Texture, @tile_width : Int32, @tile_height : Int32, name : String = "", spacing : Int32 = 0)
      super(name)
      @columns = Math.max(1, (@tileset.width + spacing) // (@tile_width + spacing))
      rows = Math.max(1, (@tileset.height + spacing) // (@tile_height + spacing))
      @regions = Array(TextureRegion).new(@columns * rows) do |i|
        @tileset.region((i % @columns) * (@tile_width + spacing), (i // @columns) * (@tile_height + spacing), @tile_width, @tile_height)
      end
    end

    # Number of tiles in the tileset.
    def tile_count : Int32; @regions.size; end
    # `(tile_width, tile_height)`.
    def tile_size : Vec2; Vec2.new(@tile_width, @tile_height); end

    # Sets the tile at column *x*, row *y*. Use -1 to clear it.
    def set_cell(x : Int32, y : Int32, id : Int32) : Nil
      if id < 0
        @cells.delete({x, y})
      else
        @cells[{x, y}] = id
        @width = Math.max(@width, x + 1)
        @height = Math.max(@height, y + 1)
      end
    end

    # The tile at column *x*, row *y*, or -1 when empty.
    def get_cell(x : Int32, y : Int32) : Int32
      @cells[{x, y}]? || -1
    end

    # Short form of `set_cell`.
    def []=(x : Int32, y : Int32, id : Int32); set_cell(x, y, id); end
    # Short form of `get_cell`.
    def [](x : Int32, y : Int32) : Int32; get_cell(x, y); end
    # Removes every tile.
    def clear : Nil; @cells.clear; @width = @height = 0; end
    # Coordinates of every non-empty cell.
    def used_cells : Array({Int32, Int32}); @cells.keys; end
    # Number of non-empty cells.
    def cell_count : Int32; @cells.size; end

    # Fills the map from text: one row per line, whitespace-separated tile ids, with `.` or a
    # negative number for empty. Returns self.
    def load_layout(text : String) : self
      text.each_line.with_index do |line, y|
        line.split.each_with_index do |tok, x|
          next if tok == "."
          set_cell(x, y, tok.to_i)
        end
      end
      self
    end

    # The cell containing a world-space point.
    def world_to_cell(global : Vec2) : {Int32, Int32}
      l = to_local(global)
      {(l.x / @tile_width).floor.to_i, (l.y / @tile_height).floor.to_i}
    end

    # The world-space position of a cell's top-left corner.
    def cell_to_world(x : Int32, y : Int32) : Vec2
      to_global(Vec2.new(x * @tile_width, y * @tile_height))
    end

    # A cell's area in local space.
    def cell_rect(x : Int32, y : Int32) : Rect
      Rect.new(x * @tile_width, y * @tile_height, @tile_width, @tile_height)
    end

    # Draws the visible tiles.
    def draw(g : Graphics) : Nil
      c = g.color * @color
      # Cull against the camera when one is active.
      visible : Rect? = nil
      if cam = g.camera
        inv = global_transform.inverse
        b = cam.bounds
        pts = [inv * b.position, inv * Vec2.new(b.right, b.y), inv * b.max, inv * Vec2.new(b.x, b.bottom)]
        mn = pts.reduce { |a, q| a.min(q) }; mx = pts.reduce { |a, q| a.max(q) }
        visible = Rect.from_bounds(mn, mx)
      end
      @cells.each do |(x, y), id|
        next if id < 0 || id >= @regions.size
        px = x * @tile_width; py = y * @tile_height
        if v = visible
          next if px + @tile_width < v.x || px > v.right || py + @tile_height < v.y || py > v.bottom
        end
        g.draw(@regions[id], px, py, 0, 1, 1, 0, 0, c)
      end
    end
  end
end
