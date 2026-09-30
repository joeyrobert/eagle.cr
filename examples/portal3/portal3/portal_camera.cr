module Portal3
  # A camera that can clip against an arbitrary plane instead of its own near plane.
  #
  # Portal views need this. The virtual camera sits in the destination room looking
  # back at the destination portal, and the wall that portal is set into sits between
  # that camera and everything the player should be able to see through the opening.
  # Skewing the near plane onto the portal's own plane removes the wall and everything
  # behind it, which is exactly the set of pixels that should not be in the view.
  #
  # This is Lengyel's oblique view frustum projection.
  class PortalCamera < Camera3D
    # The plane to clip against, in world space. A point on the plane, and the normal
    # of the half-space to keep.
    property clip_point : Vec3? = nil
    property clip_normal : Vec3? = nil

    def initialize
      super("portal_camera", Vec3::ZERO, 60, false)
    end

    # The plane expressed in this camera's own space, which is what the projection
    # maths needs.
    private def view_plane : {Vec4, Vec4}?
      point = @clip_point
      normal = @clip_normal
      return nil unless point && normal
      view = global_transform.inverse
      p = view.transform_point(point)
      n = (view.transform_point(point + normal) - p).normalized
      {p.to_vec4(1), n.to_vec4(0)}
    end

    def projection(aspect : Number) : Mat4
      m = super
      return m unless plane = view_plane
      cp, cn = plane
      # Mirror the clip normal's x and y into the corner of the frustum it points at.
      s = Vec4.new(cn.x >= 0 ? 1.0 : -1.0, cn.y >= 0 ? 1.0 : -1.0, 1.0, 1.0)
      inv = m.inverse
      q = inv * s
      denom = q.dot(cp)
      # A near-degenerate plane would blow the projection up; fall back to the normal one.
      return m if denom.abs < 1e-6
      c = q * (2.0 / denom)
      # Replace the third row with the clip plane, leaving the fourth row intact.
      m[0, 2] = c.x - m[0, 3]
      m[1, 2] = c.y - m[1, 3]
      m[2, 2] = c.z - m[2, 3]
      m[3, 2] = c.w - m[3, 3]
      m
    end
  end
end
