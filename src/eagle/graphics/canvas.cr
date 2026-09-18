module Eagle
  # An off-screen image you can draw into and then draw like a texture.
  #
  # Canvases are useful for pixel-perfect low-resolution games (draw at 320x180, then scale
  # up), for post-processing with a shader, for caching expensive drawings, and for minimaps.
  #
  # ```
  # canvas = Canvas.new(320, 180)
  # g.with_canvas(canvas) do
  #   g.clear(Color::BLACK)
  #   g.circle(160, 90, 40, color: Color::YELLOW)
  # end
  # g.draw(canvas, Window.rect) # scale up to fill the window
  # ```
  #
  # Pass `depth: true` if you render 3D into it.
  class Canvas
    # Width in pixels.
    getter width : Int32
    # Height in pixels.
    getter height : Int32
    # The texture holding the canvas's pixels, for use with sprites or shaders.
    getter texture : Texture
    # The GPU render-target handle.
    getter handle : GPU::RenderTargetHandle
    # True when the canvas has a depth buffer for 3D rendering.
    getter? depth : Bool

    # Creates a canvas of the given size.
    def initialize(@width : Int32, @height : Int32, @depth : Bool = false, filter : GPU::Filter = Texture.default_filter)
      @handle = GPU.device.create_render_target(@width, @height, @depth, filter)
      @texture = Texture.wrap_handle(@handle.color, @width, @height, filter)
    end

    # `(width, height)`.
    def size : Vec2; Vec2.new(@width, @height); end
    # The whole canvas as a `Rect`.
    def rect : Rect; Rect.new(0, 0, @width, @height); end

    # Reads the pixels back to the CPU. It is slow, so use it for screenshots and tests, not every frame.
    def to_image : Image
      GPU.device.bind_render_target(@handle)
      bytes = GPU.device.read_pixels(0, 0, @width, @height)
      GPU.device.bind_render_target(nil)
      Image.new(@width, @height, bytes)
    end

    # Frees the GPU resources.
    def dispose : Nil
      return if @handle.fbo == 0
      GPU.device.delete_render_target(@handle) if GPU.ready?
      @handle = GPU::RenderTargetHandle.new(0_u32, 0_u32, 0_u32, 0, 0)
    end
  end
end
