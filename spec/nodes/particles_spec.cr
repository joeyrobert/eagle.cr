require "../gpu_spec_helper"

describe Eagle::Particles2D do
  it "emits at a rate, ages and dies" do
    p = Particles2D.new(amount: 100, seed: 1)
    p.lifetime = 0.5
    p.update(0.1_f32)
    p.alive_count.should eq 10
    p.update(0.1_f32)
    p.alive_count.should eq 20
    p.emitting = false
    p.update(0.45_f32)
    p.alive_count.should eq 0
  end

  it "bursts, applies gravity and color ramps" do
    p = Particles2D.new(amount: 0, seed: 2, position: v2(50, 50))
    p.gravity = v2(0, 100)
    p.speed = 0
    p.lifetime = 2
    p.color_over_life = [Color::RED, Color::BLUE]
    done = false
    p.on_finished { done = true }
    p.explode(5)
    p.alive_count.should eq 5
    p.update(1_f32)
    p.particles.select(&.alive?).each do |q|
      q.velocity.y.should be_close(100, 1e-3)
      q.position.x.should eq 50
    end
    p.color_at(0.5_f32).should eq Color.new(0.5, 0, 0.5)
    p.update(1.1_f32)
    p.alive_count.should eq 0
    done.should be_true
  end

  it "one_shot emits everything at once" do
    p = Particles2D.new(amount: 30, seed: 3)
    p.one_shot = true
    p.update(0.016_f32)
    p.alive_count.should eq 30
    p.emitting?.should be_false
  end

  gpu_it "draws with additive blending" do
    p = Particles2D.new(amount: 0, seed: 4, position: v2(8, 8))
    p.blend = GPU::BlendMode::Additive
    p.color_over_life = [Color.new(0.5, 0, 0)]
    p.speed = 0
    p.explode(2)
    p.update(0.01_f32)
    img = GPUSpec.render(16, 16) { |g| p.draw_tree(g) }
    img[8, 8].r.should be_close(1.0, 0.05) # two overlapping halves add up
    img[0, 0].r.should eq 0
  end
end
