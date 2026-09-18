require "../spec_helper"

describe Eagle::Vec2 do
  it "does arithmetic" do
    (v2(1, 2) + v2(3, 4)).should eq v2(4, 6)
    (v2(1, 2) * 2).should eq v2(2, 4)
    (2 * v2(1, 2)).should eq v2(2, 4)
    (-v2(1, 2)).should eq v2(-1, -2)
  end

  it "normalizes and measures" do
    v2(3, 4).length.should eq 5
    v2(3, 4).normalized.approx?(v2(0.6, 0.8)).should be_true
    Vec2::ZERO.normalized.should eq Vec2::ZERO
    v2(1, 0).dot(v2(0, 1)).should eq 0
    v2(1, 0).cross(v2(0, 1)).should eq 1
  end

  it "rotates" do
    v2(1, 0).rotated(Math::PI / 2).approx?(v2(0, 1)).should be_true
    v2(1, 0).angle_to(v2(0, 1)).should be_close(Math::PI / 2, 1e-5)
    Vec2.from_angle(0).should eq v2(1, 0)
  end

  it "reflects" do
    v2(1, -1).reflect(v2(0, 1)).should eq v2(1, 1)
  end
end

describe Eagle::Vec3 do
  it "cross product follows right-hand rule" do
    Vec3::RIGHT.cross(Vec3::UP).should eq Vec3::BACK
    Vec3::UP.cross(Vec3::BACK).should eq Vec3::RIGHT
  end

  it "lerps" do
    Vec3::ZERO.lerp(Vec3::ONE, 0.5).should eq Vec3.new(0.5)
  end
end

describe Eagle::Mat4 do
  it "identity is neutral" do
    m = Mat4.translation(1, 2, 3)
    (Mat4.identity * m).should eq m
    (m * Mat4.identity).should eq m
  end

  it "translates points but not directions" do
    m = Mat4.translation(1, 2, 3)
    m.transform_point(Vec3::ZERO).should eq v3(1, 2, 3)
    m.transform_dir(Vec3::UP).should eq Vec3::UP
  end

  it "composes TRS in the right order" do
    m = Mat4.translation(10, 0, 0) * Mat4.scale(2)
    m.transform_point(v3(1, 0, 0)).should eq v3(12, 0, 0)
  end

  it "rotates about Z" do
    Mat4.rotation_z(Math::PI / 2).transform_point(v3(1, 0, 0)).approx?(v3(0, 1, 0)).should be_true
  end

  it "inverts" do
    m = Mat4.translation(1, 2, 3) * Mat4.rotation_y(0.7) * Mat4.scale(v3(2, 3, 4))
    (m * m.inverse).approx?(Mat4.identity).should be_true
    m.determinant.should be_close(24, 1e-3)
  end

  it "look_at puts the target on -Z" do
    v = Mat4.look_at(v3(0, 0, 5), Vec3::ZERO)
    p = v.transform_point(Vec3::ZERO)
    p.approx?(v3(0, 0, -5)).should be_true
  end

  it "orthographic maps corners to NDC" do
    m = Mat4.orthographic(0, 800, 600, 0)
    m.transform_point(v3(0, 0, 0)).approx?(v3(-1, 1, 0)).should be_true
    m.transform_point(v3(800, 600, 0)).approx?(v3(1, -1, 0)).should be_true
  end

  it "perspective maps near/far to -1/1" do
    m = Mat4.perspective(Mathf.deg2rad(60), 1, 0.1, 100)
    m.transform_point(v3(0, 0, -0.1)).z.should be_close(-1, 1e-4)
    m.transform_point(v3(0, 0, -100)).z.should be_close(1, 1e-4)
  end
end

describe Eagle::Quat do
  it "rotates vectors like the equivalent matrix" do
    q = Quat.from_axis_angle(Vec3::UP, Math::PI / 2)
    (q * Vec3::RIGHT).approx?(Vec3::FORWARD).should be_true
    q.to_mat4.transform_dir(Vec3::RIGHT).approx?(Vec3::FORWARD).should be_true
  end

  it "composes" do
    a = Quat.from_axis_angle(Vec3::UP, 0.3)
    b = Quat.from_axis_angle(Vec3::RIGHT, 0.5)
    ((a * b) * Vec3::BACK).approx?(a * (b * Vec3::BACK)).should be_true
  end

  it "slerps half way" do
    a = Quat::IDENTITY
    b = Quat.from_axis_angle(Vec3::UP, Math::PI / 2)
    half = a.slerp(b, 0.5)
    half.approx?(Quat.from_axis_angle(Vec3::UP, Math::PI / 4)).should be_true
  end

  it "euler round trip" do
    q = Quat.from_euler(0.3, 0.5, -0.2)
    e = q.to_euler
    Quat.from_euler(e).approx?(q, 1e-3).should be_true
  end

  it "look_rotation faces the target" do
    q = Quat.look_rotation(v3(1, 0, 0))
    q.forward.approx?(v3(1, 0, 0), 1e-4).should be_true
  end
end

describe Eagle::Rect do
  it "intersects and unions" do
    a = Rect.new(0, 0, 10, 10); b = Rect.new(5, 5, 10, 10)
    a.intersects?(b).should be_true
    a.intersection(b).should eq Rect.new(5, 5, 5, 5)
    a.union(b).should eq Rect.new(0, 0, 15, 15)
    a.contains?(v2(9.9, 0)).should be_true
    a.contains?(v2(10, 0)).should be_false
  end
end

describe Eagle::Ray do
  it "hits a box and a sphere" do
    r = Ray.new(v3(0, 0, 5), v3(0, 0, -1))
    r.intersect_aabb(AABB.new(v3(-1, -1, -1), v3(1, 1, 1))).not_nil!.should be_close(4, 1e-5)
    r.intersect_sphere(Vec3::ZERO, 1).not_nil!.should be_close(4, 1e-5)
    r.intersect_plane(Vec3::ZERO, Vec3::BACK).not_nil!.should be_close(5, 1e-5)
    Ray.new(v3(0, 0, 5), v3(0, 1, 0)).intersect_aabb(AABB.new(v3(-1, -1, -1), v3(1, 1, 1))).should be_nil
  end
end

describe Eagle::Frustum do
  it "classifies points and boxes against a perspective view" do
    view = Mat4.look_at(v3(0, 0, 10), Vec3::ZERO)
    f = Frustum.new(Mat4.perspective(Mathf.deg2rad(60), 1, 0.5, 50) * view)
    f.contains?(Vec3::ZERO).should be_true
    f.contains?(v3(0, 0, 20)).should be_false  # behind the camera
    f.contains?(v3(0, 0, -45)).should be_false # beyond the far plane
    f.contains?(v3(30, 0, 0)).should be_false  # off to the side
    f.intersects?(AABB.new(v3(-1, -1, -1), v3(1, 1, 1))).should be_true
    f.intersects?(AABB.new(v3(20, -1, -1), v3(22, 1, 1))).should be_false
    # a wide box poking into the view from the side counts as visible
    f.intersects?(AABB.new(v3(3, -1, -1), v3(40, 1, 1))).should be_true
    # local bounds + transform: a unit cube moved off-screen, then rotated and scaled back into view
    unit = AABB.new(v3(-0.5, -0.5, -0.5), v3(0.5, 0.5, 0.5))
    f.intersects?(unit, Mat4.translation(0, 0, 30)).should be_false
    f.intersects?(unit, Mat4.translation(12, 0, 0)).should be_false
    f.intersects?(unit, Mat4.translation(12, 0, 0) * Mat4.rotation_y(0.7) * Mat4.scale(v3(12, 1, 1))).should be_true
  end

  it "works with orthographic projections" do
    f = Frustum.new(Mat4.orthographic(-5, 5, -5, 5, 0.1, 20) * Mat4.look_at(v3(0, 10, 0), Vec3::ZERO, Vec3::BACK))
    f.contains?(v3(4, 0, 4)).should be_true
    f.contains?(v3(6, 0, 0)).should be_false
    f.contains?(v3(0, -15, 0)).should be_false
  end
end

describe Eagle::Color do
  it "parses hex" do
    Color.hex("#ff8800").should eq Color.rgb(255, 136, 0)
    Color.hex(0xff8800).should eq Color.rgb(255, 136, 0)
    Color.hex("#ff880080").a.should be_close(0.5, 0.01)
    Color.hex("#f80").should eq Color.rgb(255, 136, 0)
  end

  it "hsv" do
    Color.hsv(0, 1, 1).should eq Color::RED
    Color.hsv(120, 1, 1).should eq Color::GREEN
  end

  it "packs bytes" do
    Color::RED.to_rgba8.should eq 0xFF0000FF
  end
end

describe Eagle::Transform2D do
  it "matches manual TRS" do
    t = Transform2D.trs(v2(10, 20), Math::PI / 2, v2(2, 2))
    (t * v2(1, 0)).approx?(v2(10, 22)).should be_true
    (t * t.inverse).approx?(Transform2D.identity).should be_true
  end

  it "composes parent * child" do
    parent = Transform2D.translation(v2(100, 0))
    child = Transform2D.rotation(Math::PI)
    ((parent * child) * v2(1, 0)).approx?(v2(99, 0)).should be_true
  end
end

describe Eagle::Mathf do
  it "wraps and lerps angles" do
    Mathf.wrap_angle(Math::PI * 3).abs.should be_close(Math::PI, 1e-4)
    Mathf.wrap_angle(0.5).should be_close(0.5, 1e-5)
    Mathf.angle_diff(0.1, -0.1).should be_close(-0.2, 1e-5)
    Mathf.lerp_angle(3.0, -3.0, 0.5).abs.should be_close(Math::PI, 1e-4)
    Mathf.ping_pong(3, 2).should eq 1
    Mathf.remap(5, 0, 10, 0, 100).should eq 50
  end
end
