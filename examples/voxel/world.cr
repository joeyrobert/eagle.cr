require "../../src/eagle"

# Renderer-independent voxel island: noise terrain, greedy meshing, DDA picking and AABB
# walking. Specs drive this file without opening a window.
module EagleVoxel
  include Eagle

  # Palette index 0 is air. The rest are solid, coloured blocks the player can place.
  PALETTE = [
    Color.new(0, 0, 0, 0),
    Color.hex("#5d9b3e"), # grass
    Color.hex("#8a5a32"), # dirt
    Color.hex("#8d8d8d"), # stone
    Color.hex("#e2c56e"), # sand
    Color.hex("#6b3f22"), # wood
    Color.hex("#3b7cc4"), # water
    Color.hex("#b34335"), # brick
    Color.hex("#d4a017"), # gold
    Color.hex("#eef2f6"), # snow
    Color.hex("#2a2a2a"), # coal
    Color.hex("#c44bb0"), # magenta
    Color.hex("#3ecfcf"), # cyan
    Color.hex("#e07a2f"), # orange
    Color.hex("#f4f0e6"), # white
    Color.hex("#2f6b32"), # pine
    Color.hex("#c27a6a"), # clay
  ]

  NAMES = [
    "Air", "Grass", "Dirt", "Stone", "Sand", "Wood", "Water", "Brick",
    "Gold", "Snow", "Coal", "Magenta", "Cyan", "Orange", "White", "Pine", "Clay",
  ]

  GRASS   = 1_u8
  DIRT    = 2_u8
  STONE   = 3_u8
  SAND    = 4_u8
  WOOD    = 5_u8
  WATER   = 6_u8
  BRICK   = 7_u8

  record Hit, x : Int32, y : Int32, z : Int32, nx : Int32, ny : Int32, nz : Int32, distance : Float32 do
    def voxel : {Int32, Int32, Int32}; {x, y, z}; end
    def place : {Int32, Int32, Int32}; {x + nx, y + ny, z + nz}; end
  end

  class Island
    WIDTH  = 48
    HEIGHT = 36
    DEPTH  = 48
    VOLUME = WIDTH * HEIGHT * DEPTH

    getter seed : Int32
    getter cells : Slice(UInt8)
    getter mesh_triangles = 0
    getter mesh_quads = 0

    def initialize(@seed : Int32 = 2026)
      @cells = Slice(UInt8).new(VOLUME, 0_u8)
      generate
    end

    def self.index(x : Int32, y : Int32, z : Int32) : Int32
      x + WIDTH * (z + DEPTH * y)
    end

    def in_bounds?(x : Int, y : Int, z : Int) : Bool
      x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT && z >= 0 && z < DEPTH
    end

    def [](x : Int, y : Int, z : Int) : UInt8
      in_bounds?(x, y, z) ? @cells[Island.index(x.to_i, y.to_i, z.to_i)] : 0_u8
    end

    def []=(x : Int, y : Int, z : Int, kind : UInt8) : Nil
      @cells[Island.index(x.to_i, y.to_i, z.to_i)] = kind if in_bounds?(x, y, z)
    end

    def solid?(x : Int, y : Int, z : Int) : Bool
      self[x, y, z] != 0
    end

    def occupied : Int32
      n = 0
      @cells.each { |c| n += 1 if c != 0 }
      n
    end

    def generate : Nil
      @cells.fill(0_u8)
      noise = Noise.new(@seed)
      cx = (WIDTH - 1) * 0.5
      cz = (DEPTH - 1) * 0.5
      radius = WIDTH * 0.42
      WIDTH.times do |x|
        DEPTH.times do |z|
          dx = (x - cx) / radius
          dz = (z - cz) / radius
          dist = Math.hypot(dx, dz)
          next if dist >= 1
          mask = (1 - dist) * (1 - dist)
          hills = 0.5 + 0.5 * noise.fbm(x * 0.07, z * 0.07, octaves: 5)
          ridge = noise.ridged(x * 0.05, z * 0.05, octaves: 3)
          peak = 6 + 16 * hills * mask + 5 * ridge * mask
          top = Mathf.clamp(10 + peak, 1, HEIGHT - 2).to_i
          bottom = Mathf.clamp(8 - 7 * mask, 1, top - 3).to_i
          bottom.upto(top) do |y|
            cave = noise.perlin(x * 0.11, y * 0.13, z * 0.11)
            next if cave > 0.48 && y > bottom + 2 && y < top - 2
            kind = if y == top
                     top <= 14 ? SAND : GRASS
                   elsif y > top - 3
                     DIRT
                   else
                     STONE
                   end
            self[x, y, z] = kind
          end
        end
      end
    end

    # A 4x4 swatch of every placeable colour, for screenshots and as a nearby sample.
    def stamp_palette(origin_x : Int32, origin_y : Int32, origin_z : Int32) : Nil
      (1...PALETTE.size).each do |i|
        px = origin_x + (i - 1) % 4
        pz = origin_z + (i - 1) // 4
        self[px, origin_y - 1, pz] = STONE if self[px, origin_y - 1, pz] == 0
        self[px, origin_y, pz] = i.to_u8
      end
    end

    def spawn : Vec3
      cx = WIDTH // 2
      cz = DEPTH // 2
      best = {cx, 8, cz}
      best_y = -1
      (cx - 6).upto(cx + 6) do |x|
        (cz - 6).upto(cz + 6) do |z|
          y = HEIGHT - 1
          while y >= 0 && !solid?(x, y, z)
            y -= 1
          end
          next if y < 1
          next unless !solid?(x, y + 1, z) && !solid?(x, y + 2, z)
          if y > best_y
            best_y = y
            best = {x, y, z}
          end
        end
      end
      feet = Vec3.new(best[0] + 0.5, best[1] + 1.01, best[2] + 0.5)
      8.times do
        break unless blocked?(Vec3.new(feet.x - 0.28, feet.y, feet.z - 0.28), Vec3.new(feet.x + 0.28, feet.y + 1.7, feet.z + 0.28))
        feet = Vec3.new(feet.x, feet.y + 1, feet.z)
      end
      feet
    end

    def overlook : {Vec3, Int32}
      x = WIDTH // 2
      z = 12
      y = 8
      yy = HEIGHT - 1
      while yy >= 0 && !solid?(x, yy, z)
        yy -= 1
      end
      y = yy if yy >= 1
      {Vec3.new(x + 0.5, y + 1.05, z + 0.5), y}
    end

    def center : Vec3
      Vec3.new(WIDTH * 0.5, HEIGHT * 0.35, DEPTH * 0.5)
    end

    def raycast(origin : Vec3, direction : Vec3, max_distance : Number = 8) : Hit?
      dir = direction.normalized
      return nil if dir.length_squared < 1e-10
      max = max_distance.to_f32
      x = origin.x.floor.to_i
      y = origin.y.floor.to_i
      z = origin.z.floor.to_i
      step_x = dir.x >= 0 ? 1 : -1
      step_y = dir.y >= 0 ? 1 : -1
      step_z = dir.z >= 0 ? 1 : -1
      t_delta_x = dir.x.abs < 1e-8 ? Float32::MAX : (1 / dir.x.abs).to_f32
      t_delta_y = dir.y.abs < 1e-8 ? Float32::MAX : (1 / dir.y.abs).to_f32
      t_delta_z = dir.z.abs < 1e-8 ? Float32::MAX : (1 / dir.z.abs).to_f32
      t_max_x = dir.x.abs < 1e-8 ? Float32::MAX : (((dir.x >= 0 ? x + 1 : x) - origin.x) / dir.x).to_f32
      t_max_y = dir.y.abs < 1e-8 ? Float32::MAX : (((dir.y >= 0 ? y + 1 : y) - origin.y) / dir.y).to_f32
      t_max_z = dir.z.abs < 1e-8 ? Float32::MAX : (((dir.z >= 0 ? z + 1 : z) - origin.z) / dir.z).to_f32
      nx = 0
      ny = 0
      nz = 0
      t = 0_f32
      96.times do
        if t > max
          return nil
        end
        if t > 1e-4 && solid?(x, y, z)
          return Hit.new(x, y, z, nx, ny, nz, t)
        end
        if t_max_x < t_max_y && t_max_x < t_max_z
          t = t_max_x
          t_max_x += t_delta_x
          x += step_x
          nx = -step_x
          ny = 0
          nz = 0
        elsif t_max_y < t_max_z
          t = t_max_y
          t_max_y += t_delta_y
          y += step_y
          nx = 0
          ny = -step_y
          nz = 0
        else
          t = t_max_z
          t_max_z += t_delta_z
          z += step_z
          nx = 0
          ny = 0
          nz = -step_z
        end
      end
      nil
    end

    def break_at(hit : Hit) : UInt8
      kind = self[hit.x, hit.y, hit.z]
      self[hit.x, hit.y, hit.z] = 0_u8
      kind
    end

    def place_at(hit : Hit, kind : UInt8, feet : Vec3, radius : Number, height : Number) : Bool
      return false if kind == 0
      x, y, z = hit.place
      return false unless in_bounds?(x, y, z) && self[x, y, z] == 0
      return false if overlaps_player?(x, y, z, feet, radius, height)
      self[x, y, z] = kind
      true
    end

    def overlaps_player?(x : Int, y : Int, z : Int, feet : Vec3, radius : Number, height : Number) : Bool
      r = radius.to_f32
      h = height.to_f32
      px0 = feet.x - r
      px1 = feet.x + r
      py0 = feet.y
      py1 = feet.y + h
      pz0 = feet.z - r
      pz1 = feet.z + r
      bx0 = x.to_f32
      bx1 = x + 1_f32
      by0 = y.to_f32
      by1 = y + 1_f32
      bz0 = z.to_f32
      bz1 = z + 1_f32
      px0 < bx1 && px1 > bx0 && py0 < by1 && py1 > by0 && pz0 < bz1 && pz1 > bz0
    end

    def blocked?(min : Vec3, max : Vec3) : Bool
      x0 = min.x.floor.to_i
      y0 = min.y.floor.to_i
      z0 = min.z.floor.to_i
      x1 = (max.x - 1e-4).floor.to_i
      y1 = (max.y - 1e-4).floor.to_i
      z1 = (max.z - 1e-4).floor.to_i
      x0.upto(x1) do |x|
        y0.upto(y1) do |y|
          z0.upto(z1) do |z|
            return true if solid?(x, y, z)
          end
        end
      end
      false
    end

    # Minecraft-style AABB: move X, then Z, then Y against the occupancy grid.
    def move(feet : Vec3, velocity : Vec3, dt : Float32, radius : Number, height : Number) : {Vec3, Vec3, Bool}
      r = radius.to_f32
      h = height.to_f32
      pos = feet
      vel = velocity
      on_ground = false

      pos = Vec3.new(pos.x + vel.x * dt, pos.y, pos.z)
      if blocked?(Vec3.new(pos.x - r, pos.y, pos.z - r), Vec3.new(pos.x + r, pos.y + h, pos.z + r))
        pos = Vec3.new(pos.x - vel.x * dt, pos.y, pos.z)
        vel = Vec3.new(0, vel.y, vel.z)
      end

      pos = Vec3.new(pos.x, pos.y, pos.z + vel.z * dt)
      if blocked?(Vec3.new(pos.x - r, pos.y, pos.z - r), Vec3.new(pos.x + r, pos.y + h, pos.z + r))
        pos = Vec3.new(pos.x, pos.y, pos.z - vel.z * dt)
        vel = Vec3.new(vel.x, vel.y, 0)
      end

      pos = Vec3.new(pos.x, pos.y + vel.y * dt, pos.z)
      if blocked?(Vec3.new(pos.x - r, pos.y, pos.z - r), Vec3.new(pos.x + r, pos.y + h, pos.z + r))
        if vel.y < 0
          on_ground = true
        end
        pos = Vec3.new(pos.x, pos.y - vel.y * dt, pos.z)
        vel = Vec3.new(vel.x, 0, vel.z)
      end

      {pos, vel, on_ground}
    end

    # Greedy mesh: merge coplanar same-colour faces into quads. Vertex colours carry the palette.
    def build_mesh(into : Mesh? = nil) : Mesh
      mesh = into || Mesh.new("island")
      mesh.clear
      quads = 0
      dims = {WIDTH, HEIGHT, DEPTH}
      3.times do |d|
        u = (d + 1) % 3
        v = (d + 2) % 3
        x = [0, 0, 0]
        q = [0, 0, 0]
        q[d] = 1
        mask = Slice(Int32).new(dims[u] * dims[v], 0)
        x[d] = -1
        while x[d] < dims[d]
          n = 0
          x[v] = 0
          while x[v] < dims[v]
            x[u] = 0
            while x[u] < dims[u]
              a = x[d] >= 0 ? self[x[0], x[1], x[2]].to_i : 0
              b = x[d] < dims[d] - 1 ? self[x[0] + q[0], x[1] + q[1], x[2] + q[2]].to_i : 0
              mask[n] = if (a != 0) == (b != 0)
                          0
                        elsif a != 0
                          a
                        else
                          -b
                        end
              n += 1
              x[u] += 1
            end
            x[v] += 1
          end
          x[d] += 1
          n = 0
          j = 0
          while j < dims[v]
            i = 0
            while i < dims[u]
              if (c = mask[n]) != 0
                w = 1
                while i + w < dims[u] && mask[n + w] == c
                  w += 1
                end
                h = 1
                done = false
                while j + h < dims[v]
                  k = 0
                  while k < w
                    if mask[n + k + h * dims[u]] != c
                      done = true
                      break
                    end
                    k += 1
                  end
                  break if done
                  h += 1
                end
                x[u] = i
                x[v] = j
                du = [0, 0, 0]
                dv = [0, 0, 0]
                if c > 0
                  du[u] = w
                  dv[v] = h
                else
                  du[v] = h
                  dv[u] = w
                end
                p0 = Vec3.new(x[0].to_f32, x[1].to_f32, x[2].to_f32)
                p1 = Vec3.new((x[0] + du[0]).to_f32, (x[1] + du[1]).to_f32, (x[2] + du[2]).to_f32)
                p2 = Vec3.new((x[0] + du[0] + dv[0]).to_f32, (x[1] + du[1] + dv[1]).to_f32, (x[2] + du[2] + dv[2]).to_f32)
                p3 = Vec3.new((x[0] + dv[0]).to_f32, (x[1] + dv[1]).to_f32, (x[2] + dv[2]).to_f32)
                kind = c.abs
                color = PALETTE[kind]
                normal = if c > 0
                           Vec3.new(q[0].to_f32, q[1].to_f32, q[2].to_f32)
                         else
                           Vec3.new(-q[0].to_f32, -q[1].to_f32, -q[2].to_f32)
                         end
                add_face(mesh, p0, p1, p2, p3, normal, color)
                quads += 1
                h.times do |ly|
                  w.times do |lx|
                    mask[n + lx + ly * dims[u]] = 0
                  end
                end
                i += w
                n += w
              else
                i += 1
                n += 1
              end
            end
            j += 1
          end
        end
      end
      @mesh_quads = quads
      @mesh_triangles = quads * 2
      mesh
    end

    private def add_face(mesh : Mesh, a : Vec3, b : Vec3, c : Vec3, d : Vec3, normal : Vec3, color : Color) : Nil
      ia = mesh.add_vertex(a, normal, Vec2::ZERO, color)
      ib = mesh.add_vertex(b, normal, Vec2.new(1, 0), color)
      ic = mesh.add_vertex(c, normal, Vec2::ONE, color)
      id = mesh.add_vertex(d, normal, Vec2.new(0, 1), color)
      mesh.add_quad(ia, ib, ic, id)
    end
  end
end
