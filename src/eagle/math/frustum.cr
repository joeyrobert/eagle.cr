module Eagle
  # The six planes of a camera's view volume, for culling things that can't be seen.
  #
  # Build one from a combined projection and view matrix. `Renderer3D` uses it to skip meshes
  # outside the camera and outside the shadow map; use it yourself to skip work for
  # off-screen objects.
  #
  # ```
  # cam = Camera3D.new(position: v3(0, 2, 10))
  # frustum = Frustum.new(cam.projection(16 / 9) * cam.view)
  # frustum.intersects?(AABB.new(v3(-1, 0, -1), v3(1, 2, 1))) # => true, in front of the camera
  # frustum.contains?(v3(0, 0, 20))                           # => false, behind it
  # ```
  struct Frustum
    # Plane normals (xyz) and offsets (w), pointing inward: left, right, bottom, top, near, far.
    getter planes : StaticArray(Vec4, 6)

    # Extracts the planes from a projection * view matrix (Gribb/Hartmann).
    def initialize(m : Mat4)
      r0 = Vec4.new(m[0, 0], m[1, 0], m[2, 0], m[3, 0])
      r1 = Vec4.new(m[0, 1], m[1, 1], m[2, 1], m[3, 1])
      r2 = Vec4.new(m[0, 2], m[1, 2], m[2, 2], m[3, 2])
      r3 = Vec4.new(m[0, 3], m[1, 3], m[2, 3], m[3, 3])
      raw = StaticArray[r3 + r0, r3 - r0, r3 + r1, r3 - r1, r3 + r2, r3 - r2]
      @planes = raw.map do |p|
        len = Math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
        len > 0 ? p / len : p
      end
    end

    # True when the point is inside the volume.
    def contains?(p : Vec3) : Bool
      @planes.all? { |pl| pl.x * p.x + pl.y * p.y + pl.z * p.z + pl.w >= 0 }
    end

    # True when the box is at least partly inside. It errs on the side of true near corners.
    def intersects?(box : AABB) : Bool
      c = box.center; e = box.half
      @planes.each do |pl|
        r = e.x * pl.x.abs + e.y * pl.y.abs + e.z * pl.z.abs
        return false if pl.x * c.x + pl.y * c.y + pl.z * c.z + pl.w < -r
      end
      true
    end

    # True when a mesh with local *bounds* drawn with *transform* is at least partly inside,
    # without building the transformed box.
    def intersects?(bounds : AABB, transform : Mat4) : Bool
      c = transform.transform_point(bounds.center)
      e = bounds.half
      # world-space half extents of the rotated box (Arvo)
      ex = transform[0, 0].abs * e.x + transform[1, 0].abs * e.y + transform[2, 0].abs * e.z
      ey = transform[0, 1].abs * e.x + transform[1, 1].abs * e.y + transform[2, 1].abs * e.z
      ez = transform[0, 2].abs * e.x + transform[1, 2].abs * e.y + transform[2, 2].abs * e.z
      intersects?(AABB.from_center(c, Vec3.new(ex, ey, ez)))
    end
  end
end
