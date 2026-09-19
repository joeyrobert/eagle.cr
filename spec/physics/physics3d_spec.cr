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

describe "Physics3D capsules" do
  it "computes volume, bounds and segment constructors" do
    c = P3::Capsule.new(0.5, 1)
    c.half_height.should be_close(0.5, 1e-6)
    c.local_aabb.size.y.should be_close(2, 1e-5)
    c.volume.should be_close(Math::PI * 0.25 + 4 / 3.0 * Math::PI * 0.125, 1e-4)
    seg = P3::Capsule.from_segment(v3(0, 0, 0), v3(0, 2, 0), 0.25)
    seg.offset.approx?(v3(0, 1, 0)).should be_true
    P3::Capsule.with_half_height(0.5, 1).height.should be_close(2, 1e-6)
  end

  it "capsule-sphere, capsule-capsule and capsule-box contacts" do
    cap = ws(P3::Capsule.new(0.5, 2), Vec3::ZERO)
    m = P3::Collision.test(cap, ws(P3::Sphere.new(0.5), v3(0.9, 0.3, 0))).not_nil!
    m.normal.approx?(v3(1, 0, 0)).should be_true
    m.penetration.should be_close(0.1, 1e-4)
    P3::Collision.test(cap, ws(P3::Sphere.new(0.5), v3(1.2, 0, 0))).should be_nil
    # the cap reaches past the cylinder
    P3::Collision.test(cap, ws(P3::Sphere.new(0.5), v3(0, 1.9, 0))).not_nil!.penetration.should be_close(0.1, 1e-4)
    parallel = P3::Collision.test(cap, ws(P3::Capsule.new(0.5, 2), v3(0.8, 0, 0))).not_nil!
    parallel.normal.approx?(v3(1, 0, 0)).should be_true
    parallel.penetration.should be_close(0.2, 1e-4)
    P3::Collision.test(cap, ws(P3::Capsule.new(0.5, 2), v3(1.2, 0, 0))).should be_nil
    box = ws(P3::Cuboid.new(v3(4, 1, 4)), v3(0, -1.9, 0))
    b = P3::Collision.test(cap, box).not_nil!
    b.normal.approx?(v3(0, -1, 0)).should be_true
    b.penetration.should be_close(0.1, 1e-3)
    P3::Collision.test(box, cap).not_nil!.normal.approx?(v3(0, 1, 0)).should be_true
  end

  it "raycasts and queries capsules" do
    w = P3::World.new
    body = w.add(P3::BodyType::Static, Vec3::ZERO, P3::Capsule.new(0.5, 2))
    hit = w.raycast(v3(-5, 0, 0), Vec3::RIGHT).not_nil!
    hit.distance.should be_close(4.5, 1e-3)
    hit.body.should eq body
    w.raycast(v3(-5, 1.4, 0), Vec3::RIGHT).not_nil!.distance.should be > 4.5
    w.raycast(v3(-5, 2, 0), Vec3::RIGHT).should be_nil
    w.query_point(v3(0, 1.4, 0)).should eq [body]
    w.query_point(v3(0, 1.6, 0)).should be_empty
  end

  it "a dynamic capsule falls, tips over and rests on its side or upright" do
    w = P3::World.new
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    cap = w.add(P3::BodyType::Dynamic, v3(0, 3, 0), P3::Capsule.new(0.5, 1))
    240.times { w.step(1 / 60_f32) }
    cap.velocity.length.should be < 0.1
    # upright rests at 1.0, on its side at 0.5
    (cap.position.y > 0.45 && cap.position.y < 1.05).should be_true
  end

  it "an upright capsule stays upright on flat ground" do
    w = P3::World.new
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    cap = w.add(P3::BodyType::Dynamic, v3(0, 1.05, 0), P3::Capsule.new(0.5, 1))
    cap.fixed_rotation = true
    120.times { w.step(1 / 60_f32) }
    cap.position.y.should be_close(1, 0.03)
  end
end

describe "Physics3D mesh colliders" do
  quad = [v3(-5, 0, -5), v3(5, 0, -5), v3(5, 0, 5), v3(-5, 0, 5)]
  floor = -> { P3::MeshCollider.from_triangles(quad, [0, 2, 1, 0, 3, 2]) }

  it "builds from vertices, indices and meshes" do
    m = floor.call
    m.triangles.size.should eq 2
    m.local_aabb.size.x.should be_close(10, 1e-5)
    P3::MeshCollider.from_triangles([v3(0, 0, 0), v3(1, 0, 0), v3(0, 0, 1)]).triangles.size.should eq 1
    P3::MeshCollider.from_mesh(Mesh.cube(1)).triangles.size.should eq 12
    m.volume.should eq 0
  end

  it "collides with spheres, capsules and boxes from the top face" do
    mesh = ws(floor.call, Vec3::ZERO)
    s = P3::Collision.test(ws(P3::Sphere.new(0.5), v3(0, 0.4, 0)), mesh).not_nil!
    s.normal.approx?(v3(0, -1, 0)).should be_true
    s.penetration.should be_close(0.1, 1e-4)
    P3::Collision.test(ws(P3::Sphere.new(0.5), v3(0, 0.6, 0)), mesh).should be_nil
    P3::Collision.test(ws(P3::Sphere.new(0.5), v3(9, 0.4, 0)), mesh).should be_nil
    c = P3::Collision.test(ws(P3::Capsule.new(0.5, 1), v3(0, 0.9, 0)), mesh).not_nil!
    c.penetration.should be_close(0.1, 1e-3)
    b = P3::Collision.test(ws(P3::Cuboid.new(v3(1, 1, 1)), v3(0, 0.45, 0)), mesh).not_nil!
    b.penetration.should be_close(0.05, 1e-3)
    P3::Collision.test(mesh, ws(P3::Sphere.new(0.5), v3(0, 0.4, 0))).not_nil!.normal.approx?(v3(0, 1, 0)).should be_true
  end

  it "catches dynamic bodies and answers raycasts" do
    w = P3::World.new
    ground = w.add(P3::BodyType::Static, Vec3::ZERO, floor.call)
    ball = w.add(P3::BodyType::Dynamic, v3(0, 2, 0), P3::Sphere.new(0.5))
    box = w.add(P3::BodyType::Dynamic, v3(2, 2, 0), P3::Cuboid.cube(1))
    cap = w.add(P3::BodyType::Dynamic, v3(-2, 2, 0), P3::Capsule.new(0.3, 0.6))
    cap.fixed_rotation = true
    240.times { w.step(1 / 60_f32) }
    ball.position.y.should be_close(0.5, 0.03)
    box.position.y.should be_close(0.5, 0.03)
    cap.position.y.should be_close(0.6, 0.04)
    hit = w.raycast(v3(3, 5, 3), Vec3::DOWN).not_nil!
    hit.distance.should be_close(5, 1e-3)
    hit.body.should eq ground
    w.raycast(v3(30, 5, 3), Vec3::DOWN).should be_nil
  end

  it "rolls a ball down a sloped mesh" do
    w = P3::World.new
    ramp = [v3(-5, 2, -5), v3(5, 0, -5), v3(5, 0, 5), v3(-5, 2, 5)]
    w.add(P3::BodyType::Static, Vec3::ZERO, P3::MeshCollider.from_triangles(ramp, [0, 2, 1, 0, 3, 2]))
    ball = w.add(P3::BodyType::Dynamic, v3(-2, 3, 0), P3::Sphere.new(0.5))
    120.times { w.step(1 / 60_f32) }
    ball.position.x.should be > -1
  end
end

describe "Physics3D joints" do
  it "a distance joint holds a bob at its length" do
    w = P3::World.new
    anchor = w.add(P3::BodyType::Static, v3(0, 5, 0), P3::Sphere.new(0.1))
    bob = w.add(P3::BodyType::Dynamic, v3(2, 5, 0), P3::Sphere.new(0.2))
    j = w.distance_joint(anchor, bob)
    j.length.should be_close(2, 1e-5)
    180.times do
      w.step(1 / 60_f32)
      (bob.position - anchor.position).length.should be_close(2, 0.1)
    end
    bob.position.y.should be < 5
  end

  it "a ball joint pins two bodies while allowing swing" do
    w = P3::World.new
    anchor = w.add(P3::BodyType::Static, v3(0, 5, 0), P3::Sphere.new(0.1))
    bob = w.add(P3::BodyType::Dynamic, v3(1, 5, 0), P3::Cuboid.cube(0.4))
    j = w.ball_joint(anchor, bob, v3(0, 5, 0))
    120.times { w.step(1 / 60_f32) }
    (j.world_anchor_b - j.world_anchor_a).length.should be < 0.05
    bob.position.y.should be < 4.9
  end

  it "a hinge only rotates around its axis" do
    w = P3::World.new
    w.gravity = Vec3.new(0, -9.81, 0)
    post = w.add(P3::BodyType::Static, v3(0, 5, 0), P3::Sphere.new(0.1))
    door = w.add(P3::BodyType::Dynamic, v3(1, 5, 0), P3::Cuboid.new(v3(2, 0.2, 0.2)))
    w.hinge_joint(post, door, v3(0, 5, 0), Vec3::BACK)
    120.times { w.step(1 / 60_f32) }
    door.position.z.abs.should be < 0.05
    door.angular_velocity.x.abs.should be < 0.5
    door.angular_velocity.y.abs.should be < 0.5
    door.position.y.should be < 4.5
    (door.position - post.position).length.should be_close(1, 0.1)
  end

  it "a fixed joint welds bodies and carries them together" do
    w = P3::World.new
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    a = w.add(P3::BodyType::Dynamic, v3(0, 3, 0), P3::Cuboid.cube(1))
    b = w.add(P3::BodyType::Dynamic, v3(1.2, 3, 0), P3::Cuboid.cube(1))
    w.fixed_joint(a, b, v3(0.6, 3, 0))
    240.times { w.step(1 / 60_f32) }
    (b.position - a.position).length.should be_close(1.2, 0.1)
    (b.position.y - a.position.y).abs.should be < 0.1
  end

  it "removes joints with their bodies" do
    w = P3::World.new
    a = w.add(P3::BodyType::Static, Vec3::ZERO, P3::Sphere.new(0.1))
    b = w.add(P3::BodyType::Dynamic, v3(1, 0, 0), P3::Sphere.new(0.1))
    j = w.distance_joint(a, b)
    w.joints.size.should eq 1
    w.remove_joint(j)
    w.joints.should be_empty
    w.distance_joint(a, b)
    w.remove_body(b)
    w.joints.should be_empty
    w.clear
    w.bodies.should be_empty
  end
end

describe "Physics3D sleeping" do
  it "puts resting bodies to sleep and wakes them on demand" do
    w = P3::World.new
    w.sleep_threshold = 0.1_f32
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    ball = w.add(P3::BodyType::Dynamic, v3(0, 1, 0), P3::Sphere.new(0.5))
    300.times { w.step(1 / 60_f32) }
    ball.sleeping?.should be_true
    ball.wake
    ball.sleeping?.should be_false
  end

  it "wakes a sleeping body when another one lands on it" do
    w = P3::World.new
    w.sleep_threshold = 0.1_f32
    w.add(P3::BodyType::Static, v3(0, -0.5, 0), P3::Cuboid.new(v3(20, 1, 20)))
    ball = w.add(P3::BodyType::Dynamic, v3(0, 0.5, 0), P3::Sphere.new(0.5))
    120.times { w.step(1 / 60_f32) }
    ball.sleeping?.should be_true
    box = w.add(P3::BodyType::Dynamic, v3(0.2, 3, 0), P3::Cuboid.cube(0.5))
    120.times { w.step(1 / 60_f32) }
    (ball.position.x.abs > 0.001 || ball.position.z.abs > 0.001).should be_true
    box.position.y.should be < 1
  end
end

describe "3D physics nodes with new shapes" do
  it "builds capsule and mesh bodies from node helpers" do
    Physics3D.reset
    body = RigidBody3D.new.capsule(0.3, 0.8)
    body.body.shapes.first.should be_a(P3::Capsule)
    floor = StaticBody3D.new.mesh(Mesh.cube(2))
    floor.body.shapes.first.should be_a(P3::MeshCollider)
    Physics3D.reset
  end
end
