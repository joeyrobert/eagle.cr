module Eagle
  # Triangle mesh with interleaved position/normal/uv/color vertices.
  # Build procedurally, from primitives, or load OBJ files.
  class Mesh
    LAYOUT = GPU::VertexLayout.new.float("a_position", 3).float("a_normal", 3).float("a_uv", 2).float("a_color", 4)
    FLOATS = 12

    getter positions = [] of Vec3
    getter normals = [] of Vec3
    getter uvs = [] of Vec2
    getter colors = [] of Color
    getter indices = [] of UInt32
    getter name : String
    property primitive : GPU::Primitive = GPU::Primitive::Triangles
    @geom : UInt32 = 0_u32
    @index_count = 0
    @dirty = true
    @bounds : AABB? = nil

    def initialize(@name : String = "mesh")
    end

    def self.decode(text : String, hint : String = "") : Mesh
      Codecs::OBJ.decode(text, hint)
    end

    def self.load(path : String) : Mesh
      Assets.mesh(path)
    end

    def vertex_count : Int32; @positions.size; end
    def triangle_count : Int32; @indices.size // 3; end

    # Add a vertex; returns its index.
    def add_vertex(p : Vec3, n : Vec3 = Vec3::UP, uv : Vec2 = Vec2::ZERO, c : Color = Color::WHITE) : UInt32
      @positions << p; @normals << n; @uvs << uv; @colors << c
      @dirty = true
      (@positions.size - 1).to_u32
    end

    def add_triangle(a : UInt32, b : UInt32, c : UInt32) : Nil
      @indices << a << b << c
      @dirty = true
    end

    def add_quad(a : UInt32, b : UInt32, c : UInt32, d : UInt32) : Nil
      add_triangle(a, b, c); add_triangle(a, c, d)
    end

    def clear : Nil
      @positions.clear; @normals.clear; @uvs.clear; @colors.clear; @indices.clear
      @dirty = true; @bounds = nil
    end

    def bounds : AABB
      @bounds ||= @positions.empty? ? AABB.new(Vec3::ZERO, Vec3::ZERO) : AABB.from_points(@positions)
    end

    # Recompute smooth per-vertex normals from the triangles.
    def compute_normals : self
      acc = Array(Vec3).new(@positions.size, Vec3::ZERO)
      (0...@indices.size).step(3) do |i|
        a = @indices[i].to_i; b = @indices[i + 1].to_i; c = @indices[i + 2].to_i
        n = (@positions[b] - @positions[a]).cross(@positions[c] - @positions[a])
        acc[a] += n; acc[b] += n; acc[c] += n
      end
      @normals.clear
      acc.each { |n| @normals << (n.length > 0 ? n.normalized : Vec3::UP) }
      @dirty = true
      self
    end

    # Duplicate vertices per face so each triangle gets a flat normal.
    def flat_shaded : Mesh
      m = Mesh.new(@name)
      (0...@indices.size).step(3) do |i|
        a = @indices[i].to_i; b = @indices[i + 1].to_i; c = @indices[i + 2].to_i
        n = (@positions[b] - @positions[a]).cross(@positions[c] - @positions[a]).normalized
        ia = m.add_vertex(@positions[a], n, @uvs[a], @colors[a])
        ib = m.add_vertex(@positions[b], n, @uvs[b], @colors[b])
        ic = m.add_vertex(@positions[c], n, @uvs[c], @colors[c])
        m.add_triangle(ia, ib, ic)
      end
      m
    end

    def transform!(mat : Mat4) : self
      nm = mat.to_mat3.inverse.transposed
      @positions.map! { |p| mat.transform_point(p) }
      @normals.map! { |n| (nm * n).normalized }
      @dirty = true; @bounds = nil
      self
    end

    def color!(c : Color) : self
      @colors.fill(c)
      @dirty = true
      self
    end

    # Append another mesh's geometry (optionally transformed).
    def append(other : Mesh, mat : Mat4? = nil) : self
      base = @positions.size.to_u32
      nm = mat ? mat.to_mat3.inverse.transposed : Mat3.identity
      other.positions.each_with_index do |p, i|
        pp = mat ? mat.transform_point(p) : p
        nn = mat ? (nm * other.normals[i]).normalized : other.normals[i]
        add_vertex(pp, nn, other.uvs[i], other.colors[i])
      end
      other.indices.each { |i| @indices << base + i }
      @dirty = true; @bounds = nil
      self
    end

    # Upload to the GPU (called automatically before drawing).
    def upload : Nil
      @geom = GPU.device.create_geometry(LAYOUT) if @geom == 0
      data = Slice(Float32).new(@positions.size * FLOATS)
      @positions.size.times do |i|
        o = i * FLOATS
        p = @positions[i]; n = @normals[i]? || Vec3::UP; uv = @uvs[i]? || Vec2::ZERO; c = @colors[i]? || Color::WHITE
        data[o] = p.x; data[o + 1] = p.y; data[o + 2] = p.z
        data[o + 3] = n.x; data[o + 4] = n.y; data[o + 5] = n.z
        data[o + 6] = uv.x; data[o + 7] = uv.y
        data[o + 8] = c.r; data[o + 9] = c.g; data[o + 10] = c.b; data[o + 11] = c.a
      end
      GPU.device.upload_vertices(@geom, data, GPU::Usage::Static)
      idx = Slice(UInt32).new(@indices.size) { |i| @indices[i] }
      GPU.device.upload_indices(@geom, idx, GPU::Usage::Static)
      @index_count = @indices.size
      @dirty = false
    end

    def draw : Nil
      upload if @dirty || @geom == 0
      GPU.device.draw(@geom, @primitive, @index_count, 0, indexed: true)
    end

    def dispose : Nil
      GPU.device.delete_geometry(@geom) if @geom != 0 && GPU.ready?
      @geom = 0_u32
    end

    # --- primitives ----------------------------------------------------------
    def self.quad(w : Number = 1, h : Number = 1, color : Color = Color::WHITE) : Mesh
      m = new("quad")
      hw = w / 2; hh = h / 2
      a = m.add_vertex(Vec3.new(-hw, -hh, 0), Vec3::BACK, Vec2.new(0, 1), color)
      b = m.add_vertex(Vec3.new(hw, -hh, 0), Vec3::BACK, Vec2.new(1, 1), color)
      c = m.add_vertex(Vec3.new(hw, hh, 0), Vec3::BACK, Vec2.new(1, 0), color)
      d = m.add_vertex(Vec3.new(-hw, hh, 0), Vec3::BACK, Vec2.new(0, 0), color)
      m.add_quad(a, b, c, d)
      m
    end

    # Ground plane in XZ facing up.
    def self.plane(w : Number = 1, d : Number = 1, subdivisions : Int32 = 1, color : Color = Color::WHITE, uv_scale : Number = 1) : Mesh
      m = new("plane")
      n = Math.max(1, subdivisions)
      (0..n).each do |z|
        (0..n).each do |x|
          fx = x / n.to_f32; fz = z / n.to_f32
          m.add_vertex(Vec3.new((fx - 0.5) * w, 0, (fz - 0.5) * d), Vec3::UP, Vec2.new(fx * uv_scale, fz * uv_scale), color)
        end
      end
      n.times do |z|
        n.times do |x|
          i = (z * (n + 1) + x).to_u32
          m.add_quad(i, i + n + 1, i + n + 2, i + 1) # counter-clockwise seen from above
        end
      end
      m
    end

    def self.cube(size : Number = 1, color : Color = Color::WHITE) : Mesh
      box(size, size, size, color)
    end

    def self.box(w : Number, h : Number, d : Number, color : Color = Color::WHITE) : Mesh
      m = new("box")
      hx = w / 2; hy = h / 2; hz = d / 2
      faces = {
        {Vec3::BACK, Vec3.new(-hx, -hy, hz), Vec3.new(hx, -hy, hz), Vec3.new(hx, hy, hz), Vec3.new(-hx, hy, hz)},
        {Vec3::FORWARD, Vec3.new(hx, -hy, -hz), Vec3.new(-hx, -hy, -hz), Vec3.new(-hx, hy, -hz), Vec3.new(hx, hy, -hz)},
        {Vec3::RIGHT, Vec3.new(hx, -hy, hz), Vec3.new(hx, -hy, -hz), Vec3.new(hx, hy, -hz), Vec3.new(hx, hy, hz)},
        {Vec3::LEFT, Vec3.new(-hx, -hy, -hz), Vec3.new(-hx, -hy, hz), Vec3.new(-hx, hy, hz), Vec3.new(-hx, hy, -hz)},
        {Vec3::UP, Vec3.new(-hx, hy, hz), Vec3.new(hx, hy, hz), Vec3.new(hx, hy, -hz), Vec3.new(-hx, hy, -hz)},
        {Vec3::DOWN, Vec3.new(-hx, -hy, -hz), Vec3.new(hx, -hy, -hz), Vec3.new(hx, -hy, hz), Vec3.new(-hx, -hy, hz)},
      }
      faces.each do |(n, p0, p1, p2, p3)|
        a = m.add_vertex(p0, n, Vec2.new(0, 1), color)
        b = m.add_vertex(p1, n, Vec2.new(1, 1), color)
        c = m.add_vertex(p2, n, Vec2.new(1, 0), color)
        d = m.add_vertex(p3, n, Vec2.new(0, 0), color)
        m.add_quad(a, b, c, d)
      end
      m
    end

    def self.sphere(radius : Number = 0.5, segments : Int32 = 24, rings : Int32 = 16, color : Color = Color::WHITE) : Mesh
      m = new("sphere")
      (0..rings).each do |r|
        phi = Math::PI * r / rings
        (0..segments).each do |s|
          theta = Math::PI * 2 * s / segments
          n = Vec3.new(Math.sin(phi) * Math.cos(theta), Math.cos(phi), Math.sin(phi) * Math.sin(theta))
          m.add_vertex(n * radius, n, Vec2.new(s / segments.to_f32, r / rings.to_f32), color)
        end
      end
      rings.times do |r|
        segments.times do |s|
          i = (r * (segments + 1) + s).to_u32
          m.add_quad(i, i + segments + 1, i + segments + 2, i + 1)
        end
      end
      m
    end

    def self.cylinder(radius : Number = 0.5, height : Number = 1, segments : Int32 = 24, color : Color = Color::WHITE, top_radius : Number? = nil) : Mesh
      m = new("cylinder")
      hh = height / 2
      tr = top_radius || radius
      # side
      (0..segments).each do |s|
        theta = Math::PI * 2 * s / segments
        dir = Vec3.new(Math.cos(theta), 0, Math.sin(theta))
        slope = (radius - tr) / height
        n = Vec3.new(dir.x, slope, dir.z).normalized
        m.add_vertex(dir * radius + Vec3.new(0, -hh, 0), n, Vec2.new(s / segments.to_f32, 1), color)
        m.add_vertex(dir * tr + Vec3.new(0, hh, 0), n, Vec2.new(s / segments.to_f32, 0), color)
      end
      segments.times do |s|
        i = (s * 2).to_u32
        m.add_quad(i, i + 1, i + 3, i + 2)
      end
      # caps
      { {-hh, Vec3::DOWN, radius}, {hh, Vec3::UP, tr} }.each do |(y, n, r)|
        next if r <= 0
        center = m.add_vertex(Vec3.new(0, y, 0), n, Vec2.new(0.5, 0.5), color)
        ring = [] of UInt32
        (0..segments).each do |s|
          theta = Math::PI * 2 * s / segments
          ring << m.add_vertex(Vec3.new(Math.cos(theta) * r, y, Math.sin(theta) * r), n, Vec2.new(0.5 + Math.cos(theta) / 2, 0.5 + Math.sin(theta) / 2), color)
        end
        segments.times do |s|
          if n.y > 0
            m.add_triangle(center, ring[s], ring[s + 1])
          else
            m.add_triangle(center, ring[s + 1], ring[s])
          end
        end
      end
      m
    end

    def self.cone(radius : Number = 0.5, height : Number = 1, segments : Int32 = 24, color : Color = Color::WHITE) : Mesh
      cylinder(radius, height, segments, color, top_radius: 0)
    end

    def self.capsule(radius : Number = 0.5, height : Number = 1, segments : Int32 = 16, color : Color = Color::WHITE) : Mesh
      m = cylinder(radius, height, segments, color)
      top = sphere(radius, segments, segments // 2, color)
      m.append(top, Mat4.translation(0, height / 2, 0))
      m.append(top, Mat4.translation(0, -height / 2, 0))
      m
    end

    def self.torus(radius : Number = 1, tube : Number = 0.3, segments : Int32 = 32, rings : Int32 = 16, color : Color = Color::WHITE) : Mesh
      m = new("torus")
      (0..segments).each do |s|
        u = Math::PI * 2 * s / segments
        (0..rings).each do |r|
          v = Math::PI * 2 * r / rings
          cx = Math.cos(u); sx = Math.sin(u)
          center = Vec3.new(cx * radius, 0, sx * radius)
          n = Vec3.new(cx * Math.cos(v), Math.sin(v), sx * Math.cos(v))
          m.add_vertex(center + n * tube, n, Vec2.new(s / segments.to_f32, r / rings.to_f32), color)
        end
      end
      segments.times do |s|
        rings.times do |r|
          i = (s * (rings + 1) + r).to_u32
          m.add_quad(i, i + 1, i + rings + 2, i + rings + 1)
        end
      end
      m
    end

    # Lines: a wireframe grid on XZ (draw with a LineMaterial / unlit).
    def self.grid(size : Number = 10, divisions : Int32 = 10, color : Color = Color.gray(0.4)) : Mesh
      m = new("grid")
      m.primitive = GPU::Primitive::Lines
      half = size / 2
      (0..divisions).each do |i|
        t = -half + size * i / divisions
        a = m.add_vertex(Vec3.new(t, 0, -half), Vec3::UP, Vec2::ZERO, color)
        b = m.add_vertex(Vec3.new(t, 0, half), Vec3::UP, Vec2::ZERO, color)
        c = m.add_vertex(Vec3.new(-half, 0, t), Vec3::UP, Vec2::ZERO, color)
        d = m.add_vertex(Vec3.new(half, 0, t), Vec3::UP, Vec2::ZERO, color)
        m.indices << a << b << c << d
      end
      m
    end

    def self.axes(length : Number = 1) : Mesh
      m = new("axes")
      m.primitive = GPU::Primitive::Lines
      { {Vec3::RIGHT, Color::RED}, {Vec3::UP, Color::GREEN}, {Vec3::BACK, Color::BLUE} }.each do |(d, c)|
        a = m.add_vertex(Vec3::ZERO, Vec3::UP, Vec2::ZERO, c)
        b = m.add_vertex(d * length, Vec3::UP, Vec2::ZERO, c)
        m.indices << a << b
      end
      m
    end
  end

  module Codecs
    # Wavefront OBJ: v / vt / vn / f (triangles, quads, n-gons). Materials ignored.
    module OBJ
      def self.decode(text : String, hint : String = "") : Mesh
        mesh = Mesh.new(File.basename(hint, ".obj"))
        vs = [] of Vec3; vts = [] of Vec2; vns = [] of Vec3
        cache = {} of String => UInt32
        has_normals = false
        text.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?('#')
          parts = line.split
          case parts[0]
          when "v" then vs << Vec3.new(parts[1].to_f, parts[2].to_f, parts[3].to_f)
          when "vt" then vts << Vec2.new(parts[1].to_f, 1 - parts[2].to_f)
          when "vn" then vns << Vec3.new(parts[1].to_f, parts[2].to_f, parts[3].to_f); has_normals = true
          when "f"
            idx = parts[1..].map do |tok|
              cache[tok] ||= begin
                f = tok.split('/')
                vi = resolve(f[0], vs.size)
                ti = f.size > 1 && !f[1].empty? ? resolve(f[1], vts.size) : -1
                ni = f.size > 2 && !f[2].empty? ? resolve(f[2], vns.size) : -1
                mesh.add_vertex(vs[vi], ni >= 0 ? vns[ni] : Vec3::UP, ti >= 0 ? vts[ti] : Vec2::ZERO)
              end
            end
            (1...idx.size - 1).each { |i| mesh.add_triangle(idx[0], idx[i], idx[i + 1]) }
          end
        end
        raise AssetError.new("OBJ has no faces#{hint.empty? ? "" : " (#{hint})"}") if mesh.indices.empty?
        mesh.compute_normals unless has_normals
        mesh
      end

      private def self.resolve(s : String, count : Int32) : Int32
        i = s.to_i
        i < 0 ? count + i : i - 1
      end

      def self.encode(mesh : Mesh) : String
        String.build do |io|
          io << "# eagle\n"
          mesh.positions.each { |p| io << "v " << p.x << " " << p.y << " " << p.z << "\n" }
          mesh.uvs.each { |t| io << "vt " << t.x << " " << 1 - t.y << "\n" }
          mesh.normals.each { |n| io << "vn " << n.x << " " << n.y << " " << n.z << "\n" }
          (0...mesh.indices.size).step(3) do |i|
            a = mesh.indices[i] + 1; b = mesh.indices[i + 1] + 1; c = mesh.indices[i + 2] + 1
            io << "f #{a}/#{a}/#{a} #{b}/#{b}/#{b} #{c}/#{c}/#{c}\n"
          end
        end
      end
    end
  end
end
