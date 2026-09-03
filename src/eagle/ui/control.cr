module Eagle
  # Where a control sits inside its parent when not managed by a container.
  enum Anchor
    TopLeft; Top; TopRight
    Left; Center; Right
    BottomLeft; Bottom; BottomRight
    # Stretch to fill the parent (minus margins).
    Fill

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
  enum SizeFlags
    ExpandX
    ExpandY
    Expand = ExpandX | ExpandY
  end

  # Global keyboard focus (module so subclasses share one slot).
  module Focus
    @@current : Control? = nil
    def self.current : Control?; @@current; end
    def self.current=(c : Control?); @@current = c; end
  end

  # Base class for UI widgets. A Control has a rect (position + size) in its
  # parent's space, receives mouse/keyboard events, and can be focused.
  # Containers (VBox/HBox/Grid) lay out their Control children automatically.
  class Control < Node2D
    property size : Vec2 = Vec2.new(100, 32)
    # Explicit minimum size; combined with the computed content size.
    property min_size : Vec2 = Vec2::ZERO
    property anchor : Anchor = Anchor::TopLeft
    # Offset from the anchor point (or margins for Anchor::Fill: left/top = x/y, right/bottom = z/w).
    property margin : Vec4 = Vec4.new(0, 0, 0, 0)
    property size_flags : SizeFlags = SizeFlags::None
    property? disabled = false
    property? focusable = false
    # When false, mouse events pass through this control.
    property? mouse_enabled = true
    property theme : Theme? = nil
    property tooltip : String = ""
    getter? hovered = false
    getter? pressed = false

    signal mouse_entered
    signal mouse_exited
    signal focus_entered
    signal focus_exited
    signal resized(size : Vec2)

    def self.focused : Control?; Focus.current; end
    # :nodoc:
    def self.reset_focus; Focus.current = nil; end

    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(name, position)
      @size = size if size
    end

    def width : Float32; @size.x; end
    def height : Float32; @size.y; end
    def width=(v : Number); @size = Vec2.new(v, @size.y); end
    def height=(v : Number); @size = Vec2.new(@size.x, v); end
    def size=(v : Vec2)
      changed = v != @size
      @size = v
      emit_resized(v) if changed
    end
    def set_size(w : Number, h : Number) : self; self.size = Vec2.new(w, h); self; end

    # Local rect (origin at position).
    def rect : Rect; Rect.new(0, 0, @size.x, @size.y); end
    # Rect in parent space.
    def parent_rect : Rect; Rect.new(@position, @size); end
    # Axis-aligned rect in global (screen) space.
    def global_rect : Rect
      t = global_transform
      pts = [t * Vec2::ZERO, t * Vec2.new(@size.x, 0), t * @size, t * Vec2.new(0, @size.y)]
      mn = pts.reduce { |a, b| a.min(b) }; mx = pts.reduce { |a, b| a.max(b) }
      Rect.from_bounds(mn, mx)
    end

    def focused? : Bool; Focus.current == self; end

    def grab_focus : Nil
      return if focused? || !@focusable || @disabled
      prev = Focus.current
      Focus.current = self
      prev.try(&.emit_focus_exited)
      emit_focus_entered
    end

    def release_focus : Nil
      return unless focused?
      Focus.current = nil
      emit_focus_exited
    end

    # Effective theme: own, nearest ancestor's, or the default.
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

    def font : Font
      theme_or_inherited.font_or_default
    end

    # Minimum size required by the content (override in widgets).
    def content_min_size : Vec2; Vec2::ZERO; end

    def effective_min_size : Vec2; @min_size.max(content_min_size); end

    # Rect of the parent to lay out against (parent control or the window).
    def parent_bounds : Rect
      p = parent_control
      p ? p.rect : Window.rect
    end

    def parent_control : Control?
      p = @parent
      while p
        return p if p.is_a?(Control)
        return nil if p.is_a?(CanvasLayer)
        p = p.parent
      end
      nil
    end

    # Apply anchor + margin against the parent bounds (skipped inside layout containers).
    def apply_anchor : Nil
      if (pc = parent_control).is_a?(Container)
        return if pc.manages_children?
      end
      b = parent_bounds
      if @anchor.fill?
        @position = Vec2.new(b.x + @margin.x, b.y + @margin.y)
        self.size = Vec2.new(b.w - @margin.x - @margin.z, b.h - @margin.y - @margin.w).max(effective_min_size)
      else
        f = @anchor.factors
        self.size = @size.max(effective_min_size)
        @position = Vec2.new(b.x + b.w * f.x - @size.x * f.x + @margin.x, b.y + b.h * f.y - @size.y * f.y + @margin.y)
      end
    end

    # Called every frame before drawing; containers override to place children.
    def layout : Nil
      apply_anchor
    end

    def process(dt : Float32) : Nil
      layout
    end

    # Convert a global point to this control's local space.
    def to_local_point(p : Vec2) : Vec2; to_local(p); end

    def contains_global?(p : Vec2) : Bool
      rect.contains?(to_local(p))
    end

    # Override for widget-specific input; return true if consumed.
    def gui_input(event : Event) : Bool; false; end

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
      when KeyEvent, TextEvent
        event.handled = true if focused? && gui_input(event)
      end
    end

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

  # Base for controls that arrange their children.
  abstract class Container < Control
    property padding : Float32? = nil
    property spacing : Float32? = nil

    def pad : Float32; @padding || theme_or_inherited.padding; end
    def gap : Float32; @spacing || theme_or_inherited.spacing; end

    def control_children : Array(Control)
      @children.compact_map { |c| c.as?(Control) }.select(&.visible?)
    end

    abstract def arrange : Nil
    # Whether this container positions its children (false = children anchor freely).
    def manages_children? : Bool; true; end

    def layout : Nil
      apply_anchor
      arrange
    end
  end

  # Draws a themed background; a plain grouping container.
  class Panel < Container
    property color : Color? = nil
    property border : Color? = nil
    property? show_border = true
    # Grow to enclose the children (plus padding).
    property? fit_content = false

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

    def manages_children? : Bool; false; end

    def draw(g : Graphics) : Nil
      t = theme_or_inherited
      draw_panel(g, rect, @color || t.panel, @show_border ? (@border || t.panel_border) : nil)
    end
  end

  # Lays children out in a column (VBox) or row (HBox).
  class BoxContainer < Container
    property? vertical : Bool
    # Cross-axis alignment: :start, :center, :end, :stretch
    property align : Symbol = :stretch
    # Shrink the box to its content on the main axis.
    property? fit_content = false

    def initialize(vertical : Bool, name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(name, position, size)
      @vertical = vertical
    end

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

  class VBox < BoxContainer
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(true, name, position, size)
    end
  end

  class HBox < BoxContainer
    def initialize(name : String = "", position : Vec2 = Vec2::ZERO, size : Vec2? = nil)
      super(false, name, position, size)
    end
  end

  # Fixed number of columns; rows grow as needed.
  class GridContainer < Container
    property columns : Int32

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

    def content_min_size : Vec2
      cols, rows = cell_sizes
      Vec2.new(cols.sum + gap * Math.max(cols.size - 1, 0) + pad * 2, rows.sum + gap * Math.max(rows.size - 1, 0) + pad * 2)
    end

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

  # Empty space that expands inside boxes.
  class Spacer < Control
    def initialize(size : Number = 0)
      super("Spacer")
      @size = Vec2.new(size, size)
      @size_flags = SizeFlags::Expand
      @mouse_enabled = false
    end
  end
end
