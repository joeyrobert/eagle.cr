require "../spec_helper"

describe Eagle::Tween do
  before_each { Tween.clear }

  it "interpolates and completes" do
    values = [] of Float32
    done = false
    Tween.value(0, 10, 1.0) { |v| values << v }.on_complete { done = true }
    Tween.update_all(0.5_f32)
    values.last.should be_close(5, 1e-4)
    Tween.update_all(0.6_f32)
    values.last.should eq 10
    done.should be_true
    Tween.active_count.should eq 0
  end

  it "eases" do
    Ease.quad_in(0.5_f32).should eq 0.25
    Ease.quad_out(0.5_f32).should eq 0.75
    Ease.linear(0.3_f32).should eq 0.3_f32
    Ease.bounce_out(1_f32).should be_close(1, 1e-4)
    Ease.elastic_out(1_f32).should eq 1
    Ease.back_out(1_f32).should be_close(1, 1e-4)
    %i(linear quad_in quad_out quad_in_out cubic_in cubic_out cubic_in_out sine_in sine_out sine_in_out expo_in expo_out back_in back_out elastic_out bounce_in bounce_out).each do |name|
      f = Ease.by_name(name)
      f.call(0_f32).should be_close(0, 1e-4)
      f.call(1_f32).should be_close(1, 1e-4)
    end
    ts = [] of Float32
    Tween.to(1.0, ease: :quad_in) { |t| ts << t }
    Tween.update_all(0.5_f32)
    ts.last.should eq 0.25
  end

  it "delays" do
    hits = 0
    Tween.after(1.0) { hits += 1 }
    Tween.update_all(0.9_f32)
    hits.should eq 0
    Tween.update_all(0.2_f32)
    hits.should eq 1
  end

  it "loops" do
    ts = [] of Float32
    t = Tween.to(1.0) { |x| ts << x }
    t.loop = true
    Tween.update_all(1.5_f32)
    ts.last.should be_close(0.5, 1e-4)
    Tween.active_count.should eq 1
    t.stop
    Tween.active_count.should eq 0
  end

  it "tweens vectors and colors" do
    v = Vec2::ZERO
    Tween.value(Vec2::ZERO, v2(10, 20), 1.0) { |x| v = x }
    c = Color::BLACK
    Tween.value(Color::BLACK, Color::WHITE, 1.0) { |x| c = x }
    Tween.update_all(0.5_f32)
    v.should eq v2(5, 10)
    c.r.should eq 0.5
  end

  it "runs sequences in order" do
    log = [] of String
    Tween.sequence do |s|
      s.call { log << "start" }
      s.wait(1)
      s.to(1) { |t| log << "t#{t}" if t == 1 }
      s.call { log << "end" }
    end
    Tween.update_all(0.5_f32)
    log.should eq ["start"]
    Tween.update_all(0.6_f32)
    log.should eq ["start"]
    Tween.update_all(1.0_f32)
    log.should eq ["start", "t1.0", "end"]
  end
end
