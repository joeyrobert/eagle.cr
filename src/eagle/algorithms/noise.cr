module Eagle
  # Deterministic coherent noise for terrain, textures and procedural animation.
  #
  # Equal seeds produce bit-identical samples on every platform, including WebAssembly.
  # Perlin and simplex are signed (about -1..1). fBm layers simplex octaves. Ridged noise
  # folds that into 0..1 ridges. Worley (cellular) is the distance to the nearest feature
  # point. Domain warping offsets the sample coordinates with noise before sampling again.
  #
  # ```
  # n = Noise.new(42)
  # height = n.fbm(12.5, 8.0)
  # ridge = n.ridged(12.5, 8.0, octaves: 4)
  # caves = n.worley(v2(12.5, 8.0))
  # ```
  class Noise
    # Builds a repeatable noise field. Equal seeds produce bit-identical samples.
    def initialize(seed : Int = 0)
      values = (0..255).map(&.to_i32)
      Rng.new(seed).shuffle!(values)
      @perm = Array(Int32).new(512) { |i| values[i & 255] }
    end

    def perlin(point : Vec2) : Float32; perlin(point.x, point.y); end
    def perlin(point : Vec3) : Float32; perlin(point.x, point.y, point.z); end

    # Improved Perlin noise in approximately -1..1.
    def perlin(x : Number, y : Number) : Float32
      xf = x.to_f64
      yf = y.to_f64
      xi = xf.floor.to_i & 255
      yi = yf.floor.to_i & 255
      xf -= xf.floor
      yf -= yf.floor
      u = fade(xf)
      v = fade(yf)
      aa = @perm[@perm[xi] + yi]
      ab = @perm[@perm[xi] + yi + 1]
      ba = @perm[@perm[xi + 1] + yi]
      bb = @perm[@perm[xi + 1] + yi + 1]
      lerp(lerp(grad2(aa, xf, yf), grad2(ba, xf - 1, yf), u),
        lerp(grad2(ab, xf, yf - 1), grad2(bb, xf - 1, yf - 1), u), v).to_f32
    end

    def perlin(x : Number, y : Number, z : Number) : Float32
      xf = x.to_f64
      yf = y.to_f64
      zf = z.to_f64
      xi = xf.floor.to_i & 255
      yi = yf.floor.to_i & 255
      zi = zf.floor.to_i & 255
      xf -= xf.floor
      yf -= yf.floor
      zf -= zf.floor
      u = fade(xf); v = fade(yf); w = fade(zf)
      aaa = hash(xi, yi, zi); aba = hash(xi, yi + 1, zi)
      aab = hash(xi, yi, zi + 1); abb = hash(xi, yi + 1, zi + 1)
      baa = hash(xi + 1, yi, zi); bba = hash(xi + 1, yi + 1, zi)
      bab = hash(xi + 1, yi, zi + 1); bbb = hash(xi + 1, yi + 1, zi + 1)
      x1 = lerp(grad3(aaa, xf, yf, zf), grad3(baa, xf - 1, yf, zf), u)
      x2 = lerp(grad3(aba, xf, yf - 1, zf), grad3(bba, xf - 1, yf - 1, zf), u)
      y1 = lerp(x1, x2, v)
      x1 = lerp(grad3(aab, xf, yf, zf - 1), grad3(bab, xf - 1, yf, zf - 1), u)
      x2 = lerp(grad3(abb, xf, yf - 1, zf - 1), grad3(bbb, xf - 1, yf - 1, zf - 1), u)
      lerp(y1, lerp(x1, x2, v), w).to_f32
    end

    # Simplex noise has fewer directional artifacts than grid-aligned Perlin noise.
    def simplex(x : Number, y : Number) : Float32
      x = x.to_f64; y = y.to_f64
      f2 = 0.5 * (Math.sqrt(3.0) - 1.0)
      g2 = (3.0 - Math.sqrt(3.0)) / 6.0
      skew = (x + y) * f2
      i = (x + skew).floor.to_i
      j = (y + skew).floor.to_i
      unskew = (i + j) * g2
      x0 = x - (i - unskew)
      y0 = y - (j - unskew)
      i1, j1 = x0 > y0 ? {1, 0} : {0, 1}
      x1 = x0 - i1 + g2; y1 = y0 - j1 + g2
      x2 = x0 - 1 + 2 * g2; y2 = y0 - 1 + 2 * g2
      ii = i & 255; jj = j & 255
      n0 = simplex_corner2(@perm[ii + @perm[jj]], x0, y0)
      n1 = simplex_corner2(@perm[ii + i1 + @perm[jj + j1]], x1, y1)
      n2 = simplex_corner2(@perm[ii + 1 + @perm[jj + 1]], x2, y2)
      (70.0 * (n0 + n1 + n2)).to_f32
    end

    def simplex(x : Number, y : Number, z : Number) : Float32
      x = x.to_f64; y = y.to_f64; z = z.to_f64
      skew = (x + y + z) / 3.0
      i = (x + skew).floor.to_i; j = (y + skew).floor.to_i; k = (z + skew).floor.to_i
      unskew = (i + j + k) / 6.0
      x0 = x - (i - unskew); y0 = y - (j - unskew); z0 = z - (k - unskew)
      if x0 >= y0
        if y0 >= z0
          i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
        elsif x0 >= z0
          i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
        else
          i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1
        end
      elsif y0 < z0
        i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
      elsif x0 < z0
        i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
      else
        i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0
      end
      x1 = x0 - i1 + 1.0 / 6; y1 = y0 - j1 + 1.0 / 6; z1 = z0 - k1 + 1.0 / 6
      x2 = x0 - i2 + 2.0 / 6; y2 = y0 - j2 + 2.0 / 6; z2 = z0 - k2 + 2.0 / 6
      x3 = x0 - 0.5; y3 = y0 - 0.5; z3 = z0 - 0.5
      ii = i & 255; jj = j & 255; kk = k & 255
      n0 = simplex_corner3(hash(ii, jj, kk), x0, y0, z0)
      n1 = simplex_corner3(hash(ii + i1, jj + j1, kk + k1), x1, y1, z1)
      n2 = simplex_corner3(hash(ii + i2, jj + j2, kk + k2), x2, y2, z2)
      n3 = simplex_corner3(hash(ii + 1, jj + 1, kk + 1), x3, y3, z3)
      (32.0 * (n0 + n1 + n2 + n3)).to_f32
    end

    def simplex(point : Vec2) : Float32; simplex(point.x, point.y); end
    def simplex(point : Vec3) : Float32; simplex(point.x, point.y, point.z); end

    # Fractal Brownian motion: layered simplex noise with increasing frequency.
    def fbm(x : Number, y : Number, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      validate_fractal(octaves, lacunarity, gain)
      fractal(x, y, octaves, lacunarity, gain) { |nx, ny| simplex(nx, ny).to_f64 }
    end

    def fbm(x : Number, y : Number, z : Number, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      validate_fractal(octaves, lacunarity, gain)
      amplitude = 1.0; frequency = 1.0; value = 0.0; total = 0.0
      octaves.times do
        value += simplex(x.to_f64 * frequency, y.to_f64 * frequency, z.to_f64 * frequency) * amplitude
        total += amplitude; frequency *= lacunarity; amplitude *= gain
      end
      (value / total).to_f32
    end

    def fbm(point : Vec2, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      fbm(point.x, point.y, octaves: octaves, lacunarity: lacunarity, gain: gain)
    end

    def fbm(point : Vec3, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      fbm(point.x, point.y, point.z, octaves: octaves, lacunarity: lacunarity, gain: gain)
    end

    # Sharp mountain-like fractal noise in 0..1.
    def ridged(x : Number, y : Number, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      validate_fractal(octaves, lacunarity, gain)
      fractal(x, y, octaves, lacunarity, gain) { |nx, ny| 1.0 - simplex(nx, ny).abs }
    end

    def ridged(x : Number, y : Number, z : Number, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      validate_fractal(octaves, lacunarity, gain)
      amplitude = 1.0; frequency = 1.0; value = 0.0; total = 0.0
      octaves.times do
        value += (1.0 - simplex(x.to_f64 * frequency, y.to_f64 * frequency, z.to_f64 * frequency).abs) * amplitude
        total += amplitude; frequency *= lacunarity; amplitude *= gain
      end
      (value / total).to_f32
    end

    def ridged(point : Vec2, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      ridged(point.x, point.y, octaves: octaves, lacunarity: lacunarity, gain: gain)
    end

    def ridged(point : Vec3, octaves : Int32 = 5, lacunarity : Number = 2.0, gain : Number = 0.5) : Float32
      ridged(point.x, point.y, point.z, octaves: octaves, lacunarity: lacunarity, gain: gain)
    end

    # Warps input coordinates with two offset noise fields before sampling fBm.
    def domain_warp(x : Number, y : Number, strength : Number = 1, octaves : Int32 = 5) : Float32
      qx = fbm(x, y, octaves: octaves)
      qy = fbm(x.to_f64 + 5.2, y.to_f64 + 1.3, octaves: octaves)
      fbm(x.to_f64 + strength * qx, y.to_f64 + strength * qy, octaves: octaves)
    end

    private def domain_warp_3d(x : Number, y : Number, z : Number, strength : Number = 1, octaves : Int32 = 5) : Float32
      qx = fbm(x, y, z, octaves: octaves)
      qy = fbm(x.to_f64 + 5.2, y.to_f64 + 1.3, z.to_f64 + 7.1, octaves: octaves)
      qz = fbm(x.to_f64 + 9.2, y.to_f64 + 2.8, z.to_f64 + 3.4, octaves: octaves)
      fbm(x.to_f64 + strength * qx, y.to_f64 + strength * qy, z.to_f64 + strength * qz, octaves: octaves)
    end

    def domain_warp(point : Vec2, strength : Number = 1, octaves : Int32 = 5) : Float32
      domain_warp(point.x, point.y, strength, octaves)
    end

    def domain_warp(point : Vec3, strength : Number = 1, octaves : Int32 = 5) : Float32
      domain_warp_3d(point.x, point.y, point.z, strength, octaves)
    end

    # Distance to the nearest deterministic feature point (Worley/cellular F1).
    def worley(x : Number, y : Number) : Float32
      xf = x.to_f64; yf = y.to_f64
      cell_x = xf.floor.to_i; cell_y = yf.floor.to_i
      nearest = Float64::INFINITY
      (-1..1).each do |dy|
        (-1..1).each do |dx|
          cx = cell_x + dx; cy = cell_y + dy
          px = cx + hash_float(cx, cy, 0)
          py = cy + hash_float(cx, cy, 1)
          nearest = Math.min(nearest, Math.hypot(px - xf, py - yf))
        end
      end
      nearest.to_f32
    end

    # Three-dimensional Worley F1: distance to the nearest feature point.
    def worley(x : Number, y : Number, z : Number) : Float32
      xf = x.to_f64; yf = y.to_f64; zf = z.to_f64
      cell_x = xf.floor.to_i; cell_y = yf.floor.to_i; cell_z = zf.floor.to_i
      nearest = Float64::INFINITY
      (-1..1).each do |dz|
        (-1..1).each do |dy|
          (-1..1).each do |dx|
            cx = cell_x + dx; cy = cell_y + dy; cz = cell_z + dz
            px = cx + hash_float(cx, cy, cz, 0)
            py = cy + hash_float(cx, cy, cz, 1)
            pz = cz + hash_float(cx, cy, cz, 2)
            nearest = Math.min(nearest, Math.sqrt((px - xf) ** 2 + (py - yf) ** 2 + (pz - zf) ** 2))
          end
        end
      end
      nearest.to_f32
    end

    def worley(point : Vec2) : Float32; worley(point.x, point.y); end
    def worley(point : Vec3) : Float32; worley(point.x, point.y, point.z); end

    private def fractal(x, y, octaves, lacunarity, gain, &sample : Float64, Float64 -> Float64) : Float32
      amplitude = 1.0; frequency = 1.0; value = 0.0; total = 0.0
      octaves.times do
        value += sample.call(x.to_f64 * frequency, y.to_f64 * frequency) * amplitude
        total += amplitude; frequency *= lacunarity; amplitude *= gain
      end
      (value / total).to_f32
    end

    private def validate_fractal(octaves, lacunarity, gain) : Nil
      raise ArgumentError.new("octaves must be positive") unless octaves > 0
      raise ArgumentError.new("lacunarity must be positive") unless lacunarity > 0
      raise ArgumentError.new("gain must be positive") unless gain > 0
    end

    private def fade(t)
      t * t * t * (t * (t * 6 - 15) + 10)
    end

    private def lerp(a, b, t)
      a + t * (b - a)
    end

    private def hash(x, y, z)
      @perm[@perm[@perm[x & 255] + (y & 255)] + (z & 255)]
    end

    private def grad2(hash, x, y)
      (hash & 1 == 0 ? x : -x) + (hash & 2 == 0 ? y : -y)
    end

    private def grad3(hash, x, y, z)
      h = hash & 15; u = h < 8 ? x : y; v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
      (h & 1 == 0 ? u : -u) + (h & 2 == 0 ? v : -v)
    end

    private def simplex_corner2(hash, x, y)
      t = 0.5 - x * x - y * y
      t < 0 ? 0.0 : t ** 4 * grad2(hash, x, y)
    end

    private def simplex_corner3(hash, x, y, z)
      t = 0.6 - x * x - y * y - z * z
      t < 0 ? 0.0 : t ** 4 * grad3(hash, x, y, z)
    end

    private def hash_float(x, y, salt)
      hash_unit(x.to_i64.to_u64! &* 374761393_u64 ^ y.to_i64.to_u64! &* 668265263_u64 ^ salt.to_u64! &* 1442695041_u64)
    end
    private def hash_float(x, y, z, salt)
      hash_unit(x.to_i64.to_u64! &* 374761393_u64 ^ y.to_i64.to_u64! &* 668265263_u64 ^ z.to_i64.to_u64! &* 2246822519_u64 ^ salt.to_u64! &* 1442695041_u64)
    end
    private def hash_unit(n : UInt64) : Float64
      n ^= @perm[(n & 255).to_i].to_u64
      n = (n ^ (n >> 30)) &* 0xbf58476d1ce4e5b9_u64
      n = (n ^ (n >> 27)) &* 0x94d049bb133111eb_u64
      ((n ^ (n >> 31)) >> 40).to_f64 / 16777216.0
    end
  end
end
