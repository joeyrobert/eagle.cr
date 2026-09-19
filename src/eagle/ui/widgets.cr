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
    # The input method's in-progress text, shown underlined at the caret until it is committed.
    getter preedit : String = ""
    @blink = 0_f32
    @area_sent : {Rect, String, Int32}? = nil

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
      sync_text_input_area if focused?
    end

    # :nodoc:
    def focus_entered_hook; end

    # Copies the whole text to the clipboard (nothing for password fields).
    def copy : Nil
      Clipboard.text = @text unless @password
    end

    # Copies the whole text to the clipboard and clears the field.
    def cut : Nil
      return if @password
      copy
      self.text = ""
      @caret = 0
    end

    # Inserts the clipboard text at the caret.
    def paste : Nil
      insert(Clipboard.text)
    end

    # Handles typing, editing keys, clicks and Enter.
    def gui_input(event : Event) : Bool
      case event
      when TextEvent
        @preedit = ""
        insert(event.text)
        return true
      when CompositionEvent
        @preedit = event.text
        @blink = 0_f32
        return true
      when ClipboardEvent
        case event.action
        in .paste? then insert(event.text)
        in .copy? then copy
        in .cut? then cut
        end
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
        when Key::V, Key::C, Key::X
          return false unless event.mods.ctrl? || event.mods.gui?
          case event.key
          when Key::V then paste
          when Key::C then copy
          else             cut
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
      @preedit = ""
      @area_sent = nil
      Input.text_input = false if was
    end

    private def sync_text_input_area : Nil
      t = theme_or_inherited
      f = font
      g = global_rect
      cx = g.x + t.padding + f.width(display_text[0, @caret])
      state = {Rect.new(cx, g.y, 2, g.h), @password ? "" : @text, @caret}
      return if @area_sent == state
      @area_sent = state
      Input.text_input_area(*state)
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
      before = shown[0, @caret]
      g.with_scissor(global_rect.intersection(g.scissor_rect || Rect.new(-1e6, -1e6, 2e6, 2e6))) do
        if shown.empty? && !focused? && @preedit.empty?
          g.print(@placeholder, x, y, g.color * t.text_disabled, f)
        else
          g.print(before + @preedit + shown[@caret..], x, y, g.color * t.text, f)
        end
        unless @preedit.empty?
          px = x + f.width(before)
          g.rect(px, y + f.height - 1, f.width(@preedit), 1, color: g.color * t.text)
        end
        if focused? && (@blink % 1.0) < 0.5
          cx = x + f.width(before + @preedit)
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

  # A closed field that shows the current item, and an open list for picking another.
  # The list is a popup overlay (high `z_index`) so it draws above sibling controls.
  # Click an item or use the arrow keys and Enter while focused.
  #
  # ```
  # biome = OptionButton.new(["Forest", "Desert", "Ocean"])
  # biome.on_item_selected { |i| puts biome.items[i] }
  # ```
  class OptionButton < Control
    # :nodoc:
    class Overlay < Control
      def initialize(@owner : OptionButton)
        super("OptionOverlay")
        @anchor = Anchor::Fill
        @z_index = 1000
        @focusable = false
      end

      def gui_input(event : Event) : Bool
        case event
        when MouseButtonEvent
          if event.pressed? && event.button.left?
            @owner.close unless @owner.popup_contains?(event.position)
            return true
          end
        end
        false
      end

      def draw(g : Graphics) : Nil
      end
    end

    # :nodoc:
    class Item < Control
      getter index : Int32
      getter text : String

      def initialize(@owner : OptionButton, @index : Int32, @text : String)
        super("OptionItem")
        @focusable = false
      end

      def content_min_size : Vec2
        t = theme_or_inherited
        ts = font.measure(@text)
        Vec2.new(ts.x + t.padding * 2, Math.max(ts.y, t.control_height))
      end

      def gui_input(event : Event) : Bool
        case event
        when MouseButtonEvent
          if event.button.left? && event.released? && @pressed && contains_global?(event.position)
            @owner.pick(@index)
            return true
          end
          return event.pressed?
        when MouseMotionEvent
          @owner.highlight = @index if contains_global?(event.position)
        end
        false
      end

      def draw(g : Graphics) : Nil
        t = theme_or_inherited
        hi = @owner.highlight == @index
        sel = @owner.selected == @index
        bg = t.input_bg
        bg = t.button_hover if hi
        bg = t.button_pressed if sel && !hi
        bg = t.accent if sel && hi
        draw_panel(g, rect, bg, nil, 0)
        tc = (sel && hi) ? t.accent_text : (@disabled ? t.text_disabled : t.text)
        ts = font.measure(@text)
        g.print(@text, t.padding, (@size.y - ts.y) / 2, g.color * tc, font)
      end
    end

    # Entries shown in the closed field and in the open list.
    getter items : Array(String)
    # Index of the current item, or `-1` when the list is empty.
    getter selected : Int32
    # Index drawn as the keyboard or mouse highlight in the open list.
    property highlight : Int32 = 0
    # True while the popup list is shown.
    getter? open = false
    # Background color. `nil` uses the theme.
    property color : Color? = nil
    # Text color. `nil` uses the theme.
    property text_color : Color? = nil

    @popup : {Overlay, Panel, VBox}? = nil

    # Emitted when an item is picked, with its index. Connect with `on_item_selected { |i| ... }`.
    signal item_selected(index : Int32)

    # Creates a drop-down from *items*. The first item is selected by default.
    def initialize(@items : Array(String) = [] of String, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @focusable = true
      @selected = @items.empty? ? -1 : 0
      @highlight = @selected < 0 ? 0 : @selected
      @size = size || content_min_size
      on_focus_exited { close }
    end

    # Replaces the item list. Keeps `selected` when it is still in range.
    def items=(v : Array(String))
      @items = v
      @selected = v.empty? ? -1 : @selected.clamp(0, v.size - 1)
      @highlight = @selected < 0 ? 0 : @selected
      close
    end

    # Sets the selected index without emitting `item_selected`.
    def selected=(i : Int32)
      @selected = @items.empty? ? -1 : i.clamp(0, @items.size - 1)
      @highlight = @selected < 0 ? 0 : @selected
    end

    # The current item's text, or `""` when nothing is selected.
    def selected_text : String
      @selected >= 0 && @selected < @items.size ? @items[@selected] : ""
    end

    # Appends an item.
    def add_item(text : String) : Nil
      @items << text
      @selected = 0 if @selected < 0
    end

    # Removes every item and closes the popup.
    def clear : Nil
      @items = [] of String
      @selected = -1
      close
    end

    # Size needed for the current text and the chevron.
    def content_min_size : Vec2
      t = theme_or_inherited
      label = selected_text.empty? ? " " : selected_text
      ts = font.measure(label)
      Vec2.new(ts.x + t.padding * 2 + 16, Math.max(ts.y + t.padding, t.control_height))
    end

    # Resizes to fit the content when needed.
    def layout : Nil
      super
      self.size = @size.max(content_min_size)
      update_popup_transform if @open
    end

    # :nodoc:
    def process(dt : Float32) : Nil
      super
      update_popup_transform if @open
    end

    # Opens the list. Does nothing when empty or disabled.
    def open : Nil
      return if @open || @disabled || @items.empty?
      rebuild_items
      host = popup_host
      overlay = popup[0]
      host.add(overlay) unless overlay.parent
      @open = true
      @highlight = @selected < 0 ? 0 : @selected
      grab_focus
      update_popup_transform
    end

    # Hides the list.
    def close : Nil
      return unless @open
      @open = false
      @popup.try { |p| p[0].remove_from_parent }
    end

    # Selects *index*, closes the list, and emits `item_selected`.
    def pick(index : Int32) : Nil
      return if @disabled || @items.empty?
      close
      @selected = index.clamp(0, @items.size - 1)
      @highlight = @selected
      emit_item_selected(@selected)
    end

    # :nodoc:
    def popup_contains?(p : Vec2) : Bool
      @popup.try { |pp| pp[1].contains_global?(p) } || false
    end

    # Handles click-to-toggle and keyboard picking.
    def gui_input(event : Event) : Bool
      case event
      when MouseButtonEvent
        if event.button.left? && event.released? && @pressed && contains_global?(event.position)
          @open ? close : self.open
          return true
        end
        return event.pressed?
      when KeyEvent
        return false unless event.pressed?
        if @open
          case event.key
          when Key::Up
            @highlight = Math.max(0, @highlight - 1)
            return true
          when Key::Down
            @highlight = Math.min(@items.size - 1, @highlight + 1)
            return true
          when Key::Home
            @highlight = 0
            return true
          when Key::End
            @highlight = Math.max(0, @items.size - 1)
            return true
          when Key::Enter, Key::Space, Key::KpEnter
            pick(@highlight)
            return true
          when Key::Escape
            close
            return true
          end
        else
          case event.key
          when Key::Enter, Key::Space, Key::KpEnter, Key::Down, Key::Up
            self.open
            return true
          end
        end
      end
      false
    end

    # :nodoc:
    def exit_tree : Nil
      close
      super
    end

    # Draws the closed field and chevron.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      bg = @color || t.button
      bg = t.button_hover if @hovered && !@pressed
      bg = t.button_pressed if @pressed || @open
      bg = bg.lerp(t.panel, 0.5) if @disabled
      draw_panel(g, rect, bg, t.button_border)
      draw_focus_ring(g)
      tc = @text_color || (@disabled ? t.text_disabled : t.text)
      ts = font.measure(selected_text)
      g.print(selected_text, t.padding, (@size.y - ts.y) / 2, g.color * tc, font)
      ax = @size.x - t.padding - 5
      ay = @size.y / 2
      g.triangle(Vec2.new(ax - 5, ay - 3), Vec2.new(ax + 5, ay - 3), Vec2.new(ax, ay + 4), color: g.color * tc)
    end

    # The overlay, its panel and the item column, built on first use.
    private def popup : {Overlay, Panel, VBox}
      @popup ||= begin
        overlay = Overlay.new(self)
        panel = Panel.new
        panel.fit_content = true
        panel.z_index = 1
        list = VBox.new
        list.fit_content = true
        list.spacing = 0
        list.padding = 0
        panel.add(list)
        overlay.add(panel)
        {overlay, panel, list}
      end
    end

    private def popup_host : Node
      each_ancestor { |n| return n if n.is_a?(CanvasLayer) }
      SceneTree.root
    end

    private def rebuild_items : Nil
      list = popup[2]
      list.children.dup.each(&.remove_from_parent)
      @items.each_with_index do |text, i|
        row = Item.new(self, i, text)
        row.min_size = Vec2.new(@size.x, theme_or_inherited.control_height)
        list.add(row)
      end
    end

    private def update_popup_transform : Nil
      overlay, panel, _ = popup
      return unless overlay.parent
      panel.position = global_position + Vec2.new(0, @size.y) - overlay.global_position
      panel.width = Math.max(@size.x, panel.size.x)
    end
  end

  # Shows part of one large child and scrolls it with the mouse wheel or draggable bars.
  # The child is usually a `VBox`. Its size follows the container's width unless
  # `horizontal` is set. Content outside the viewport is clipped and does not get clicks.
  #
  # ```
  # list = VBox.new
  # 30.times { |i| list.add(Label.new("Row #{i}")) }
  # scroller = ScrollContainer.new(size: v2(200, 120))
  # scroller.add(list)
  # scroller.on_scrolled { |offset| puts offset.y }
  # scroller.scroll_to(v2(0, 64))
  # ```
  class ScrollContainer < Container
    # Thickness of the scroll bars.
    BAR = 10_f32

    # Allow scrolling left and right.
    property? horizontal = false
    # Allow scrolling up and down.
    property? vertical = true
    # Points scrolled per wheel notch.
    property wheel_step : Float32 = 32_f32
    # Background color. `nil` uses the theme's field color.
    property color : Color? = nil
    # Current scroll offset in points.
    getter scroll : Vec2 = Vec2::ZERO
    # Size of the visible area, excluding the bars, after the last layout.
    getter viewport : Vec2 = Vec2::ZERO

    @bar_v = false
    @bar_h = false
    @drag = -1
    @drag_grab = 0_f32

    # Emitted when the offset changes, with the new offset. Connect with `on_scrolled { |offset| ... }`.
    signal scrolled(offset : Vec2)

    # Creates a scroll container.
    def initialize(position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size || Vec2.new(200, 150))
      @viewport = @size
    end

    # The scrolled child: the first visible control.
    def content : Control?
      control_children.first?
    end

    # Largest valid scroll offset.
    def max_scroll : Vec2
      update_metrics
      return Vec2::ZERO unless c = content
      Vec2.new(@horizontal ? Math.max(0_f32, c.size.x - @viewport.x) : 0_f32, @vertical ? Math.max(0_f32, c.size.y - @viewport.y) : 0_f32)
    end

    # Scrolls to *offset*, clamped to the content. Emits `scrolled` when it changes.
    def scroll_to(offset : Vec2) : Nil
      m = max_scroll
      v = Vec2.new(offset.x.clamp(0_f32, m.x), offset.y.clamp(0_f32, m.y))
      return if v == @scroll
      @scroll = v
      place_content
      emit_scrolled(v)
    end

    # Scrolls the least amount that brings *child* fully into view.
    def ensure_visible(child : Control) : Nil
      return unless c = content
      top_left = child.global_position - c.global_position
      o = @scroll
      x = top_left.x < o.x ? top_left.x : (top_left.x + child.size.x > o.x + @viewport.x ? top_left.x + child.size.x - @viewport.x : o.x)
      y = top_left.y < o.y ? top_left.y : (top_left.y + child.size.y > o.y + @viewport.y ? top_left.y + child.size.y - @viewport.y : o.y)
      scroll_to(Vec2.new(x, y))
    end

    # Sizes and positions the content, and clamps the offset.
    def arrange : Nil
      update_metrics
      m = max_scroll
      @scroll = Vec2.new(@scroll.x.clamp(0_f32, m.x), @scroll.y.clamp(0_f32, m.y))
      place_content
    end

    # Scroll containers position only their content.
    def manages_children? : Bool; true; end

    # Routes wheel scrolling and bar dragging.
    def gui_input(event : Event) : Bool
      case event
      when MouseWheelEvent
        m = max_scroll
        d = event.delta * @wheel_step
        d = Vec2.new(d.y, 0) if m.y <= 0 && m.x > 0 && d.x == 0
        before = @scroll
        scroll_to(Vec2.new(@scroll.x - d.x, @scroll.y - d.y))
        return @scroll != before
      when MouseButtonEvent
        if event.button.left? && event.pressed?
          p = to_local(event.position)
          2.times do |axis|
            next unless bar_shown?(axis)
            if thumb_rect(axis).contains?(p)
              @drag = axis
              @drag_grab = (axis == 1 ? p.y : p.x) - (axis == 1 ? thumb_rect(axis).y : thumb_rect(axis).x)
              return true
            elsif bar_rect(axis).contains?(p)
              page = axis == 1 ? @viewport.y : @viewport.x
              before = axis == 1 ? thumb_rect(axis).y : thumb_rect(axis).x
              dir = (axis == 1 ? p.y : p.x) < before ? -1 : 1
              scroll_to(axis == 1 ? Vec2.new(@scroll.x, @scroll.y + dir * page) : Vec2.new(@scroll.x + dir * page, @scroll.y))
              return true
            end
          end
        elsif event.button.left? && event.released?
          @drag = -1
        end
      when MouseMotionEvent
        if @drag >= 0
          p = to_local(event.position)
          axis = @drag
          range = track_length(axis) - thumb_length(axis)
          m = max_scroll
          if range > 0
            pos = ((axis == 1 ? p.y : p.x) - @drag_grab).clamp(0_f32, range)
            scroll_to(axis == 1 ? Vec2.new(@scroll.x, pos / range * m.y) : Vec2.new(pos / range * m.x, @scroll.y))
          end
          return true
        end
      end
      false
    end

    # Skips clipped content for clicks and wheel events outside the container.
    def input_tree(event : Event) : Nil
      outside = case event
                when MouseButtonEvent, MouseWheelEvent then !contains_global?(event.position)
                else false
                end
      if outside
        input(event) if can_process?
      else
        super
      end
    end

    # Draws the background and scroll bars.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      draw_panel(g, rect, @color || t.input_bg, t.panel_border)
      2.times do |axis|
        next unless bar_shown?(axis)
        g.rect(bar_rect(axis), color: g.color * t.track)
        tr = thumb_rect(axis)
        g.rect(tr, color: g.color * ((@drag == axis || @hovered) ? t.button_hover : t.button_border))
      end
    end

    # Clips the children to the viewport.
    protected def draw_children(g : Graphics) : Nil
      gp = global_position
      clip = Rect.new(gp.x, gp.y, @viewport.x, @viewport.y)
      outer = g.scissor_rect
      g.with_scissor(outer ? clip.intersection(outer) : clip) { super(g) }
    end

    private def bar_shown?(axis : Int32) : Bool
      axis == 1 ? @bar_v : @bar_h
    end

    private def track_length(axis : Int32) : Float32
      axis == 1 ? @viewport.y : @viewport.x
    end

    private def thumb_length(axis : Int32) : Float32
      c = content
      return 0_f32 unless c
      tl = track_length(axis)
      total = axis == 1 ? c.size.y : c.size.x
      return tl if total <= 0
      (tl * tl / total).clamp(Math.min(BAR * 2, tl), tl)
    end

    private def thumb_pos(axis : Int32) : Float32
      m = max_scroll
      max = axis == 1 ? m.y : m.x
      return 0_f32 if max <= 0
      (axis == 1 ? @scroll.y : @scroll.x) / max * (track_length(axis) - thumb_length(axis))
    end

    private def bar_rect(axis : Int32) : Rect
      axis == 1 ? Rect.new(@viewport.x, 0, BAR, @viewport.y) : Rect.new(0, @viewport.y, @viewport.x, BAR)
    end

    private def thumb_rect(axis : Int32) : Rect
      axis == 1 ? Rect.new(@viewport.x + 1, thumb_pos(axis), BAR - 2, thumb_length(axis)) : Rect.new(thumb_pos(axis), @viewport.y + 1, thumb_length(axis), BAR - 2)
    end

    private def update_metrics : Nil
      c = content
      @bar_v = false
      @bar_h = false
      @viewport = @size
      return unless c
      min = c.effective_min_size
      2.times do
        @bar_v = @vertical && min.y > @size.y - (@bar_h ? BAR : 0)
        @bar_h = @horizontal && min.x > @size.x - (@bar_v ? BAR : 0)
      end
      @viewport = Vec2.new(@size.x - (@bar_v ? BAR : 0), @size.y - (@bar_h ? BAR : 0))
      w = @horizontal ? Math.max(min.x, @viewport.x) : @viewport.x
      h = @vertical ? Math.max(min.y, @viewport.y) : @viewport.y
      c.size = Vec2.new(w, h)
    end

    private def place_content : Nil
      content.try { |c| c.position = Vec2.new(-@scroll.x, -@scroll.y) }
    end
  end

  # A drop-down list. Same as `OptionButton`.
  #
  # ```
  # quality = DropDown.new(["Low", "High"])
  # ```
  alias DropDown = OptionButton

  # Label that draws a small markup subset: `**bold**` or `[b]bold[/b]`,
  # `[color=#rrggbb]text[/color]`, newlines, and optional `[url=meta]text[/url]`
  # links. It is not HTML.
  #
  # ```
  # hint = RichTextLabel.new("**Tip:** collect [color=#e3a537]coins[/color].")
  # hint.wrap = true
  # ```
  class RichTextLabel < Control
    # One styled slice of the source string, after markup is stripped.
    #
    # ```
    # spans = RichTextLabel.parse("plain **bold**")
    # spans[1].bold? # => true
    # ```
    struct Span
      # Visible text in this slice.
      getter text : String
      # True when the slice is bold.
      getter? bold : Bool
      # Fill color, or `nil` to use the theme text color.
      getter color : Color?
      # Link meta string from `[url=...]`, or `nil`.
      getter url : String?

      # Creates a span.
      def initialize(@text : String, @bold = false, @color : Color? = nil, @url : String? = nil)
      end
    end

    # A laid-out fragment ready to draw.
    #
    # ```
    # label = RichTextLabel.new("go [url=door]here[/url]")
    # label.layout
    # link = label.runs.find { |run| run.url }
    # ```
    struct Run
      # Visible text.
      getter text : String
      # Top-left in the control's local space.
      getter position : Vec2
      # Measured size of this fragment.
      getter size : Vec2
      # True when drawn with a fake bold offset.
      getter? bold : Bool
      # Draw color.
      getter color : Color
      # Link meta, or `nil`.
      getter url : String?

      # Creates a run.
      def initialize(@text, @position, @size, @bold, @color, @url = nil)
      end

      # Hit area of this fragment.
      def rect : Rect
        Rect.new(@position, @size)
      end
    end

    # Source string, including markup.
    getter text : String
    # Text color used when a span has no `[color]` tag. `nil` uses the theme.
    property color : Color? = nil
    # Text scale.
    property font_scale : Float32 = 1_f32
    # Wrap runs to the control's width.
    property? wrap = false
    # A font for this label only.
    property label_font : Font? = nil
    # Parsed spans. Useful in tests.
    getter spans = [] of Span
    # Laid-out fragments. Useful in tests.
    getter runs = [] of Run
    # Number of lines after the last layout pass.
    getter line_count : Int32 = 1

    @layout_w = 0_f32
    @layout_h = 0_f32
    @pen_x = 0_f32
    @pen_y = 0_f32

    # Emitted when a `[url]` run is clicked, with the tag's meta string.
    # Connect with `on_meta_clicked { |meta| ... }`.
    signal meta_clicked(meta : String)

    # Creates a rich-text label.
    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, color : Color? = nil, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @color = color
      @spans = RichTextLabel.parse(@text)
      @mouse_enabled = @spans.any? { |s| s.url }
      @size = size || (GPU.ready? ? content_min_size : Vec2.new(100, 20))
    end

    # The font in use.
    def font : Font; @label_font || super; end

    # Replaces the source string and re-parses markup.
    def text=(t : String)
      @text = t
      @spans = RichTextLabel.parse(t)
      @mouse_enabled = @spans.any? { |s| s.url }
      @runs = [] of Run
    end

    # Visible text with markup removed.
    def plain_text : String
      @spans.map(&.text).join
    end

    # Parses *text* into styled spans. Unknown tags are kept as literal text.
    def self.parse(text : String) : Array(Span)
      spans = [] of Span
      buf = [] of Char
      md_bold = false
      b_count = 0
      colors = [] of Color
      urls = [] of String
      chars = text.chars
      i = 0
      n = chars.size
      flush = -> {
        unless buf.empty?
          spans << Span.new(buf.join, md_bold || b_count > 0, colors.last?, urls.last?)
          buf.clear
        end
      }
      while i < n
        if chars[i] == '*' && i + 1 < n && chars[i + 1] == '*'
          flush.call
          md_bold = !md_bold
          i += 2
          next
        end
        if chars[i] == '['
          j = i + 1
          while j < n && chars[j] != ']'
            j += 1
          end
          if j < n
            tag = String.build { |io| (i + 1...j).each { |k| io << chars[k] } }
            applied = true
            case tag
            when "b"
              flush.call
              b_count += 1
            when "/b"
              flush.call
              b_count = Math.max(0, b_count - 1)
            when "/color"
              flush.call
              colors.pop? unless colors.empty?
            when "/url"
              flush.call
              urls.pop? unless urls.empty?
            else
              if tag.starts_with?("color=")
                begin
                  col = Color.hex(tag.lchop("color="))
                  flush.call
                  colors << col
                rescue
                  applied = false
                end
              elsif tag.starts_with?("url=")
                flush.call
                urls << tag.lchop("url=")
              else
                applied = false
              end
            end
            if applied
              i = j + 1
              next
            end
          end
        end
        buf << chars[i]
        i += 1
      end
      flush.call
      spans
    end

    # Size of the laid-out text.
    def content_min_size : Vec2
      rebuild_layout
      @wrap ? Vec2.new(0, @layout_h) : Vec2.new(@layout_w, @layout_h)
    end

    # Relays out when the size changes.
    def layout : Nil
      super
      rebuild_layout
      self.size = @size.max(@wrap ? Vec2.new(@size.x, @layout_h) : Vec2.new(@layout_w, @layout_h))
    end

    # Clicks `[url]` runs.
    def gui_input(event : Event) : Bool
      case event
      when MouseButtonEvent
        if event.button.left? && event.released? && contains_global?(event.position)
          local = to_local(event.position)
          @runs.each do |run|
            if (meta = run.url) && run.rect.contains?(local)
              emit_meta_clicked(meta)
              return true
            end
          end
        end
      end
      false
    end

    # Draws each run, with a one-pixel offset for bold.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      @runs.each do |run|
        col = g.color * (@disabled ? t.text_disabled : run.color)
        g.print(run.text, run.position.x, run.position.y, col, font, @font_scale)
        g.print(run.text, run.position.x + 1, run.position.y, col, font, @font_scale) if run.bold?
        if run.url
          g.rect(run.position.x, run.position.y + run.size.y - 1, run.size.x, 1, color: col)
        end
      end
    end

    private def rebuild_layout : Nil
      @runs = [] of Run
      @pen_x = 0_f32
      @pen_y = 0_f32
      @line_count = 1
      @layout_w = 0_f32
      line_h = font.height * @font_scale
      @spans.each do |span|
        parts = span.text.split('\n')
        parts.each_with_index do |part, pi|
          newline(line_h) if pi > 0
          emit_text(part, span)
        end
      end
      @layout_h = @pen_y + line_h
      @layout_h = line_h if @spans.empty?
      @layout_w = Math.max(@layout_w, @pen_x)
    end

    private def newline(line_h : Float32)
      @layout_w = Math.max(@layout_w, @pen_x)
      @pen_x = 0_f32
      @pen_y += line_h
      @line_count += 1
    end

    private def emit_text(text : String, span : Span)
      return if text.empty?
      unless @wrap && @size.x > 0
        emit_run(text, span)
        return
      end
      token = String::Builder.new
      text.each_char do |c|
        if c == ' '
          emit_run(token.to_s, span) unless token.empty?
          token = String::Builder.new
          emit_run(" ", span)
        else
          token << c
        end
      end
      emit_run(token.to_s, span) unless token.empty?
    end

    private def emit_run(text : String, span : Span)
      return if text.empty?
      f = font
      w = f.width(text) * @font_scale
      w += 1 if span.bold? && w > 0
      h = f.height * @font_scale
      if @wrap && @size.x > 0 && @pen_x > 0 && (@pen_x + w) > @size.x && text != " "
        newline(h)
      end
      col = span.color || @color || theme_or_inherited.text
      @runs << Run.new(text, Vec2.new(@pen_x, @pen_y), Vec2.new(w, h), span.bold?, col, span.url)
      @pen_x += w
      @layout_w = Math.max(@layout_w, @pen_x)
    end
  end

  # Same as `RichTextLabel`.
  #
  # ```
  # note = RichText.new("[b]Note:[/b] saved")
  # ```
  alias RichText = RichTextLabel
end

