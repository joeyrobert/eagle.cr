module Eagle
  # Turns raw fingers into taps, double taps, long presses, swipes, pinches and two-finger
  # rotations. It is opt-in: add one to the scene and connect the signals you care about.
  #
  # It only listens; it does not claim touches, so drag handling and UI keep working. A
  # single finger produces at most one of tap, double tap, long press or swipe, and a second
  # finger cancels those in favor of pinch and rotate. Pinch and rotate report the total change
  # since the two fingers landed plus the change since the last report.
  #
  # ```
  # camera = Camera2D.new
  # ship = Node2D.new
  # gestures = GestureRecognizer.new
  # gestures.on_tapped { |pos| puts "tap at #{pos}" }
  # gestures.on_double_tapped { |pos| camera.zoom = 1_f32 }
  # gestures.on_long_pressed { |pos| puts "menu at #{pos}" }
  # gestures.on_swiped { |dir, from, to| puts "swipe #{dir}" }
  # gestures.on_pinched { |scale, delta, center| camera.zoom *= delta }
  # gestures.on_rotated { |angle, delta, center| ship.rotation += delta }
  # SceneTree.root.add(gestures)
  # ```
  class GestureRecognizer < Node
    # A finger lifted quickly without moving. Gives the position.
    signal tapped(position : Vec2)
    # Two taps in quick succession close together. Gives the second tap's position.
    signal double_tapped(position : Vec2)
    # A finger stayed down without moving for `long_press_time`. Fires while still held.
    signal long_pressed(position : Vec2)
    # A fast flick. Gives the direction as a unit vector plus where it started and ended.
    signal swiped(direction : Vec2, from : Vec2, to : Vec2)
    # Two fingers moved together or apart. *scale* is the total since they landed (1 is unchanged), *delta* the factor since the last report.
    signal pinched(scale : Float32, delta : Float32, center : Vec2)
    # Two fingers turned. *angle* is the total in radians since they landed, *delta* the change since the last report.
    signal rotated(angle : Float32, delta : Float32, center : Vec2)

    # Longest a finger may stay down and still count as a tap, in seconds.
    property tap_time : Float64 = 0.3
    # Longest gap between two taps of a double tap, in seconds.
    property double_tap_time : Float64 = 0.3
    # How far apart two taps of a double tap may land, in pixels.
    property double_tap_distance : Float32 = 40_f32
    # How long a finger must stay put to count as a long press, in seconds.
    property long_press_time : Float64 = 0.5
    # Shortest travel for a swipe, in pixels.
    property swipe_distance : Float32 = 60_f32
    # Longest a swipe may take, in seconds.
    property swipe_time : Float64 = 0.5

    @single : Int32? = nil
    @multi = false
    @long_fired = false
    @two = false
    @start_dist = 1_f32
    @prev_dist = 1_f32
    @last_angle = 0_f32
    @total_angle = 0_f32
    @last_tap_time : Float64? = nil
    @last_tap_pos = Vec2::ZERO

    # Feeds touch events into the recognizer.
    def input(event : Event) : Nil
      return unless event.is_a?(TouchEvent)
      case event.phase
      in .began?
        if Touch.count == 1
          @single = event.id
          @multi = false
          @long_fired = false
        else
          @single = nil
          @multi = true
          begin_two
        end
      in .moved?
        update_two if @two
      in .ended?
        if (id = @single) && id == event.id && !@multi && !@long_fired
          Touch.released.reverse.find { |f| f.id == id }.try { |f| finish_single(f) }
        end
        finger_lifted
      in .cancelled?
        finger_lifted
      end
    end

    # Watches for long presses.
    def process(dt : Float32) : Nil
      return if @multi || @long_fired
      id = @single || return
      f = Touch.finger(id) || return
      return if f.dragging? || f.duration < @long_press_time
      @long_fired = true
      emit_long_pressed(f.position)
    end

    private def finger_lifted
      @two = false
      @single = nil
      if Touch.count == 0
        @multi = false
      elsif Touch.count >= 2
        begin_two
      end
    end

    private def two : {Finger, Finger}?
      f = Touch.fingers
      f.size >= 2 ? {f[0], f[1]} : nil
    end

    private def begin_two
      a, b = two || return
      @two = true
      @start_dist = @prev_dist = Math.max(a.position.distance(b.position), 1_f32)
      @last_angle = (b.position - a.position).angle
      @total_angle = 0_f32
    end

    private def update_two
      a, b = two || return
      center = (a.position + b.position) / 2
      dist = Math.max(a.position.distance(b.position), 1_f32)
      if dist != @prev_dist
        delta = dist / @prev_dist
        @prev_dist = dist
        emit_pinched(dist / @start_dist, delta, center)
      end
      ang = (b.position - a.position).angle
      d = ang - @last_angle
      d -= Mathf::TAU if d > Mathf::PI
      d += Mathf::TAU if d < -Mathf::PI
      @last_angle = ang
      if d != 0
        @total_angle += d
        emit_rotated(@total_angle, d, center)
      end
    end

    private def finish_single(f : Finger)
      if f.dragging?
        if f.duration <= @swipe_time && f.distance >= @swipe_distance
          emit_swiped(f.total.normalized, f.start_position, f.position)
        end
        return
      end
      return if f.duration > @tap_time
      now = Clock.elapsed
      if (t = @last_tap_time) && now - t <= @double_tap_time && f.position.distance(@last_tap_pos) <= @double_tap_distance
        @last_tap_time = nil
        emit_double_tapped(f.position)
      else
        @last_tap_time = now
        @last_tap_pos = f.position
        emit_tapped(f.position)
      end
    end
  end
end
