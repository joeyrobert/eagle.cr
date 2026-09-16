require "./spec_helper"

# Boots a hidden window + GL context once for the whole spec run. Specs that
# need a GPU `require` this file. Set EAGLE_NO_GPU=1 to skip them.
module GPUSpec
  @@booted = false

  def self.boot : Bool
    return false if ENV["EAGLE_NO_GPU"]? == "1"
    unless @@booted
      Eagle.init(Eagle::App.new, title: "eagle spec", width: 320, height: 240, hidden: true, vsync: false, audio: false, highdpi: false)
      @@booted = true
      Spec.after_suite { Eagle.shutdown }
    end
    true
  end

  # Render with the block into a fresh canvas and return the image.
  def self.render(w = 64, h = 64, clear = Eagle::Color::BLACK, &block : Eagle::Graphics ->) : Eagle::Image
    g = Eagle.graphics
    g.begin_frame
    canvas = Eagle::Canvas.new(w, h)
    g.with_canvas(canvas, clear: clear) { block.call(g) }
    g.end_frame
    Eagle::GPU.device.check_errors("GPUSpec.render")
    img = canvas.to_image
    canvas.dispose
    img
  end
end

GPU_OK = GPUSpec.boot

macro gpu_it(desc, &block)
  it {{desc}} do
    pending!("no GPU") unless GPU_OK
    {{block.body}}
    Eagle::GPU.device.check_errors("after example: " + {{desc}})
  end
end
