module Eagle
  # A grid of tiles drawn from a tileset texture. Cells hold a tile id
  # (index into the tileset grid, row-major) or -1 for empty.
  #
  #   map = TileMap.new(tileset_texture, 16, 16)
  #   map.set_cell(3, 4, 7)
  #   map.load_layout("0 0 1\n2 3 3")   # rows of ids
  class TileMap < Node2D
    getter tileset : Texture
    getter tile_width : Int32
    getter tile_height : Int32
    getter width : Int32 = 0
    getter height : Int32 = 0
    property color : Color = Color::WHITE
    @cells = {} of {Int32, Int32} => Int32
    @regions : Array(TextureRegion)
    @columns : Int32

    def initialize(@tileset : Texture, @tile_width : Int32, @tile_height : Int32, name : String = "", spacing : Int32 = 0)
      super(name)
      @columns = Math.max(1, (@tileset.width + spacing) // (@tile_width + spacing))
      rows = Math.max(1, (@tileset.height + spacing) // (@tile_height + spacing))
      @regions = Array(TextureRegion).new(@columns * rows) do |i|
        @tileset.region((i % @columns) * (@tile_width + spacing), (i // @columns) * (@tile_height + spacing), @tile_width, @tile_height)
      end
    end

    def tile_count : Int32; @regions.size; end
    def tile_size : Vec2; Vec2.new(@tile_width, @tile_height); end

    def set_cell(x : Int32, y : Int32, id : Int32) : Nil
      if id < 0
        @cells.delete({x, y})
      else
        @cells[{x, y}] = id
        @width = Math.max(@width, x + 1)
        @height = Math.max(@height, y + 1)
      end
    end

    def get_cell(x : Int32, y : Int32) : Int32
      @cells[{x, y}]? || -1
    end

    def []=(x : Int32, y : Int32, id : Int32); set_cell(x, y, id); end
    def [](x : Int32, y : Int32) : Int32; get_cell(x, y); end
    def clear : Nil; @cells.clear; @width = @height = 0; end
    def used_cells : Array({Int32, Int32}); @cells.keys; end
    def cell_count : Int32; @cells.size; end

    # Load rows of whitespace-separated ids ('.' or negative = empty).
    def load_layout(text : String) : self
      text.each_line.with_index do |line, y|
        line.split.each_with_index do |tok, x|
          next if tok == "."
          set_cell(x, y, tok.to_i)
        end
      end
      self
    end

    # Convert between local coordinates and cell indices.
    def world_to_cell(global : Vec2) : {Int32, Int32}
      l = to_local(global)
      {(l.x / @tile_width).floor.to_i, (l.y / @tile_height).floor.to_i}
    end

    def cell_to_world(x : Int32, y : Int32) : Vec2
      to_global(Vec2.new(x * @tile_width, y * @tile_height))
    end

    def cell_rect(x : Int32, y : Int32) : Rect
      Rect.new(x * @tile_width, y * @tile_height, @tile_width, @tile_height)
    end

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
