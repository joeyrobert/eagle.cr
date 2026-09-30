require "./portal_camera"
require "./portal_hole"

module Portal3
  # Where a portal sits in the world, and the orthonormal basis that fixes its
  # orientation. The basis is stored as three vectors rather than a quaternion because
  # the teleport transform is a direct product of them.
  struct Placement
    # Half-extents of the elliptical opening, matching an Aperture door frame.
    HALF_WIDTH  = 0.45_f32
    HALF_HEIGHT = 0.92_f32

    getter position : Vec3
    getter normal : Vec3
    getter up : Vec3
    getter right : Vec3

    def initialize(@position : Vec3, @normal : Vec3, @up : Vec3)
      @normal = @normal.normalized
      # Re-orthogonalise so the basis stays valid however the up vector was chosen.
      r = @up.cross(@normal).normalized
      @right = r
      @up = @normal.cross(r).normalized
    end

    # Builds a placement from a surface hit. Walls align to world up the way Portal's
    # portals do; floors and ceilings fall back to the player's own up so they read
    # right when looked at from above.
    def self.from_hit(point : Vec3, normal : Vec3, view_up : Vec3 = Vec3::UP) : Placement
      n = normal.normalized
      up = if n.dot(Vec3::UP).abs > 0.98
             fallback = view_up - n * view_up.dot(n)
             fallback.normalized.zero? ? Vec3::FORWARD : fallback.normalized
           else
             (Vec3::UP - n * n.dot(Vec3::UP)).normalized
           end
      Placement.new(point, n, up)
    end

    # True when *point* falls inside the elliptical opening.
    def contains?(point : Vec3) : Bool
      d = point - @position
      x = d.dot(@right) / HALF_WIDTH
      y = d.dot(@up) / HALF_HEIGHT
      x * x + y * y <= 1.0
    end

    # Distance in front of the portal plane. Positive is on the open side.
    def in_front(point : Vec3) : Float32
      (point - @position).dot(@normal)
    end

    # The matrix whose columns are the basis vectors, so it maps portal-local axes
    # into world space. Used to build the teleport transform.
    def to_matrix : Mat4
      Placement.basis_matrix(@right, @up, @normal)
    end

    def self.basis_matrix(right : Vec3, up : Vec3, forward : Vec3) : Mat4
      m = Mat4.identity
      {right, up, forward}.each_with_index do |axis, col|
        m[col, 0] = axis.x
        m[col, 1] = axis.y
        m[col, 2] = axis.z
      end
      m
    end
  end

  # One end of a linked portal pair. Holds the off-screen view that makes the opening
  # genuinely see-through, plus the rim that gives it its glow.
  class Portal
    getter placement : Placement?
    getter? open = false
    getter color : Color

    # The body the portal is set into. It is hidden while this portal's view is being
    # rendered, because the virtual camera looks straight at it and would otherwise see
    # the back of the wall rather than the room beyond.
    getter host : Node3D?

    # The host's mesh with this opening cut in it, built once when the portal opens.
    @holed : Mesh? = nil
    @host_mesh : MeshInstance3D? = nil
    @original_mesh : Mesh? = nil

    @node : MeshInstance3D? = nil
    @rim : MeshInstance3D? = nil
    @canvas : Canvas
    @camera : PortalCamera? = nil
    @surface_mat : Material
    @rim_mat : Material

    # The off-screen buffer matches the opening's aspect, so the rendered view can be
    # mapped straight onto the ellipse with no distortion.
    def self.view_size(width : Int32) : {Int32, Int32}
      {width, (width * Placement::HALF_HEIGHT / Placement::HALF_WIDTH).to_i}
    end

    def initialize(@color : Color, @root : Node3D, width : Int32, height : Int32)
      @canvas = Canvas.new(width, height, depth: true)
      @surface_mat = Material.new(Color::WHITE, texture: @canvas.texture, unlit: true)
      # The opening is a hole, not a decal: never let the texture's alpha discard it.
      @surface_mat.alpha_cutoff = 0.0_f32
      @rim_mat = Material.new(@color, unlit: true, emissive: @color)
    end

    def surface_material : Material
      @surface_mat
    end

    def rim_material : Material
      @rim_mat
    end

    # Opens a portal at *placement*, creating its meshes the first time.
    def open_at(placement : Placement, host : Node3D? = nil) : Nil
      @placement = placement
      @host = host
      @open = true
      build_holed_wall(placement, host)
      unless node = @node
        node = MeshInstance3D.new(Portal.ellipse_mesh, @surface_mat)
        node.cast_shadows = false
        @root.add(node)
        @node = node
      end
      unless rim = @rim
        rim = MeshInstance3D.new(Portal.rim_mesh, @rim_mat)
        rim.cast_shadows = false
        @root.add(rim)
        @rim = rim
      end
      # Aim -Z into the wall, which leaves the mesh's +Z facing out of the room.
      target = placement.position - placement.normal
      # Lift both meshes clear of the wall face. Sitting exactly on it would lose the
      # depth test against the panel and the portal would be invisible.
      node.position = placement.position + placement.normal * 0.03_f32
      node.look_at(target, placement.up)
      rim.position = placement.position + placement.normal * 0.022_f32
      rim.look_at(target, placement.up)
      node.visible = true
      rim.visible = true
    end

    # Cuts a copy of the host wall with the opening in it, and remembers both meshes so
    # the swap can be undone after the off-screen render.
    private def build_holed_wall(placement : Placement, host : Node3D?) : Nil
      @holed = nil
      @host_mesh = nil
      @original_mesh = nil
      return unless host
      instance = host.children.first?.as(MeshInstance3D)
      original = instance.try(&.mesh)
      return unless instance && original
      local_center = placement.position - host.global_position
      local_normal = placement.normal
      axis = local_normal.x.abs > 0.5 ? 0 : (local_normal.y.abs > 0.5 ? 1 : 2)
      u = (axis + 1) % 3
      v = (axis + 2) % 3
      # The opening's radii along the face's two axes, taken from its own basis.
      # Each face axis gets the width the opening actually spans along it. On an
      # axis-aligned wall one of the two basis vectors is zero, so this picks the
      # right one rather than adding both.
      ru = component(placement.right, u).abs * Placement::HALF_WIDTH +
           component(placement.up, u).abs * Placement::HALF_HEIGHT
      rv = component(placement.right, v).abs * Placement::HALF_WIDTH +
           component(placement.up, v).abs * Placement::HALF_HEIGHT
      size = original.bounds.size
      @holed = PortalHole.build(size, local_normal, local_center, v2(ru, rv))
      @host_mesh = instance
      @original_mesh = original
    end

    # One component of a vector, by axis index.
    private def component(v : Vec3, axis : Int32) : Float32
      axis == 0 ? v.x : (axis == 1 ? v.y : v.z)
    end

    # Swaps the host wall to the holed version for one off-screen render.
    def show_hole : Nil
      return unless h = @holed
      return unless m = @host_mesh
      m.mesh = h
    end

    # Puts the host wall back.
    def hide_hole : Nil
      return unless m = @host_mesh
      m.mesh = @original_mesh if @original_mesh
    end

    def close : Nil
      @open = false
      @placement = nil
      @host = nil
      @node.try(&.visible = false)
      @rim.try(&.visible = false)
    end

    def canvas : Canvas
      @canvas
    end

    def node : MeshInstance3D?
      @node
    end

    def rim_node : MeshInstance3D?
      @rim
    end

    # The camera used to render this portal's view. It is never parented to the tree,
    # so `make_current` is the only way it becomes active. It is a PortalCamera so the
    # destination wall can be clipped out of the view.
    def camera : PortalCamera
      @camera ||= begin
        cam = PortalCamera.new
        # Parented to the tree so its global transform is a real one, the same as any
        # other node, rather than depending on how a detached node resolves it.
        @root.add(cam)
        cam
      end
    end

    def set_visible(visible : Bool) : Nil
      @node.try(&.visible = visible)
      @rim.try(&.visible = visible)
    end

    @@ellipse : Mesh? = nil
    @@rim : Mesh? = nil

    # The elliptical opening, a triangle fan whose UVs span the whole canvas so the
    # rendered view maps across it like a window.
    def self.ellipse_mesh : Mesh
      @@ellipse ||= begin
        mesh = Mesh.new("portal")
        segments = 48
        center = mesh.add_vertex(Vec3::ZERO, Vec3::BACK, v2(0.5, 0.5))
        ring = [] of UInt32
        (0..segments).each do |i|
          a = Math::TAU * i / segments
          x = Math.cos(a) * Placement::HALF_WIDTH
          y = Math.sin(a) * Placement::HALF_HEIGHT
          uv = v2(0.5 + x / (Placement::HALF_WIDTH * 2), 0.5 + y / (Placement::HALF_HEIGHT * 2))
          ring << mesh.add_vertex(v3(x, y, 0), Vec3::BACK, uv)
        end
        segments.times { |i| mesh.add_triangle(center, ring[i], ring[i + 1]) }
        mesh
      end
    end

    # An annulus just larger than the opening, which reads as the glowing rim.
    def self.rim_mesh : Mesh
      @@rim ||= begin
        mesh = Mesh.new("portal_rim")
        segments = 48
        outer = [] of UInt32
        inner = [] of UInt32
        (0..segments).each do |i|
          a = Math::TAU * i / segments
          cs = Math.cos(a)
          sn = Math.sin(a)
          outer << mesh.add_vertex(v3(cs * Placement::HALF_WIDTH * 1.14, sn * Placement::HALF_HEIGHT * 1.07, 0), Vec3::BACK, v2(0.5, 0.5))
          inner << mesh.add_vertex(v3(cs * Placement::HALF_WIDTH, sn * Placement::HALF_HEIGHT, 0), Vec3::BACK, v2(0.5, 0.5))
        end
        segments.times do |i|
          j = i + 1
          mesh.add_quad(outer[i], outer[j], inner[j], inner[i])
        end
        mesh
      end
    end
  end

  # The rigid transform that carries a point, a velocity or a direction from one
  # opening to the other. These are free functions over Placements so the traversal
  # maths can be tested without a GPU device.
  module Teleport
    extend self

    # The rigid transform from *src* space to *dst* space.
    #
    # R maps src's right to minus dst's right, and src's up to dst's up, so the
    # horizontal axis is mirrored and exits feel handedness-flipped. It maps src's
    # forward to MINUS dst's forward, which is what makes a player emerge travelling
    # away from the destination wall rather than into it.
    #
    # Expressed as R = D * F * S^-1. F flips the right and forward axes and leaves up
    # alone; flipping only one of them would be a reflection, and a portal has to be a
    # proper rotation or momentum and handedness both come out wrong.
    def rotation(src : Placement, dst : Placement) : Mat4
      flip = Mat4.identity
      flip[0, 0] = -1
      flip[2, 2] = -1
      dst.to_matrix * flip * src.to_matrix.inverse
    end

    # Applies the src-to-dst transform to a world point.
    def point(src : Placement, dst : Placement, p : Vec3) : Vec3
      dst.position + rotation(src, dst).transform_dir(p - src.position)
    end

    # Applies only the rotation, for velocities and look directions.
    def direction(src : Placement, dst : Placement, v : Vec3) : Vec3
      rotation(src, dst).transform_dir(v)
    end

    # True when moving from *from* to *to* passes through the front of *src* and lands
    # inside both ellipses. This is the traversal test, run on the swept segment each
    # step so a fast exit can never skip over a portal.
    def crosses?(from : Vec3, to : Vec3, src : Placement, dst : Placement) : Bool
      d0 = src.in_front(from)
      d1 = src.in_front(to)
      return false unless d0 >= 0 && d1 < 0
      t = d0 / (d0 - d1)
      hit = from + (to - from) * t
      src.contains?(hit) && dst.contains?(hit + src.normal * 0.03_f32)
    end
  end

  # The two linked portals. Holds the endpoints and delegates the geometry to Teleport.
  class PortalPair
    def initialize(@blue : Portal, @orange : Portal)
    end

    def linked? : Bool
      @blue.open? && @orange.open?
    end

    def blue : Portal
      @blue
    end

    def orange : Portal
      @orange
    end

    # Moves a point through the portal from *src* to *dst*.
    def point(src : Placement, dst : Placement, p : Vec3) : Vec3
      Teleport.point(src, dst, p)
    end

    # Rotates a velocity or look direction into the destination's frame.
    def direction(src : Placement, dst : Placement, v : Vec3) : Vec3
      Teleport.direction(src, dst, v)
    end

    def crosses?(from : Vec3, to : Vec3, src : Placement, dst : Placement) : Bool
      Teleport.crosses?(from, to, src, dst)
    end
  end
end
