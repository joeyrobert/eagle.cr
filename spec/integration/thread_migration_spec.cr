require "../gpu_spec_helper"

# Without pinning, a long blocking syscall moves the main fiber to a new thread that has no GL context.
private def block_in_syscall : Nil
  Fiber.syscall { Thread.sleep(60.milliseconds) }
end

describe "GL after a long blocking call" do
  it "keeps the fiber on its thread" do
    before = Thread.current
    block_in_syscall
    Thread.current.should be before
  end

  gpu_it "keeps stepping frames" do
    block_in_syscall
    Eagle.step(1 / 60)
    Clock.frame.should be > 0
  end

  gpu_it "keeps offscreen rendering working" do
    block_in_syscall
    GPUSpec.render(8, 8, clear: Eagle::Color::RED) { }.width.should eq 8
  end
end
