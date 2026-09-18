require "../spec_helper"

describe Eagle::Noise do
  it "is deterministic per seed and changes with another seed" do
    a = Noise.new(123)
    b = Noise.new(123)
    c = Noise.new(124)
    points = [{0.125, -3.75}, {11.5, 9.25}, {-104.2, 81.7}]
    points.each do |(x, y)|
      a.perlin(x, y).should eq b.perlin(x, y)
      a.simplex(x, y).should eq b.simplex(x, y)
      a.worley(x, y).should eq b.worley(x, y)
    end
    points.any? { |(x, y)| a.simplex(x, y) != c.simplex(x, y) }.should be_true
  end

  it "samples Perlin and simplex coherently in 2D and 3D" do
    n = Noise.new(7)
    n.perlin(4, -2).should eq 0_f32
    n.perlin(4, -2, 9).should eq 0_f32
    {n.perlin(1.2, 3.4), n.simplex(1.2, 3.4), n.perlin(1.2, 3.4, 5.6), n.simplex(1.2, 3.4, 5.6)}.each do |value|
      value.finite?.should be_true
      value.abs.should be <= 1.5
    end
    (n.perlin(1.2001, 3.4001) - n.perlin(1.2, 3.4)).abs.should be < 0.01
    (n.simplex(1.2001, 3.4001, 5.6001) - n.simplex(1.2, 3.4, 5.6)).abs.should be < 0.01
  end

  it "supports vector samples" do
    n = Noise.new(55)
    p2 = v2(1.25, -7.5)
    p3 = v3(1.25, -7.5, 2.75)
    n.perlin(p2).should eq n.perlin(p2.x, p2.y)
    n.simplex(p3).should eq n.simplex(p3.x, p3.y, p3.z)
    n.fbm(p2).should eq n.fbm(p2.x, p2.y)
    n.ridged(p3).should eq n.ridged(p3.x, p3.y, p3.z)
    n.domain_warp(p3).finite?.should be_true
    n.worley(p3).should eq n.worley(p3.x, p3.y, p3.z)
  end

  it "layers fBm, ridged noise and domain warping deterministically" do
    n = Noise.new(19)
    n.fbm(2.3, -4.1, octaves: 6).should eq n.fbm(2.3, -4.1, octaves: 6)
    n.fbm(v3(2.3, -4.1, 0.7), octaves: 4).finite?.should be_true
    n.ridged(2.3, -4.1, octaves: 6).in?(0_f32..1_f32).should be_true
    n.ridged(v3(2.3, -4.1, 0.7), octaves: 4).in?(0_f32..1_f32).should be_true
    n.domain_warp(2.3, -4.1, strength: 2.5, octaves: 4).finite?.should be_true
    n.domain_warp(v3(2.3, -4.1, 0.7), strength: 2.5, octaves: 4).finite?.should be_true
  end

  it "returns Worley nearest-feature distances in 2D and 3D" do
    n = Noise.new(91)
    d2 = n.worley(-12.25, 8.75)
    d3 = n.worley(-12.25, 8.75, 3.5)
    d2.should be >= 0
    d2.should be <= Math.sqrt(2)
    d3.should be >= 0
    d3.should be <= Math.sqrt(3)
  end

  it "rejects invalid fractal settings" do
    n = Noise.new
    expect_raises(ArgumentError) { n.fbm(0, 0, octaves: 0) }
    expect_raises(ArgumentError) { n.ridged(0, 0, lacunarity: 0) }
    expect_raises(ArgumentError) { n.fbm(0, 0, gain: 0) }
  end
end
