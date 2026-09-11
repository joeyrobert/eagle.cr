require "../spec_helper"

alias P3 = Eagle::Physics3D

private def ws(shape, pos, rot = Quat::IDENTITY)
  P3::WorldShape.new(shape, pos, rot)
end

describe Eagle::Physics3D::Collision do
  it "sphere-sphere" do
    m = P3::Collision.test(ws(P3::Sphere.new(1), v3(0, 0, 0)), ws(P3::Sphere.new(1), v3(1.5, 0, 0))).not_nil!
    m.normal.approx?(v3(1, 0, 0)).should be_true
    m.penetration.should be_close(0.5, 1e-5)
    P3::Collision.test(ws(P3::Sphere.new(1), v3(0, 0, 0)), ws(P3::Sphere.new(1), v3(2.5, 0, 0))).should be_nil
  end

  it "sphere-box faces, edges and rotated boxes" do
    box = ws(P3::Cuboid.new(v3(2, 2, 2)), Vec3::ZERO)
    m = P3::Collision.test(ws(P3::Sphere.new(0.5), v3(0, 1.3, 0)), box).not_nil!
    m.normal.approx?(v3(0, -1, 0)).should be_true
    m.penetration.should be_close(0.2, 1e-5)
    m.contacts[0].approx?(v3(0, 1, 0)).should be_true
    edge = P3::Collision.test(ws(P3::Sphere.new(0.5), v3(1.3, 1.3, 0)), box).not_nil!
    edge.penetration.should be_close(0.5 - Math.sqrt(0.18), 1e-4)
    inside = P3::Collision.test(ws(P3::Sphere.new(0.5), v3(0.2, 0, 0)), box).not_nil!
    inside.penetration.should be > 1
    rot = ws(P3::Cuboid.new(v3(2, 2, 2)), Vec3::ZERO, Quat.from_axis_angle(Vec3::BACK, Math::PI / 4))
    P3::Collision.test(ws(P3::Sphere.new(0.3), v3(0, 1.3, 0)), rot).not_nil!.penetration.should be > 0.3 # corner points up
    P3::Collision.test(ws(P3::Sphere.new(0.3), v3(1.3, 0, 0)), box).not_nil!.normal.approx?(v3(-1, 0, 0)).should be_true
    P3::Collision.test(box, ws(P3::Sphere.new(0.5), v3(0, 1.3, 0))).not_nil!.normal.approx?(v3(0, 1, 0)).should be_true
  end

  it "box-box face contact with up to four points" do
    a = ws(P3::Cuboid.new(v3(2, 2, 2)), Vec3::ZERO)
    b = ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0, 1.4, 0))
    m = P3::Collision.test(a, b).not_nil!
    m.normal.approx?(v3(0, 1, 0)).should be_true
    m.penetration.should be_close(0.1, 1e-5)
    m.contacts.size.should eq 4
    m.contacts.each { |c| c.y.should be_close(1, 1e-4) }
    P3::Collision.test(a, ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0, 1.6, 0))).should be_nil
    # overhanging box: only the covered corners count
    over = P3::Collision.test(a, ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0.8, 1.4, 0))).not_nil!
    over.contacts.size.should eq 2
  end

  it "box-box rotated (edge and face axes)" do
    a = ws(P3::Cuboid.new(v3(2, 2, 2)), Vec3::ZERO)
    tilted = ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0, 1.6, 0), Quat.from_axis_angle(Vec3::BACK, Math::PI / 4))
    m = P3::Collision.test(a, tilted).not_nil!
    m.normal.y.should be > 0.9
    m.penetration.should be_close(Math.sqrt(0.5) - 0.6, 1e-3)
    m.contacts.size.should eq 2 # the resting edge's two vertices
    far = ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0, 1.8, 0), Quat.from_axis_angle(Vec3::BACK, Math::PI / 4))
    P3::Collision.test(a, far).should be_nil
    # edge-edge: two unit cubes rotated 45° about different axes touching at edges
    e1 = ws(P3::Cuboid.new(v3(1, 1, 1)), Vec3::ZERO, Quat.from_axis_angle(Vec3::BACK, Math::PI / 4))
    e2 = ws(P3::Cuboid.new(v3(1, 1, 1)), v3(1.25, 0, 0), Quat.from_axis_angle(Vec3::UP, Math::PI / 4)) # edges cross at x≈0.6
    m2 = P3::Collision.test(e1, e2).not_nil!
    m2.penetration.should be > 0
    m2.contacts.size.should eq 1
  end

  it "raycasts" do
    box = ws(P3::Cuboid.new(v3(2, 2, 2)), v3(5, 0, 0), Quat.from_axis_angle(Vec3::UP, Math::PI / 4))
    t, n = P3::Collision.ray(v3(0, 0, 0), v3(1, 0, 0), 100_f32, box).not_nil!
    t.should be_close(5 - Math.sqrt(2), 1e-3)
    n.x.should be < -0.7
    P3::Collision.ray(v3(0, 5, 0), v3(1, 0, 0), 100_f32, box).should be_nil
    sph = ws(P3::Sphere.new(1), v3(0, 0, -5))
    t, n = P3::Collision.ray(v3(0, 0, 0), v3(0, 0, -1), 100_f32, sph).not_nil!
    t.should be_close(4, 1e-4)
    n.approx?(v3(0, 0, 1)).should be_true
  end
end

describe Eagle::Physics3D::World do
  it "drops a sphere onto a floor and it rests" do
    w = P3::World.new
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    ball = w.add(P3::BodyType::Dynamic, v3(0, 3, 0), P3::Sphere.new(0.5))
    began = 0
    w.on_contact_begin { |a, b| began += 1 }
    180.times { w.step(1 / 60_f32) }
    ball.position.y.should be_close(0.5, 0.02)
    ball.velocity.length.should be < 0.05
    began.should eq 1
  end

  it "stacks boxes and lets them settle" do
    w = P3::World.new
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    boxes = (0...3).map { |i| w.add(P3::BodyType::Dynamic, v3(0, 0.5 + i * 1.02, 0), P3::Cuboid.cube(1)) }
    240.times { w.step(1 / 60_f32) }
    boxes.each_with_index do |b, i|
      b.position.y.should be_close(0.5 + i, 0.05)
      b.position.xz.length.should be < 0.05
      (b.rotation * Vec3::UP).y.should be > 0.99
    end
  end

  it "bounces, slides, filters layers and reports sensors" do
    w = P3::World.new
    floor = w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    bouncy = w.add(P3::BodyType::Dynamic, v3(2, 3, 0), P3::Sphere.new(0.5))
    bouncy.restitution = 0.8_f32
    peak = 0_f32; landed = false
    120.times do
      w.step(1 / 60_f32)
      landed = true if bouncy.velocity.y > 0
      peak = Math.max(peak, bouncy.velocity.y) if landed
    end
    peak.should be > 3
    ghost = w.add(P3::BodyType::Dynamic, v3(-2, 2, 0), P3::Sphere.new(0.5))
    ghost.mask = 2_u32
    sensor = w.add(P3::BodyType::Kinematic, v3(-2, 1, 0), P3::Sphere.new(1))
    sensor.sensor = true; sensor.layer = 2_u32
    entered = [] of P3::Body
    w.on_contact_begin { |a, b| entered << (a == sensor ? b : a) if a == sensor || b == sensor }
    120.times { w.step(1 / 60_f32) }
    ghost.position.y.should be < -1 # fell through the floor (layer filtered)
    entered.should eq [ghost]
    slider = w.add(P3::BodyType::Dynamic, v3(-5, 0.5, 0), P3::Cuboid.cube(1))
    slider.velocity = v3(5, 0, 0)
    slider.friction = 1_f32
    60.times { w.step(1 / 60_f32) }
    slider.velocity.x.should be < 2
  end

  it "queries and raycasts the world" do
    w = P3::World.new
    a = w.add(P3::BodyType::Static, v3(0, 0, 0), P3::Sphere.new(1))
    b = w.add(P3::BodyType::Static, v3(10, 0, 0), P3::Cuboid.cube(2))
    w.query_point(v3(0.5, 0, 0)).should eq [a]
    w.query_point(v3(5, 0, 0)).should be_empty
    w.query_aabb(AABB.new(v3(8, -1, -1), v3(12, 1, 1))).should eq [b]
    w.query_sphere(v3(9, 0, 0), 0.5).should eq [b]
    hit = w.raycast(v3(-5, 0, 0), v3(1, 0, 0)).not_nil!
    hit.body.should eq a
    hit.distance.should be_close(4, 1e-3)
    w.raycast(v3(-5, 0, 0), v3(1, 0, 0), exclude: a).not_nil!.body.should eq b
    w.raycast(v3(-5, 0, 0), v3(1, 0, 0), max_distance: 2).should be_nil
  end

  it "applies impulses with rotation and moves kinematic bodies with sliding" do
    w = P3::World.new
    w.gravity = Vec3::ZERO
    b = w.add(P3::BodyType::Dynamic, Vec3::ZERO, P3::Cuboid.cube(1))
    b.apply_impulse(v3(0, 0, -1), v3(0.5, 0, 0)) # off-centre: spins about Y
    w.step(1 / 60_f32)
    b.velocity.z.should be < 0
    b.angular_velocity.y.abs.should be > 0
    w2 = P3::World.new
    w2.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    w2.add(P3::BodyType::Static, v3(5, 1, 0), P3::Cuboid.new(v3(1, 4, 20)))
    k = w2.add(P3::BodyType::Kinematic, v3(0, 0.5, 0), P3::Cuboid.cube(1))
    normals = w2.move_and_slide(k, v3(0, -1, 0))
    normals[0].approx?(v3(0, 1, 0), 1e-3).should be_true
    k.position.y.should be_close(0.5, 0.01)
    w2.move_and_slide(k, v3(10, 0, 0))[0].approx?(v3(-1, 0, 0), 1e-3).should be_true
    k.position.x.should be_close(4, 0.01)
  end
end

describe Eagle::CollisionObject3D do
  before_each { SceneTree.reset; Physics3D.reset }

  it "syncs nodes and emits signals" do
    root = SceneTree.root
    floor = StaticBody3D.new(position: v3(0, -0.5, 0)).box(20, 1, 20)
    ball = RigidBody3D.new(position: v3(0, 3, 0)).sphere(0.5)
    hits = [] of CollisionObject3D
    ball.on_body_entered { |o| hits << o }
    root.add(floor, ball)
    Physics3D.active?.should be_true
    180.times do
      Physics3D.world.step(1 / 60_f32)
      root.physics_process_tree(1 / 60_f32)
    end
    ball.position.y.should be_close(0.5, 0.02)
    hits.should eq [floor]
    ball.free
    Physics3D.world.bodies.size.should eq 1
  end

  it "character body walks, slides and detects the floor; areas and rays work" do
    root = SceneTree.root
    floor = StaticBody3D.new(position: v3(0, -0.5, 0)).box(20, 1, 20)
    wall = StaticBody3D.new(position: v3(4, 1, 0)).box(1, 4, 20)
    area = Area3D.new(position: v3(2, 1.2, 0)).sphere(0.5) # above the floor, overlapping the player's top
    player = KinematicBody3D.new(position: v3(0, 0.5, 0)).box(0.8, 1, 0.8)
    entered = [] of CollisionObject3D
    area.on_body_entered { |o| entered << o }
    root.add(floor, wall, area, player)
    player.velocity = v3(3, -1, 0)
    hit_wall = false
    90.times do
      player.move_and_slide(1 / 60_f32)
      hit_wall ||= player.on_wall?
      Physics3D.world.step(1 / 60_f32)
      root.physics_process_tree(1 / 60_f32)
    end
    player.on_floor?.should be_true
    hit_wall.should be_true
    player.velocity.x.should eq 0 # wall cancelled the horizontal velocity
    player.position.x.should be_close(3.1, 0.05)
    entered.should eq [player]
    ray = RayCast3D.new(v3(0, -2, 0))
    player.add(ray)
    ray.update_cast
    ray.collider.should eq floor
  end
end
