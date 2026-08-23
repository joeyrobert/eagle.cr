module Eagle
  # The main window. Sizes are in logical points; `pixel_size` in device pixels.
  module Window
    @@size = Vec2.new(1280, 720)
    @@pixel_size = Vec2.new(1280, 720)
    @@title = "Eagle"
    @@fullscreen = false
    @@vsync = true
    @@focused = true

    def self.width : Int32; @@size.x.to_i; end
    def self.height : Int32; @@size.y.to_i; end
    def self.size : Vec2; @@size; end
    def self.center : Vec2; @@size / 2; end
    def self.rect : Rect; Rect.new(0, 0, @@size.x, @@size.y); end
    def self.aspect : Float32; @@size.y == 0 ? 1_f32 : @@size.x / @@size.y; end
    def self.pixel_size : Vec2; @@pixel_size; end
    def self.pixel_width : Int32; @@pixel_size.x.to_i; end
    def self.pixel_height : Int32; @@pixel_size.y.to_i; end
    # Device pixels per logical point (2 on Retina).
    def self.scale : Float32; @@size.x == 0 ? 1_f32 : @@pixel_size.x / @@size.x; end
    def self.focused? : Bool; @@focused; end
    def self.title : String; @@title; end
    def self.fullscreen? : Bool; @@fullscreen; end
    def self.vsync? : Bool; @@vsync; end

    def self.title=(t : String)
      @@title = t
      Eagle.platform?.try(&.title=(t))
    end

    def self.fullscreen=(v : Bool)
      @@fullscreen = v
      Eagle.platform?.try(&.fullscreen=(v))
    end

    def self.vsync=(v : Bool)
      @@vsync = v
      Eagle.platform?.try(&.vsync=(v))
    end

    def self.cursor_visible=(v : Bool); Eagle.platform?.try(&.cursor_visible=(v)); end
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
