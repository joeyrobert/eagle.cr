require "../../src/eagle"

# Joyride world: an infinite, deterministic open world made of square chunks.
# Everything here is plain data (no GPU), so specs can generate and inspect chunks.
#
# Each chunk may hold an intersection ("node") with up to four road "arms" that run to the
# chunk edges. Whether a road crosses an edge, and where along it, is a function of the edge
# alone, so the two chunks that share an edge always agree and roads join seamlessly.
module Joyride
  include Eagle

  CHUNK      = 96_f32
  HALF       = CHUNK / 2
  SIDEWALK   = 3.5_f32
  STREET_HW  = 6.5_f32 # half width of city and town streets
  COUNTRY_HW = 4.2_f32 # half width of country roads
  CURB_H     = 0.2_f32

  # Traffic drives this far right of the center line.
  def self.lane_offset(half_width : Float32) : Float32
    half_width > 5 ? 2.3_f32 : 2.0_f32
  end

  # SplitMix64 finalizer, the basis of every deterministic choice in the world.
  def self.mix(h : UInt64) : UInt64
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9_u64
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB_u64
    h ^ (h >> 31)
  end

  def self.hash(seed : Int64, a : Int32, b : Int32, salt : Int32) : UInt64
    h = mix(seed.to_u64! &+ 0x9E3779B97F4A7C15_u64)
    h = mix(h ^ a.to_i64!.to_u64!)
    h = mix(h ^ (b.to_i64!.to_u64! &* 0x632BE59BD9B4E019_u64))
    mix(h ^ (salt.to_u64! &* 0x85EBCA77C2B2AE63_u64))
  end

  # A number in [0, 1) from a lattice point.
  def self.hash01(seed : Int64, a : Int32, b : Int32, salt : Int32) : Float32
    (hash(seed, a, b, salt) >> 40).to_f32 / (1_u64 << 24).to_f32
  end

  # Small deterministic generator (same results natively and in WebAssembly).
  class Rng
    def initialize(@state : UInt64); end

    def next_u64 : UInt64
      @state = @state &+ 0x9E3779B97F4A7C15_u64
      Joyride.mix(@state)
    end

    # Uniform float in [0, 1).
    def float : Float32
      (next_u64 >> 40).to_f32 / (1_u64 << 24).to_f32
    end

    # Uniform float in [lo, hi).
    def range(lo : Number, hi : Number) : Float32
      (lo + (hi - lo) * float).to_f32
    end

    # Uniform integer in [0, n).
    def int(n : Int32) : Int32
      (next_u64 % n.to_u64).to_i32
    end

    def chance(p : Number) : Bool
      float < p
    end

    def pick(arr : Array(T)) : T forall T
      arr[int(arr.size)]
    end
  end

  enum Zone
    City
    Town
    Country

    def street? : Bool
      !country?
    end
  end

  # The four directions a road can leave a chunk. North is -Z, like `Vec3::FORWARD`.
  enum Dir
    N; E; S; W

    def dx : Int32
      e? ? 1 : w? ? -1 : 0
    end

    def dz : Int32
      s? ? 1 : n? ? -1 : 0
    end

    def vec : Vec2
      Vec2.new(dx, dz)
    end

    def opposite : Dir
      Dir.new((value + 2) % 4)
    end
  end

  # A road from a chunk's node to one of its edges, as a polyline in world coordinates.
  class Arm
    getter dir : Dir
    getter points : Array(Vec2)
    getter half_width : Float32
    getter? street : Bool

    def initialize(@dir, @points, @half_width, @street); end

    def node : Vec2
      @points.first
    end

    def crossing : Vec2
      @points.last
    end

    def length : Float32
      l = 0_f32
      (1...@points.size).each { |i| l += @points[i - 1].distance(@points[i]) }
      l
    end

    def distance_to(p : Vec2) : Float32
      Joyride.polyline_distance(@points, p)
    end
  end

  def self.segment_distance(a : Vec2, b : Vec2, p : Vec2) : Float32
    ab = b - a
    l2 = ab.length_squared
    t = l2 > 0 ? ((p - a).dot(ab) / l2).clamp(0_f32, 1_f32) : 0_f32
    (a + ab * t).distance(p)
  end

  def self.polyline_distance(points : Array(Vec2), p : Vec2) : Float32
    best = Float32::INFINITY
    (1...points.size).each { |i| best = Math.min(best, segment_distance(points[i - 1], points[i], p)) }
    best
  end

  def self.bezier(p0 : Vec2, p1 : Vec2, p2 : Vec2, p3 : Vec2, t : Float32) : Vec2
    u = 1 - t
    p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
  end

  # Something the car can hit: an axis-aligned box or a circle, on the ground plane.
  struct Collider
    getter center : Vec2
    getter half : Vec2
    getter radius : Float32
    getter? circle : Bool

    def initialize(@center, @half, @radius, @circle); end

    def self.box(x0 : Number, z0 : Number, x1 : Number, z1 : Number) : Collider
      new(Vec2.new((x0 + x1) / 2, (z0 + z1) / 2), Vec2.new((x1 - x0).abs / 2, (z1 - z0).abs / 2), 0_f32, false)
    end

    def self.circle(c : Vec2, r : Number) : Collider
      new(c, Vec2.new(r, r), r.to_f32, true)
    end

    # Push-out normal and depth for a circle overlapping this shape, or nil.
    def penetration(p : Vec2, r : Float32) : {Vec2, Float32}?
      if @circle
        d = p - @center
        dist = d.length
        return nil if dist >= r + @radius
        n = dist > 1e-4 ? d / dist : Vec2.new(1, 0)
        {n, r + @radius - dist}
      else
        mn = @center - @half; mx = @center + @half
        if p.x > mn.x && p.x < mx.x && p.y > mn.y && p.y < mx.y
          # center inside the box: leave through the nearest face
          dl = p.x - mn.x; dr = mx.x - p.x; dt = p.y - mn.y; db = mx.y - p.y
          m = {dl, dr, dt, db}.min
          return {Vec2.new(-1, 0), dl + r} if m == dl
          return {Vec2.new(1, 0), dr + r} if m == dr
          return {Vec2.new(0, -1), dt + r} if m == dt
          return {Vec2.new(0, 1), db + r}
        end
        c = Vec2.new(p.x.clamp(mn.x, mx.x), p.y.clamp(mn.y, mx.y))
        d = p - c
        dist = d.length
        return nil if dist >= r
        {d / dist, r - dist}
      end
    end

    # Distance along a ray to this shape, or nil.
    def raycast(o : Vec2, d : Vec2, max : Float32) : Float32?
      if @circle
        oc = o - @center
        b = oc.dot(d); c = oc.length_squared - @radius * @radius
        disc = b * b - c
        return nil if disc < 0
        t = -b - Math.sqrt(disc)
        t = 0_f32 if t < 0 && c < 0
        t >= 0 && t <= max ? t.to_f32 : nil
      else
        mn = @center - @half; mx = @center + @half
        tmin = 0_f32; tmax = max
        {% for a in %w(x y) %}
          if d.{{a.id}}.abs < 1e-6
            return nil if o.{{a.id}} < mn.{{a.id}} || o.{{a.id}} > mx.{{a.id}}
          else
            t1 = (mn.{{a.id}} - o.{{a.id}}) / d.{{a.id}}; t2 = (mx.{{a.id}} - o.{{a.id}}) / d.{{a.id}}
            t1, t2 = t2, t1 if t1 > t2
            tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2)
            return nil if tmin > tmax
          end
        {% end %}
        tmin
      end
    end
  end

  enum BuildingKind
    Office
    Shop
    House
    Barn
    Farmhouse
    Silo
  end

  record Building, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32, height : Float32,
    kind : BuildingKind, color : Color, roof : Color, tier : Float32 = 0_f32 do
    def center : Vec2
      Vec2.new((x0 + x1) / 2, (z0 + z1) / 2)
    end

    def width : Float32
      x1 - x0
    end

    def depth : Float32
      z1 - z0
    end
  end

  enum PropKind
    Tree
    Pine
    Bush
    Lamp
    ParkedCar
    Hill
    Rock
    HayBale
    Bench
  end

  record Prop, kind : PropKind, pos : Vec2, rot : Float32 = 0_f32, scale : Float32 = 1_f32, color : Color = Color::WHITE

  # A flat colored area on the ground (fields, parks, plazas).
  record Patch, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32, color : Color, rows : Int32 = 0, rows_x : Bool = true

  # Raised sidewalk slab.
  record Slab, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32

  # Everything generated for one chunk. Deterministic from the world seed and coordinates.
  class ChunkLayout
    getter cx : Int32
    getter cz : Int32
    getter zone : Zone
    getter density : Float32
    getter node : Vec2?
    getter arms : Array(Arm)
    getter buildings = [] of Building
    getter props = [] of Prop
    getter patches = [] of Patch
    getter slabs = [] of Slab
    getter colliders = [] of Collider
    # Sidewalk segments pedestrians stroll along.
    getter walkways = [] of {Vec2, Vec2}
    getter ground : Color = Color.hex("#6f9a4c")

    def initialize(@cx, @cz, @zone, @density, @node, @arms); end

    def origin : Vec2
      Vec2.new(@cx * CHUNK, @cz * CHUNK)
    end

    def center : Vec2
      origin + Vec2.new(HALF, HALF)
    end

    def arm(d : Dir) : Arm?
      @arms.find { |a| a.dir == d }
    end

    def lamps : Array(Prop)
      @props.select(&.kind.lamp?)
    end

    def ground=(c : Color)
      @ground = c
    end

    def road_distance(p : Vec2) : Float32
      best = Float32::INFINITY
      @arms.each { |a| best = Math.min(best, a.distance_to(p) - a.half_width) }
      best
    end

    def on_road?(p : Vec2, margin : Number = 0) : Bool
      return false if @arms.empty?
      node_hw = @arms.max_of(&.half_width)
      return true if (n = @node) && (p - n).abs.x <= node_hw + margin && (p - n).abs.y <= node_hw + margin
      road_distance(p) <= margin
    end

    def on_sidewalk?(p : Vec2) : Bool
      @slabs.any? { |s| p.x >= s.x0 && p.x <= s.x1 && p.y >= s.z0 && p.y <= s.z1 }
    end

    def contains?(p : Vec2) : Bool
      o = origin
      p.x >= o.x && p.x < o.x + CHUNK && p.y >= o.y && p.y < o.y + CHUNK
    end
  end

  # The infinite world. Chunk layouts are cached; call `evict` for chunks that are far away.
  class World
    getter seed : Int64
    @layouts = {} of {Int32, Int32} => ChunkLayout
    @arms_cache = {} of {Int32, Int32} => Array(Arm)

    def initialize(@seed : Int64 = 1_i64); end

    def self.chunk_of(p : Vec2) : {Int32, Int32}
      {(p.x / CHUNK).floor.to_i, (p.y / CHUNK).floor.to_i}
    end

    # --- zoning ---------------------------------------------------------------

    # City-ness from 0 (open country) to 1 (downtown), continuous over the plane.
    def density_at(p : Vec2) : Float32
      c = 1_f32 - p.length / (CHUNK * 7.5_f32)
      # towns: one candidate per 10x10 chunk super cell
      sx = (p.x / (CHUNK * 10)).floor.to_i; sz = (p.y / (CHUNK * 10)).floor.to_i
      t = 0_f32
      (-1..1).each do |ox|
        (-1..1).each do |oz|
          ax = sx + ox; az = sz + oz
          next if ax == 0 && az == 0
          next unless Joyride.hash01(@seed, ax, az, 11) < 0.7
          tc = Vec2.new((ax * 10 + 2 + Joyride.hash01(@seed, ax, az, 12) * 6) * CHUNK, (az * 10 + 2 + Joyride.hash01(@seed, ax, az, 13) * 6) * CHUNK)
          t = Math.max(t, (1_f32 - p.distance(tc) / (CHUNK * 2.2_f32)) * 0.42_f32)
        end
      end
      n = value_noise(p / (CHUNK * 3), 21) * 0.18_f32 - 0.09_f32
      (Math.max(c, t) + n).clamp(0_f32, 1_f32)
    end

    def density(cx : Int32, cz : Int32) : Float32
      density_at(Vec2.new((cx + 0.5_f32) * CHUNK, (cz + 0.5_f32) * CHUNK))
    end

    def zone(cx : Int32, cz : Int32) : Zone
      d = density(cx, cz)
      d > 0.45 ? Zone::City : d > 0.14 ? Zone::Town : Zone::Country
    end

    def value_noise(p : Vec2, salt : Int32) : Float32
      x0 = p.x.floor.to_i; z0 = p.y.floor.to_i
      fx = p.x - x0; fz = p.y - z0
      sx = fx * fx * (3 - 2 * fx); sz = fz * fz * (3 - 2 * fz)
      a = Joyride.hash01(@seed, x0, z0, salt); b = Joyride.hash01(@seed, x0 + 1, z0, salt)
      c = Joyride.hash01(@seed, x0, z0 + 1, salt); d = Joyride.hash01(@seed, x0 + 1, z0 + 1, salt)
      (a + (b - a) * sx) * (1 - sz) + (c + (d - c) * sx) * sz
    end

    # --- road network ---------------------------------------------------------

    # Road on the edge between (cx, cz) and (cx + 1, cz)?
    def road_x?(cx : Int32, cz : Int32) : Bool
      return true if zone(cx, cz).street? || zone(cx + 1, cz).street?
      return true if cz % 4 == 0 # country highway rows keep the network connected
      Joyride.hash01(@seed, cx, cz, 31) < 0.3
    end

    # Road on the edge between (cx, cz) and (cx, cz + 1)?
    def road_z?(cx : Int32, cz : Int32) : Bool
      return true if zone(cx, cz).street? || zone(cx, cz + 1).street?
      return true if cx % 4 == 0
      Joyride.hash01(@seed, cx, cz, 32) < 0.3
    end

    def road?(cx : Int32, cz : Int32, d : Dir) : Bool
      case d
      in .e? then road_x?(cx, cz)
      in .w? then road_x?(cx - 1, cz)
      in .s? then road_z?(cx, cz)
      in .n? then road_z?(cx, cz - 1)
      end
    end

    # Where along the edge the road crosses, as an offset from the edge midpoint.
    private def edge_offset(ax : Int32, az : Int32, bx : Int32, bz : Int32, salt : Int32) : Float32
      return 0_f32 if zone(ax, az).street? || zone(bx, bz).street?
      (Joyride.hash01(@seed, ax, az, salt) - 0.5_f32) * 40_f32
    end

    private def edge_street?(ax : Int32, az : Int32, bx : Int32, bz : Int32) : Bool
      zone(ax, az).street? && zone(bx, bz).street?
    end

    def crossing(cx : Int32, cz : Int32, d : Dir) : Vec2
      x0 = cx * CHUNK; z0 = cz * CHUNK
      case d
      in .e? then Vec2.new(x0 + CHUNK, z0 + HALF + edge_offset(cx, cz, cx + 1, cz, 41))
      in .w? then Vec2.new(x0, z0 + HALF + edge_offset(cx - 1, cz, cx, cz, 41))
      in .s? then Vec2.new(x0 + HALF + edge_offset(cx, cz, cx, cz + 1, 42), z0 + CHUNK)
      in .n? then Vec2.new(x0 + HALF + edge_offset(cx, cz - 1, cx, cz, 42), z0)
      end
    end

    def node(cx : Int32, cz : Int32) : Vec2
      c = Vec2.new((cx + 0.5_f32) * CHUNK, (cz + 0.5_f32) * CHUNK)
      return c if zone(cx, cz).street?
      c + Vec2.new(Joyride.hash01(@seed, cx, cz, 51) - 0.5_f32, Joyride.hash01(@seed, cx, cz, 52) - 0.5_f32) * 28_f32
    end

    # The road arms of a chunk (cached; cheap enough to query far from the player).
    def arms(cx : Int32, cz : Int32) : Array(Arm)
      @arms_cache[{cx, cz}] ||= build_arms(cx, cz)
    end

    private def build_arms(cx : Int32, cz : Int32) : Array(Arm)
      n = node(cx, cz)
      Dir.values.compact_map do |d|
        next unless road?(cx, cz, d)
        cr = crossing(cx, cz, d)
        street = edge_street?(cx, cz, cx + d.dx, cz + d.dz)
        hw = street ? STREET_HW : COUNTRY_HW
        v = d.vec
        along = (cr - n).dot(v)
        side = (cr - n) - v * along
        pts = if side.length < 0.01
                [n, cr]
              else
                l = n.distance(cr)
                p1 = n + v * (l * 0.4_f32); p2 = cr - v * (l * 0.4_f32)
                (0..12).map { |i| Joyride.bezier(n, p1, p2, cr, i / 12_f32) }
              end
        Arm.new(d, pts, hw, street)
      end
    end

    def node?(cx : Int32, cz : Int32) : Bool
      !arms(cx, cz).empty?
    end

    # Chunks reachable from (cx, cz) by one road.
    def neighbors(cx : Int32, cz : Int32) : Array({Int32, Int32})
      arms(cx, cz).map { |a| {cx + a.dir.dx, cz + a.dir.dz} }
    end

    # Breadth-first route over chunk nodes, limited to *max_nodes* explored. Returns the chunk
    # sequence from start to goal inclusive, or nil.
    def route(from : {Int32, Int32}, to : {Int32, Int32}, max_nodes : Int32 = 900) : Array({Int32, Int32})?
      return [from] if from == to
      prev = {from => from}
      queue = Deque{from}
      while (cur = queue.shift?) && prev.size < max_nodes
        neighbors(*cur).each do |nb|
          next if prev.has_key?(nb)
          prev[nb] = cur
          if nb == to
            path = [nb]
            while (p = prev[path.last]) != path.last
              path << p
            end
            return path.reverse
          end
          queue << nb
        end
      end
      nil
    end

    # Road centerline between the nodes of two adjacent chunks.
    def leg(a : {Int32, Int32}, b : {Int32, Int32}) : Array(Vec2)
      d = Dir.values.find { |x| a[0] + x.dx == b[0] && a[1] + x.dz == b[1] }.not_nil!
      pa = arms(*a).find { |x| x.dir == d }.not_nil!.points
      pb = arms(*b).find { |x| x.dir == d.opposite }.not_nil!.points
      pa + pb.reverse[1..]
    end

    # Nearest chunk with a road node to *p*, searching outward.
    def nearest_node_chunk(p : Vec2, radius : Int32 = 6) : {Int32, Int32}?
      cx, cz = World.chunk_of(p)
      best = nil; best_d = Float32::INFINITY
      (-radius..radius).each do |ox|
        (-radius..radius).each do |oz|
          next unless node?(cx + ox, cz + oz)
          dd = node(cx + ox, cz + oz).distance(p)
          if dd < best_d
            best_d = dd; best = {cx + ox, cz + oz}
          end
        end
      end
      best
    end

    # The closest point on any road to *p* (within the surrounding chunks), with its direction.
    def nearest_road_point(p : Vec2) : {Vec2, Vec2}?
      cx, cz = World.chunk_of(p)
      best = nil; best_d = Float32::INFINITY
      (-1..1).each do |ox|
        (-1..1).each do |oz|
          arms(cx + ox, cz + oz).each do |a|
            (1...a.points.size).each do |i|
              s0 = a.points[i - 1]; s1 = a.points[i]
              ab = s1 - s0
              t = ((p - s0).dot(ab) / Math.max(ab.length_squared, 1e-6_f32)).clamp(0_f32, 1_f32)
              q = s0 + ab * t
              if (dd = q.distance(p)) < best_d
                best_d = dd; best = {q, ab.normalized}
              end
            end
          end
        end
      end
      best
    end

    # --- chunk contents -------------------------------------------------------

    def layout(cx : Int32, cz : Int32) : ChunkLayout
      @layouts[{cx, cz}] ||= generate(cx, cz)
    end

    def layout?(cx : Int32, cz : Int32) : ChunkLayout?
      @layouts[{cx, cz}]?
    end

    # Drops cached chunks farther than *keep* chunks from (cx, cz).
    def evict(cx : Int32, cz : Int32, keep : Int32) : Nil
      @layouts.reject! { |k, _| (k[0] - cx).abs > keep || (k[1] - cz).abs > keep }
      @arms_cache.reject! { |k, _| (k[0] - cx).abs > keep * 4 || (k[1] - cz).abs > keep * 4 } if @arms_cache.size > 4000
    end

    def cached_layouts : Int32
      @layouts.size
    end

    # Static colliders within *r* of *p* (generating chunks as needed).
    def each_collider_near(p : Vec2, r : Float32, & : Collider ->) : Nil
      x0, z0 = World.chunk_of(p - Vec2.new(r, r))
      x1, z1 = World.chunk_of(p + Vec2.new(r, r))
      (x0..x1).each do |cx|
        (z0..z1).each do |cz|
          layout(cx, cz).colliders.each do |c|
            next if (c.center.x - p.x).abs > c.half.x + r || (c.center.y - p.y).abs > c.half.y + r
            yield c
          end
        end
      end
    end

    # Height of the ground the car rests on (curbs raise it on sidewalks).
    def ground_height(p : Vec2) : Float32
      cx, cz = World.chunk_of(p)
      layout(cx, cz).on_sidewalk?(p) ? CURB_H : 0_f32
    end

    # Distance to the first static collider along a ray, or nil.
    def raycast(o : Vec2, d : Vec2, max : Float32) : Float32?
      best = nil
      mid = o + d * (max / 2)
      each_collider_near(mid, max / 2 + 1) do |c|
        if (t = c.raycast(o, d, max)) && (best.nil? || t < best)
          best = t
        end
      end
      best
    end

    private def generate(cx : Int32, cz : Int32) : ChunkLayout
      z = zone(cx, cz)
      a = arms(cx, cz)
      lay = ChunkLayout.new(cx, cz, z, density(cx, cz), a.empty? ? nil : node(cx, cz), a)
      rng = Rng.new(Joyride.hash(@seed, cx, cz, 99))
      case z
      in .city?, .town? then Generator.streets(lay, rng, self)
      in .country?      then Generator.country(lay, rng, self)
      end
      lay
    end
  end

  # Fills chunk layouts with buildings, props and ground patches.
  module Generator
    OFFICE_COLORS = %w(#b8b2a6 #9fa6ad #c9b79c #a2785e #8c96a0 #d6d0c4 #7b8793 #b39478 #6e7f8f #c4c9cf).map { |h| Color.hex(h) }
    HOUSE_COLORS  = %w(#e8d8b0 #d9e4ea #f0c9a8 #c9d9b8 #e6e6e6 #d8b8b8 #b8c8e0 #f2e2c2).map { |h| Color.hex(h) }
    ROOF_COLORS   = %w(#8a3b2e #5a4a42 #4a5560 #7a5a3a #3e4448).map { |h| Color.hex(h) }
    CAR_COLORS    = %w(#c0392b #2e86c1 #f1c40f #ecf0f1 #27ae60 #1c1c1c #8e44ad #e67e22 #7f8c8d #16a085).map { |h| Color.hex(h) }
    CROP_COLORS   = %w(#d8c060 #8a6a44 #7fb04a #a8c050 #c8a048 #9a86c8).map { |h| Color.hex(h) }

    # City and town chunks: a four-way intersection, sidewalks, lots with buildings.
    def self.streets(lay : ChunkLayout, rng : Rng, world : World) : Nil
      node = lay.node.not_nil!
      o = lay.origin
      lay.ground = lay.zone.city? ? Color.hex("#7a8a5a") : Color.hex("#6f9a4c")
      hw = ->(d : Dir) { lay.arm(d).try(&.half_width) || STREET_HW }
      [{1, -1}, {-1, -1}, {1, 1}, {-1, 1}].each do |(sx, sz)|
        wv = hw.call(sz < 0 ? Dir::N : Dir::S) # vertical road bounding this quadrant
        wh = hw.call(sx > 0 ? Dir::E : Dir::W) # horizontal road
        edge_x = sx > 0 ? o.x + CHUNK : o.x
        edge_z = sz > 0 ? o.y + CHUNK : o.y
        # sidewalk along the vertical road, then along the horizontal road
        add_slab(lay, node.x + sx * wv, node.y + sz * wh, node.x + sx * (wv + SIDEWALK), edge_z)
        add_slab(lay, node.x + sx * (wv + SIDEWALK), node.y + sz * wh, edge_x, node.y + sz * (wh + SIDEWALK))
        lay.walkways << {Vec2.new(node.x + sx * (wv + SIDEWALK * 0.5_f32), node.y + sz * (wh + 1)), Vec2.new(node.x + sx * (wv + SIDEWALK * 0.5_f32), edge_z - sz * 1)}
        lay.walkways << {Vec2.new(node.x + sx * (wv + 1), node.y + sz * (wh + SIDEWALK * 0.5_f32)), Vec2.new(edge_x - sx * 1, node.y + sz * (wh + SIDEWALK * 0.5_f32))}
        lot_x0 = node.x + sx * (wv + SIDEWALK); lot_z0 = node.y + sz * (wh + SIDEWALK)
        lot_x1 = edge_x - sx * 0.6_f32; lot_z1 = edge_z - sz * 0.6_f32
        fill_lot(lay, rng, Math.min(lot_x0, lot_x1), Math.min(lot_z0, lot_z1), Math.max(lot_x0, lot_x1), Math.max(lot_z0, lot_z1), sx, sz)
      end
      # street furniture along each arm
      lay.arms.each do |arm|
        d = arm.dir.vec
        side = Vec2.new(-d.y, d.x)
        perp = arm.dir.n? || arm.dir.s? ? hw.call(Dir::E) : hw.call(Dir::N)
        start = perp + SIDEWALK + 2
        len = arm.length
        [-1, 1].each do |s|
          # parked cars in the curb lane
          t = start + 1.5_f32
          while t < len - 3
            if rng.chance(0.3)
              p = node + d * t + side * (s * (arm.half_width - 1.3_f32))
              rot = Math.atan2(-d.x, -d.y).to_f32 + (s < 0 ? Math::PI.to_f32 : 0_f32)
              lay.props << Prop.new(PropKind::ParkedCar, p, rot, 1_f32, rng.pick(CAR_COLORS))
              half = arm.dir.n? || arm.dir.s? ? Vec2.new(1.0, 2.25) : Vec2.new(2.25, 1.0)
              lay.colliders << Collider.new(p, half, 0_f32, false)
              t += 7
            else
              t += 3.5_f32
            end
          end
          # lamps and trees on the sidewalk
          t = start + (s > 0 ? 0 : 11)
          while t < len - 1
            p = node + d * t + side * (s * (arm.half_width + 0.6_f32))
            lay.props << Prop.new(PropKind::Lamp, p, Math.atan2(side.x * s, side.y * s).to_f32)
            lay.colliders << Collider.circle(p, 0.25)
            tp = p + d * 6 + side * (s * 1.9_f32)
            if lay.zone.town? || rng.chance(0.35)
              if t + 6 < len - 1
                lay.props << Prop.new(PropKind::Tree, tp, rng.range(0, 6.28), rng.range(0.7, 0.95), Color.hsv(rng.range(85, 125), 0.5, 0.55))
                lay.colliders << Collider.circle(tp, 0.35)
              end
            end
            t += 22
          end
        end
      end
    end

    private def self.add_slab(lay : ChunkLayout, x0 : Number, z0 : Number, x1 : Number, z1 : Number) : Nil
      lay.slabs << Slab.new(Math.min(x0, x1).to_f32, Math.min(z0, z1).to_f32, Math.max(x0, x1).to_f32, Math.max(z0, z1).to_f32)
    end

    # One quadrant lot. *sx*, *sz* point away from the intersection.
    private def self.fill_lot(lay : ChunkLayout, rng : Rng, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32, sx : Int32, sz : Int32) : Nil
      dens = lay.density
      if lay.zone.town? && dens < 0.3
        houses(lay, rng, x0, z0, x1, z1, sx, sz)
        return
      end
      if rng.chance(0.07)
        park(lay, rng, x0, z0, x1, z1)
        return
      end
      parcels = [] of {Float32, Float32, Float32, Float32}
      case rng.int(4)
      when 0 then parcels << {x0 + 2, z0 + 2, x1 - 2, z1 - 2}
      when 1
        if rng.chance(0.5)
          m = x0 + (x1 - x0) * rng.range(0.4, 0.6); parcels << {x0, z0, m, z1} << {m, z0, x1, z1}
        else
          m = z0 + (z1 - z0) * rng.range(0.4, 0.6); parcels << {x0, z0, x1, m} << {x0, m, x1, z1}
        end
      else
        mx = x0 + (x1 - x0) * rng.range(0.4, 0.6); mz = z0 + (z1 - z0) * rng.range(0.4, 0.6)
        parcels << {x0, z0, mx, mz} << {mx, z0, x1, mz} << {x0, mz, mx, z1} << {mx, mz, x1, z1}
      end
      parcels.each do |(a, b, c, d)|
        inset = 0.8_f32
        bx0 = a + inset; bz0 = b + inset; bx1 = c - inset; bz1 = d - inset
        next if bx1 - bx0 < 5 || bz1 - bz0 < 5
        if lay.zone.city?
          base = 7 + dens ** 1.6 * 70
          h = (base * rng.range(0.45, 1.35)).clamp(6_f32, 95_f32)
          h = (h / 3.5_f32).floor * 3.5_f32 + 1
          tier = h > 30 && rng.chance(0.5) ? h * rng.range(0.55, 0.75) : 0_f32
          lay.buildings << Building.new(bx0, bz0, bx1, bz1, h, BuildingKind::Office, rng.pick(OFFICE_COLORS), Color.gray(rng.range(0.3, 0.45)), tier)
        else
          h = rng.chance(0.5) ? 4.5_f32 : 8_f32
          lay.buildings << Building.new(bx0, bz0, bx1, bz1, h, BuildingKind::Shop, rng.pick(HOUSE_COLORS), Color.gray(0.4))
        end
        lay.colliders << Collider.box(bx0, bz0, bx1, bz1)
      end
    end

    private def self.park(lay : ChunkLayout, rng : Rng, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32) : Nil
      lay.patches << Patch.new(x0, z0, x1, z1, Color.hex("#5f9a40"))
      (4 + rng.int(5)).times do
        p = Vec2.new(rng.range(x0 + 3, x1 - 3), rng.range(z0 + 3, z1 - 3))
        lay.props << Prop.new(PropKind::Tree, p, rng.range(0, 6.28), rng.range(0.9, 1.4), Color.hsv(rng.range(80, 130), 0.55, 0.5))
        lay.colliders << Collider.circle(p, 0.45)
      end
      2.times do
        p = Vec2.new(rng.range(x0 + 4, x1 - 4), rng.range(z0 + 4, z1 - 4))
        lay.props << Prop.new(PropKind::Bench, p, rng.chance(0.5) ? 0_f32 : 1.5708_f32)
      end
    end

    private def self.houses(lay : ChunkLayout, rng : Rng, x0 : Float32, z0 : Float32, x1 : Float32, z1 : Float32, sx : Int32, sz : Int32) : Nil
      mx = (x0 + x1) / 2; mz = (z0 + z1) / 2
      [{x0, z0, mx, mz}, {mx, z0, x1, mz}, {x0, mz, mx, z1}, {mx, mz, x1, z1}].each do |(a, b, c, d)|
        next if rng.chance(0.12)
        w = rng.range(7.5, 10.5); dp = rng.range(6.5, 8.5)
        # face the nearer street: the lot side toward the intersection
        cxp = sx > 0 ? a + 2.5_f32 + w / 2 : c - 2.5_f32 - w / 2
        czp = sz > 0 ? b + 2.5_f32 + dp / 2 : d - 2.5_f32 - dp / 2
        cxp = cxp.clamp(a + w / 2 + 0.5_f32, c - w / 2 - 0.5_f32)
        czp = czp.clamp(b + dp / 2 + 0.5_f32, d - dp / 2 - 0.5_f32)
        h = rng.chance(0.4) ? 6_f32 : 3.4_f32
        lay.buildings << Building.new(cxp - w / 2, czp - dp / 2, cxp + w / 2, czp + dp / 2, h, BuildingKind::House, rng.pick(HOUSE_COLORS), rng.pick(ROOF_COLORS))
        lay.colliders << Collider.box(cxp - w / 2, czp - dp / 2, cxp + w / 2, czp + dp / 2)
        # a yard tree away from the house
        tp = Vec2.new(sx > 0 ? c - 3 : a + 3, sz > 0 ? d - 3 : b + 3)
        if rng.chance(0.7)
          lay.props << Prop.new(rng.chance(0.3) ? PropKind::Pine : PropKind::Tree, tp, rng.range(0, 6.28), rng.range(0.8, 1.2), Color.hsv(rng.range(80, 130), 0.55, 0.5))
          lay.colliders << Collider.circle(tp, 0.45)
        end
      end
    end

    # Country chunks: fields, farms, forests and hills, kept clear of the roads.
    def self.country(lay : ChunkLayout, rng : Rng, world : World) : Nil
      o = lay.origin
      g = world.value_noise(lay.center / (CHUNK * 2), 61)
      lay.ground = Color.hsv(88 + g * 18, 0.45 + g * 0.1, 0.52 + g * 0.08)
      solid = [] of {Vec2, Float32} # occupied circles, to keep things apart
      clear = ->(p : Vec2, r : Float32) do
        lay.road_distance(p) > r + 2.5_f32 && solid.none? { |(q, qr)| q.distance(p) < r + qr } &&
        p.x > o.x + r && p.x < o.x + CHUNK - r && p.y > o.y + r && p.y < o.y + CHUNK - r
      end
      # fields on a 3x3 grid
      cell = CHUNK / 3
      forests = [] of {Float32, Float32}
      3.times do |i|
        3.times do |j|
          x0 = o.x + i * cell + 1; z0 = o.y + j * cell + 1
          r = rng.float
          if r < 0.55
            c = rng.pick(CROP_COLORS)
            lay.patches << Patch.new(x0, z0, x0 + cell - 2, z0 + cell - 2, c, 8 + rng.int(6), rng.chance(0.5))
            if c == CROP_COLORS[0] && rng.chance(0.6)
              (2 + rng.int(4)).times do
                p = Vec2.new(rng.range(x0 + 3, x0 + cell - 5), rng.range(z0 + 3, z0 + cell - 5))
                next unless clear.call(p, 1.2_f32)
                lay.props << Prop.new(PropKind::HayBale, p, rng.range(0, 3.14))
                lay.colliders << Collider.circle(p, 0.9)
                solid << {p, 1.2_f32}
              end
            end
          elsif r < 0.72
            forests << {x0, z0}
          end
        end
      end
      # a farm by the road
      if (node = lay.node) && rng.chance(0.4)
        arm = rng.pick(lay.arms)
        d = (arm.points[Math.min(2, arm.points.size - 1)] - node).normalized
        side = Vec2.new(-d.y, d.x) * (rng.chance(0.5) ? 1 : -1)
        base = node + d * 18 + side * (arm.half_width + 13)
        spots = [{BuildingKind::Farmhouse, base, 9_f32, 8_f32}, {BuildingKind::Barn, base + d * 16, 11_f32, 14_f32}, {BuildingKind::Silo, base + d * 16 + side * 11, 3.2_f32, 3.2_f32}]
        spots.each do |(kind, p, w, dp)|
          r = Math.max(w, dp) * 0.75_f32
          next unless clear.call(p, r)
          h = kind.silo? ? 13_f32 : kind.barn? ? 7_f32 : 5.5_f32
          color = kind.barn? ? Color.hex("#a8322a") : kind.silo? ? Color.hex("#c8ccd0") : rng.pick(HOUSE_COLORS)
          lay.buildings << Building.new(p.x - w / 2, p.y - dp / 2, p.x + w / 2, p.y + dp / 2, h, kind, color, kind.barn? ? Color.hex("#5a3a2a") : rng.pick(ROOF_COLORS))
          if kind.silo?
            lay.colliders << Collider.circle(p, w / 2)
          else
            lay.colliders << Collider.box(p.x - w / 2, p.y - dp / 2, p.x + w / 2, p.y + dp / 2)
          end
          solid << {p, r + 2}
        end
      end
      # hills
      if rng.chance(0.35)
        (1 + rng.int(2)).times do
          r = rng.range(14, 24)
          p = Vec2.new(rng.range(o.x + r, o.x + CHUNK - r), rng.range(o.y + r, o.y + CHUNK - r))
          next unless clear.call(p, r)
          lay.props << Prop.new(PropKind::Hill, p, rng.range(0, 6.28), r, Color.hsv(rng.range(85, 110), 0.45, rng.range(0.45, 0.55)))
          lay.colliders << Collider.circle(p, r * 0.72_f32)
          solid << {p, r}
        end
      end
      # forests, then scattered trees and rocks
      forests.each do |(x0, z0)|
        pine = rng.chance(0.5)
        (10 + rng.int(8)).times do
          p = Vec2.new(rng.range(x0 + 2, x0 + cell - 4), rng.range(z0 + 2, z0 + cell - 4))
          next unless clear.call(p, 1.6_f32)
          add_tree(lay, rng, p, pine, solid)
        end
      end
      (6 + rng.int(10)).times do
        p = Vec2.new(rng.range(o.x + 2, o.x + CHUNK - 2), rng.range(o.y + 2, o.y + CHUNK - 2))
        next unless clear.call(p, 1.6_f32)
        if rng.chance(0.15)
          lay.props << Prop.new(PropKind::Rock, p, rng.range(0, 6.28), rng.range(0.6, 1.6))
          lay.colliders << Collider.circle(p, 0.8)
          solid << {p, 1.5_f32}
        else
          add_tree(lay, rng, p, rng.chance(0.3), solid)
        end
      end
    end

    private def self.add_tree(lay : ChunkLayout, rng : Rng, p : Vec2, pine : Bool, solid : Array({Vec2, Float32})) : Nil
      s = rng.range(0.8, 1.5)
      color = pine ? Color.hsv(rng.range(120, 150), 0.5, 0.35) : Color.hsv(rng.range(70, 125), 0.55, rng.range(0.42, 0.58))
      lay.props << Prop.new(pine ? PropKind::Pine : PropKind::Tree, p, rng.range(0, 6.28), s, color)
      lay.colliders << Collider.circle(p, 0.45 * s)
      solid << {p, 1.6_f32 * s}
    end
  end
end
