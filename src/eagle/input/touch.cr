module Eagle
  # One finger on the screen. Get them from `Touch.fingers` or `Touch.finger`.
  #
  # A finger keeps the same `id` from touching down until it lifts, so you can follow it
  # across frames even while other fingers come and go.
  #
  # ```
  # Touch.fingers.each do |f|
  #   puts "finger #{f.id} at #{f.position}, moved #{f.distance.round} px" if f.dragging?
  # end
  # ```
  class Finger
    # Stable id, from 0.
    getter id : Int32
    # Current position in window coordinates.
    getter position : Vec2
    # Where the finger first touched down.
    getter start_position : Vec2
    # How far the finger moved this frame.
    getter delta : Vec2 = Vec2::ZERO
    # Pressure from 0 to 1, or 1 on devices without pressure.
    getter pressure : Float32
    # True once the finger has moved past `Touch.drag_threshold`.
    getter? dragging = false
    # True on the frame the finger touched down.
    getter? began = true
    # True on the frame the finger lifted or was cancelled.
    getter? ended = false
    # True when the system cancelled the touch.
    getter? cancelled = false
    @start_time : Float64
    @end_time : Float64 = 0.0

    # :nodoc:
    def initialize(@id, @position, @pressure)
      @start_position = @position
      @start_time = Clock.elapsed
    end

    # Straight-line distance from where the finger landed.
    def distance : Float32; (@position - @start_position).length; end
    # Movement since the finger landed.
    def total : Vec2; @position - @start_position; end
    # Seconds since the finger landed, or how long it stayed down once it has lifted.
    def duration : Float64; (@ended ? @end_time : Clock.elapsed) - @start_time; end

    # :nodoc:
    def move(to : Vec2, pressure : Float32) : Vec2
      d = to - @position
      @position = to
      @pressure = pressure
      @delta += d
      d
    end

    # :nodoc:
    def start_drag; @dragging = true; end
    # :nodoc:
    def finish(cancelled : Bool); @ended = true; @cancelled = cancelled; @end_time = Clock.elapsed; end
    # :nodoc:
    def end_frame; @began = false; @delta = Vec2::ZERO; end
  end

  # Touch screen state you can poll from anywhere, next to `Input` for keys and the mouse.
  #
  # `fingers` lists every finger currently down, so multi-touch is a loop. Each finger has a
  # stable id and knows whether it has dragged past `drag_threshold`, which is how you tell a tap
  # from a drag. For events instead of polling, handle `TouchEvent` and `TouchDragEvent` in
  # `Node#input`; for tap, pinch and rotate, add a `GestureRecognizer`.
  #
  # By default an unhandled touch also acts as the left mouse button (`emulate_mouse=`), so
  # games and UI written for the mouse keep working on phones. Those mouse events carry
  # `from_touch?`. Turn emulation off for a game that reads touches itself.
  #
  # ```
  # class Game < App
  #   def update(dt : Float32) : Nil
  #     if Touch.count == 2
  #       a, b = Touch.fingers
  #       puts "fingers #{a.position.distance(b.position).round} px apart"
  #     end
  #     Touch.released.each { |f| puts "tap!" if !f.dragging? && f.duration < 0.3 }
  #   end
  # end
  # ```
  module Touch
    @@fingers = [] of Finger
    @@released = [] of Finger
    @@derived = [] of Event
    @@emulate_mouse = true
    @@drag_threshold = 10_f32
    @@primary : Int32? = nil

    # Fingers currently on the screen, in the order they touched down.
    def self.fingers : Array(Finger); @@fingers; end
    # Fingers that lifted or were cancelled this frame.
    def self.released : Array(Finger); @@released; end
    # How many fingers are down.
    def self.count : Int32; @@fingers.size; end
    # True while at least one finger is down.
    def self.any? : Bool; !@@fingers.empty?; end
    # The finger with this id, or `nil` if it is not down.
    def self.finger(id : Int32) : Finger?; @@fingers.find { |f| f.id == id }; end

    # Whether unhandled touches also produce left-mouse events. On by default.
    def self.emulate_mouse? : Bool; @@emulate_mouse; end
    # Turns mouse emulation on or off.
    def self.emulate_mouse=(v : Bool); @@emulate_mouse = v; end
    # Pixels a finger must travel from where it landed before it counts as a drag.
    def self.drag_threshold : Float32; @@drag_threshold; end
    # Sets the drag threshold.
    def self.drag_threshold=(v : Number); @@drag_threshold = v.to_f32; end

    # :nodoc:
    def self.handle(e : TouchEvent) : Nil
      case e.phase
      in .began?
        @@fingers.reject! { |f| f.id == e.id }
        @@fingers << Finger.new(e.id, e.position, e.pressure)
        e.delta = Vec2::ZERO
      in .moved?
        f = finger(e.id) || return
        e.delta = f.move(e.position, e.pressure)
        if !f.dragging?
          if f.distance >= @@drag_threshold
            f.start_drag
            @@derived << TouchDragEvent.new(f.id, TouchDragKind::Started, f.position, f.start_position, f.total)
          end
        elsif e.delta != Vec2::ZERO
          @@derived << TouchDragEvent.new(f.id, TouchDragKind::Moved, f.position, f.start_position, e.delta)
        end
      in .ended?, .cancelled?
        f = finger(e.id) || return
        e.delta = f.move(e.position, e.pressure)
        cancelled = e.cancelled?
        f.finish(cancelled)
        @@fingers.delete(f)
        @@released << f
        @@derived << TouchDragEvent.new(f.id, TouchDragKind::Ended, f.position, f.start_position, e.delta, cancelled) if f.dragging?
      end
    end

    # :nodoc: Drag events produced by the last touch event; the engine delivers them.
    def self.take_derived : Array(Event)
      return @@derived if @@derived.empty?
      list = @@derived
      @@derived = [] of Event
      list
    end

    # :nodoc: Mouse events standing in for an unhandled touch. Only one finger drives the mouse at a time.
    def self.mouse_events(e : TouchEvent) : Array(Event)
      list = [] of Event
      case e.phase
      in .began?
        return list if @@primary
        @@primary = e.id
        list << mouse_motion(e.position, Vec2::ZERO)
        list << mouse_button(true, e.position)
      in .moved?
        list << mouse_motion(e.position, e.delta) if @@primary == e.id
      in .ended?
        if @@primary == e.id
          @@primary = nil
          list << mouse_motion(e.position, e.delta) if e.delta != Vec2::ZERO
          list << mouse_button(false, e.position)
        end
      in .cancelled?
        if @@primary == e.id
          @@primary = nil
          list << mouse_button(false, Vec2.new(-100000, -100000))
        end
      end
      list
    end

    private def self.mouse_motion(p : Vec2, d : Vec2) : MouseMotionEvent
      m = MouseMotionEvent.new(p, d)
      m.from_touch = true
      m
    end

    private def self.mouse_button(pressed : Bool, p : Vec2) : MouseButtonEvent
      m = MouseButtonEvent.new(MouseButton::Left, pressed, p)
      m.from_touch = true
      m
    end

    # :nodoc:
    def self.begin_frame : Nil
      @@released.clear
      @@fingers.each(&.end_frame)
    end

    # :nodoc:
    def self.reset : Nil
      @@fingers.clear; @@released.clear; @@derived.clear
      @@primary = nil
      @@emulate_mouse = true
      @@drag_threshold = 10_f32
    end
  end
end
