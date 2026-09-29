require "../spec_helper"

describe Eagle::Config do
  it "applies false and zero options instead of ignoring them" do
    c = Config.new(vsync: false, audio: false, resizable: false, fixed_fps: 30)
    c.vsync.should be_false
    c.audio.should be_false
    c.resizable.should be_false
    c.fixed_fps.should eq 30
    Config.new.vsync.should be_true
  end
end
