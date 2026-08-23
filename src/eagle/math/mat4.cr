module Eagle
  # 4x4 column-major matrix (OpenGL layout). `m[col, row]`.
  struct Mat4
    @m : StaticArray(Float32, 16)

    def initialize(@m : StaticArray(Float32, 16)); end

    def initialize
      @m = StaticArray(Float32, 16).new(0_f32)
    end

    def self.identity : Mat4
      m = Mat4.new
      m[0, 0] = 1; m[1, 1] = 1; m[2, 2] = 1; m[3, 3] = 1
      m
    end

    IDENTITY = identity

    def [](col : Int, row : Int) : Float32; @m[col * 4 + row]; end
    def []=(col : Int, row : Int, v : Number); @m[col * 4 + row] = v.to_f32; end
    def to_unsafe : Pointer(Float32); @m.to_unsafe; end
    def data : StaticArray(Float32, 16); @m; end
    def to_a : Array(Float32); @m.to_a; end

    def ==(o : Mat4) : Bool; @m == o.data; end

    def *(o : Mat4) : Mat4
      r = Mat4.new
      4.times do |c|
        4.times do |row|
          sum = 0_f32
          4.times { |k| sum += self[k, row] * o[c, k] }
          r[c, row] = sum
        end
      end
      r
    end

    def *(v : Vec4) : Vec4
      Vec4.new(
        self[0, 0] * v.x + self[1, 0] * v.y + self[2, 0] * v.z + self[3, 0] * v.w,
        self[0, 1] * v.x + self[1, 1] * v.y + self[2, 1] * v.z + self[3, 1] * v.w,
        self[0, 2] * v.x + self[1, 2] * v.y + self[2, 2] * v.z + self[3, 2] * v.w,
        self[0, 3] * v.x + self[1, 3] * v.y + self[2, 3] * v.z + self[3, 3] * v.w)
    end

    # Transforms a point (w = 1) and performs the perspective divide.
    def transform_point(v : Vec3) : Vec3
      r = self * v.to_vec4(1)
      r.w == 0 || r.w == 1 ? r.xyz : r.homogenized
    end

    # Transforms a direction (w = 0).
    def transform_dir(v : Vec3) : Vec3
      (self * v.to_vec4(0)).xyz
    end

    def self.translation(v : Vec3) : Mat4
      m = identity
      m[3, 0] = v.x; m[3, 1] = v.y; m[3, 2] = v.z
      m
    end

    def self.translation(x : Number, y : Number, z : Number = 0) : Mat4
      translation(Vec3.new(x, y, z))
    end

    def self.scale(v : Vec3) : Mat4
      m = Mat4.new
      m[0, 0] = v.x; m[1, 1] = v.y; m[2, 2] = v.z; m[3, 3] = 1
      m
    end

    def self.scale(s : Number) : Mat4; scale(Vec3.new(s, s, s)); end

    def self.rotation_x(rad : Number) : Mat4
      c = Math.cos(rad).to_f32; s = Math.sin(rad).to_f32
      m = identity
      m[1, 1] = c; m[2, 1] = -s; m[1, 2] = s; m[2, 2] = c
      m
    end

    def self.rotation_y(rad : Number) : Mat4
      c = Math.cos(rad).to_f32; s = Math.sin(rad).to_f32
      m = identity
      m[0, 0] = c; m[2, 0] = s; m[0, 2] = -s; m[2, 2] = c
      m
    end

    def self.rotation_z(rad : Number) : Mat4
      c = Math.cos(rad).to_f32; s = Math.sin(rad).to_f32
      m = identity
      m[0, 0] = c; m[1, 0] = -s; m[0, 1] = s; m[1, 1] = c
      m
    end

    def self.rotation(axis : Vec3, rad : Number) : Mat4
      Quat.from_axis_angle(axis, rad).to_mat4
    end

    def self.orthographic(left : Number, right : Number, bottom : Number, top : Number, near : Number = -1, far : Number = 1) : Mat4
      m = Mat4.new
      m[0, 0] = 2 / (right - left)
      m[1, 1] = 2 / (top - bottom)
      m[2, 2] = -2 / (far - near)
      m[3, 0] = -(right + left) / (right - left)
      m[3, 1] = -(top + bottom) / (top - bottom)
      m[3, 2] = -(far + near) / (far - near)
      m[3, 3] = 1
      m
    end

    def self.perspective(fov_y_rad : Number, aspect : Number, near : Number, far : Number) : Mat4
      f = 1 / Math.tan(fov_y_rad / 2)
      m = Mat4.new
      m[0, 0] = f / aspect
      m[1, 1] = f
      m[2, 2] = (far + near) / (near - far)
      m[2, 3] = -1
      m[3, 2] = (2 * far * near) / (near - far)
      m
    end

    def self.look_at(eye : Vec3, target : Vec3, up : Vec3 = Vec3::UP) : Mat4
      f = (target - eye).normalized
      s = f.cross(up).normalized
      u = s.cross(f)
      m = identity
      m[0, 0] = s.x; m[1, 0] = s.y; m[2, 0] = s.z
      m[0, 1] = u.x; m[1, 1] = u.y; m[2, 1] = u.z
      m[0, 2] = -f.x; m[1, 2] = -f.y; m[2, 2] = -f.z
      m[3, 0] = -s.dot(eye)
      m[3, 1] = -u.dot(eye)
      m[3, 2] = f.dot(eye)
      m
    end

    # Translation * Rotation * Scale
    def self.trs(t : Vec3, r : Quat, s : Vec3) : Mat4
      translation(t) * r.to_mat4 * scale(s)
    end

    def transposed : Mat4
      r = Mat4.new
      4.times { |c| 4.times { |row| r[row, c] = self[c, row] } }
      r
    end

    def translation : Vec3; Vec3.new(self[3, 0], self[3, 1], self[3, 2]); end

    def determinant : Float32
      a = @m
      a[0]*a[5]*a[10]*a[15] - a[0]*a[5]*a[11]*a[14] - a[0]*a[6]*a[9]*a[15] + a[0]*a[6]*a[11]*a[13] +
      a[0]*a[7]*a[9]*a[14] - a[0]*a[7]*a[10]*a[13] - a[1]*a[4]*a[10]*a[15] + a[1]*a[4]*a[11]*a[14] +
      a[1]*a[6]*a[8]*a[15] - a[1]*a[6]*a[11]*a[12] - a[1]*a[7]*a[8]*a[14] + a[1]*a[7]*a[10]*a[12] +
      a[2]*a[4]*a[9]*a[15] - a[2]*a[4]*a[11]*a[13] - a[2]*a[5]*a[8]*a[15] + a[2]*a[5]*a[11]*a[12] +
      a[2]*a[7]*a[8]*a[13] - a[2]*a[7]*a[9]*a[12] - a[3]*a[4]*a[9]*a[14] + a[3]*a[4]*a[10]*a[13] +
      a[3]*a[5]*a[8]*a[14] - a[3]*a[5]*a[10]*a[12] - a[3]*a[6]*a[8]*a[13] + a[3]*a[6]*a[9]*a[12]
    end

    def inverse : Mat4
      m = @m
      inv = StaticArray(Float32, 16).new(0_f32)
      inv[0] = m[5]*m[10]*m[15] - m[5]*m[11]*m[14] - m[9]*m[6]*m[15] + m[9]*m[7]*m[14] + m[13]*m[6]*m[11] - m[13]*m[7]*m[10]
      inv[4] = -m[4]*m[10]*m[15] + m[4]*m[11]*m[14] + m[8]*m[6]*m[15] - m[8]*m[7]*m[14] - m[12]*m[6]*m[11] + m[12]*m[7]*m[10]
      inv[8] = m[4]*m[9]*m[15] - m[4]*m[11]*m[13] - m[8]*m[5]*m[15] + m[8]*m[7]*m[13] + m[12]*m[5]*m[11] - m[12]*m[7]*m[9]
      inv[12] = -m[4]*m[9]*m[14] + m[4]*m[10]*m[13] + m[8]*m[5]*m[14] - m[8]*m[6]*m[13] - m[12]*m[5]*m[10] + m[12]*m[6]*m[9]
      inv[1] = -m[1]*m[10]*m[15] + m[1]*m[11]*m[14] + m[9]*m[2]*m[15] - m[9]*m[3]*m[14] - m[13]*m[2]*m[11] + m[13]*m[3]*m[10]
      inv[5] = m[0]*m[10]*m[15] - m[0]*m[11]*m[14] - m[8]*m[2]*m[15] + m[8]*m[3]*m[14] + m[12]*m[2]*m[11] - m[12]*m[3]*m[10]
      inv[9] = -m[0]*m[9]*m[15] + m[0]*m[11]*m[13] + m[8]*m[1]*m[15] - m[8]*m[3]*m[13] - m[12]*m[1]*m[11] + m[12]*m[3]*m[9]
      inv[13] = m[0]*m[9]*m[14] - m[0]*m[10]*m[13] - m[8]*m[1]*m[14] + m[8]*m[2]*m[13] + m[12]*m[1]*m[10] - m[12]*m[2]*m[9]
      inv[2] = m[1]*m[6]*m[15] - m[1]*m[7]*m[14] - m[5]*m[2]*m[15] + m[5]*m[3]*m[14] + m[13]*m[2]*m[7] - m[13]*m[3]*m[6]
      inv[6] = -m[0]*m[6]*m[15] + m[0]*m[7]*m[14] + m[4]*m[2]*m[15] - m[4]*m[3]*m[14] - m[12]*m[2]*m[7] + m[12]*m[3]*m[6]
      inv[10] = m[0]*m[5]*m[15] - m[0]*m[7]*m[13] - m[4]*m[1]*m[15] + m[4]*m[3]*m[13] + m[12]*m[1]*m[7] - m[12]*m[3]*m[5]
      inv[14] = -m[0]*m[5]*m[14] + m[0]*m[6]*m[13] + m[4]*m[1]*m[14] - m[4]*m[2]*m[13] - m[12]*m[1]*m[6] + m[12]*m[2]*m[5]
      inv[3] = -m[1]*m[6]*m[11] + m[1]*m[7]*m[10] + m[5]*m[2]*m[11] - m[5]*m[3]*m[10] - m[9]*m[2]*m[7] + m[9]*m[3]*m[6]
      inv[7] = m[0]*m[6]*m[11] - m[0]*m[7]*m[10] - m[4]*m[2]*m[11] + m[4]*m[3]*m[10] + m[8]*m[2]*m[7] - m[8]*m[3]*m[6]
      inv[11] = -m[0]*m[5]*m[11] + m[0]*m[7]*m[9] + m[4]*m[1]*m[11] - m[4]*m[3]*m[9] - m[8]*m[1]*m[7] + m[8]*m[3]*m[5]
      inv[15] = m[0]*m[5]*m[10] - m[0]*m[6]*m[9] - m[4]*m[1]*m[10] + m[4]*m[2]*m[9] + m[8]*m[1]*m[6] - m[8]*m[2]*m[5]
      det = m[0]*inv[0] + m[1]*inv[4] + m[2]*inv[8] + m[3]*inv[12]
      return Mat4.identity if det == 0
      inv_det = 1_f32 / det
      16.times { |i| inv[i] *= inv_det }
      Mat4.new(inv)
    end

    # Upper-left 3x3 as a Mat3 (for normal matrices).
    def to_mat3 : Mat3
      r = Mat3.new
      3.times { |c| 3.times { |row| r[c, row] = self[c, row] } }
      r
    end

    def approx?(o : Mat4, eps = 1e-4) : Bool
      16.times { |i| return false if (@m[i] - o.data[i]).abs > eps }
      true
    end

    def to_s(io : IO) : Nil
      4.times do |row|
        io << "[ "
        4.times { |c| io << self[c, row] << " " }
        io << "]\n"
      end
    end
  end

  # 3x3 column-major matrix.
  struct Mat3
    @m : StaticArray(Float32, 9)

    def initialize(@m : StaticArray(Float32, 9)); end
    def initialize; @m = StaticArray(Float32, 9).new(0_f32); end

    def self.identity : Mat3
      m = Mat3.new
      m[0, 0] = 1; m[1, 1] = 1; m[2, 2] = 1
      m
    end

    def [](col : Int, row : Int) : Float32; @m[col * 3 + row]; end
    def []=(col : Int, row : Int, v : Number); @m[col * 3 + row] = v.to_f32; end
    def to_unsafe : Pointer(Float32); @m.to_unsafe; end
    def data; @m; end

    def *(o : Mat3) : Mat3
      r = Mat3.new
      3.times do |c|
        3.times do |row|
          sum = 0_f32
          3.times { |k| sum += self[k, row] * o[c, k] }
          r[c, row] = sum
        end
      end
      r
    end

    def *(v : Vec3) : Vec3
      Vec3.new(
        self[0, 0] * v.x + self[1, 0] * v.y + self[2, 0] * v.z,
        self[0, 1] * v.x + self[1, 1] * v.y + self[2, 1] * v.z,
        self[0, 2] * v.x + self[1, 2] * v.y + self[2, 2] * v.z)
    end

    def transposed : Mat3
      r = Mat3.new
      3.times { |c| 3.times { |row| r[row, c] = self[c, row] } }
      r
    end

    def determinant : Float32
      self[0, 0] * (self[1, 1] * self[2, 2] - self[2, 1] * self[1, 2]) -
        self[1, 0] * (self[0, 1] * self[2, 2] - self[2, 1] * self[0, 2]) +
        self[2, 0] * (self[0, 1] * self[1, 2] - self[1, 1] * self[0, 2])
    end

    def inverse : Mat3
      det = determinant
      return Mat3.identity if det == 0
      r = Mat3.new
      r[0, 0] = (self[1, 1] * self[2, 2] - self[2, 1] * self[1, 2]) / det
      r[1, 0] = (self[2, 0] * self[1, 2] - self[1, 0] * self[2, 2]) / det
      r[2, 0] = (self[1, 0] * self[2, 1] - self[2, 0] * self[1, 1]) / det
      r[0, 1] = (self[2, 1] * self[0, 2] - self[0, 1] * self[2, 2]) / det
      r[1, 1] = (self[0, 0] * self[2, 2] - self[2, 0] * self[0, 2]) / det
      r[2, 1] = (self[2, 0] * self[0, 1] - self[0, 0] * self[2, 1]) / det
      r[0, 2] = (self[0, 1] * self[1, 2] - self[1, 1] * self[0, 2]) / det
      r[1, 2] = (self[1, 0] * self[0, 2] - self[0, 0] * self[1, 2]) / det
      r[2, 2] = (self[0, 0] * self[1, 1] - self[1, 0] * self[0, 1]) / det
      r
    end
  end
end
