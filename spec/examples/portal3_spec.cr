require "../spec_helper"
require "../../examples/portal3/portal3/portals"

# Two walls back to back: one facing +X, one facing -X. This is the classic two-room
# setup and it isolates the transform from any real chamber geometry. Placements are
# immutable, so constants are the simplest way to share them across examples.
WEST_ROOM    = Portal3::Placement.new(v3(0, 1.2, 0), v3(1, 0, 0), v3(0, 1, 0))
EAST_ROOM    = Portal3::Placement.new(v3(0, 1.2, 0), v3(-1, 0, 0), v3(0, 1, 0))
FLOOR_PORTAL = Portal3::Placement.new(v3(5, 0, 5), v3(0, 1, 0), v3(0, 0, -1))
WALL_PORTAL  = Portal3::Placement.new(v3(0, 1.2, 0), v3(1, 0, 0), v3(0, 1, 0))

# The traversal maths is the part of a Portal game that is easiest to get subtly wrong,
# so it is tested directly against placements rather than through the renderer.
describe Portal3::Teleport do
  it "aligns a wall portal to world up" do
    p = Portal3::Placement.from_hit(v3(0, 1.2, 0), v3(1, 0, 0))
    p.up.y.should be_close(1.0, 0.001)
    p.up.x.should be_close(0.0, 0.001)
    p.normal.x.should be_close(1.0, 0.001)
    p.normal.y.should be_close(0.0, 0.001)
  end

  it "keeps the placement basis orthonormal" do
    p = Portal3::Placement.from_hit(v3(0, 1.2, 0), v3(0, 1, 0))
    p.up.dot(p.normal).abs.should be_close(0.0, 0.001)
    p.right.dot(p.normal).abs.should be_close(0.0, 0.001)
    p.right.dot(p.up).abs.should be_close(0.0, 0.001)
    p.up.length.should be_close(1.0, 0.001)
  end

  it "carries a straight walk straight through" do
    # Two portals in the same wall plane face opposite ways, so a player walking into
    # one leaves the other still heading the same way, out into the far room.
    out = Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, v3(-1, 0, 0))
    out.x.should be_close(-1.0, 0.001)
    out.y.should be_close(0.0, 0.001)
    out.z.should be_close(0.0, 0.001)
  end

  it "sends a player entering a wall out into the room beyond" do
    # West and east rooms sit either side of the plane. Heading away from the west
    # wall must leave heading away from the east wall, or the player would emerge
    # inside it.
    out = Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, v3(-1, 0, 0))
    out.dot(EAST_ROOM.normal).should be > 0
  end

  it "is a proper rotation, not a mirror" do
    # A reflection would silently corrupt momentum and handedness. The determinant of
    # the linear part must be +1.
    r = Portal3::Teleport.rotation(WEST_ROOM, EAST_ROOM)
    det = r[0, 0] * (r[1, 1] * r[2, 2] - r[2, 1] * r[1, 2]) -
          r[0, 1] * (r[1, 0] * r[2, 2] - r[2, 0] * r[1, 2]) +
          r[0, 2] * (r[1, 0] * r[2, 1] - r[2, 0] * r[1, 1])
    det.should be_close(1.0, 0.001)
  end

  it "carries a player from a wall out past a facing pair" do
    # A corridor: two portals facing each other ten metres apart. Walking into the
    # near one must leave the far one heading back down the corridor.
    left = Portal3::Placement.new(v3(0, 1.2, 0), v3(1, 0, 0), v3(0, 1, 0))
    right = Portal3::Placement.new(v3(10, 1.2, 0), v3(-1, 0, 0), v3(0, 1, 0))
    out = Portal3::Teleport.direction(left, right, v3(-1, 0, 0))
    out.x.should be_close(-1.0, 0.001)
    out.dot(right.normal).should be > 0
    # The transform only applies once something is crossing, so the opening itself
    # must land exactly on the far opening.
    exit = Portal3::Teleport.point(left, right, v3(0, 1.2, 0))
    exit.x.should be_close(10.0, 0.001)
  end

  it "preserves the speed of a fast entry" do
    velocity = v3(12, 0, 0)
    out = Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, velocity)
    out.length.should be_close(velocity.length, 0.001)
  end

  it "keeps the player upright through a traversal" do
    Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, v3(1, 0, 0)).y.should be_close(0.0, 0.001)
    Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, v3(1, 3, 0)).y.should be_close(3.0, 0.001)
  end

  it "flips handedness on exit" do
    # The invariant: stepping to the player's right on one side leaves as the
    # opposite lateral direction on the other, which is the mirror Portal performs.
    out = Portal3::Teleport.direction(WEST_ROOM, EAST_ROOM, WEST_ROOM.right)
    out.x.should be_close((-EAST_ROOM.right).x, 0.001)
    out.y.should be_close((-EAST_ROOM.right).y, 0.001)
    out.z.should be_close((-EAST_ROOM.right).z, 0.001)
  end

  it "maps the source plane onto the destination plane" do
    # Whatever crosses the opening comes out on the far opening, not in front of it.
    exit = Portal3::Teleport.point(WEST_ROOM, EAST_ROOM, v3(0, 1.2, 0.4))
    exit.x.should be_close(0.0, 0.001)
    exit.y.should be_close(1.2, 0.001)
    # The tangential offset is mirrored, so a player who enters off-centre comes out
    # off-centre on the opposite side.
    exit.z.should be_close(0.4, 0.001)
  end

  it "detects a player walking through" do
    Portal3::Teleport.crosses?(v3(1, 1.2, 0), v3(-1, 1.2, 0), WEST_ROOM, EAST_ROOM).should be_true
  end

  it "ignores a player who does not reach the portal" do
    Portal3::Teleport.crosses?(v3(1, 1.2, 3), v3(-1, 1.2, 3), WEST_ROOM, EAST_ROOM).should be_false
  end

  it "ignores a player who is already behind the portal" do
    # Travelling away from the wall must not read as a traversal.
    Portal3::Teleport.crosses?(v3(-1, 1.2, 0), v3(1, 1.2, 0), WEST_ROOM, EAST_ROOM).should be_false
  end

  it "ignores a player too high up the wall" do
    Portal3::Teleport.crosses?(v3(1, 4.0, 0), v3(-1, 4.0, 0), WEST_ROOM, EAST_ROOM).should be_false
  end

  it "round-trips a point back to where it started" do
    start = v3(1.5, 1.6, 0.3)
    there = Portal3::Teleport.point(WEST_ROOM, EAST_ROOM, start)
    back = Portal3::Teleport.point(EAST_ROOM, WEST_ROOM, there)
    back.x.should be_close(start.x, 0.001)
    back.y.should be_close(start.y, 0.001)
    back.z.should be_close(start.z, 0.001)
  end

  it "maps a floor portal's up onto a wall portal's up" do
    # The floor portal's up is (0,0,-1); rotating it into the wall portal's frame
    # must land on the wall portal's own up.
    out = Portal3::Teleport.direction(FLOOR_PORTAL, WALL_PORTAL, FLOOR_PORTAL.up)
    out.y.should be_close(WALL_PORTAL.up.y, 0.001)
    out.x.should be_close(WALL_PORTAL.up.x, 0.001)
    out.z.should be_close(WALL_PORTAL.up.z, 0.001)
  end

  it "sends a player out of a floor portal into a wall's room" do
    # Falling onto a floor portal must arrive travelling away from the wall it links
    # to, not into it.
    out = Portal3::Teleport.direction(FLOOR_PORTAL, WALL_PORTAL, FLOOR_PORTAL.normal)
    out.dot(WALL_PORTAL.normal).should be < 0
    out.length.should be_close(1.0, 0.001)
  end

  it "puts a floor portal's exit on the wall it links to" do
    # One metre "up" from the floor portal becomes one metre up from the wall
    # portal's centre, and the 0.1m height becomes 0.1m out from the wall.
    exit = Portal3::Teleport.point(FLOOR_PORTAL, WALL_PORTAL, v3(5, 0.1, 4))
    exit.x.should be_close(-0.1, 0.001)
    exit.y.should be_close(2.2, 0.001)
    exit.z.should be_close(0.0, 0.001)
  end
end
