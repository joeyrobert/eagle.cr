module Portal3
  # Anything a button can switch. Doors and lifts both implement it, which keeps the
  # signal wiring in the level files to a single list.
  module Receiver
    def receive(value : Bool) : Nil
    end

    def set_receivers(list : Array(Receiver)) : Nil
      @receivers = list
    end
  end

  # The three storage cube types. Each presses only its own buttons, which is what
  # turns a room with one cube type into a puzzle about matching them up.
  enum CubeKind
    Standard
    Red
    Blue

    # The colour each type is painted and the light its buttons show.
    def tint : Color
      case self
      in Standard then Color.hex("#e8e6dc")
      in Red      then Color.hex("#e0483c")
      in Blue     then Color.hex("#4a86e8")
      end
    end

    def glow : Color
      case self
      in Standard then Color.hex("#ffb648")
      in Red      then Color.hex("#ff6a5a")
      in Blue     then Color.hex("#6aa8ff")
      end
    end

    # A short tag for the self test's check names.
    def label : String
      case self
      in Standard then "standard"
      in Red      then "red"
      in Blue     then "blue"
      end
    end
  end

  # Something standing on a button: the player, or a cube of some type.
  record Occupant, position : Vec3, kind : CubeKind, is_player : Bool

  # Passes the opposite of what it receives, so a second button can drive the same
  # target in the other direction.
  class Inverter
    include Receiver

    def initialize(@target : Receiver)
    end

    def receive(value : Bool) : Nil
      @target.receive(!value)
    end
  end

  # A floor plate. Pressed by the player standing on it or by a weighted cube resting
  # on it, which is the whole basis of the game's puzzle language.
  class Button
    SIZE   =  1.0_f32
    HEIGHT = 0.12_f32

    getter receivers = [] of Receiver
    property? pressed = false

    # Where the plate sits, so a test or a level can refer to it.
    getter position : Vec3

    @plate : MeshInstance3D
    @light : MeshInstance3D
    @ring : MeshInstance3D
    @base : StaticBody3D
    @pulse = 0_f32

    # Builds a floor button at *position*. The surface is non-portalable.
    def initialize(builder : Builder, @position : Vec3, @kind : CubeKind = CubeKind::Standard)
      @base = builder.box(position + v3(0, -HEIGHT / 2 - 0.04_f32, 0), v3(SIZE, 0.08_f32, SIZE), Palette.metal, Layers::PANEL)
      @plate = builder.decor(Mesh.cylinder(SIZE * 0.42_f32, HEIGHT, 20), Palette.metal, position + v3(0, HEIGHT / 2, 0))
      @ring = builder.decor(Mesh.torus(SIZE * 0.47_f32, 0.045_f32, 24, 8), Palette.glow(idle_colour), position + v3(0, 0.02_f32, 0))
      @light = builder.decor(Mesh.cylinder(SIZE * 0.2_f32, HEIGHT + 0.02_f32, 16), Palette.glow(idle_colour), position + v3(0, HEIGHT / 2 + 0.01_f32, 0))
    end

    # Only a cube of the matching type presses this plate. The player presses any of
    # them, which keeps the type puzzle about moving cubes rather than standing on them.
    getter kind : CubeKind

    def idle_colour : Color
      case @kind
      in CubeKind::Red      then Color.hex("#e0483c")
      in CubeKind::Blue     then Color.hex("#4a86e8")
      in CubeKind::Standard then Color.hex("#4ea8ff")
      end
    end

    include Receiver

    # Moves the whole plate. A control mounted on the lift uses this to ride with it.
    def position=(point : Vec3) : Nil
      @position = point
      @base.global_position = point + v3(0, -HEIGHT / 2 - 0.04_f32, 0)
      @plate.global_position = point + v3(0, HEIGHT / 2, 0)
      @ring.global_position = point + v3(0, 0.02_f32, 0)
      @light.global_position = point + v3(0, HEIGHT / 2 + 0.01_f32, 0)
    end

    # Updates the plate from who is standing on it. A cube only counts if it is the
    # right type for this plate; the player counts on any of them.
    def update(dt : Float32, occupants : Array(Occupant)) : Nil
      held = occupants.any? do |occupant|
        d = occupant.position - @position
        over_plate = d.x.abs < SIZE * 0.5_f32 && d.z.abs < SIZE * 0.5_f32 && d.y > -0.2_f32 && d.y < 1.4_f32
        next false unless over_plate
        occupant.is_player || occupant.kind == @kind
      end
      if held != @pressed
        @pressed = held
        color = held ? Color.hex("#ffa028") : Color.hex("#4ea8ff")
        @light.material = Palette.glow(color)
        @ring.material = Palette.glow(color)
        @receivers.each { |r| r.receive(held) }
        @pulse = 1_f32
      end
      @pulse = Math.max(0_f32, @pulse - dt * 3_f32)
    end
  end

  # A sliding door. Opens when a button sends it `true`, and rides up into the frame.
  class Door
    include Receiver

    WIDTH  = 1.6_f32
    HEIGHT = 2.6_f32
    SPEED  = 3.2_f32

    getter receivers = [] of Receiver
    property? open = false
    getter position : Vec3

    @body : StaticBody3D
    @mesh : MeshInstance3D
    @closed_y : Float32
    @amount = 0_f32
    @target = 0_f32
    @closed_pos : Vec3

    def initialize(builder : Builder, @position : Vec3)
      @closed_pos = @position
      @closed_y = @position.y
      # The frame is static; only the panel slides.
      builder.trim(@position + v3(0, HEIGHT / 2 + 0.16_f32, 0), v3(WIDTH + 0.5_f32, 0.32_f32, 0.5_f32))
      builder.trim(@position + v3(-(WIDTH + 0.5_f32) / 2, HEIGHT / 2, 0), v3(0.3_f32, HEIGHT, 0.5_f32))
      builder.trim(@position + v3((WIDTH + 0.5_f32) / 2, HEIGHT / 2, 0), v3(0.3_f32, HEIGHT, 0.5_f32))
      builder.light_panel(@position + v3(0, HEIGHT + 0.1_f32, 0), v3(WIDTH * 0.8_f32, 0.08_f32, 0.3_f32))

      @body = builder.box(@position, v3(WIDTH, HEIGHT, 0.22_f32), Palette.metal, Layers::DOOR)
      @mesh = @body.children.first.as(MeshInstance3D)
    end

    # A button signal opens the door.
    def receive(value : Bool) : Nil
      return if @open == value
      @open = value
      Audio.play_at(Sounds[:door], @position, 0.5, min_distance: 2, max_distance: 40)
    end

    # Slides the panel. Returns the distance it moved this step, so anything riding it
    # can be carried along.
    def update(dt : Float32) : Vec3
      @target = @open ? 1_f32 : 0_f32
      return Vec3::ZERO if (@amount - @target).abs < 0.0005_f32 && @amount == @target
      step = SPEED * dt
      @amount = Util.approach(@amount, @target, step)
      before = @body.global_position
      @body.global_position = v3(@closed_pos.x, @closed_y + @amount * (HEIGHT + 0.1_f32), @closed_pos.z)
      @body.global_position - before
    end

    # True while the panel is low enough to still block the doorway.
    def blocking? : Bool
      @amount < 0.6_f32
    end
  end

  # A weighted storage cube. The player can pick it up, carry it through portals, and
  # drop it on a button. It is a rigid body so it tumbles convincingly.
  class Cube
    SIZE = 0.62_f32

    getter body : RigidBody3D
    property? held = false
    property? fizzled = false

    @mesh : MeshInstance3D
    @marker : MeshInstance3D
    @home : Vec3
    @spin = 0_f32

    getter kind : CubeKind

    def initialize(builder : Builder, position : Vec3, @kind : CubeKind = CubeKind::Standard)
      @home = position
      @body = RigidBody3D.new("cube", position)
      @body.box(SIZE, SIZE, SIZE)
      @body.layer = Layers::PROP
      @body.mask = Layers::ALL & ~Layers::PROP
      @body.mass = 4_f32
      @body.friction = 0.7_f32
      @body.restitution = 0.05_f32
      @body.fixed_rotation = true
      @mesh = MeshInstance3D.new(Mesh.box(SIZE, SIZE, SIZE), Palette.cube(@kind))
      @body.add(@mesh)
      # A glowing dot on each face, the way Aperture marks its cubes.
      @marker = MeshInstance3D.new(Mesh.cylinder(0.11_f32, 0.02_f32, 16), Palette.glow(@kind.glow))
      @marker.rotation = Quat.from_axis_angle(Vec3::RIGHT, Math::PI / 2)
      @marker.position = v3(0, 0, SIZE / 2 + 0.015_f32)
      @body.add(@marker)
      builder.root.add(@body)
    end

    # Centre of the cube in world space.
    def position : Vec3
      @body.global_position
    end

    # A point just above the cube, used for button tests.
    def test_point : Vec3
      @body.global_position + v3(0, SIZE / 2, 0)
    end

    # Picks the cube up and holds it in front of the player.
    def grab(eye : Vec3, forward : Vec3) : Nil
      return if fizzled?
      @held = true
      @body.velocity = Vec3::ZERO
      # Teleporting a rigid body each frame avoids fighting the solver.
      @body.global_position = eye + forward * 1.5_f32
      @body.rotation = Quat.identity
      @spin += 1_f32
    end

    # Releases the cube with the player's momentum, so a thrown cube keeps going.
    def release(velocity : Vec3 = Vec3::ZERO) : Nil
      @held = false
      @body.velocity = velocity
      @body.angular_velocity = v3(0, @spin * 0.6_f32, 0)
      @spin = 0_f32
    end

    # Destroys the cube, as a field or a fizzler would.
    def dissolve : Nil
      @held = false
      @fizzled = true
      @body.visible = false
    end

    def reset : Nil
      @fizzled = false
      @held = false
      @body.visible = true
      @body.global_position = @home
      @body.rotation = Quat::IDENTITY
      @body.velocity = Vec3::ZERO
      @body.angular_velocity = Vec3::ZERO
    end

    # True when the player is looking at the cube from close range.
    def in_reach?(eye : Vec3, forward : Vec3, reach : Float32 = 2.6_f32) : Bool
      return false if fizzled?
      to = @body.global_position - eye
      to.length < reach && to.normalized.dot(forward) > 0.72_f32
    end
  end

  # A laser beam between an emitter and a receiver. It kills the player, and can be
  # blocked by a cube, which is the whole point of putting one in the room.
  class Laser
    # Beam height above the floor. It has to cross the player's body, not pass under
    # it, and still sit below the crouch height so ducking is not an answer.
    BEAM_HEIGHT = 1.05_f32
    # How close a point has to be to the beam to count as a hit. Generous enough that
    # the capsule cannot squeeze past the gap between the beam and its own radius.
    HIT_RADIUS = 0.5_f32

    getter from : Vec3
    getter to : Vec3

    @beam : MeshInstance3D?
    @emitter : MeshInstance3D
    @shooter : MeshInstance3D

    def initialize(builder : Builder, from : Vec3, to : Vec3)
      @from = v3(from.x, from.y + BEAM_HEIGHT, from.z)
      @to = v3(to.x, to.y + BEAM_HEIGHT, to.z)
      length = @from.distance(@to)
      # The beam is a thin box stretched along the line between the two heads.
      if beam = builder.decor(Mesh.box(0.07_f32, 0.07_f32, Math.max(length, 0.01_f32)),
           Palette.glow(Color.hex("#ff2a1a")), (@from + @to) / 2)
        beam.look_at(@from)
        @beam = beam
      end
      # Emitter and receiver sit level with the beam, on short posts.
      @emitter = builder.decor(Mesh.cylinder(0.2_f32, 0.34_f32, 16), Palette.metal,
        @from + v3(0, -0.28_f32, 0))
      @shooter = builder.decor(Mesh.cylinder(0.16_f32, 0.16_f32, 16), Palette.glow(Color.hex("#ff2a1a")), @from)
      builder.box(v3(@from.x, (@from.y - BEAM_HEIGHT) / 2, @from.z),
        v3(0.4_f32, BEAM_HEIGHT, 0.4_f32), Palette.metal, Layers::PANEL)
      builder.box(v3(@to.x, (@to.y - BEAM_HEIGHT) / 2, @to.z),
        v3(0.4_f32, BEAM_HEIGHT, 0.4_f32), Palette.metal, Layers::PANEL)
    end

    # True when *point* lies on the beam, allowing for the player's width.
    def hits?(point : Vec3, radius : Float32 = HIT_RADIUS) : Bool
      segment = @to - @from
      len = segment.length
      return false if len < 0.01
      dir = segment / len
      t = (point - @from).dot(dir)
      return false if t < 0 || t > len
      (@from + dir * t).distance(point) < radius
    end
  end

  # A lift that travels between two heights when signalled. Anything standing on it
  # is carried along, which is what makes it usable as an elevator.
  class Lift
    include Receiver

    SIZE = v3(2.4_f32, 0.3_f32, 2.4_f32)

    getter receivers = [] of Receiver
    property? at_top = false

    @body : StaticBody3D
    @low : Float32
    @high : Float32
    @position = Vec3::ZERO
    @progress = 0_f32
    @target = 0_f32

    # How far the platform moved on its last update, so riders can be carried.
    getter last_motion = Vec3::ZERO

    # A control mounted on the platform, moved with it every update.
    @rider : Button? = nil

    def initialize(builder : Builder, center : Vec3, low_y : Float32, high_y : Float32)
      @low = low_y
      @high = high_y
      @position = v3(center.x, low_y, center.z)
      @body = StaticBody3D.new("lift", @position)
      @body.box(SIZE)
      @body.layer = Layers::PANEL
      @body.mask = Layers::ALL
      @body.add(MeshInstance3D.new(Mesh.box(SIZE.x, SIZE.y, SIZE.z), Palette.metal))
      builder.root.add(@body)
    end

    def position : Vec3
      @body.global_position
    end

    # Mounts a control on the platform. It has to travel with the platform or the
    # player would ride up and off a button they had left behind on the floor.
    def rider=(button : Button) : Nil
      @rider = button
      button.position = rider_position
    end

    # Where a mounted control sits, level with the platform's top surface.
    def rider_position : Vec3
      base = @body.global_position
      v3(base.x, base.y + SIZE.y / 2, base.z)
    end

    # A button signal sends the lift up. The upper control reaches it through an
    # inverter, so pressing that one brings it back down.
    def receive(value : Bool) : Nil
      @at_top = value
    end

    # Moves the platform, returning how far it travelled this step.
    def update(dt : Float32) : Vec3
      @target = @at_top ? 1_f32 : 0_f32
      if @progress == @target
        @last_motion = Vec3::ZERO
        return Vec3::ZERO
      end
      before = @body.global_position
      @progress = Util.approach(@progress, @target, (1.1_f32 * dt).clamp(0_f32, 1_f32))
      @body.global_position = v3(@position.x, @low + (@high - @low) * @progress, @position.z)
      # Static bodies do not follow their node, so the platform's collider is pushed
      # across explicitly. Without this the platform would rise visually while the
      # floor the player stands on stayed at the bottom.
      @body.push_transform
      @last_motion = @body.global_position - before
      @rider.try { |button| button.position = rider_position }
      @last_motion
    end

    # The platform's top surface, where the player stands.
    def top : Float32
      @body.global_position.y + SIZE.y / 2
    end

    # True when a body whose feet are at *point* is resting on the platform. The point
    # has to be the feet, not the centre: a standing player's centre is most of a metre
    # above the surface they are standing on.
    def carries?(point : Vec3) : Bool
      surface = top
      on_top = (point.y - surface).abs < 0.35_f32
      within_x = (point.x - @body.global_position.x).abs < SIZE.x / 2 + 0.15_f32
      within_z = (point.z - @body.global_position.z).abs < SIZE.z / 2 + 0.15_f32
      on_top && within_x && within_z
    end
  end

  # A pit of toxic liquid. Touching it respawns the player and clears the portals,
  # which is the punishment Portal uses for a bad fall.
  class Goo
    getter surface : Float32
    getter bounds : AABB

    @mesh : MeshInstance3D

    def initialize(builder : Builder, center : Vec3, size : Vec3, surface : Float32)
      @surface = surface
      @bounds = AABB.new(v3(center.x - size.x / 2, surface - 4, center.z - size.z / 2),
        v3(center.x + size.x / 2, surface, center.z + size.z / 2))
      # Dark and glossy, the way the films keep it: a bright surface here reads as a
      # solid slab rather than a liquid.
      # Dark, glossy, with a faint warm emissive so the pool reads as liquid rather
      # than as a hole in the floor. The emissive is what marks it as dangerous; the
      # gloss is what makes it look wet.
      mat = Material.new(Color.hex("#2a1c08"), shininess: 160, specular: 0.9, metallic: 0.05,
        emissive: Color.hex("#2e1403"))
      @mesh = builder.decor(Mesh.plane(size.x, size.z, 8, uv_scale: 4), mat, v3(center.x, surface, center.z))
    end

    # True when *point* is inside the liquid.
    def contains?(point : Vec3) : Bool
      point.y < @surface + 0.35_f32 && @bounds.contains?(v3(point.x, @surface, point.z))
    end

    # Ripples the surface a little so it does not look like a flat plate.
    def update(elapsed : Float32) : Nil
      @mesh.position.y = @surface + Math.sin(elapsed * 1.3_f32) * 0.015_f32
    end
  end

  # A Sentry turret. It tracks the player, charges, and fires. A cube or a hard enough
  # portal fling knocks it over, which is the only way past one you cannot walk around.
  class Turret
    RANGE       =  18_f32
    CHARGE      = 1.1_f32
    BREAK_SPEED =   6_f32

    getter? defunct = false
    getter position : Vec3

    @head : MeshInstance3D
    @eye : MeshInstance3D
    @base : MeshInstance3D
    @charge = 0_f32
    @muzzle : Vec3 = Vec3::ZERO

    def initialize(builder : Builder, position : Vec3, facing : Vec3 = v3(1, 0, 0))
      @position = position
      @base = builder.decor(Mesh.cylinder(0.42_f32, 0.22_f32, 16), Palette.metal, position)
      body = builder.decor(Mesh.box(0.5_f32, 0.62_f32, 0.5_f32), Palette.metal, position + v3(0, 0.42, 0))
      body.look_at(position + v3(0, 0.42, 0) + facing)
      @head = body
      @eye = builder.decor(Mesh.sphere(0.17_f32, 14, 10), Palette.glow(Color.hex("#7fe07f")), position + v3(0, 0.5, 0))
      builder.box(v3(position.x, (position.y - 0.11) / 2, position.z),
        v3(0.7_f32, position.y + 0.11_f32, 0.7_f32), Palette.metal, Layers::PANEL)
    end

    # True when the turret is on target. Only then does it charge and fire.
    def sees?(from : Vec3) : Bool
      return false if defunct?
      to = from - @muzzle
      return false if to.length > RANGE
      Physics3D.world.raycast(@muzzle, to.normalized, to.length, Layers::WHITE | Layers::PANEL).nil?
    end

    # Advances the charge. Returns true on the frame it fires.
    def update(dt : Float32, player_eye : Vec3) : Bool
      return false if defunct?
      if sees?(player_eye)
        @charge = Math.min(CHARGE, @charge + dt)
      else
        @charge = Math.max(0_f32, @charge - dt * 1.6_f32)
      end
      ready = @charge >= CHARGE
      colour = @charge > 0_f32 ? Color.hex("#ff2a1a") : Color.hex("#7fe07f")
      @eye.material = Palette.glow(colour)
      @eye.scale = 1.0_f32 + 0.35_f32 * (@charge / CHARGE)
      @muzzle = @position + v3(0, 0.5, 0)
      if ready
        @charge = 0_f32
        return true
      end
      false
    end

    # Knocks the turret over. Returns true if this hit was what did it.
    def hit_by(speed : Float32) : Bool
      return false if defunct?
      return false if speed < BREAK_SPEED
      @defunct = true
      @eye.material = Palette.glow(Color.hex("#40444a"))
      @eye.scale = 0.5_f32
      @head.rotation = Quat.from_axis_angle(v3(1, 0, 0), -1.2_f32)
      true
    end
  end

  # A materialisation field. Anything that passes through it is cleaned up and removed,
  # which is how a chamber asks for a fresh cube or clears a path.
  class Fizzler
    getter position : Vec3
    getter normal : Vec3
    getter half : Vec3

    def initialize(builder : Builder, position : Vec3, normal : Vec3, half : Vec3)
      @position = position
      @normal = normal.normalized
      @half = half
      mat = Material.new(Color.new(0.35, 0.85, 1.0, 0.18), unlit: true, transparent: true)
      mat.double_sided = true
      builder.decor(Mesh.box(half.x * 2, half.y * 2, 0.06_f32), mat, position)
    end

    # True when *point* has crossed the field this step. The field is a slab, so the
    # test is whether the segment passed from one side of it to the other.
    def cleans?(from : Vec3, to : Vec3) : Bool
      d0 = (from - @position).dot(@normal)
      d1 = (to - @position).dot(@normal)
      return false unless d0 * d1 < 0
      # And it has to be within the field's face, not somewhere off to the side.
      local = to - @position
      local -= @normal * local.dot(@normal)
      local.x.abs < @half.x && local.y.abs < @half.y
    end
  end

  # A launch plate. Standing on it throws whatever is on it, player or cube, upward.
  class FaithPlate
    LAUNCH = 9.5_f32

    @node : MeshInstance3D
    @position : Vec3

    def initialize(builder : Builder, position : Vec3)
      @position = position
      builder.box(position + v3(0, -0.06, 0), v3(1.4_f32, 0.12_f32, 1.4_f32), Palette.metal, Layers::PANEL)
      @node = builder.decor(Mesh.cylinder(0.58_f32, 0.1_f32, 20), Palette.metal, position)
      # A painted arrow, which is what tells the player the plate throws rather than holds.
      builder.decor(Mesh.cylinder(0.26_f32, 0.13_f32, 14), Palette.glow(Color.hex("#ffd23a")), position + v3(0, 0.02, 0))
    end

    # True when *point* is over the plate.
    def under?(point : Vec3) : Bool
      d = point - @position
      d.x.abs < 0.75_f32 && d.z.abs < 0.75_f32 && d.y > -0.4_f32 && d.y < 1.6_f32
    end

    def position : Vec3
      @position
    end
  end

  # A bridge plate. Pressed, it slides a walkway out over a gap; released, it retracts.
  class Bridge
    include Receiver

    getter receivers = [] of Receiver
    property? extended = false

    @body : StaticBody3D
    @mesh : MeshInstance3D
    @retracted : Vec3
    @extended_to : Vec3
    @progress = 0_f32

    def initialize(builder : Builder, retracted : Vec3, extended_to : Vec3, size : Vec3)
      @retracted = retracted
      @extended_to = extended_to
      @body = StaticBody3D.new("bridge", retracted)
      @body.box(size)
      @body.layer = Layers::PANEL
      @body.mask = Layers::ALL
      @mesh = MeshInstance3D.new(Mesh.box(size.x, size.y, size.z), Palette.metal)
      @body.add(@mesh)
      builder.root.add(@body)
    end

    def receive(value : Bool) : Nil
      return if @extended == value
      @extended = value
      @receivers.each { |r| r.receive(value) }
    end

    # Slides the walkway. The collider is pushed across by hand, as a static body does
    # not follow its own node.
    def update(dt : Float32) : Vec3
      target = @extended ? 1_f32 : 0_f32
      before = @body.global_position
      @progress = Util.approach(@progress, target, dt * 1.6_f32)
      @body.global_position = @retracted.lerp(@extended_to, @progress)
      @body.push_transform
      @body.global_position - before
    end
  end

  # The weighted pellet from the first game: a ball you can carry, and two plates that
  # either throw it up or drop it through a hole.
  class Ball
    RADIUS = 0.22_f32
    MASS   =  2.0_f32

    getter body : RigidBody3D
    property? held = false
    property? fizzled = false

    @home : Vec3

    def initialize(builder : Builder, position : Vec3)
      @home = position
      @body = RigidBody3D.new("ball", position)
      @body.sphere(RADIUS)
      @body.layer = Layers::PROP
      @body.mask = Layers::ALL & ~Layers::PROP
      @body.mass = MASS
      @body.friction = 0.4_f32
      @body.restitution = 0.55_f32
      @body.add(MeshInstance3D.new(Mesh.sphere(RADIUS, 18, 12), Palette.glow(Color.hex("#ff8a3a"))))
      builder.root.add(@body)
    end

    def position : Vec3
      @body.global_position
    end

    def test_point : Vec3
      @body.global_position
    end

    def grab(eye : Vec3, forward : Vec3) : Nil
      return if fizzled?
      @held = true
      @body.velocity = Vec3::ZERO
      @body.global_position = eye + forward * 1.4_f32
    end

    def release(velocity : Vec3 = Vec3::ZERO) : Nil
      @held = false
      @body.velocity = velocity
    end

    def dissolve : Nil
      @held = false
      @fizzled = true
      @body.visible = false
    end

    def reset : Nil
      @fizzled = false
      @held = false
      @body.visible = true
      @body.global_position = @home
      @body.velocity = Vec3::ZERO
      @body.angular_velocity = Vec3::ZERO
    end

    def in_reach?(eye : Vec3, forward : Vec3, reach : Float32 = 2.4_f32) : Bool
      return false if fizzled?
      to = @body.global_position - eye
      to.length < reach && to.normalized.dot(forward) > 0.7_f32
    end
  end

  # A plate that throws the ball straight up when it passes over.
  class BallCatcher
    LAUNCH = 8.5_f32

    @position : Vec3
    @launch = true

    def initialize(builder : Builder, position : Vec3, launch : Bool = true)
      @position = position
      @launch = launch
      builder.box(position + v3(0, -0.05, 0), v3(1.2_f32, 0.1_f32, 1.2_f32), Palette.metal, Layers::PANEL)
      colour = launch ? Color.hex("#ff8a3a") : Color.hex("#7f9fe0")
      builder.decor(Mesh.cylinder(0.5_f32, 0.08_f32, 18), Palette.glow(colour), position)
    end

    # Returns an upward or downward velocity for a ball over the plate.
    def kick(point : Vec3) : Vec3?
      d = point - @position
      return nil unless d.x.abs < 0.6_f32 && d.z.abs < 0.6_f32 && d.y > -0.3_f32 && d.y < 1.2_f32
      @launch ? v3(0, LAUNCH, 0) : v3(0, -LAUNCH, 0)
    end

    def position : Vec3
      @position
    end
  end

  # Hands out a fresh cube on a timer, so a chamber never becomes unsolvable because the
  # player dropped the only one into a pit.
  class CubeDispenser
    PERIOD = 6.0_f32

    @body : MeshInstance3D
    @position : Vec3
    @timer = 1.5_f32
    @spawned : Array(Cube) = [] of Cube

    def initialize(builder : Builder, position : Vec3)
      @position = position
      builder.box(position + v3(0, -0.5, 0), v3(1.3_f32, 1.0_f32, 1.3_f32), Palette.metal, Layers::PANEL)
      @body = builder.decor(Mesh.box(0.9_f32, 0.3_f32, 0.9_f32), Palette.glow(Color.hex("#8fd0ff")), position)
    end

    def position : Vec3
      @position
    end

    # Drops a cube if there is room for one. Returns the cube it made, if any.
    def update(dt : Float32, builder : Builder, kind : CubeKind = CubeKind::Standard) : Cube?
      @timer -= dt
      return nil if @timer > 0
      @timer = PERIOD
      # Only hand out a cube if there is room for one where it would land.
      probe = AABB.from_center(@position + v3(0, 0.6, 0), v3(Cube::SIZE, Cube::SIZE, Cube::SIZE))
      return nil unless Physics3D.world.query_aabb(probe, Layers::ALL).empty?
      cube = Cube.new(builder, @position + v3(0, 0.6_f32, 0), kind)
      @spawned << cube
      cube
    end
  end
end
