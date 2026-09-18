module Eagle
  # Text on screen. It works inside UI containers and as a plain node in the game world.
  #
  # ```
  # title = Label.new("GAME OVER", position: v2(0, 200), align: TextAlign::Center, size: v2(800, 40))
  # title.font_scale = 3
  # title.shadow = Color::BLACK
  # score = Label.new("0")
  # score.text = "1200"
  # ```
  class Label < Control
    # The text to show.
    property text : String
    # Text color. `nil` uses the theme.
    property color : Color? = nil
    # Horizontal alignment within the control's width.
    property align : TextAlign = TextAlign::Left
    # Vertical alignment within the control's height: `:top`, `:center` or `:bottom`.
    property valign : Symbol = :top # :top, :center, :bottom
    # Text scale.
    property font_scale : Float32 = 1_f32
    # Wrap text to the control's width.
    property? wrap = false
    # Drop-shadow color, or `nil` for none. It helps text stay readable over busy backgrounds.
    property shadow : Color? = nil
    # Drop-shadow offset in points.
    property shadow_offset : Vec2 = Vec2.new(1, 1)
    # A font for this label only.
    property label_font : Font? = nil

    # Creates a label.
    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, color : Color? = nil, name : String = "", @align = TextAlign::Left, font : Font? = nil, size : Vec2? = nil)
      super(name, position, size)
      @color = color
      @label_font = font
      @mouse_enabled = false
      @size = content_min_size if size.nil? && GPU.ready? # otherwise sized on first layout
    end

    # The font in use.
    def font : Font; @label_font || super; end
    # Changes the text.
    def text=(t : String); @text = t; end

    # Size of the text.
    def content_min_size : Vec2
      f = font
      if @wrap && @size.x > 0
        lines = f.wrap(@text, @size.x / @font_scale)
        Vec2.new(0, lines.size * f.height * @font_scale)
      else
        f.measure(@text) * @font_scale
      end
    end

    # Resizes to fit the text when needed.
    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

    # Draws the text.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      c = @color || (@disabled ? t.text_disabled : t.text)
      f = font
      th = (@wrap ? f.wrap(@text, @size.x / @font_scale).size : @text.count('\n') + 1) * f.height * @font_scale
      y = case @valign
          when :center then (@size.y - th) / 2
          when :bottom then @size.y - th
          else 0_f32
          end
      if s = @shadow
        draw_text(g, @shadow_offset.x, y + @shadow_offset.y, g.color * s, f)
      end
      draw_text(g, 0, y, g.color * c, f)
    end

    private def draw_text(g, x, y, color, f)
      if @wrap
        g.printf(@text, x, y, @size.x, @align, color, f, @font_scale)
      else
        ax = case @align
             in TextAlign::Left then x
             in TextAlign::Center then x + @size.x / 2
             in TextAlign::Right then x + @size.x
             end
        g.print(@text, ax, y, color, f, @font_scale, @align)
      end
    end
  end

  # A clickable button. Connect to `pressed`, or pass a block to the constructor.
  #
  # ```
  # start = Button.new("Start") { puts "go" }
  # mute = Button.new("Mute")
  # mute.toggle_mode = true
  # mute.on_toggled { |on| Audio.bus("music").muted = on }
  # ```
  class Button < Control
    # The label on the button.
    property text : String
    # An image drawn before the text.
    property icon : Drawable? = nil
    # Makes the button stay down when clicked and pop up on the next click.
    property? toggle_mode = false
    # True while a toggle button is down.
    getter? toggled = false
    # Background color. `nil` uses the theme.
    property color : Color? = nil
    # Text color. `nil` uses the theme.
    property text_color : Color? = nil
    # Text scale.
    property font_scale : Float32 = 1_f32

    # Emitted when the button is clicked or activated with Enter or Space.
    # Connect with `on_pressed { ... }`.
    signal pressed
    # Emitted when a toggle-mode button changes state, with the new state.
    # Connect with `on_toggled { |on| ... }`.
    signal toggled(on : Bool)

    # Creates a button and connects the block to `pressed`.
    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil, &block : ->)
      super(name, position, size)
      @focusable = true
      on_pressed(&block)
      @size = content_min_size unless size
    end

    # Creates a button.
    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @focusable = true
      @size = content_min_size unless size
    end

    # Sets the toggle state and emits `toggled`.
    def toggled=(v : Bool)
      return if v == @toggled
      @toggled = v
      emit_toggled(v)
    end

    # Size needed for the text and icon.
    def content_min_size : Vec2
      t = theme_or_inherited
      ts = font.measure(@text) * @font_scale
      iw = 0_f32
      if ic = @icon
        iw = (ic.is_a?(Texture) ? ic.width.to_f32 : ic.width) + (@text.empty? ? 0 : t.spacing)
      end
      Vec2.new(ts.x + iw + t.padding * 2, Math.max(ts.y + t.padding, t.control_height))
    end

    # Resizes to fit the content when needed.
    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

    # Clicks the button from code, emitting the same signals as a real click.
    def click : Nil
      return if @disabled
      self.toggled = !@toggled if @toggle_mode
      emit_pressed
    end

    # Handles clicks and keyboard activation.
    def gui_input(event : Event) : Bool
      case event
      when MouseButtonEvent
        if event.button.left? && event.released? && @pressed && contains_global?(event.position)
          click
          return true
        end
        return event.pressed?
      when KeyEvent
        if event.pressed? && (event.key == Key::Space || event.key == Key::Enter)
          click
          return true
        end
      end
      false
    end

    # Draws the button.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      bg = @color || t.button
      bg = t.button_pressed if (@pressed && @hovered) || @toggled
      bg = t.button_hover if @hovered && !@pressed && !@toggled
      bg = t.accent if @toggled && @hovered
      bg = bg.lerp(t.panel, 0.5) if @disabled
      draw_panel(g, rect, bg, t.button_border)
      draw_focus_ring(g)
      tc = @text_color || (@disabled ? t.text_disabled : t.text)
      f = font
      ts = f.measure(@text) * @font_scale
      x = (@size.x - content_min_size.x) / 2 + t.padding
      if ic = @icon
        iw = ic.is_a?(Texture) ? ic.width.to_f32 : ic.width
        ih = ic.is_a?(Texture) ? ic.height.to_f32 : ic.height
        g.draw(ic, x, (@size.y - ih) / 2, color: g.color * (@disabled ? tc : Color::WHITE))
        x += iw + (@text.empty? ? 0 : t.spacing)
      end
      g.print(@text, x, (@size.y - ts.y) / 2, g.color * tc, f, @font_scale)
    end
  end

  # A box that toggles on and off, with a label.
  #
  # ```
  # music = CheckBox.new("Music", checked: true)
  # music.on_toggled { |on| Audio.bus("music").muted = !on }
  # ```
  class CheckBox < Control
    # The label.
    property text : String
    # True when ticked.
    getter? checked : Bool

    # Emitted when the box is ticked or unticked, with the new state.
    # Connect with `on_toggled { |checked| ... }`.
    signal toggled(checked : Bool)

    # Creates a check box.
    def initialize(@text : String = "", @checked = false, position : Vec2 = Vec2::ZERO, name : String = "")
      super(name, position)
      @focusable = true
      @size = content_min_size
    end

    # Sets the state and emits `toggled`.
    def checked=(v : Bool)
      return if v == @checked
      @checked = v
      emit_toggled(v)
    end

    # Flips the state.
    def toggle : Nil; self.checked = !@checked; end

    # Size of the square box, from the theme.
    def box_size : Float32; theme_or_inherited.control_height * 0.6_f32; end

    # Size needed for the box and label.
    def content_min_size : Vec2
      t = theme_or_inherited
      ts = font.measure(@text)
      Vec2.new(box_size + t.spacing + ts.x, Math.max(ts.y, t.control_height))
    end

    # Resizes to fit the content.
    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

    # Handles clicks and keyboard activation.
    def gui_input(event : Event) : Bool
      case event
      when MouseButtonEvent
        if event.button.left? && event.released? && @pressed && contains_global?(event.position)
          toggle
          return true
        end
        return event.pressed?
      when KeyEvent
        if event.pressed? && (event.key == Key::Space || event.key == Key::Enter)
          toggle
          return true
        end
      end
      false
    end

    # Draws the check box.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      bs = box_size
      by = (@size.y - bs) / 2
      draw_panel(g, Rect.new(0, by, bs, bs), @hovered ? t.button_hover : t.input_bg, t.button_border, 3_f32)
      if @checked
        g.rounded_rect(3, by + 3, bs - 6, bs - 6, 2, color: g.color * t.accent)
      end
      draw_focus_ring(g)
      f = font
      ts = f.measure(@text)
      g.print(@text, bs + t.spacing, (@size.y - ts.y) / 2, g.color * (@disabled ? t.text_disabled : t.text), f)
    end
  end

  # Picks a number by dragging, for volume, difficulty and color controls.
  # Arrow keys adjust it while focused.
  #
  # ```
  # volume = Slider.new(0, 100, 80, step: 5)
  # volume.on_value_changed { |v| Audio.volume = v / 100 }
  # ```
  class Slider < Control
    # Smallest value.
    property min : Float32
    # Largest value.
    property max : Float32
    # Value increments. 0 means continuous.
    property step : Float32
    # The current value.
    getter value : Float32
    # Slide up and down instead of left and right.
    property? vertical = false
    @dragging = false

    # Emitted when the value changes, by dragging, clicking, keys or code.
    # Connect with `on_value_changed { |value| ... }`.
    signal value_changed(value : Float32)

    # Creates a slider.
    def initialize(min : Number = 0, max : Number = 1, value : Number = 0, step : Number = 0, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @min = min.to_f32; @max = max.to_f32; @step = step.to_f32
      @value = snap(value.to_f32)
      @focusable = true
      @size = size || Vec2.new(160, theme_or_inherited.control_height)
    end

    # Sets the value, clamped and snapped to `step`. Emits `value_changed` when it changes.
    def value=(v : Number)
      nv = snap(v.to_f32)
      return if nv == @value
      @value = nv
      emit_value_changed(nv)
    end

    # Where the value sits between `min` and `max`, from 0 to 1.
    def ratio : Float32; @max == @min ? 0_f32 : (@value - @min) / (@max - @min); end
    # Sets the value from a 0 to 1 fraction.
    def ratio=(r : Number); self.value = @min + (@max - @min) * r.to_f32.clamp(0_f32, 1_f32); end

    private def snap(v : Float32) : Float32
      v = v.clamp(Math.min(@min, @max), Math.max(@min, @max))
      @step > 0 ? (((v - @min) / @step).round * @step + @min).clamp(@min, @max) : v
    end

    # Minimum size of the track.
    def content_min_size : Vec2
      t = theme_or_inherited
      @vertical ? Vec2.new(t.control_height, 60) : Vec2.new(60, t.control_height)
    end

    private def set_from_point(p : Vec2)
      l = to_local(p)
      self.ratio = @vertical ? 1 - l.y / @size.y : l.x / @size.x
    end

    # Handles dragging, clicks and arrow keys.
    def gui_input(event : Event) : Bool
      case event
      when MouseButtonEvent
        if event.button.left?
          if event.pressed?
            @dragging = true
            set_from_point(event.position)
            return true
          else
            @dragging = false
          end
        end
      when MouseMotionEvent
        if @dragging
          set_from_point(event.position)
          return true
        end
      when MouseWheelEvent
        self.value = @value + (@step > 0 ? @step : (@max - @min) / 20) * event.delta.y
        return true
      when KeyEvent
        if event.pressed?
          inc = @step > 0 ? @step : (@max - @min) / 20
          case event.key
          when Key::Left, Key::Down then self.value = @value - inc; return true
          when Key::Right, Key::Up then self.value = @value + inc; return true
          when Key::Home then self.value = @min; return true
          when Key::End then self.value = @max; return true
          end
        end
      end
      false
    end

    # Draws the slider.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      thickness = 6_f32
      knob = @size.y.clamp(12_f32, 20_f32)
      if @vertical
        track = Rect.new((@size.x - thickness) / 2, knob / 2, thickness, @size.y - knob)
        g.rounded_rect(track.x, track.y, track.w, track.h, 3, color: g.color * t.track)
        ky = track.bottom - track.h * ratio
        g.rounded_rect(track.x, ky, track.w, track.bottom - ky, 3, color: g.color * t.accent)
        g.circle(@size.x / 2, ky, knob / 2, color: g.color * (@hovered || @dragging ? t.focus : t.text))
      else
        track = Rect.new(knob / 2, (@size.y - thickness) / 2, @size.x - knob, thickness)
        g.rounded_rect(track.x, track.y, track.w, track.h, 3, color: g.color * t.track)
        g.rounded_rect(track.x, track.y, track.w * ratio, track.h, 3, color: g.color * t.accent)
        g.circle(track.x + track.w * ratio, @size.y / 2, knob / 2, color: g.color * (@hovered || @dragging ? t.focus : t.text))
      end
      draw_focus_ring(g)
    end
  end

  # Shows how full something is: health, loading, experience.
  #
  # ```
  # hp = ProgressBar.new(0.75, size: v2(200, 16))
  # hp.color = Color::RED
  # hp.show_text = false
  # ```
  class ProgressBar < Control
    # Value for an empty bar.
    property min : Float32 = 0_f32
    # Value for a full bar.
    property max : Float32 = 1_f32
    # The current value.
    property value : Float32
    # Show the percentage on the bar.
    property? show_text = true
    # Fill color. `nil` uses the theme accent.
    property color : Color? = nil

    # Creates a progress bar.
    def initialize(value : Number = 0, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @value = value.to_f32
      @mouse_enabled = false
      @size = size || Vec2.new(160, theme_or_inherited.control_height * 0.6)
    end

    # How full the bar is, from 0 to 1.
    def ratio : Float32; @max == @min ? 0_f32 : ((@value - @min) / (@max - @min)).clamp(0_f32, 1_f32); end
    # Minimum size.
    def content_min_size : Vec2; Vec2.new(40, 10); end

    # Draws the bar.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      draw_panel(g, rect, t.input_bg, t.panel_border)
      w = (@size.x - 2) * ratio
      g.rounded_rect(1, 1, w, @size.y - 2, t.corner_radius, color: g.color * (@color || t.accent)) if w > 0
      if @show_text
        s = "#{(ratio * 100).round.to_i}%"
        ts = font.measure(s)
        g.print(s, (@size.x - ts.x) / 2, (@size.y - ts.y) / 2, g.color * t.text, font) if ts.y <= @size.y
      end
    end
  end

  # A single-line text field, for player names, chat and search boxes. It turns on OS text
  # input while focused, so accents and IME input work.
  #
  # ```
  # name = TextInput.new("", "your name")
  # name.max_length = 16
  # name.on_submitted { |text| puts "hello #{text}" }
  # name.grab_focus
  # ```
  class TextInput < Control
    # The current text.
    getter text : String
    # Gray hint text shown while empty.
    property placeholder : String
    # Maximum number of characters. 0 means no limit.
    property max_length : Int32 = 0
    # Show dots instead of the characters.
    property? password = false
    # Caret position, in characters.
    getter caret : Int32 = 0
    @blink = 0_f32

    # Emitted after every edit, with the new text. Connect with `on_text_changed { |text| ... }`.
    signal text_changed(text : String)
    # Emitted when the player presses Enter. Connect with `on_submitted { |text| ... }`.
    signal submitted(text : String)

    # Creates a text field.
    def initialize(@text : String = "", @placeholder : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @focusable = true
      @caret = @text.size
      @size = size || Vec2.new(200, theme_or_inherited.control_height)
    end

    # Replaces the text and emits `text_changed`.
    def text=(t : String)
      t = t[0, @max_length] if @max_length > 0 && t.size > @max_length
      return if t == @text
      @text = t
      @caret = @caret.clamp(0, @text.size)
      emit_text_changed(t)
    end

    # Minimum size.
    def content_min_size : Vec2
      t = theme_or_inherited
      Vec2.new(60, Math.max(font.height + t.padding, t.control_height))
    end

    # Inserts text at the caret.
    def insert(s : String) : Nil
      s = s.gsub('\n', "")
      return if s.empty?
      nt = @text[0, @caret] + s + @text[@caret..]
      old = @caret
      self.text = nt
      @caret = Math.min(old + s.size, @text.size) if @text != nt || @text.size >= old + s.size
      @blink = 0_f32
    end

    # Blinks the caret. Called by the engine.
    def process(dt : Float32) : Nil
      super
      @blink += dt
    end

    # :nodoc:
    def focus_entered_hook; end

    # Handles typing, editing keys, clicks and Enter.
    def gui_input(event : Event) : Bool
      case event
      when TextEvent
        insert(event.text)
        return true
      when KeyEvent
        return false unless event.pressed?
        @blink = 0_f32
        case event.key
        when Key::Backspace
          if @caret > 0
            self.text = @text[0, @caret - 1] + @text[@caret..]
            @caret -= 1
          end
        when Key::Delete
          self.text = @text[0, @caret] + @text[@caret + 1..] if @caret < @text.size
        when Key::Left then @caret = Math.max(0, @caret - 1)
        when Key::Right then @caret = Math.min(@text.size, @caret + 1)
        when Key::Home then @caret = 0
        when Key::End then @caret = @text.size
        when Key::Enter, Key::KpEnter then emit_submitted(@text)
        when Key::Escape then release_focus
        when Key::V
          if event.mods.ctrl? || event.mods.gui?
            insert(Eagle.platform?.try(&.clipboard) || "")
          else
            return false
          end
        else
          return false
        end
        return true
      when MouseButtonEvent
        if event.pressed? && event.button.left?
          # place caret near click
          l = to_local(event.position)
          t = theme_or_inherited
          best = @text.size
          (0..@text.size).each do |i|
            w = font.width(display_text[0, i]) + t.padding
            if w >= l.x
              best = i
              break
            end
          end
          @caret = best
          @blink = 0_f32
          return true
        end
      end
      false
    end

    # Takes focus and turns on text input.
    def grab_focus : Nil
      super
      Input.text_input = true if focused?
    end

    # Gives up focus and turns off text input.
    def release_focus : Nil
      was = focused?
      super
      Input.text_input = false if was
    end

    private def display_text : String
      @password ? "*" * @text.size : @text
    end

    # Draws the field.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      draw_panel(g, rect, t.input_bg, focused? ? t.focus : t.panel_border)
      f = font
      shown = display_text
      x = t.padding
      y = (@size.y - f.height) / 2
      g.with_scissor(global_rect.intersection(g.scissor_rect || Rect.new(-1e6, -1e6, 2e6, 2e6))) do
        if shown.empty? && !focused?
          g.print(@placeholder, x, y, g.color * t.text_disabled, f)
        else
          g.print(shown, x, y, g.color * t.text, f)
        end
        if focused? && (@blink % 1.0) < 0.5
          cx = x + f.width(shown[0, @caret])
          g.rect(cx, y, 2, f.height, color: g.color * t.text)
        end
      end
    end
  end

  # An image inside a UI layout, for icons, portraits and logos.
  class ImageControl < Control
    # The image to show.
    property texture : Drawable?
    # Keep the image's proportions when the control's shape differs.
    property? keep_aspect = true
    # Color multiplied into the image.
    property tint : Color = Color::WHITE

    # Creates an image control.
    def initialize(@texture : Drawable? = nil, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @mouse_enabled = false
      @size = size || content_min_size
    end

    # The image's size.
    def content_min_size : Vec2
      case (t = @texture)
      in Texture then t.size
      in TextureRegion then t.size
      in Nil then Vec2::ZERO
      end
    end

    # Draws the image.
    def draw(g : Graphics) : Nil
      t = @texture
      return unless t
      ts = content_min_size
      dest = rect
      if @keep_aspect && ts.x > 0 && ts.y > 0
        s = Math.min(@size.x / ts.x, @size.y / ts.y)
        w = ts.x * s; h = ts.y * s
        dest = Rect.new((@size.x - w) / 2, (@size.y - h) / 2, w, h)
      end
      g.draw(t, dest, g.color * @tint)
    end
  end
end
