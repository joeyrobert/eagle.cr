module Eagle
  # The game window: its size, title, fullscreen state and cursor.
  #
  # Sizes are in logical points, the units you draw in. On high-DPI screens the
  # framebuffer has more pixels (`pixel_size`), and Eagle scales for you.
  #
  # ```
  # g.print("PAUSED", Window.center.x, Window.center.y, align: TextAlign::Center)
  # Window.fullscreen = !Window.fullscreen? if Input.pressed?(Key::F11)
  # Window.title = "Level 2"
  # ```
  module Window
    @@size = Vec2.new(1280, 720)
    @@pixel_size = Vec2.new(1280, 720)
    @@title = "Eagle"
    @@fullscreen = false
    @@vsync = true
    @@focused = true

    # Width in logical points.
    def self.width : Int32; @@size.x.to_i; end
    # Height in logical points.
    def self.height : Int32; @@size.y.to_i; end
    # `(width, height)` in logical points.
    def self.size : Vec2; @@size; end
    # The center of the window, handy for placing things in the middle of the screen.
    def self.center : Vec2; @@size / 2; end
    # The whole window as a `Rect` from `(0, 0)`.
    def self.rect : Rect; Rect.new(0, 0, @@size.x, @@size.y); end
    # Width divided by height.
    def self.aspect : Float32; @@size.y == 0 ? 1_f32 : @@size.x / @@size.y; end
    # Framebuffer size in device pixels. It is larger than `size` on Retina screens.
    def self.pixel_size : Vec2; @@pixel_size; end
    # Framebuffer width in device pixels.
    def self.pixel_width : Int32; @@pixel_size.x.to_i; end
    # Framebuffer height in device pixels.
    def self.pixel_height : Int32; @@pixel_size.y.to_i; end
    # Device pixels per logical point: 2 on most Retina screens, 1 elsewhere.
    def self.scale : Float32; @@size.x == 0 ? 1_f32 : @@pixel_size.x / @@size.x; end
    # True while the window has keyboard focus. Pause the game when it loses focus if you like.
    def self.focused? : Bool; @@focused; end
    # The window title.
    def self.title : String; @@title; end
    # True in fullscreen mode.
    def self.fullscreen? : Bool; @@fullscreen; end
    # True when presentation waits for the display's refresh.
    def self.vsync? : Bool; @@vsync; end

    # Changes the window title.
    def self.title=(t : String)
      @@title = t
      Eagle.platform?.try(&.title=(t))
    end

    # Switches between fullscreen and windowed mode.
    def self.fullscreen=(v : Bool)
      @@fullscreen = v
      Eagle.platform?.try(&.fullscreen=(v))
    end

    # Turns vsync on or off.
    def self.vsync=(v : Bool)
      @@vsync = v
      Eagle.platform?.try(&.vsync=(v))
    end

    # Shows or hides the mouse cursor, for games that draw their own crosshair.
    def self.cursor_visible=(v : Bool); Eagle.platform?.try(&.cursor_visible=(v)); end
    # Captures the mouse for mouse-look: the cursor is hidden and locked, and `Input.mouse_delta`
    # keeps reporting movement. Turn it off again for menus.
    def self.relative_mouse=(v : Bool); Eagle.platform?.try(&.relative_mouse=(v)); end

    # :nodoc:
    def self.refresh(platform : Platform::Base) : Nil
      w, h = platform.window_size
      pw, ph = platform.drawable_size
      @@size = Vec2.new(w, h)
      @@pixel_size = Vec2.new(pw, ph)
    end

    # :nodoc:
    def self.focused=(v : Bool); @@focused = v; end
  end
end
