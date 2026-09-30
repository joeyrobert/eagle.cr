module Portal3
  # Builds a copy of a box mesh with an elliptical opening cut through one face.
  #
  # A portal is a hole in a wall, not a decal on one. While the off-screen portal view
  # is rendering, the wall the destination is set into is hidden so the virtual camera
  # can see past it. Swapping in this mesh for the duration of that render leaves the
  # wall standing everywhere except the opening, which is what a real portal looks
  # like. The original mesh is restored immediately afterwards.
  module PortalHole
    extend self

    # Rebuilds *size* as a box, cutting an opening into the face pointing along
    # *local_normal*. *center* is the opening's centre in the box's own space, and
    # *radii* are its half-extents along the two axes that span that face.
    def build(size : Vec3, local_normal : Vec3, center : Vec3, radii : Vec2,
              segments : Int32 = 48) : Mesh
      mesh = Mesh.new("portal_wall")
      n = axis_of(local_normal)
      sign = component(local_normal, n) > 0 ? 1 : -1
      u = (n + 1) % 3
      v = (n + 2) % 3
      eu = component(size, u) / 2
      ev = component(size, v) / 2

      # The four sides of the box, both faces of each, then the holed one.
      [0, 1, 2].each do |axis|
        next if axis == n
        add_solid_face(mesh, size, axis, 1)
        add_solid_face(mesh, size, axis, -1)
      end
      add_holed_face(mesh, size, n, sign, u, v, eu, ev, component(center, u), component(center, v), radii, segments)
      mesh
    end

    # An ordinary quad on one face of the box.
    private def add_solid_face(mesh : Mesh, size : Vec3, axis : Int32, sign : Int32) : Nil
      u = (axis + 1) % 3
      v = (axis + 2) % 3
      eu = component(size, u) / 2
      ev = component(size, v) / 2
      normal = axis_vector(axis, sign)
      a = point(axis, sign * component(size, axis) / 2, u, -eu, v, -ev)
      b = point(axis, sign * component(size, axis) / 2, u, +eu, v, -ev)
      c = point(axis, sign * component(size, axis) / 2, u, +eu, v, +ev)
      d = point(axis, sign * component(size, axis) / 2, u, -eu, v, +ev)
      add_quad(mesh, [a, b, c, d], u, -eu, eu, v, -ev, ev, normal)
    end

    # The face carrying the opening. Walking once around the ellipse and pairing each
    # point with where the same ray leaves the face gives a ring of quads, which is
    # the rectangle with an ellipse removed from it.
    private def add_holed_face(mesh : Mesh, size : Vec3, n : Int32, sign : Int32,
                               u : Int32, v : Int32, eu : Float32, ev : Float32,
                               cu : Float32, cv : Float32, radii : Vec2,
                               segments : Int32) : Nil
      normal = axis_vector(n, sign)
      plane = sign * component(size, n) / 2
      # Keep the opening inside the face, so the ring never turns inside out.
      ru = Math.min(radii.x, eu - cu.abs).clamp(0.01_f32, eu)
      rv = Math.min(radii.y, ev - cv.abs).clamp(0.01_f32, ev)
      # Face bounds in the u and v directions.
      bu0 = -eu
      bu1 = eu
      bv0 = -ev
      bv1 = ev

      inner = [] of Vec2
      outer = [] of Vec2
      (0..segments).each do |i|
        angle = Math::TAU * i / segments
        ca = Math.cos(angle).to_f32
        cb = Math.sin(angle).to_f32
        inner << v2(cu + ca * ru, cv + cb * rv)
        # How far the ray from the centre travels before it leaves the face.
        ta = ca.abs < 1e-6 ? Float32::INFINITY : ((ca > 0 ? bu1 : bu0) - cu) / ca
        tb = cb.abs < 1e-6 ? Float32::INFINITY : ((cb > 0 ? bv1 : bv0) - cv) / cb
        t = Math.min(ta, tb)
        outer << v2(cu + ca * t, cv + cb * t)
      end

      segments.times do |i|
        j = i + 1
        quad = [
          point(n, plane, u, inner[i].x, v, inner[i].y),
          point(n, plane, u, outer[i].x, v, outer[i].y),
          point(n, plane, u, outer[j].x, v, outer[j].y),
          point(n, plane, u, inner[j].x, v, inner[j].y),
        ]
        add_quad(mesh, quad, u, bu0, bu1, v, bv0, bv1, normal)
      end
    end

    # A point on the box surface, given its coordinates along the two face axes.
    private def point(axis : Int32, axis_value : Float32, u : Int32, uv : Float32,
                      v : Int32, vv : Float32) : Vec3
      coords = [0_f32, 0_f32, 0_f32]
      coords[axis] = axis_value
      coords[u] = uv
      coords[v] = vv
      v3(coords[0], coords[1], coords[2])
    end

    private def axis_vector(axis : Int32, sign : Int32) : Vec3
      axis == 0 ? v3(sign, 0, 0) : (axis == 1 ? v3(0, sign, 0) : v3(0, 0, sign))
    end

    private def axis_of(v : Vec3) : Int32
      v.x.abs > 0.5 ? 0 : (v.y.abs > 0.5 ? 1 : 2)
    end

    # One component of a vector, by axis index.
    private def component(v : Vec3, axis : Int32) : Float32
      axis == 0 ? v.x : (axis == 1 ? v.y : v.z)
    end

    # Emits a quad, choosing the winding that puts *normal* on the front, and gives it
    # planar UVs across the face so the panel texture still tiles to the same density.
    private def add_quad(mesh : Mesh, points : Array(Vec3), u : Int32, u0 : Float32,
                         u1 : Float32, v : Int32, v0 : Float32, v1 : Float32,
                         normal : Vec3) : Nil
      # UVs run 0..1 across the face, matching the box mesh this one replaces, so the
      # panel texture keeps the same density once the opening is cut.
      ids = points.map do |p|
        a = (component(p, u) - u0) / (u1 - u0)
        b = (component(p, v) - v0) / (v1 - v0)
        mesh.add_vertex(p, normal, v2(a, b))
      end
      a, b, c, d = ids
      if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) < 0
        mesh.add_quad(a, d, c, b)
      else
        mesh.add_quad(a, b, c, d)
      end
    end
  end
end
