module Portal3
  # One test chamber: its geometry, its puzzle parts and its exit. A chamber is
  # self-contained, so completing it can simply load the next one.
  class Chamber
    getter index : Int32
    getter title : String
    getter subtitle : String
    getter spawn : Vec3
    getter spawn_facing : Vec3

    getter buttons = [] of Button
    getter doors = [] of Door
    getter cubes = [] of Cube
    getter lasers = [] of Laser
    getter lifts = [] of Lift
    getter goos = [] of Goo
    getter portals = [] of Portal
    getter turrets = [] of Turret
    getter fizzlers = [] of Fizzler
    getter faith_plates = [] of FaithPlate
    getter bridges = [] of Bridge
    getter balls = [] of Ball
    getter catchers = [] of BallCatcher
    getter dispensers = [] of CubeDispenser

    # Where the player has to reach to finish the chamber.
    getter exit_zone : AABB
    property solved = false

    def initialize(@index : Int32, @title : String, @subtitle : String,
                   @spawn : Vec3, @spawn_facing : Vec3, @exit_zone : AABB)
    end

    # True when the player is standing in the exit.
    def at_exit?(point : Vec3) : Bool
      @solved = true if @exit_zone.contains?(point)
      @solved
    end

    # Advances everything that moves, and returns the total lift and door motion so
    # the player can be carried along by anything they are standing on.
    def update(dt : Float32) : Vec3
      motion = Vec3::ZERO
      @doors.each { |d| motion += d.update(dt) }
      @lifts.each { |l| motion += l.update(dt) }
      @bridges.each { |b| motion += b.update(dt) }
      @goos.each { |g| g.update(Clock.elapsed.to_f32) }
      motion
    end

    # Every prop that can be cleaned up, cubes and balls alike.
    def props : Array(Cube | Ball)
      @cubes + @balls
    end

    # The total speed of every moving prop, used to knock turrets over.
    def prop_speed : Float32
      highest = 0_f32
      @cubes.each do |cube|
        next if cube.held? || cube.fizzled?
        highest = Math.max(highest, cube.body.velocity.length)
      end
      @balls.each do |ball|
        next if ball.held? || ball.fizzled?
        highest = Math.max(highest, ball.body.velocity.length)
      end
      highest
    end

    # Everything standing on a button right now: the player, and every cube that is
    # still in the room. Each carries its type so a plate can insist on the right one.
    def button_occupants(player_position : Vec3) : Array(Occupant)
      points = [Occupant.new(player_position, CubeKind::Standard, true)]
      @cubes.each do |cube|
        points << Occupant.new(cube.test_point, cube.kind, false) unless cube.fizzled?
      end
      points
    end

    # Restores every cube and ball, for when the player respawns.
    def reset_cubes : Nil
      @cubes.each(&.reset)
      @balls.each(&.reset)
    end
  end

  # Builds the chambers. Each one is built fresh when it starts, so the geometry code
  # below reads as a description of the room rather than as scene setup.
  module Levels
    extend self

    COUNT = 20

    WALL        = 0.5_f32
    DOOR_WIDTH  = 1.6_f32
    DOOR_HEIGHT = 2.6_f32

    def title(index : Int32) : String
      "Chamber #{index.to_s.rjust(2, '0')}"
    end

    # The line GLaDOS says when the chamber opens. Each one hints at the solution
    # without ever stating it.
    def line(index : Int32) : String
      case index
      when  0 then "Please keep your arms inside the vehicle."
      when  1 then "This device opens portals. Aim at white."
      when  2 then "Forgive me. I did not expect a pit."
      when  3 then "Weighted storage cubes are portable."
      when  4 then "Your cube is out of reach. Fetch it."
      when  5 then "The laser is a safety measure."
      when  6 then "Two controls. One lift. Not a coincidence."
      when  7 then "Momentum is conserved. Dignity is not."
      when  8 then "The final test. Everything at once."
      when  9 then "Two types of cube. Match them to their buttons."
      when 10 then "Sentry units are not part of the test."
      when 11 then "The pellet predates the cubes. It bounces."
      when 12 then "Materialisation replaces what you lose."
      when 13 then "Faith plates do not ask if you are ready."
      when 14 then "A bridge is a promise that something will hold."
      when 15 then "The pellet weighs almost nothing."
      when 16 then "A cube thrown hard enough is a bullet."
      when 17 then "I replaced the last one twice already."
      when 18 then "Sentries, lasers and a long drop."
      else         "The final test. Remember all of it."
      end
    end

    def build(index : Int32, b : Builder) : Chamber
      case index
      when  0 then chamber_00(b)
      when  1 then chamber_01(b)
      when  2 then chamber_02(b)
      when  3 then chamber_03(b)
      when  4 then chamber_04(b)
      when  5 then chamber_05(b)
      when  6 then chamber_06(b)
      when  7 then chamber_07(b)
      when  8 then chamber_08(b)
      when  9 then chamber_09(b)
      when 10 then chamber_10(b)
      when 11 then chamber_11(b)
      when 12 then chamber_12(b)
      when 13 then chamber_13(b)
      when 14 then chamber_14(b)
      when 15 then chamber_15(b)
      when 16 then chamber_16(b)
      when 17 then chamber_17(b)
      when 18 then chamber_18(b)
      else         chamber_19(b)
      end
    end

    # A rectangular room with an exit doorway in the +X wall. Walls are white and
    # portalable; the floor, ceiling and door frame are not. *sill* raises the doorway
    # off the floor, for chambers whose exit is up on a deck.
    private def shell(b : Builder, lo : Vec3, hi : Vec3, exit_z : Float32,
                      sill : Float32 = 0_f32) : Void
      cx = (lo.x + hi.x) / 2
      cz = (lo.z + hi.z) / 2
      w = hi.x - lo.x
      d = hi.z - lo.z
      h = hi.y - lo.y

      b.floor(v3(cx, lo.y - WALL / 2, cz), v3(w + WALL * 2, WALL, d + WALL * 2))
      b.ceiling(v3(cx, hi.y + WALL / 2, cz), v3(w + WALL * 2, WALL, d + WALL * 2))

      # -X and the two side walls are solid white panels.
      b.wall(v3(lo.x - WALL / 2, lo.y + h / 2, cz), v3(WALL, h, d))
      b.wall(v3(cx, lo.y + h / 2, lo.z - WALL / 2), v3(w, h, WALL))
      b.wall(v3(cx, lo.y + h / 2, hi.z + WALL / 2), v3(w, h, WALL))

      # +X wall carries the exit, so it is built as pieces around the opening.
      wall_with_door(b, hi.x + WALL / 2, lo.y, h, lo.z, hi.z, exit_z, sill)

      # Recessed ceiling strips, the way a test chamber lights itself.
      strips = 3
      strips.times do |i|
        z = lo.z + d * (i + 1) / (strips + 1)
        b.light_panel(v3(cx, hi.y - 0.08_f32, z), v3(w * 0.62_f32, 0.12_f32, 0.5_f32), Color.hex("#fff6e4"))
      end
    end

    # Builds one wall with a doorway cut out of it: a full-height piece either side of
    # the opening, a solid panel under the sill, and a lintel over the top.
    private def wall_with_door(b : Builder, x : Float32, floor_y : Float32, h : Float32,
                               z_lo : Float32, z_hi : Float32, door_z : Float32,
                               sill : Float32 = 0_f32) : Void
      half = DOOR_WIDTH / 2
      below = z_hi - (door_z + half)
      above = (door_z - half) - z_lo
      if below > 0.01
        b.wall(v3(x, floor_y + h / 2, (door_z + half + z_hi) / 2), v3(WALL, h, below))
      end
      if above > 0.01
        b.wall(v3(x, floor_y + h / 2, (z_lo + door_z - half) / 2), v3(WALL, h, above))
      end
      # The wall under a raised doorway, so a sill is solid ground rather than a hole.
      if sill > 0.01
        b.wall(v3(x, floor_y + sill / 2, door_z), v3(WALL, sill, DOOR_WIDTH))
      end
      # The lintel above the doorway.
      lintel = h - sill - DOOR_HEIGHT
      if lintel > 0.01
        b.wall(v3(x, floor_y + sill + DOOR_HEIGHT + lintel / 2, door_z), v3(WALL, lintel, DOOR_WIDTH))
      end
      # Door frame trim, which reads as a proper Aperture doorway.
      base = floor_y + sill
      b.trim(v3(x - 0.02_f32, base + DOOR_HEIGHT / 2, door_z - half - 0.1_f32), v3(WALL + 0.1_f32, DOOR_HEIGHT, 0.2_f32))
      b.trim(v3(x - 0.02_f32, base + DOOR_HEIGHT / 2, door_z + half + 0.1_f32), v3(WALL + 0.1_f32, DOOR_HEIGHT, 0.2_f32))
      b.trim(v3(x - 0.02_f32, base + DOOR_HEIGHT + 0.1_f32, door_z), v3(WALL + 0.1_f32, 0.2_f32, DOOR_WIDTH + 0.4_f32))
    end

    # The finished-chamber marker. A thick green frame around a lit recess, so the
    # way out reads from anywhere in the room.
    private def exit_frame(b : Builder, x : Float32, floor_y : Float32, door_z : Float32) : AABB
      color = Color.hex("#54ff8c")
      t = 0.34_f32
      face = x - 0.14_f32
      b.light_panel(v3(face, floor_y + 0.12_f32, door_z), v3(t, 0.16_f32, DOOR_WIDTH + t * 2), color)
      b.light_panel(v3(face, floor_y + DOOR_HEIGHT - 0.12_f32, door_z), v3(t, 0.16_f32, DOOR_WIDTH + t * 2), color)
      b.light_panel(v3(face, floor_y + DOOR_HEIGHT / 2, door_z - DOOR_WIDTH / 2 - 0.08_f32),
        v3(t, DOOR_HEIGHT, 0.16_f32), color)
      b.light_panel(v3(face, floor_y + DOOR_HEIGHT / 2, door_z + DOOR_WIDTH / 2 + 0.08_f32),
        v3(t, DOOR_HEIGHT, 0.16_f32), color)
      # A shallow lit recess behind the frame, so the doorway is not a black hole.
      b.decor(Mesh.box(0.1_f32, DOOR_HEIGHT, DOOR_WIDTH), Palette.glow(Color.hex("#123a22")),
        v3(x + 0.55_f32, floor_y + DOOR_HEIGHT / 2, door_z))
      AABB.new(v3(x - 1.4_f32, floor_y, door_z - DOOR_WIDTH / 2 - 0.2_f32),
        v3(x - 0.2_f32, floor_y + DOOR_HEIGHT, door_z + DOOR_WIDTH / 2 + 0.2_f32))
    end

    # A raised ledge the player cannot reach by jumping, so a portal is the answer.
    private def ledge(b : Builder, center : Vec3, size : Vec3) : StaticBody3D
      b.wall(center, size)
    end

    # ---------------------------------------------------------------- chambers

    # 00: an empty room. Teaches movement, and that the exit is where the light is.
    private def chamber_00(b : Builder) : Chamber
      lo = v3(-5, 0, -5)
      hi = v3(5, 5, 5)
      shell(b, lo, hi, 0)
      Chamber.new(0, title(0), line(0), v3(-3, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
    end

    # 01: a ledge too high to climb, with white walls either side. Teaches the device.
    private def chamber_01(b : Builder) : Chamber
      lo = v3(-6, 0, -4)
      hi = v3(6, 6, 4)
      shell(b, lo, hi, 0)
      # The ledge has to run all the way to the exit wall, or the exit stands on nothing.
      ledge(b, v3(3.4, 1.5, 0), v3(4.0, 3, 4))
      Chamber.new(1, title(1), line(1), v3(-4, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 3, 0))
    end

    # 02: a goo pit splitting the room. The far wall is the only white surface past it.
    private def chamber_02(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 7, 5)
      shell(b, lo, hi, 0)
      # The pit occupies the middle of the room, so the floor is built in two halves.
      pit_lo = v3(-2, 0, -5)
      pit_hi = v3(2, 7, 5)
      b.wall(v3((-7 + pit_lo.x) / 2, 0, 0), v3(5, 0.5_f32, 10))
      b.wall(v3((pit_hi.x + 7) / 2, 0, 0), v3(5, 0.5_f32, 10))
      b.hazard_strip(v3(pit_lo.x - 0.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 10))
      b.hazard_strip(v3(pit_hi.x + 0.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 10))
      goo = Goo.new(b, v3(0, -1.5_f32, 0), v3(4, 3, 10), 0.06_f32)
      ledge(b, v3(5, 1.5_f32, 0), v3(4, 3, 4))
      chamber = Chamber.new(2, title(2), line(2), v3(-5.5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 3, 0))
      chamber.goos << goo
      chamber
    end

    # 03: a cube and a button. Teaches carrying and the weight mechanic.
    private def chamber_03(b : Builder) : Chamber
      lo = v3(-6, 0, -5)
      hi = v3(6, 5, 5)
      shell(b, lo, hi, 0)
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button = Button.new(b, v3(-2, 0.06_f32, 2.5_f32))
      button.receivers << door
      chamber = Chamber.new(3, title(3), line(3), v3(-4, 1, -2), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.buttons << button
      chamber.doors << door
      chamber.cubes << Cube.new(b, v3(-1, 1, -2))
      chamber
    end

    # 04: the cube starts on a ledge the player cannot climb to. The cube itself is
    # the only way to press the button.
    private def chamber_04(b : Builder) : Chamber
      lo = v3(-7, 0, -6)
      hi = v3(7, 6, 6)
      shell(b, lo, hi, 0)
      ledge(b, v3(4.5, 2.0_f32, -3), v3(5, 4, 4))
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button = Button.new(b, v3(-3, 0.06_f32, 3))
      button.receivers << door
      chamber = Chamber.new(4, title(4), line(4), v3(-5.5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.buttons << button
      chamber.doors << door
      # On top of the ledge, which is four metres up.
      chamber.cubes << Cube.new(b, v3(4.5, 4.4, -3))
      chamber
    end

    # 05: a laser guards the corridor to the exit. The cube blocks it.
    private def chamber_05(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 5, 5)
      shell(b, lo, hi, 0)
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button = Button.new(b, v3(-3, 0.06_f32, 0))
      button.receivers << door
      laser = Laser.new(b, v3(0, 0, -4.4_f32), v3(0, 0, 4.4_f32))
      # A gap in the floor to drop the cube through and stand on the button behind.
      b.hazard_strip(v3(-1.2_f32, 0.3_f32, 0), v3(0.1_f32, 0.1_f32, 10))
      chamber = Chamber.new(5, title(5), line(5), v3(-5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.buttons << button
      chamber.doors << door
      chamber.lasers << laser
      chamber.cubes << Cube.new(b, v3(-4, 1, 3))
      chamber
    end

    # 06: a lift with two controls. The up-control rides the platform, so the player
    # steps on, holds it down and rides; the other is on the deck it delivers them to.
    private def chamber_06(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 8, 5)
      sill = 5.2_f32
      shell(b, lo, hi, 0, sill)
      # The deck runs from beside the lift out to the exit wall, narrow enough that the
      # room still reads as a room.
      b.wall(v3(3.9, sill / 2, 0), v3(6.2_f32, sill, 5))
      b.trim(v3(3.9, sill + 0.06_f32, 0), v3(6.2_f32, 0.12_f32, 5))
      lift = Lift.new(b, v3(-0.4, 0, 0), 0.35_f32, sill)
      ride = Button.new(b, v3(-0.4, 0.65_f32, 0))
      descend = Button.new(b, v3(2.2, sill + 0.12_f32, 1.4_f32))
      ride.receivers << lift
      # The deck control sends the lift back down, hence the inverter.
      descend.receivers << Inverter.new(lift)
      lift.rider = ride
      chamber = Chamber.new(6, title(6), line(6), v3(-4.5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, sill, 0))
      chamber.lifts << lift
      chamber.buttons << ride
      chamber.buttons << descend
      chamber
    end

    # 07: a long drop. The floor is cut away in the middle, so the only way across is
    # to build speed and fling.
    private def chamber_07(b : Builder) : Chamber
      lo = v3(-12, 0, -5)
      hi = v3(12, 9, 5)
      shell(b, lo, hi, 0)
      # The pit the player cannot survive, with a launch pad on one side and a ledge on
      # the other.
      b.floor(v3(-8, 0, 0), v3(8, 0.5, 10))
      b.floor(v3(8, 0, 0), v3(8, 0.5, 10))
      b.hazard_strip(v3(-4.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 10))
      b.hazard_strip(v3(4.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 10))
      goo = Goo.new(b, v3(0, -3, 0), v3(8, 6, 10), 0.06_f32)
      ledge(b, v3(8, 1.5, 0), v3(8, 3, 5))
      b.metal(v3(-6, 0.05, 0), v3(3, 0.1, 3))
      chamber = Chamber.new(7, title(7), line(7), v3(-10, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 3, 0))
      chamber.goos << goo
      chamber
    end

    # 08: the finale. A pit to carry a cube across, and a laser that has to be blocked
    # by the second one before the exit will open.
    private def chamber_08(b : Builder) : Chamber
      lo = v3(-9, 0, -7)
      hi = v3(9, 6, 7)
      shell(b, lo, hi, 0)
      # A pit splits the room in two; both platforms are at floor level.
      b.floor(v3(-6, 0, 0), v3(6, 0.5, 14))
      b.floor(v3(6, 0, 0), v3(6, 0.5, 14))
      b.hazard_strip(v3(-3.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 14))
      b.hazard_strip(v3(3.1_f32, 0.3_f32, 0), v3(0.2_f32, 0.1_f32, 14))
      goo = Goo.new(b, v3(0, -1.5_f32, 0), v3(6, 3, 14), 0.06_f32)
      # The laser crosses the right platform, so one cube has to sit in the beam before
      # the player can reach the button behind it.
      laser = Laser.new(b, v3(5.5, 0, -6.4), v3(5.5, 0, 6.4))
      button = Button.new(b, v3(7.2, 0.06_f32, 0))
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button.receivers << door
      chamber = Chamber.new(8, title(8), line(8), v3(-7, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.goos << goo
      chamber.lasers << laser
      chamber.buttons << button
      chamber.doors << door
      chamber.cubes << Cube.new(b, v3(-5, 1, 2.5))
      chamber.cubes << Cube.new(b, v3(4, 1, 3.5))
      chamber
    end

    # 09: the two cube types. Each plate only answers to its own colour.
    private def chamber_09(b : Builder) : Chamber
      lo = v3(-8, 0, -5)
      hi = v3(8, 5, 5)
      shell(b, lo, hi, 0)
      red_door = Door.new(b, v3(2.0, 0, 0))
      blue_door = Door.new(b, v3(5.6, 0, 0))
      red_button = Button.new(b, v3(-2, 0.06, 2.6), CubeKind::Red)
      blue_button = Button.new(b, v3(-2, 0.06, -2.6), CubeKind::Blue)
      red_button.receivers << red_door
      blue_button.receivers << blue_door
      chamber = Chamber.new(9, title(9), line(9), v3(-6, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.buttons << red_button << blue_button
      chamber.doors << red_door << blue_door
      chamber.cubes << Cube.new(b, v3(-5, 1, 3), CubeKind::Red)
      chamber.cubes << Cube.new(b, v3(-5, 1, -3), CubeKind::Blue)
      chamber
    end

    # 10: a sentry guards the way out. It can be knocked over, or walked around by
    # putting a portal where its line of sight does not reach.
    private def chamber_10(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 7, 5)
      shell(b, lo, hi, 0)
      ledge(b, v3(3.5, 1.75, 0), v3(7, 3.5, 4))
      chamber = Chamber.new(10, title(10), line(10), v3(-5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 3.5, 0))
      chamber.turrets << Turret.new(b, v3(2.0, 3.5, 0), v3(0, 0, -1))
      chamber
    end

    # 11: the pellet. Throw it at the catcher to lift something out of a recess.
    private def chamber_11(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 6, 5)
      shell(b, lo, hi, 0)
      ledge(b, v3(4.5, 1.5, 0), v3(5, 3, 6))
      ledge(b, v3(4.5, 3.6, 0), v3(5, 1.2, 2))
      door = Door.new(b, v3(4.5, 3.0, 0))
      catcher = BallCatcher.new(b, v3(-3, 0.06, 0))
      button = Button.new(b, v3(-3, 0.06, 3))
      button.receivers << door
      chamber = Chamber.new(11, title(11), line(11), v3(-5.5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 4.2, 0))
      chamber.balls << Ball.new(b, v3(-4, 1, -2))
      chamber.catchers << catcher
      chamber.buttons << button
      chamber.doors << door
      chamber
    end

    # 12: a materialisation field eats anything that goes through it, and a dispenser
    # keeps handing out fresh cubes, so the solution is repeatable rather than one-shot.
    private def chamber_12(b : Builder) : Chamber
      lo = v3(-8, 0, -5)
      hi = v3(8, 5, 5)
      shell(b, lo, hi, 0)
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button = Button.new(b, v3(3.5, 0.06, 0))
      button.receivers << door
      chamber = Chamber.new(12, title(12), line(12), v3(-6, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.buttons << button
      chamber.doors << door
      chamber.fizzlers << Fizzler.new(b, v3(-1.5, 1.2, 0), v3(1, 0, 0), v3(0.1, 1.2, 4))
      chamber.dispensers << CubeDispenser.new(b, v3(5, 1.4, -3))
      chamber
    end

    # 13: a launch plate. The only way up is to be thrown.
    private def chamber_13(b : Builder) : Chamber
      lo = v3(-7, 0, -5)
      hi = v3(7, 7, 5)
      shell(b, lo, hi, 0)
      plate = FaithPlate.new(b, v3(-3, 0.06, 0))
      ledge(b, v3(3.5, 2.2, 0), v3(7, 4.4, 5))
      chamber = Chamber.new(13, title(13), line(13), v3(-5.5, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 4.4, 0))
      chamber.faith_plates << plate
      chamber
    end

    # 14: a bridge that is only there while something stands on its plate.
    private def chamber_14(b : Builder) : Chamber
      lo = v3(-9, 0, -5)
      hi = v3(9, 5, 5)
      shell(b, lo, hi, 0)
      # A gap in the floor, with a plate on one side and a walkway that folds out over it.
      b.floor(v3(-6, 0, 0), v3(6, 0.5, 10))
      b.floor(v3(6, 0, 0), v3(6, 0.5, 10))
      bridge = Bridge.new(b, v3(0, -0.15, 0), v3(0, 0.1, 0), v3(5.4, 0.3, 3))
      plate = Button.new(b, v3(-4.5, 0.06, 0))
      plate.receivers << bridge
      chamber = Chamber.new(14, title(14), line(14), v3(-7, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.bridges << bridge
      chamber.buttons << plate
      chamber
    end

    # 15: the pellet is light enough to sit on a plate and hold a door open while the
    # player is somewhere else entirely.
    private def chamber_15(b : Builder) : Chamber
      lo = v3(-8, 0, -5)
      hi = v3(8, 5, 5)
      shell(b, lo, hi, 0)
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button = Button.new(b, v3(2.0, 0.06, 0))
      button.receivers << door
      chamber = Chamber.new(15, title(15), line(15), v3(-6, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.balls << Ball.new(b, v3(-4, 1, 2))
      chamber.catchers << BallCatcher.new(b, v3(5, 0.06, 3), false)
      chamber.buttons << button
      chamber.doors << door
      chamber
    end

    # 16: knock the sentry out with a cube. Momentum does the work.
    private def chamber_16(b : Builder) : Chamber
      lo = v3(-9, 0, -5)
      hi = v3(9, 8, 6)
      shell(b, lo, hi, 0)
      ledge(b, v3(3.25, 2.6, 0), v3(11.5, 5.2, 4))
      chamber = Chamber.new(16, title(16), line(16), v3(-7, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 5.2, 0))
      chamber.turrets << Turret.new(b, v3(4.5, 5.2, 0), v3(0, 0, -1))
      chamber.faith_plates << FaithPlate.new(b, v3(-2.5, 0.06, 0))
      chamber.cubes << Cube.new(b, v3(-6, 1, 3))
      chamber
    end

    # 17: a field in the way of the plate, and a dispenser that does not care.
    private def chamber_17(b : Builder) : Chamber
      lo = v3(-8, 0, -5)
      hi = v3(8, 8, 5)
      shell(b, lo, hi, 0)
      ledge(b, v3(4.5, 1.6, 0), v3(5, 3.2, 6))
      # The exit is up on a second deck, level with the dispenser shelf.
      ledge(b, v3(5.5, 3.4, 0), v3(5, 2.4, 6))
      door = Door.new(b, v3(4.5, 3.0, 0))
      button = Button.new(b, v3(-3, 0.06, 0))
      button.receivers << door
      chamber = Chamber.new(17, title(17), line(17), v3(-6, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 4.6, 0))
      chamber.buttons << button
      chamber.doors << door
      chamber.fizzlers << Fizzler.new(b, v3(0.5, 1.2, 0), v3(1, 0, 0), v3(0.1, 1.2, 4))
      chamber.dispensers << CubeDispenser.new(b, v3(-6, 1.4, 3))
      chamber.cubes << Cube.new(b, v3(-6, 1, -3))
      chamber
    end

    # 18: a sentry, a laser and a pit, in the same room.
    private def chamber_18(b : Builder) : Chamber
      lo = v3(-10, 0, -6)
      hi = v3(10, 6, 6)
      shell(b, lo, hi, 0)
      b.floor(v3(-6.5, 0, 0), v3(7, 0.5, 12))
      b.floor(v3(6.5, 0, 0), v3(7, 0.5, 12))
      b.hazard_strip(v3(-3.1_f32, 0.3, 0), v3(0.2, 0.1, 12))
      b.hazard_strip(v3(3.1_f32, 0.3, 0), v3(0.2, 0.1, 12))
      goo = Goo.new(b, v3(0, -1.5, 0), v3(6, 3, 12), 0.06_f32)
      laser = Laser.new(b, v3(7.2, 0, -5.4), v3(7.2, 0, 5.4))
      button = Button.new(b, v3(8.6, 0.06, 0))
      door = Door.new(b, v3(hi.x - 0.1_f32, 0, 0))
      button.receivers << door
      chamber = Chamber.new(18, title(18), line(18), v3(-8, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 0, 0))
      chamber.goos << goo
      chamber.lasers << laser
      chamber.buttons << button
      chamber.doors << door
      chamber.turrets << Turret.new(b, v3(-2.0, 0, 0), v3(1, 0, 0))
      chamber.cubes << Cube.new(b, v3(-7, 1, 3))
      chamber
    end

    # 19: the last one. Every element the facility has, arranged so none of them
    # matter on their own.
    private def chamber_19(b : Builder) : Chamber
      lo = v3(-11, 0, -7)
      hi = v3(11, 8, 7)
      shell(b, lo, hi, 0)
      b.floor(v3(-7, 0, 0), v3(8, 0.5, 14))
      b.floor(v3(7, 0, 0), v3(8, 0.5, 14))
      b.hazard_strip(v3(-3.1_f32, 0.3, 0), v3(0.2, 0.1, 14))
      b.hazard_strip(v3(3.1_f32, 0.3, 0), v3(0.2, 0.1, 14))
      goo = Goo.new(b, v3(0, -2, 0), v3(6, 4, 14), 0.06_f32)
      # The upper deck, reached by a launch plate and guarded by a sentry.
      ledge(b, v3(7, 2.2, 0), v3(8, 4.4, 14))
      red_button = Button.new(b, v3(5.5, 4.46, 0), CubeKind::Red)
      blue_button = Button.new(b, v3(8.5, 4.46, 0), CubeKind::Blue)
      red_door = Door.new(b, v3(7, 4.4, 0))
      blue_door = Door.new(b, v3(hi.x - 0.1_f32, 4.4, 0))
      red_button.receivers << red_door
      blue_button.receivers << blue_door
      chamber = Chamber.new(19, title(19), line(19), v3(-9, 1, 0), v3(1, 0, 0), exit_frame(b, hi.x, 4.4, 0))
      chamber.goos << goo
      chamber.buttons << red_button << blue_button
      chamber.doors << red_door << blue_door
      chamber.turrets << Turret.new(b, v3(3.6, 4.4, 0), v3(1, 0, 0))
      chamber.faith_plates << FaithPlate.new(b, v3(-6, 0.06, 0))
      chamber.fizzlers << Fizzler.new(b, v3(0, 1.2, 3.5), v3(0, 0, 1), v3(4, 1.2, 0.1))
      chamber.dispensers << CubeDispenser.new(b, v3(-9, 1.4, 4))
      chamber.cubes << Cube.new(b, v3(-8, 1, -3), CubeKind::Blue)
      chamber.balls << Ball.new(b, v3(-8, 1, 3))
      chamber.catchers << BallCatcher.new(b, v3(9, 4.46, 4))
      chamber
    end
  end
end
