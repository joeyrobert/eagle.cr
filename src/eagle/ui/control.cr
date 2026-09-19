module Eagle
  # Where a control sits inside its parent when no container is arranging it. `margin`
  # offsets it from that spot, and `Fill` stretches it to the parent's size minus the margins.
  #
  # ```
  # pause = Panel.new(size: v2(300, 200))
  # pause.anchor = Anchor::Center            # stays centered when the window resizes
  #
  # hud_score = Label.new("0")
  # hud_score.anchor = Anchor::TopRight
  # hud_score.margin = Vec4.new(-10, 10, 0, 0) # 10 px in from the corner
  # ```
  enum Anchor
    TopLeft; Top; TopRight
    Left; Center; Right
    BottomLeft; Bottom; BottomRight
    # Stretch to fill the parent, minus margins.
    Fill

    # Where the anchor sits as fractions of the parent size: `(0, 0)` is top-left and `(1, 1)` bottom-right.
    def factors : Vec2
      case self
      in TopLeft then Vec2.new(0, 0)
      in Top then Vec2.new(0.5, 0)
      in TopRight then Vec2.new(1, 0)
      in Left then Vec2.new(0, 0.5)
      in Center then Vec2.new(0.5, 0.5)
      in Right then Vec2.new(1, 0.5)
      in BottomLeft then Vec2.new(0, 1)
      in Bottom then Vec2.new(0.5, 1)
      in BottomRight then Vec2.new(1, 1)
      in Fill then Vec2.new(0, 0)
      end
    end
  end

  @[Flags]
  # How a control grows inside a box container. `ExpandX` or `ExpandY` makes it take up the spare space.
  enum SizeFlags
    # Take a share of spare width in an `HBox`.
    ExpandX
    # Take a share of spare height in a `VBox`.
    ExpandY
    # Expand in both directions.
    Expand = ExpandX | ExpandY
  end

  # Which control currently has keyboard focus. There is only one at a time.
  module Focus
    @@current : Control? = nil
    # The focused control, or `nil`.
    def self.current : Control?; @@current; end
    # Moves focus. Prefer `Control#grab_focus`.
    def self.current=(c : Control?); @@current = c; end
  end

  # The base class of every UI widget. A control has a size, reacts to the mouse and
  # keyboard, can hold keyboard focus, and is laid out by containers.
  #
  # Build UIs from widgets (`Label`, `Button`, `CheckBox`, `Slider`, `ProgressBar`,
  # `TextInput`, `ImageControl`) arranged by containers (`VBox`, `HBox`, `GridContainer`,
  # `Panel`). Put the UI on a `CanvasLayer` so it ignores the game camera.
  #
  # ```
  # hud = CanvasLayer.new
  # menu = Panel.new(size: v2(260, 0))
  # menu.anchor = Anchor::Center
  # menu.fit_content = true
  #
  # list = VBox.new(size: v2(240, 0))
  # list.position = v2(10, 10)
  # list.fit_content = true
  # list.add(Label.new("Settings"),
  #   Slider.new(0, 100, 50).tap { |s| s.on_value_changed { |v| Audio.volume = v / 100 } },
  #   CheckBox.new("Fullscreen").tap { |c| c.on_toggled { |on| Window.fullscreen = on } },
  #   Button.new("Play") { puts "start!" })
  #
  # menu.add(list)
  # hud.add(menu)
  # SceneTree.root.add(hud)
  # ```
  #
  # Tab and Shift+Tab move focus between focusable controls, Enter and Space activate buttons,
  # and Escape clears focus. Style controls with a `Theme`.
  class Control < Node2D
    # Width and height in points.
    property size : Vec2 = Vec2.new(100, 32)
    # Smallest size the control accepts, combined with what its content needs.
    property min_size : Vec2 = Vec2::ZERO
    # Where the control sits in its parent when no container arranges it.
    property anchor : Anchor = Anchor::TopLeft
    # Offset from the anchor point as `x` and `y`. With `Anchor::Fill`, the four components are
    # the left, top, right and bottom insets.
    # With the default `Anchor::TopLeft`, `position` is used as is and the margin is ignored.
    property margin : Vec4 = Vec4.new(0, 0, 0, 0)
    # Whether the control expands to take spare space in a box container.
    property size_flags : SizeFlags = SizeFlags::None
    # Disabled controls are drawn grayed out and ignore input.
    property? disabled = false
    # Whether the control can hold keyboard focus.
    property? focusable = false
    # When false, mouse events pass through to what's behind.
    property? mouse_enabled = true
    # A theme for this control and its descendants. `nil` inherits from the parent.
    property theme : Theme? = nil
    # Text for a tooltip. Stored for your own tooltip display.
    property tooltip : String = ""
    # True while the mouse is over the control.
    getter? hovered = false
    # True while a mouse button is held down on the control.
    getter? pressed = false

    # Emitted when the mouse moves over the control. Connect with `on_mouse_entered { ... }`.
    signal mouse_entered
    # Emitted when the mouse leaves the control.
    signal mouse_exited
    # Emitted when the control gains keyboard focus.
    signal focus_entered
    # Emitted when the control loses keyboard focus.
    signal focus_exited
    # Emitted when the control's size changes, with the new size.
    signal resized(size : Vec2)

    # The control with keyboard focus, or `nil`.
    def self.focused : Control?; Focus.current; end
    # :nodoc:
    def self.reset_focus; Focus.current = nil; end

    # Every visible, enabled, focusable control under *root*, in tree order.
    def self.focusable_controls(root : Node = SceneTree.root) : Array(Control)
      list = [] of Control
      root.each_descendant { |n| list << n if n.is_a?(Control) && n.focusable? && !n.disabled? && n.visible? && n.can_process? }
      list
    end

    # Handles Tab, Shift+Tab and Escape. The engine calls it for key events nothing else handled.
    def self.handle_focus_navigation(ev : Event) : Nil
      return unless ev.is_a?(KeyEvent) && ev.pressed?
      case ev.key
      when Key::Tab
        list = focusable_controls
        return if list.empty?
        cur = Focus.current
        idx = cur ? (list.index(cur) || -1) : -1
        idx = ev.mods.shift? ? (idx - 1) % list.size : (idx + 1) % list.size
        list[idx].grab_focus
        ev.handled = true
      when Key::Escape
        Focus.current.try(&.release_focus)
      end
    end

    # Moves focus to the next focusable control.
    def focus_next : Nil
      list = Control.focusable_controls
      return if list.empty?
      i = list.index(self) || -1
      list[(i + 1) % list.size].grab_focus
    end

    # Creates a control.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(name, position)
      @size = size if size
    end

    # Width in points.
    def width : Float32; @size.x; end
    # Height in points.
    def height : Float32; @size.y; end
    # Sets the width.
    def width=(v : Number); @size = Vec2.new(v, @size.y); end
    # Sets the height.
    def height=(v : Number); @size = Vec2.new(@size.x, v); end
    # Sets the size and emits `resized`.
    def size=(v : Vec2)
      changed = v != @size
      @size = v
      emit_resized(v) if changed
    end
    # Sets the size and returns self, for chaining.
    def set_size(w : Number, h : Number) : self; self.size = Vec2.new(w, h); self; end

    # The control's area in its own space, from `(0, 0)`.
    def rect : Rect; Rect.new(0, 0, @size.x, @size.y); end
    # The control's area in its parent's space.
    def parent_rect : Rect; Rect.new(@position, @size); end
    # The control's area in screen space.
    def global_rect : Rect
      t = global_transform
      pts = [t * Vec2::ZERO, t * Vec2.new(@size.x, 0), t * @size, t * Vec2.new(0, @size.y)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    # True when this control has keyboard focus.
    def focused? : Bool; Focus.current == self; end

    # Takes keyboard focus, if the control is focusable.
    def grab_focus : Nil
      return if focused? || !@focusable || @disabled
      prev = Focus.current
      Focus.current = self
      prev.try(&.emit_focus_exited)
      emit_focus_entered
    end

    # Gives up keyboard focus.
    def release_focus : Nil
      return unless focused?
      Focus.current = nil
      emit_focus_exited
    end

    # The theme in effect: this control's, the nearest ancestor's, or `Theme.default`.
    def theme_or_inherited : Theme
      return @theme.not_nil! if @theme
      p = @parent
      while p
        if p.is_a?(Control) && (t = p.theme)
          return t
        end
        p = p.parent
      end
      Theme.default
    end

    # The font this control draws with.
    def font : Font
      theme_or_inherited.font_or_default
    end

    # The smallest size the content needs. Widgets override it.
    def content_min_size : Vec2; Vec2::ZERO; end

    # The larger of `min_size` and `content_min_size`.
    def effective_min_size : Vec2; @min_size.max(content_min_size); end

    # The area anchors are measured against: the parent control, or the window.
    def parent_bounds : Rect
      p = parent_control
      p ? p.rect : Window.rect
    end

    # The nearest ancestor that is a control, if any.
    def parent_control : Control?
      p = @parent
      while p
        return p if p.is_a?(Control)
        return nil if p.is_a?(CanvasLayer)
        p = p.parent
      end
      nil
    end

    # Positions the control from its anchor and margin.
    def apply_anchor : Nil
      if (pc = parent_control).is_a?(Container)
        return if pc.manages_children?
      end
      b = parent_bounds
      if @anchor.fill?
        @position = Vec2.new(b.x + @margin.x, b.y + @margin.y)
        self.size = Vec2.new(b.w - @margin.x - @margin.z, b.h - @margin.y - @margin.w).max(effective_min_size)
      elsif @anchor.top_left?
        # default anchor: `position` is used as-is
        self.size = @size.max(effective_min_size)
      else
        f = @anchor.factors
        self.size = @size.max(effective_min_size)
        @position = Vec2.new(b.x + b.w * f.x - @size.x * f.x + @margin.x, b.y + b.h * f.y - @size.y * f.y + @margin.y)
      end
    end

    # Updates layout before drawing. Containers override it to place children.
    def layout : Nil
      apply_anchor
    end

    # Runs layout. Called by the engine.
    def process(dt : Float32) : Nil
      layout
    end

    # Converts a screen point to this control's space.
    def to_local_point(p : Vec2) : Vec2; to_local(p); end

    # True when a screen point is over the control.
    def contains_global?(p : Vec2) : Bool
      rect.contains?(to_local(p))
    end

    # Handles input for this widget. Return true when the event was used. Override it in custom widgets.
    def gui_input(event : Event) : Bool; false; end

    # Routes mouse and keyboard events to `gui_input`, tracking hover, press and focus.
    def input(event : Event) : Nil
      return if @disabled || !@visible
      case event
      when MouseMotionEvent
        inside = @mouse_enabled && contains_global?(event.position)
        if inside != @hovered
          @hovered = inside
          inside ? emit_mouse_entered : emit_mouse_exited
        end
        event.handled = true if gui_input(event)
      when MouseButtonEvent
        if @mouse_enabled && contains_global?(event.position)
          if event.pressed?
            grab_focus if @focusable
            @pressed = true if event.button.left?
          end
          consumed = gui_input(event)
          @pressed = false if event.released?
          event.handled = true if consumed || @mouse_enabled
        elsif event.released?
          was = @pressed
          @pressed = false
          gui_input(event) if was
        elsif event.pressed? && focused?
          release_focus
        end
      when MouseWheelEvent
        event.handled = true if @hovered && gui_input(event)
      when KeyEvent, TextEvent, CompositionEvent, ClipboardEvent
        event.handled = true if focused? && gui_input(event)
      end
    end

    # Releases focus when removed.
    def exit_tree : Nil
      release_focus
      super
    end

    # Drawing helpers for widgets
    protected def draw_panel(g : Graphics, r : Rect, fill : Color, border : Color? = nil, radius : Float32? = nil)
      t = theme_or_inherited
      rad = radius || t.corner_radius
      if rad > 0
        g.rounded_rect(r.x, r.y, r.w, r.h, rad, color: g.color * fill)
        g.rounded_rect(r.x, r.y, r.w, r.h, rad, DrawMode::Line, g.color * border) if border && t.border_width > 0
      else
        g.rect(r, color: g.color * fill)
        g.rect_line(r, g.color * border) if border
      end
    end

    protected def draw_focus_ring(g : Graphics)
      return unless focused?
      t = theme_or_inherited
      g.rounded_rect(-2, -2, @size.x + 4, @size.y + 4, t.corner_radius + 2, DrawMode::Line, g.color * t.focus)
    end
  end

  # Base class for controls that arrange their children, such as `VBox`, `HBox` and `GridContainer`.
  abstract class Container < Control
    # Space between the container's edge and its children. `nil` uses the theme's.
    property padding : Float32? = nil
    # Space between children. `nil` uses the theme's.
    property spacing : Float32? = nil

    # Padding in effect.
    def pad : Float32; @padding || theme_or_inherited.padding; end
    # Spacing in effect.
    def gap : Float32; @spacing || theme_or_inherited.spacing; end

    # Children that are controls.
    def control_children : Array(Control)
      @children.compact_map { |c| c.as?(Control) }.select(&.visible?)
    end

    # Positions the children. Subclasses implement it.
    abstract def arrange : Nil
    # True when the container positions its children. When false, children use their own anchors.
    def manages_children? : Bool; true; end

    # Arranges the children.
    def layout : Nil
      apply_anchor
      arrange
    end
  end

  # A background box for grouping controls. Children keep their own positions and anchors,
  # so a panel works as a frame for any layout.
  class Panel < Container
    # Background color. `nil` uses the theme.
    property color : Color? = nil
    # Border color. `nil` uses the theme.
    property border : Color? = nil
    # Whether to draw the border.
    property? show_border = true
    # Grow to enclose the children plus padding.
    property? fit_content = false

    # Resizes to fit the children when `fit_content` is set.
    def arrange : Nil
      return unless @fit_content
      kids = control_children
      return if kids.empty?
      w = 0_f32; h = 0_f32
      kids.each do |c|
        w = Math.max(w, c.position.x + c.size.x)
        h = Math.max(h, c.position.y + c.size.y)
      end
      self.size = Vec2.new(Math.max(@size.x, w + pad), h + pad).max(effective_min_size)
    end

    # Panels don't position their children.
    def manages_children? : Bool; false; end

    # Draws the background and border.
    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      draw_panel(g, rect, @color || t.panel, @show_border ? (@border || t.panel_border) : nil)
    end
  end

  # Lays children out in a column or a row. Use `VBox` or `HBox`.
  class BoxContainer < Container
    # True for a column, false for a row.
    property? vertical : Bool
    # Cross-axis alignment: `:start`, `:center`, `:end`, or `:stretch` to fill the width of a column
    # or the height of a row.
    property align : Symbol = :stretch
    # Shrink the box to its content along the main axis.
    property? fit_content = false

    # Creates a box.
    def initialize(vertical : Bool, name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(name, position, size)
      @vertical = vertical
    end

    # Size needed for all children plus spacing.
    def content_min_size : Vec2
      kids = control_children
      return Vec2.new(pad * 2, pad * 2) if kids.empty?
      main = 0_f32; cross = 0_f32
      kids.each do |c|
        m = c.effective_min_size
        if @vertical
          main += m.y; cross = Math.max(cross, m.x)
        else
          main += m.x; cross = Math.max(cross, m.y)
        end
      end
      main += gap * (kids.size - 1) + pad * 2
      cross += pad * 2
      @vertical ? Vec2.new(cross, main) : Vec2.new(main, cross)
    end

    # Places the children.
    def arrange : Nil
      kids = control_children
      cm = content_min_size
      if @fit_content
        self.size = @vertical ? Vec2.new(Math.max(@size.x, cm.x), cm.y) : Vec2.new(cm.x, Math.max(@size.y, cm.y))
      else
        self.size = @size.max(cm)
      end
      return if kids.empty?
      main_total = (@vertical ? @size.y : @size.x) - pad * 2 - gap * (kids.size - 1)
      cross_total = (@vertical ? @size.x : @size.y) - pad * 2
      mins = kids.map { |c| m = c.effective_min_size; @vertical ? m.y : m.x }
      expand = kids.map { |c| @vertical ? c.size_flags.expand_y? : c.size_flags.expand_x? }
      fixed = mins.sum
      extra = Math.max(0_f32, main_total - fixed)
      n_expand = expand.count(true)
      pos = pad
      kids.each_with_index do |c, i|
        m = c.effective_min_size
        main = mins[i] + (expand[i] && n_expand > 0 ? extra / n_expand : 0_f32)
        cross_min = @vertical ? m.x : m.y
        cross = case @align
                when :stretch then Math.max(cross_total, cross_min)
                else Math.max(cross_min, @vertical ? c.size.x : c.size.y)
                end
        cross = Math.min(cross, cross_total) if @align == :stretch
        cross_off = case @align
                    when :center then (cross_total - cross) / 2
                    when :end then cross_total - cross
                    else 0_f32
                    end
        if @vertical
          c.position = Vec2.new(pad + cross_off, pos)
          c.size = Vec2.new(cross, main)
        else
          c.position = Vec2.new(pos, pad + cross_off)
          c.size = Vec2.new(main, cross)
        end
        pos += main + gap
      end
    end
  end

  # Stacks children top to bottom. Children with `SizeFlags::ExpandY` share the spare height.
  class VBox < BoxContainer
    # Creates a column.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(true, name, position, size)
    end
  end

  # Places children left to right. Children with `SizeFlags::ExpandX` share the spare width.
  class HBox < BoxContainer
    # Creates a row.
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(false, name, position, size)
    end
  end

  # Arranges children in a grid with a fixed number of columns, for inventories and settings forms.
  #
  # ```
  # inventory = GridContainer.new(4)
  # 16.times { |i| inventory.add(Button.new("#{i}")) }
  # ```
  class GridContainer < Container
    # Number of columns. Rows are added as needed.
    property columns : Int32

    # Creates a grid.
    def initialize(@columns : Int32 = 2, name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(name, position, size)
    end

    private def cell_sizes : {Array(Float32), Array(Float32)}
      kids = control_children
      cols = Array(Float32).new(@columns, 0_f32)
      rows = Array(Float32).new((kids.size + @columns - 1) // Math.max(@columns, 1), 0_f32)
      kids.each_with_index do |c, i|
        m = c.effective_min_size
        col = i % @columns; row = i // @columns
        cols[col] = Math.max(cols[col], m.x)
        rows[row] = Math.max(rows[row], m.y)
      end
      {cols, rows}
    end

    # Size needed for all cells.
    def content_min_size : Vec2
      cols, rows = cell_sizes
      Vec2.new(cols.sum + gap * Math.max(cols.size - 1, 0) + pad * 2, rows.sum + gap * Math.max(rows.size - 1, 0) + pad * 2)
    end

    # Places the children in cells.
    def arrange : Nil
      cols, rows = cell_sizes
      self.size = @size.max(content_min_size)
      # distribute extra width across columns evenly
      extra_w = Math.max(0_f32, @size.x - pad * 2 - gap * Math.max(cols.size - 1, 0) - cols.sum)
      cols = cols.map { |w| w + extra_w / Math.max(cols.size, 1) }
      y = pad
      control_children.each_with_index do |c, i|
        col = i % @columns; row = i // @columns
        x = pad + cols[0, col].sum + gap * col
        y = pad + rows[0, row].sum + gap * row
        c.position = Vec2.new(x, y)
        c.size = Vec2.new(cols[col], rows[row])
      end
    end
  end

  # Empty space inside a box. With an expand flag, it pushes the following children to the far end.
  class Spacer < Control
    # Creates a spacer of at least *size* points.
    def initialize(size : Number = 0)
      super("Spacer")
      @size = Vec2.new(size, size)
      @size_flags = SizeFlags::Expand
      @mouse_enabled = false
    end
  end
end
