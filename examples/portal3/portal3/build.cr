module Portal3
  # Collision layers. The portal device casts only against LAYER_WHITE, which is what
  # makes white panels the only portalable surfaces and keeps the puzzles readable.
  module Layers
    WHITE  =          1_u32 # portalable wall panel
    PANEL  =          2_u32 # solid but not portalable
    DOOR   =          4_u32 # sliding doors and their frames
    HAZARD =          8_u32 # goo pit
    PROP   =         16_u32 # cubes and other pushable things
    GLASS  =         32_u32 # observation glass, blocks nothing
    ALL    = 0xFFFFFFFF_u32
  end

  # Shared material palette. One material per look keeps draw calls low and the
  # chambers visually consistent. Everything is built on first use, because materials
  # need a GPU device and the scene is not constructed until the engine has started.
  module Palette
    extend self

    @@white : Material? = nil
    @@panel : Material? = nil
    @@metal : Material? = nil
    @@floor : Material? = nil
    @@hazard : Material? = nil
    @@glass : Material? = nil
    @@cubes : Hash(CubeKind, Material)? = nil

    def white : Material
      @@white ||= Material.new(Color.hex("#ffffff"), texture: Textures.get(:white), shininess: 18, specular: 0.12)
    end

    def panel : Material
      @@panel ||= Material.new(Color.hex("#ffffff"), texture: Textures.get(:panel), shininess: 26, specular: 0.22)
    end

    def metal : Material
      @@metal ||= Material.new(Color.hex("#ffffff"), texture: Textures.get(:metal),
        shininess: 64, specular: 0.55, metallic: 0.7)
    end

    def floor : Material
      @@floor ||= Material.new(Color.hex("#ffffff"), texture: Textures.get(:floor), shininess: 22, specular: 0.15)
    end

    def hazard : Material
      @@hazard ||= Material.new(Color.hex("#ffffff"), texture: Textures.get(:hazard), shininess: 14, specular: 0.1)
    end

    # Weighted storage cubes, one per type. They are pale enough to read against the
    # chamber walls while still carrying their type colour.
    def cube(kind : CubeKind) : Material
      @@cubes ||= {} of CubeKind => Material
      @@cubes.try(&.[kind]?) || Material.new(kind.tint, texture: Textures.get(:white),
        shininess: 30, specular: 0.25).tap { |m| @@cubes.not_nil![kind] = m }
    end

    def glass : Material
      @@glass ||= begin
        m = Material.new(Color.new(0.5, 0.7, 0.85, 0.1), unlit: true, transparent: true)
        m.double_sided = true
        m
      end
    end

    # An unlit emissive colour, used for beams, indicators and portal rims.
    def glow(color : Color) : Material
      Material.new(color, unlit: true, emissive: color)
    end
  end

  # Small maths helpers shared by the moving parts.
  module Util
    extend self

    # Moves *value* toward *target* by at most *max_delta*, never overshooting.
    def approach(value : Float32, target : Float32, max_delta : Float32) : Float32
      if value < target
        Math.min(value + max_delta, target)
      else
        Math.max(value - max_delta, target)
      end
    end
  end

  # Builds chamber geometry. Every call adds a physics body and a matching mesh, so what
  # the player sees and what the player collides with can never drift apart.
  class Builder
    getter root : Node3D

    def initialize(@root : Node3D = SceneTree.root)
    end

    # Adds a box-shaped piece of chamber. Textures are scaled to world units so they
    # tile at a constant density however big the box is. *casts_shadow* is false for
    # ceilings and other overhead geometry, which would otherwise block the key light
    # and leave the room below them unlit.
    def box(center : Vec3, size : Vec3, material : Material = Palette.white,
            layer : UInt32 = Layers::WHITE, casts_shadow : Bool = true) : StaticBody3D
      body = StaticBody3D.new(position: center)
      body.box(size.x, size.y, size.z)
      body.layer = layer
      body.mask = Layers::ALL

      mat = material.dup
      mat.uv_scale = v3_tiles(size)
      instance = MeshInstance3D.new(Mesh.box(size.x, size.y, size.z), mat)
      instance.cast_shadows = casts_shadow
      body.add(instance)
      @root.add(body)
      body
    end

    # A wall panel, always portalable.
    def wall(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.white, Layers::WHITE)
    end

    # Structural trim, never portalable.
    def trim(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.panel, Layers::PANEL)
    end

    # The ceiling. White like the walls, and it never casts a shadow, so the room is
    # lit from above the way a test chamber is.
    def ceiling(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.white, Layers::WHITE, false)
    end

    # Floors are white panels and accept portals, the way they do in the films. A
    # non-portalable floor would rule out dropping a cube through one, which is a
    # large part of the language the chambers are built from.
    def floor(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.white, Layers::WHITE)
    end

    def metal(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.metal, Layers::PANEL)
    end

    # A hazard-striped lip around the edge of a pit.
    def hazard_strip(center : Vec3, size : Vec3) : StaticBody3D
      box(center, size, Palette.hazard, Layers::PANEL)
    end

    # A non-colliding decoration, for lights, trim and background detail.
    def decor(mesh : Mesh, material : Material, position : Vec3 = Vec3::ZERO,
              rotation : Quat = Quat::IDENTITY) : MeshInstance3D
      node = MeshInstance3D.new(mesh, material, position: position)
      node.rotation = rotation
      node.cast_shadows = false
      @root.add(node)
      node
    end

    # A wall light: an unlit emissive slab, no physics.
    def light_panel(position : Vec3, size : Vec3, color : Color = Color.hex("#fff6e0"),
                    rotation : Quat = Quat::IDENTITY) : MeshInstance3D
      decor(Mesh.box(size.x, size.y, size.z), Palette.glow(color), position, rotation)
    end

    # Chooses a UV scale so one texture tile covers roughly a metre on each face.
    private def v3_tiles(size : Vec3) : Vec2
      u = size.x.abs > size.z.abs ? size.x : size.z
      u = 1_f32 if u < 0.01
      v = size.y.abs
      v = u if v < 0.01
      v2(u, v)
    end
  end
end
