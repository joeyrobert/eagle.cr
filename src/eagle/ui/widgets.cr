module Eagle
  # Text. Works both as a plain scene node and inside UI containers.
  class Label < Control
    property text : String
    property color : Color? = nil
    property align : TextAlign = TextAlign::Left
    property valign : Symbol = :top # :top, :center, :bottom
    property font_scale : Float32 = 1_f32
    # Wrap text to the control width.
    property? wrap = false
    property shadow : Color? = nil
    property shadow_offset : Vec2 = Vec2.new(1, 1)
    # Use a specific font instead of the theme font.
    property label_font : Font? = nil

    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, color : Color? = nil, name : String = "", @align = TextAlign::Left, font : Font? = nil, size : Vec2? = nil)
      super(name, position, size)
      @color = color
      @label_font = font
      @mouse_enabled = false
      @size = content_min_size unless size
    end

    def font : Font; @label_font || super; end
    def text=(t : String); @text = t; end

    def content_min_size : Vec2
      f = font
      if @wrap && @size.x > 0
        lines = f.wrap(@text, @size.x / @font_scale)
        Vec2.new(0, lines.size * f.height * @font_scale)
      else
        f.measure(@text) * @font_scale
      end
    end

    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

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

  # A clickable button. `on_pressed { }`.
  class Button < Control
    property text : String
    property icon : Drawable? = nil
    property? toggle_mode = false
    getter? toggled = false
    property color : Color? = nil
    property text_color : Color? = nil
    property font_scale : Float32 = 1_f32

    signal pressed
    signal toggled(on : Bool)

    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil, &block : ->)
      super(name, position, size)
      @focusable = true
      on_pressed(&block)
      @size = content_min_size unless size
    end

    def initialize(@text : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @focusable = true
      @size = content_min_size unless size
    end

    def toggled=(v : Bool)
      return if v == @toggled
      @toggled = v
      emit_toggled(v)
    end

    def content_min_size : Vec2
      t = theme_or_inherited
      ts = font.measure(@text) * @font_scale
      iw = 0_f32
      if ic = @icon
        iw = (ic.is_a?(Texture) ? ic.width.to_f32 : ic.width) + (@text.empty? ? 0 : t.spacing)
      end
      Vec2.new(ts.x + iw + t.padding * 2, Math.max(ts.y + t.padding, t.control_height))
    end

    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

    # Programmatic click.
    def click : Nil
      return if @disabled
      self.toggled = !@toggled if @toggle_mode
      emit_pressed
    end

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

  # A toggle with a box and label. `on_toggled { |checked| }`.
  class CheckBox < Control
    property text : String
    getter? checked : Bool

    signal toggled(checked : Bool)

    def initialize(@text : String = "", @checked = false, position : Vec2 = Vec2::ZERO, name : String = "")
      super(name, position)
      @focusable = true
      @size = content_min_size
    end

    def checked=(v : Bool)
      return if v == @checked
      @checked = v
      emit_toggled(v)
    end

    def toggle : Nil; self.checked = !@checked; end

    def box_size : Float32; theme_or_inherited.control_height * 0.6_f32; end

    def content_min_size : Vec2
      t = theme_or_inherited
      ts = font.measure(@text)
      Vec2.new(box_size + t.spacing + ts.x, Math.max(ts.y, t.control_height))
    end

    def layout : Nil
      super
      self.size = @size.max(content_min_size)
    end

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

  # Horizontal or vertical value slider. `on_value_changed { |v| }`.
  class Slider < Control
    property min : Float32
    property max : Float32
    property step : Float32
    getter value : Float32
    property? vertical = false
    @dragging = false

    signal value_changed(value : Float32)

    def initialize(min : Number = 0, max : Number = 1, value : Number = 0, step : Number = 0, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @min = min.to_f32; @max = max.to_f32; @step = step.to_f32
      @value = snap(value.to_f32)
      @focusable = true
      @size = size || Vec2.new(160, theme_or_inherited.control_height)
    end

    def value=(v : Number)
      nv = snap(v.to_f32)
      return if nv == @value
      @value = nv
      emit_value_changed(nv)
    end

    def ratio : Float32; @max == @min ? 0_f32 : (@value - @min) / (@max - @min); end
    def ratio=(r : Number); self.value = @min + (@max - @min) * r.to_f32.clamp(0_f32, 1_f32); end

    private def snap(v : Float32) : Float32
      v = v.clamp(Math.min(@min, @max), Math.max(@min, @max))
      @step > 0 ? (((v - @min) / @step).round * @step + @min).clamp(@min, @max) : v
    end

    def content_min_size : Vec2
      t = theme_or_inherited
      @vertical ? Vec2.new(t.control_height, 60) : Vec2.new(60, t.control_height)
    end

    private def set_from_point(p : Vec2)
      l = to_local(p)
      self.ratio = @vertical ? 1 - l.y / @size.y : l.x / @size.x
    end

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

  # Shows progress 0..1 (or min..max).
  class ProgressBar < Control
    property min : Float32 = 0_f32
    property max : Float32 = 1_f32
    property value : Float32
    property? show_text = true
    property color : Color? = nil

    def initialize(value : Number = 0, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @value = value.to_f32
      @mouse_enabled = false
      @size = size || Vec2.new(160, theme_or_inherited.control_height * 0.6)
    end

    def ratio : Float32; @max == @min ? 0_f32 : ((@value - @min) / (@max - @min)).clamp(0_f32, 1_f32); end
    def content_min_size : Vec2; Vec2.new(40, 10); end

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

  # Single-line text entry. `on_submitted { |text| }`, `on_text_changed { |text| }`.
  class TextInput < Control
    getter text : String
    property placeholder : String
    property max_length : Int32 = 0
    property? password = false
    getter caret : Int32 = 0
    @blink = 0_f32

    signal text_changed(text : String)
    signal submitted(text : String)

    def initialize(@text : String = "", @placeholder : String = "", position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @focusable = true
      @caret = @text.size
      @size = size || Vec2.new(200, theme_or_inherited.control_height)
    end

    def text=(t : String)
      t = t[0, @max_length] if @max_length > 0 && t.size > @max_length
      return if t == @text
      @text = t
      @caret = @caret.clamp(0, @text.size)
      emit_text_changed(t)
    end

    def content_min_size : Vec2
      t = theme_or_inherited
      Vec2.new(60, Math.max(font.height + t.padding, t.control_height))
    end

    def insert(s : String) : Nil
      s = s.gsub('\n', "")
      return if s.empty?
      nt = @text[0, @caret] + s + @text[@caret..]
      old = @caret
      self.text = nt
      @caret = Math.min(old + s.size, @text.size) if @text != nt || @text.size >= old + s.size
      @blink = 0_f32
    end

    def process(dt : Float32) : Nil
      super
      @blink += dt
    end

    def focus_entered_hook; end

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

    def grab_focus : Nil
      super
      Input.text_input = true if focused?
    end

    def release_focus : Nil
      was = focused?
      super
      Input.text_input = false if was
    end

    private def display_text : String
      @password ? "*" * @text.size : @text
    end

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

  # An image inside a UI layout.
  class ImageControl < Control
    property texture : Drawable?
    property? keep_aspect = true
    property tint : Color = Color::WHITE

    def initialize(@texture : Drawable? = nil, position : Vec2 = Vec2::ZERO, name : String = "", size : Vec2? = nil)
      super(name, position, size)
      @mouse_enabled = false
      @size = size || content_min_size
    end

    def content_min_size : Vec2
      case (t = @texture)
      in Texture then t.size
      in TextureRegion then t.size
      in Nil then Vec2::ZERO
      end
    end

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
