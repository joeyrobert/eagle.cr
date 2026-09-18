module Eagle
  # Easing curves: functions that reshape progress from 0..1 so motion speeds up, slows
  # down, overshoots or bounces instead of moving at a constant rate.
  #
  # You usually pass an easing to a tween by name, as in `ease: :quad_out`. Call the
  # functions directly when you animate something by hand.
  #
  # Which one to pick:
  #
  # * `_out` curves start fast and settle, which suits things arriving: UI sliding in, a camera stopping.
  # * `_in` curves start slow and accelerate, which suits things leaving.
  # * `_in_out` curves are slow at both ends, which suits back-and-forth motion.
  # * `back_out` overshoots a little and comes back. It makes buttons and popups feel springy.
  # * `bounce_out` and `elastic_out` are playful, for landing items and wobbling icons.
  #
  # ```
  # t = 0.5_f32
  # Ease.quad_out(t)   # => 0.75, already three quarters of the way there
  # Ease.by_name(:bounce_out).call(t)
  # ```
  module Ease
    extend self

    # Constant speed.
    def linear(t : Float32) : Float32; t; end
    # Starts slow and speeds up (t²).
    def quad_in(t : Float32) : Float32; t * t; end
    # Starts fast and slows to a stop. A good default for most UI motion.
    def quad_out(t : Float32) : Float32; 1 - (1 - t) * (1 - t); end
    # Slow at both ends.
    def quad_in_out(t : Float32) : Float32; t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) ** 2) / 2; end
    # Like `quad_in`, but stronger.
    def cubic_in(t : Float32) : Float32; t * t * t; end
    # Like `quad_out`, but stronger.
    def cubic_out(t : Float32) : Float32; 1 - ((1 - t) ** 3); end
    # Like `quad_in_out`, but stronger.
    def cubic_in_out(t : Float32) : Float32; t < 0.5 ? 4 * t * t * t : 1 - ((-2 * t + 2) ** 3) / 2; end
    # Gentle acceleration following a quarter sine wave.
    def sine_in(t : Float32) : Float32; (1 - Math.cos(t * Math::PI / 2)).to_f32; end
    # Gentle deceleration.
    def sine_out(t : Float32) : Float32; Math.sin(t * Math::PI / 2).to_f32; end
    # Gentle at both ends, good for breathing and hovering motion.
    def sine_in_out(t : Float32) : Float32; (-(Math.cos(Math::PI * t) - 1) / 2).to_f32; end
    # Very fast start with a long, soft landing.
    def expo_out(t : Float32) : Float32; t >= 1 ? 1_f32 : (1 - 2 ** (-10 * t)).to_f32; end
    # Almost still, then a sudden rush at the end.
    def expo_in(t : Float32) : Float32; t <= 0 ? 0_f32 : (2 ** (10 * t - 10)).to_f32; end
    # Overshoots the target slightly, then settles back. Great for popups.
    def back_out(t : Float32) : Float32
      c1 = 1.70158_f32; c3 = c1 + 1
      (1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)).to_f32
    end
    # Pulls back slightly before moving forward, like winding up.
    def back_in(t : Float32) : Float32
      c1 = 1.70158_f32; c3 = c1 + 1
      (c3 * t * t * t - c1 * t * t).to_f32
    end
    # Overshoots and wobbles like a spring before settling.
    def elastic_out(t : Float32) : Float32
      return t if t <= 0 || t >= 1
      c4 = (2 * Math::PI) / 3
      ((2 ** (-10 * t)) * Math.sin((t * 10 - 0.75) * c4) + 1).to_f32
    end
    # Bounces against the target like a dropped ball.
    def bounce_out(t : Float32) : Float32
      n1 = 7.5625_f32; d1 = 2.75_f32
      if t < 1 / d1
        n1 * t * t
      elsif t < 2 / d1
        t -= 1.5_f32 / d1
        n1 * t * t + 0.75_f32
      elsif t < 2.5 / d1
        t -= 2.25_f32 / d1
        n1 * t * t + 0.9375_f32
      else
        t -= 2.625_f32 / d1
        n1 * t * t + 0.984375_f32
      end
    end
    # Bounces at the start instead of the end.
    def bounce_in(t : Float32) : Float32; 1 - bounce_out(1 - t); end

    # Looks up an easing by symbol, such as `:quad_out`. Raises `ArgumentError` for unknown names.
    def by_name(name : Symbol) : Proc(Float32, Float32)
      case name
      when :linear then ->linear(Float32)
      when :quad_in then ->quad_in(Float32)
      when :quad_out then ->quad_out(Float32)
      when :quad_in_out then ->quad_in_out(Float32)
      when :cubic_in then ->cubic_in(Float32)
      when :cubic_out then ->cubic_out(Float32)
      when :cubic_in_out then ->cubic_in_out(Float32)
      when :sine_in then ->sine_in(Float32)
      when :sine_out then ->sine_out(Float32)
      when :sine_in_out then ->sine_in_out(Float32)
      when :expo_in then ->expo_in(Float32)
      when :expo_out then ->expo_out(Float32)
      when :back_in then ->back_in(Float32)
      when :back_out then ->back_out(Float32)
      when :elastic_out then ->elastic_out(Float32)
      when :bounce_in then ->bounce_in(Float32)
      when :bounce_out then ->bounce_out(Float32)
      else raise ArgumentError.new("Unknown easing #{name}")
      end
    end
  end

  # Animates a value over time, so you don't have to track timers yourself.
  #
  # A tween calls your block every frame with progress eased from 0 to 1, or with an
  # interpolated value, until its duration is up. The engine updates tweens automatically,
  # and they follow `Clock.scale`.
  #
  # ```
  # class Popup < Node2D
  #   def ready : Nil
  #     self.scale = 0.0
  #     # Grow in with a springy overshoot.
  #     Tween.value(0, 1, 0.4, ease: :back_out) { |s| self.scale = s }
  #
  #     # Fade out after 2 seconds, then remove.
  #     Tween.value(Color::WHITE, Color::TRANSPARENT, 0.5, delay: 2) { |c| self.modulate = c }
  #       .on_complete { queue_free }
  #   end
  # end
  #
  # # Run steps one after another.
  # Tween.sequence do |s|
  #   s.wait(1)
  #   s.to(0.5, ease: :quad_out) { |t| puts "sliding #{t}" }
  #   s.call { puts "done" }
  # end
  #
  # Tween.after(3) { puts "three seconds later" }
  # ```
  #
  # Keep the returned `Tween` if you need to `stop` it early, or set `loop` or `ping_pong`
  # for animations that repeat.
  class Tween
    @@active = [] of Tween

    # Length of the tween in seconds, not counting `delay`.
    getter duration : Float32
    # Seconds played so far.
    getter elapsed = 0_f32
    # True once the tween has reached the end and called its completion blocks.
    getter? finished = false
    # Freezes the tween in place while true.
    property? paused = false
    # Restarts from the beginning when it finishes, forever.
    property? loop = false
    # With `loop`, plays forward then backward alternately.
    property? ping_pong = false
    # Seconds to wait before starting.
    property delay : Float32
    @ease : Proc(Float32, Float32)
    @on_update : Proc(Float32, Nil)?
    @on_complete = [] of ->

    # Creates a tween without starting it. Call `start` when ready, or use `Tween.to`,
    # which creates and starts in one step.
    def initialize(duration : Number, ease : Symbol | Proc(Float32, Float32) = :linear, delay : Number = 0, &block : Float32 ->)
      @duration = duration.to_f32
      @delay = delay.to_f32
      @ease = ease.is_a?(Symbol) ? Ease.by_name(ease) : ease
      @on_update = block
    end

    # Starts a tween whose block receives eased progress from 0 to 1. Use it to drive any
    # property you like.
    #
    # ```
    # start, target = v2(0, 0), v2(300, 200)
    # node = Node2D.new
    # Tween.to(1.5, ease: :sine_in_out) { |t| node.position = start.lerp(target, t) }
    # ```
    def self.to(duration : Number, ease : Symbol | Proc(Float32, Float32) = :linear, delay : Number = 0, &block : Float32 ->) : Tween
      new(duration, ease, delay, &block).start
    end

    # Tweens a number from *from* to *to* and passes each value to the block.
    def self.value(from : Number, to : Number, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Float32 ->) : Tween
      a = from.to_f32; b = to.to_f32
      to(duration, ease, delay) { |t| block.call(a + (b - a) * t) }
    end

    # Tweens a `Vec2`, for moving things between two points.
    def self.value(from : Vec2, to : Vec2, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Vec2 ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    # Tweens a `Vec3`.
    def self.value(from : Vec3, to : Vec3, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Vec3 ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    # Tweens a `Color`, for fades and flashes.
    def self.value(from : Color, to : Color, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Color ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    # Calls the block once after *seconds*. A timer without a node.
    def self.after(seconds : Number, &block : ->) : Tween
      t = new(0, :linear, seconds) { }
      t.on_complete(&block)
      t.start
    end

    # Builds a chain of steps with the yielded `Sequence` and starts it.
    def self.sequence(&) : Sequence
      s = Sequence.new
      yield s
      s.start
      s
    end

    # Starts or resumes updating this tween. Returns self.
    def start : self
      if @duration <= 0 && @delay <= 0
        # Zero-length tweens complete synchronously (used for sequence callbacks).
        @on_update.try(&.call(@ease.call(1_f32)))
        @finished = true
        @on_complete.each(&.call)
        return self
      end
      @@active << self unless @@active.includes?(self)
      self
    end

    # Removes the tween from the update list. Its completion blocks won't run.
    def stop : Nil
      @@active.delete(self)
    end

    # Adds a block to run when the tween finishes. Returns self so calls can be chained.
    def on_complete(&block : ->) : self
      @on_complete << block
      self
    end

    # Linear progress from 0 to 1, before easing.
    def progress : Float32
      @duration <= 0 ? 1_f32 : (@elapsed / @duration).clamp(0_f32, 1_f32)
    end

    # :nodoc:
    def update(dt : Float32) : Nil
      return if @paused || @finished
      if @delay > 0
        @delay -= dt
        return if @delay > 0
        dt = -@delay
        @delay = 0_f32
      end
      @elapsed += dt
      if @elapsed >= @duration
        if @loop
          @elapsed -= @duration if @duration > 0
          @elapsed = 0_f32 if @duration <= 0
          @on_update.try(&.call(@ease.call(progress)))
          return
        end
        @elapsed = @duration
        @on_update.try(&.call(@ease.call(1_f32)))
        @finished = true
        @@active.delete(self)
        @on_complete.each(&.call)
      else
        t = progress
        t = Mathf.ping_pong(t * 2, 1) if @ping_pong
        @on_update.try(&.call(@ease.call(t)))
      end
    end

    # :nodoc:
    def self.update_all(dt : Float32) : Nil
      @@active.dup.each(&.update(dt))
    end

    # Number of tweens currently running.
    def self.active_count : Int32; @@active.size; end
    # Stops every running tween, for example when changing scenes.
    def self.clear : Nil; @@active.clear; end

    # Steps that run one after another: tweens, waits and callbacks. Build one with `Tween.sequence`.
    class Sequence
      @steps = [] of Tween
      @index = 0
      @started = false
      # True once every step has run.
      getter? finished = false
      @on_complete = [] of ->

      # Adds a tween step whose block receives eased progress.
      def to(duration : Number, ease : Symbol = :linear, &block : Float32 ->) : self
        @steps << Tween.new(duration, ease, &block)
        self
      end

      # Adds a pause.
      def wait(seconds : Number) : self
        @steps << Tween.new(seconds) { }
        self
      end

      # Adds a step that runs the block and moves on right away.
      def call(&block : ->) : self
        t = Tween.new(0) { }
        t.on_complete(&block)
        @steps << t
        self
      end

      # Adds a block to run after the last step.
      def on_complete(&block : ->) : self
        @on_complete << block
        self
      end

      # Starts the sequence. `Tween.sequence` does this for you.
      def start : self
        return self if @started
        @started = true
        run_next
        self
      end

      private def run_next
        if @index >= @steps.size
          @finished = true
          @on_complete.each(&.call)
          return
        end
        t = @steps[@index]
        @index += 1
        t.on_complete { run_next }
        t.start
      end
    end
  end
end
