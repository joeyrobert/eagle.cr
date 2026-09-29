require "../../src/eagle/math/math"

module EagleRocketBall
  include Eagle

  enum ItemKind
    Button
    Choice
    Slider
    Header
  end

  # One row of a menu: a button, a choice that cycles through options, a slider or a non-selectable heading.
  class MenuItem
    getter label : String
    getter kind : ItemKind
    getter options : Array(String)
    property index : Int32 = 0
    property value : Float32 = 0_f32
    getter min : Float32 = 0_f32
    getter max : Float32 = 1_f32
    getter step : Float32 = 0.1_f32
    property? enabled = true
    property formatter : Proc(Float32, String)? = nil
    @on_activate : Proc(Nil)? = nil
    @on_index : Proc(Int32, Nil)? = nil
    @on_value : Proc(Float32, Nil)? = nil

    def initialize(@label : String, @kind : ItemKind = ItemKind::Button, @options : Array(String) = [] of String)
    end

    def self.button(label : String, &block : ->) : MenuItem
      item = MenuItem.new(label)
      item.on_activate(&block)
      item
    end

    def self.header(label : String) : MenuItem
      MenuItem.new(label, ItemKind::Header).tap { |i| i.enabled = false }
    end

    def self.choice(label : String, options : Array(String), index : Int32 = 0, &block : Int32 ->) : MenuItem
      item = MenuItem.new(label, ItemKind::Choice, options)
      item.index = index.clamp(0, options.size - 1)
      item.on_index(&block)
      item
    end

    def self.slider(label : String, min : Number, max : Number, value : Number, step : Number = 0.05, &block : Float32 ->) : MenuItem
      item = MenuItem.new(label, ItemKind::Slider)
      item.set_range(min.to_f32, max.to_f32, step.to_f32)
      item.value = value.to_f32.clamp(item.min, item.max)
      item.on_value(&block)
      item
    end

    protected def set_range(@min : Float32, @max : Float32, @step : Float32) : Nil; end

    def on_activate(&block : ->) : Nil
      @on_activate = block
    end

    def on_index(&block : Int32 ->) : Nil
      @on_index = block
    end

    def on_value(&block : Float32 ->) : Nil
      @on_value = block
    end

    # The text shown on the right of the row.
    def display : String
      case @kind
      in .choice?           then @options[@index]? || ""
      in .slider?           then @formatter.try(&.call(@value)) || "#{(fraction * 100).round.to_i}%"
      in .button?, .header? then ""
      end
    end

    def fraction : Float32
      @max > @min ? ((@value - @min) / (@max - @min)).clamp(0_f32, 1_f32) : 0_f32
    end

    def activate : Nil
      case @kind
      in .button?           then @on_activate.try(&.call)
      in .choice?           then adjust(1)
      in .slider?, .header? then nil
      end
    end

    # Moves a choice to its next or previous option, or a slider one step. Choices wrap around.
    def adjust(dir : Int32) : Nil
      case @kind
      in .choice?
        return if @options.empty?
        @index = (@index + dir) % @options.size
        @on_index.try(&.call(@index))
      in .slider?
        set_fraction(fraction + dir * @step / (@max - @min))
      in .button?, .header? then nil
      end
    end

    def set_fraction(f : Float32) : Nil
      v = @min + f.clamp(0_f32, 1_f32) * (@max - @min)
      v = (v / @step).round * @step if @step > 0
      v = v.clamp(@min, @max)
      return if v == @value
      @value = v
      @on_value.try(&.call(v))
    end
  end

  # A vertical list of items with a cursor, driven by keys, a gamepad or the mouse.
  class Menu
    getter title : String
    getter subtitle : String
    getter items : Array(MenuItem)
    getter cursor : Int32 = 0
    property back : Proc(Nil)? = nil

    def initialize(@title : String, @items : Array(MenuItem) = [] of MenuItem, @subtitle : String = "")
      @cursor = next_enabled(-1, 1) || 0
    end

    def <<(item : MenuItem) : self
      @items << item
      @cursor = next_enabled(-1, 1) || 0 unless @items[@cursor]?.try(&.enabled?)
      self
    end

    def selected : MenuItem?
      @items[@cursor]?
    end

    # Moves the cursor to the next selectable row, wrapping around.
    def move(dir : Int32) : Nil
      if i = next_enabled(@cursor, dir)
        @cursor = i
      end
    end

    def select(i : Int32) : Nil
      @cursor = i if @items[i]?.try(&.enabled?)
    end

    def activate : Nil
      selected.try(&.activate)
    end

    def adjust(dir : Int32) : Nil
      selected.try(&.adjust(dir))
    end

    def go_back : Bool
      if b = @back
        b.call
        true
      else
        false
      end
    end

    # Row rectangles for a column of *w* by *h* rows centered on *cx*, starting at *top*.
    def layout(cx : Number, top : Number, w : Number, h : Number, gap : Number) : Array(Rect)
      @items.map_with_index do |_, i|
        Rect.new(cx - w / 2, top + i * (h + gap), w, h)
      end
    end

    # The row under a screen point, if it can be selected.
    def item_at(p : Vec2, rects : Array(Rect)) : Int32?
      rects.each_with_index do |r, i|
        return i if @items[i].enabled? && p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h
      end
      nil
    end

    private def next_enabled(from : Int32, dir : Int32) : Int32?
      n = @items.size
      return nil if n == 0
      i = from
      n.times do
        i = (i + dir) % n
        return i if @items[i].enabled?
      end
      nil
    end
  end
end
