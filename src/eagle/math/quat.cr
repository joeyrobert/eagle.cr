module Eagle
  # Unit quaternion for 3D rotations. (x, y, z, w)
  struct Quat
    property x : Float32
    property y : Float32
    property z : Float32
    property w : Float32

    def initialize(x : Number, y : Number, z : Number, w : Number)
      @x = x.to_f32; @y = y.to_f32; @z = z.to_f32; @w = w.to_f32
    end

    def initialize
      @x = @y = @z = 0_f32; @w = 1_f32
    end

    IDENTITY = Quat.new

    def self.identity : Quat; Quat.new; end

    def self.from_axis_angle(axis : Vec3, rad : Number) : Quat
      a = axis.normalized
      s = Math.sin(rad / 2)
      Quat.new(a.x * s, a.y * s, a.z * s, Math.cos(rad / 2))
    end

    # Yaw (Y), pitch (X), roll (Z) in radians, applied as Y * X * Z.
    def self.from_euler(pitch : Number, yaw : Number, roll : Number) : Quat
      from_axis_angle(Vec3::UP, yaw) * from_axis_angle(Vec3::RIGHT, pitch) * from_axis_angle(Vec3::BACK, roll)
    end

    def self.from_euler(v : Vec3) : Quat; from_euler(v.x, v.y, v.z); end

    def self.look_rotation(forward : Vec3, up : Vec3 = Vec3::UP) : Quat
      f = forward.normalized
      up = (up.dot(f).abs > 0.999 ? (f.y.abs > 0.9 ? Vec3::BACK : Vec3::UP) : up)
      r = f.cross(up).normalized
      u = r.cross(f)
      # Rotation matrix columns: right, up, back (-forward), row-major mRC below.
      m00 = r.x; m01 = u.x; m02 = -f.x
      m10 = r.y; m11 = u.y; m12 = -f.y
      m20 = r.z; m21 = u.z; m22 = -f.z
      trace = m00 + m11 + m22
      if trace > 0
        s = Math.sqrt(trace + 1.0) * 2
        Quat.new((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
      elsif m00 > m11 && m00 > m22
        s = Math.sqrt(1.0 + m00 - m11 - m22) * 2
        Quat.new(0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
      elsif m11 > m22
        s = Math.sqrt(1.0 + m11 - m00 - m22) * 2
        Quat.new((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
      else
        s = Math.sqrt(1.0 + m22 - m00 - m11) * 2
        Quat.new((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
      end
    end

    def *(o : Quat) : Quat
      Quat.new(
        @w * o.x + @x * o.w + @y * o.z - @z * o.y,
        @w * o.y - @x * o.z + @y * o.w + @z * o.x,
        @w * o.z + @x * o.y - @y * o.x + @z * o.w,
        @w * o.w - @x * o.x - @y * o.y - @z * o.z)
    end

    # Rotate a vector.
    def *(v : Vec3) : Vec3
      q = Vec3.new(@x, @y, @z)
      t = q.cross(v) * 2
      v + t * @w + q.cross(t)
    end

    def ==(o : Quat) : Bool; @x == o.x && @y == o.y && @z == o.z && @w == o.w; end
    def conjugate : Quat; Quat.new(-@x, -@y, -@z, @w); end
    def inverse : Quat; conjugate / length_squared; end
    def /(s : Number) : Quat; Quat.new(@x / s, @y / s, @z / s, @w / s); end
    def dot(o : Quat) : Float32; @x * o.x + @y * o.y + @z * o.z + @w * o.w; end
    def length_squared : Float32; dot(self); end
    def length : Float32; Math.sqrt(length_squared).to_f32; end

    def normalized : Quat
      l = length
      l > 0 ? self / l : Quat::IDENTITY
    end

    def slerp(o : Quat, t : Number) : Quat
      d = dot(o)
      b = o
      if d < 0
        b = Quat.new(-o.x, -o.y, -o.z, -o.w)
        d = -d
      end
      if d > 0.9995
        return Quat.new(@x + (b.x - @x) * t, @y + (b.y - @y) * t, @z + (b.z - @z) * t, @w + (b.w - @w) * t).normalized
      end
      theta0 = Math.acos(d)
      theta = theta0 * t
      s0 = Math.cos(theta) - d * Math.sin(theta) / Math.sin(theta0)
      s1 = Math.sin(theta) / Math.sin(theta0)
      Quat.new(@x * s0 + b.x * s1, @y * s0 + b.y * s1, @z * s0 + b.z * s1, @w * s0 + b.w * s1)
    end

    def to_mat4 : Mat4
      xx = @x * @x; yy = @y * @y; zz = @z * @z
      xy = @x * @y; xz = @x * @z; yz = @y * @z
      wx = @w * @x; wy = @w * @y; wz = @w * @z
      m = Mat4.identity
      m[0, 0] = 1 - 2 * (yy + zz); m[1, 0] = 2 * (xy - wz);     m[2, 0] = 2 * (xz + wy)
      m[0, 1] = 2 * (xy + wz);     m[1, 1] = 1 - 2 * (xx + zz); m[2, 1] = 2 * (yz - wx)
      m[0, 2] = 2 * (xz - wy);     m[1, 2] = 2 * (yz + wx);     m[2, 2] = 1 - 2 * (xx + yy)
      m
    end

    # Euler angles (pitch, yaw, roll) — approximate inverse of from_euler.
    def to_euler : Vec3
      sinp = 2 * (@w * @x - @y * @z)
      pitch = sinp.abs >= 1 ? Math.copysign(Math::PI / 2, sinp) : Math.asin(sinp)
      yaw = Math.atan2(2 * (@w * @y + @x * @z), 1 - 2 * (@x * @x + @y * @y))
      roll = Math.atan2(2 * (@w * @z + @x * @y), 1 - 2 * (@x * @x + @z * @z))
      Vec3.new(pitch, yaw, roll)
    end

    def forward : Vec3; self * Vec3::FORWARD; end
    def up : Vec3; self * Vec3::UP; end
    def right : Vec3; self * Vec3::RIGHT; end

    def approx?(o : Quat, eps = 1e-4) : Bool
      (@x - o.x).abs <= eps && (@y - o.y).abs <= eps && (@z - o.z).abs <= eps && (@w - o.w).abs <= eps
    end

    def to_s(io : IO) : Nil; io << "Quat(" << @x << ", " << @y << ", " << @z << ", " << @w << ")"; end
  end
end
