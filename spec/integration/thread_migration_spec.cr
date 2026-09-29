require "../gpu_spec_helper"

{% unless flag?(:without_mt) %}
  {% raise "Eagle's specs must be built with -Dwithout_mt (crystal spec -Dwithout_mt) so the GL thread can't change mid-run" %}
{% end %}

describe "GL thread affinity" do
  it "keeps the main fiber on its thread across a long blocking call" do
    before = Thread.current
    Fiber.syscall { Thread.sleep(60.milliseconds) }
    Thread.current.should be before
  end

  gpu_it "keeps stepping frames after a long blocking call" do
    Fiber.syscall { Thread.sleep(60.milliseconds) }
    Eagle.step(1 / 60)
    Clock.frame.should be > 0
  end

  gpu_it "raises a clear error when the GPU is used from another thread" do
    Eagle::GPU.device
    message = nil.as(String?)
    Thread.new do
      Eagle::GPU.device
    rescue ex : Eagle::Error
      message = ex.message
    end.join
    message.not_nil!.should contain "-Dwithout_mt"
  end
end
