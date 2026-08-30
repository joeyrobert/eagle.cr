require "../spec_helper"

include Eagle::Physics2D

describe Eagle::Physics2D::Collision do
  it "detects circle-circle" do
    a = Circle.new(10); a.center = v2(0, 0)
    b = Circle.new(10); b.center = v2(15, 0)
    m = Collision.test(a, b).not_nil!
    m.normal.should eq v2(1, 0)
    m.penetration.should be_close(5, 1e-5)
    b.center = v2(25, 0)
    Collision.test(a, b).should be_nil
  end

  it "detects circle-polygon on faces and corners" do
    box = Polygon.box(20, 20).transformed(Transform2D.identity)
    c = Circle.new(5); c.center = v2(13, 0)
    m = Collision.test(c, box).not_nil!
    m.normal.approx?(v2(-1, 0)).should be_true
    m.penetration.should be_close(2, 1e-4)
    c.center = v2(13, 13) # corner region
    m = Collision.test(c, box).not_nil!
    m.penetration.should be_close(5 - Math.sqrt(18), 1e-4)
    c.center = v2(0, 0) # inside
    Collision.test(c, box).not_nil!.penetration.should be > 10
    c.center = v2(30, 0)
    Collision.test(c, box).should be_nil
    # reversed order flips the normal
    c.center = v2(13, 0)
    Collision.test(box, c).not_nil!.normal.approx?(v2(1, 0)).should be_true
  end

  it "detects polygon-polygon with SAT and clipped contacts" do
    a = Polygon.box(20, 20).transformed(Transform2D.identity)
    b = Polygon.box(20, 20).transformed(Transform2D.translation(v2(15, 5)))
    m = Collision.test(a, b).not_nil!
    m.normal.approx?(v2(1, 0)).should be_true
    m.penetration.should be_close(5, 1e-4)
    m.contacts.size.should eq 2
    c = Polygon.box(20, 20).transformed(Transform2D.translation(v2(30, 0)))
    Collision.test(a, c).should be_nil
    rot = Polygon.box(20, 20).transformed(Transform2D.trs(v2(0, 18), Math::PI / 4, Vec2::ONE))
    Collision.test(a, rot).not_nil!.normal.y.should be > 0.9
  end

  it "casts rays against circles and polygons" do
    c = Circle.new(5); c.center = v2(20, 0)
    t, n = Collision.ray_circle(v2(0, 0), v2(1, 0), 100_f32, c).not_nil!
    t.should be_close(15, 1e-4)
    n.approx?(v2(-1, 0)).should be_true
    Collision.ray_circle(v2(0, 0), v2(0, 1), 100_f32, c).should be_nil
    box = Polygon.box(10, 10).transformed(Transform2D.translation(v2(30, 0)))
    t, n = Collision.ray_polygon(v2(0, 0), v2(1, 0), 100_f32, box).not_nil!
    t.should be_close(25, 1e-4)
    n.approx?(v2(-1, 0)).should be_true
    Collision.ray_polygon(v2(0, 0), v2(1, 0), 10_f32, box).should be_nil
  end

  it "computes polygon area, centroid, containment, winding" do
    p = Polygon.new([v2(0, 0), v2(0, 10), v2(10, 10), v2(10, 0)]) # counter-clockwise input
    p.area.should eq 100
    p.centroid.approx?(v2(5, 5)).should be_true
    p.contains?(v2(5, 5)).should be_true
    p.contains?(v2(15, 5)).should be_false
    p.normals.each { |n| n.length.should be_close(1, 1e-5) }
    # outward normals point away from the centroid
    p.points.each_with_index { |pt, i| (pt - p.centroid).dot(p.normals[i]).should be > 0 }
    Polygon.regular(6, 10).points.size.should eq 6
  end
end

describe Eagle::Physics2D::World do
  it "drops dynamic bodies onto static ground and reports contacts" do
    w = World.new
    ground = w.add(BodyType::Static, v2(0, 100), Polygon.box(1000, 20))
    ball = w.add(BodyType::Dynamic, v2(0, 0), Circle.new(10))
    ball.restitution = 0_f32
    began = [] of {Body, Body}
    w.on_contact_begin { |a, b| began << {a, b} }
    120.times { w.step(1 / 60_f32) }
    ball.position.y.should be_close(80, 1.0)
    ball.velocity.length.should be < 5
    began.size.should eq 1
    ball.contacts.should contain(ground)
    w.began.should be_empty
  end

  it "bounces with restitution and slides with friction" do
    w = World.new
    w.add(BodyType::Static, v2(0, 100), Polygon.box(1000, 20))
    ball = w.add(BodyType::Dynamic, v2(0, 0), Circle.new(10))
    ball.restitution = 0.9_f32
    max_up = 0_f32
    hit = false
    200.times do
      w.step(1 / 60_f32)
      hit = true if ball.velocity.y < 0
      max_up = Math.min(max_up, ball.velocity.y) if hit
    end
    hit.should be_true
    max_up.should be < -100
    slider = w.add(BodyType::Dynamic, v2(-200, 79), Polygon.box(20, 20))
    slider.velocity = v2(200, 0)
    slider.friction = 1_f32
    60.times { w.step(1 / 60_f32) }
    slider.velocity.x.should be < 100
  end

  it "stacks boxes" do
    w = World.new
    w.add(BodyType::Static, v2(0, 200), Polygon.box(400, 40))
    boxes = (0...4).map { |i| w.add(BodyType::Dynamic, v2(0, 160 - i * 40), Polygon.box(38, 38)) }
    180.times { w.step(1 / 60_f32) }
    boxes.each_with_index do |b, i|
      b.position.x.abs.should be < 3
      b.position.y.should be_close(161 - i * 38, 4)
    end
  end

  it "filters by layer/mask and sensors don't collide" do
    w = World.new
    ground = w.add(BodyType::Static, v2(0, 100), Polygon.box(1000, 20))
    ghost = w.add(BodyType::Dynamic, v2(0, 0), Circle.new(10))
    ghost.mask = 2_u32
    sensor = w.add(BodyType::Kinematic, v2(0, 50), Circle.new(30))
    sensor.sensor = true
    sensor.layer = 2_u32
    entered = [] of Body
    exited = [] of Body
    w.on_contact_begin { |a, b| entered << (a == sensor ? b : a) if a == sensor || b == sensor }
    w.on_contact_end { |a, b| exited << (a == sensor ? b : a) if a == sensor || b == sensor }
    60.times { w.step(1 / 60_f32) }
    ghost.position.y.should be > 120 # fell through
    entered.should eq [ghost]
    exited.should eq [ghost]
  end

  it "answers queries" do
    w = World.new
    a = w.add(BodyType::Static, v2(0, 0), Circle.new(10))
    b = w.add(BodyType::Static, v2(100, 0), Polygon.box(20, 20))
    w.query_point(v2(5, 5)).should eq [a]
    w.query_point(v2(50, 0)).should be_empty
    w.query_rect(Rect.new(90, -5, 20, 10)).should eq [b]
    hit = w.raycast(v2(-50, 0), v2(1, 0)).not_nil!
    hit.body.should eq a
    hit.distance.should be_close(40, 1e-3)
    w.raycast(v2(-50, 0), v2(1, 0), exclude: a).not_nil!.body.should eq b
    w.raycast(v2(-50, 0), v2(1, 0), max_distance: 10).should be_nil
    probe = Circle.new(15); probe.center = v2(90, 0)
    w.query_shape(probe).should eq [b]
  end

  it "applies forces, impulses and damping" do
    w = World.new
    w.gravity = Vec2::ZERO
    b = w.add(BodyType::Dynamic, v2(0, 0), Circle.new(10))
    b.mass = 2
    b.apply_impulse(v2(20, 0))
    b.velocity.should eq v2(10, 0)
    b.apply_force(v2(0, 120))
    w.step(0.5_f32)
    b.velocity.y.should be_close(30, 1e-4)
    b.linear_damping = 1
    b.apply_impulse(v2(0, 0), v2(10, 0))
    b.apply_torque(100)
    w.step(1_f32)
    b.velocity.x.should be_close(5, 1e-4)
    b.angular_velocity.should be > 0
    w.remove_body(b)
    w.bodies.should be_empty
  end

  it "moves kinematic bodies with sliding" do
    w = World.new
    w.add(BodyType::Static, v2(0, 100), Polygon.box(1000, 20))
    w.add(BodyType::Static, v2(200, 0), Polygon.box(20, 400))
    k = w.add(BodyType::Kinematic, v2(0, 70), Polygon.box(20, 40))
    normals = w.move_and_slide(k, v2(0, 50))
    normals.size.should eq 1
    normals[0].approx?(v2(0, -1)).should be_true
    k.position.y.should be_close(70, 0.1)
    w.move_and_slide(k, v2(300, 0))[0].approx?(v2(-1, 0)).should be_true
    k.position.x.should be_close(180, 0.1)
  end
end

describe Eagle::CollisionObject2D do
  before_each { SceneTree.reset; Physics2D.reset }

  it "syncs nodes with bodies and emits body signals" do
    root = SceneTree.root
    ground = StaticBody2D.new(position: v2(0, 100)).box(1000, 20)
    ball = RigidBody2D.new(position: v2(0, 0))
    ball.add(CollisionShape2D.circle(10))
    root.add(ground, ball)
    Physics2D.active?.should be_true
    Physics2D.world.bodies.size.should eq 2
    ball.body.shapes.size.should eq 1
    hits = [] of CollisionObject2D
    ball.on_body_entered { |o| hits << o }
    120.times do
      Physics2D.world.step(1 / 60_f32)
      root.physics_process_tree(1 / 60_f32)
    end
    ball.position.y.should be_close(80, 1)
    hits.uniq.should eq [ground]
    ball.overlapping.should eq [ground]
    ball.free
    Physics2D.world.bodies.size.should eq 1
  end

  it "areas detect overlaps and kinematic bodies slide" do
    root = SceneTree.root
    floor = StaticBody2D.new(position: v2(0, 100)).box(1000, 20)
    area = Area2D.new(position: v2(100, 60)).circle(30)
    player = KinematicBody2D.new(position: v2(0, 70)).box(20, 40)
    root.add(floor, area, player)
    entered = [] of CollisionObject2D
    area.on_body_entered { |o| entered << o }
    player.velocity = v2(200, 100)
    30.times do
      player.move_and_slide(1 / 60_f32)
      Physics2D.world.step(1 / 60_f32)
      root.physics_process_tree(1 / 60_f32)
    end
    player.on_floor?.should be_true
    player.velocity.y.should eq 0
    player.position.x.should be_close(100, 1)
    entered.should eq [player]
    area.bodies.should eq [player]
    ray = RayCast2D.new(v2(0, 100))
    player.add(ray)
    ray.update_cast
    ray.colliding?.should be_true
    ray.collider.should eq floor
  end
end
