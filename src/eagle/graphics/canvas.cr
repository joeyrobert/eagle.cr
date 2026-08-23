module Eagle
  # An off-screen render target you can draw to and then draw as a texture.
  #
  #   canvas = Canvas.new(320, 180)
  #   g.with_canvas(canvas) { g.circle(10, 10, 5) }
  #   g.draw(canvas, 0, 0, sx: 4, sy: 4)   # pixel-perfect upscale
  class Canvas
    getter width : Int32
    getter height : Int32
    getter texture : Texture
    getter handle : GPU::RenderTargetHandle
    getter? depth : Bool

    def initialize(@width : Int32, @height : Int32, @depth : Bool = false, filter : GPU::Filter = Texture.default_filter)
      @handle = GPU.device.create_render_target(@width, @height, @depth, filter)
      @texture = Texture.wrap_handle(@handle.color, @width, @height, filter)
    end

    def size : Vec2; Vec2.new(@width, @height); end
    def rect : Rect; Rect.new(0, 0, @width, @height); end

    # Read the canvas back to the CPU (slow; for tests and screenshots).
    def to_image : Image
      GPU.device.bind_render_target(@handle)
      bytes = GPU.device.read_pixels(0, 0, @width, @height)
      GPU.device.bind_render_target(nil)
      Image.new(@width, @height, bytes)
    end

    def dispose : Nil
      return if @handle.fbo == 0
      GPU.device.delete_render_target(@handle) if GPU.ready?
      @handle = GPU::RenderTargetHandle.new(0_u32, 0_u32, 0_u32, 0, 0)
    end
  end
end
