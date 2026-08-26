require "../spec_helper"

describe Eagle::Clock do
  it "advances, scales and clamps" do
    Clock.reset
    Clock.fixed_delta = 0.1
    Clock.advance(0.05)
    Clock.delta.should be_close(0.05, 1e-6)
    Clock.frame.should eq 1
    Clock.scale = 0.5
    Clock.advance(0.05)
    Clock.delta.should be_close(0.025, 1e-6)
    Clock.raw_delta.should be_close(0.05, 1e-6)
    Clock.elapsed.should be_close(0.1, 1e-6)
    Clock.scale = 1
    Clock.advance(10) # clamped to max_delta
    Clock.raw_delta.should eq 0.25_f32
  end

  it "yields fixed steps" do
    Clock.reset
    Clock.fixed_delta = 0.1
    Clock.advance(0.25)
    steps = 0
    Clock.each_fixed_step { |dt| steps += 1; dt.should eq 0.1_f32 }
    steps.should eq 2
    Clock.fixed_alpha.should be_close(0.5, 1e-4)
    Clock.advance(0.1)
    steps = 0
    Clock.each_fixed_step { steps += 1 }
    steps.should eq 1
  end
end
