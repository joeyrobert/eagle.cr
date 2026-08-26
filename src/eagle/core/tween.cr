module Eagle
  # Easing functions (t in 0..1).
  module Ease
    extend self

    def linear(t : Float32) : Float32; t; end
    def quad_in(t : Float32) : Float32; t * t; end
    def quad_out(t : Float32) : Float32; 1 - (1 - t) * (1 - t); end
    def quad_in_out(t : Float32) : Float32; t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) ** 2) / 2; end
    def cubic_in(t : Float32) : Float32; t * t * t; end
    def cubic_out(t : Float32) : Float32; 1 - ((1 - t) ** 3); end
    def cubic_in_out(t : Float32) : Float32; t < 0.5 ? 4 * t * t * t : 1 - ((-2 * t + 2) ** 3) / 2; end
    def sine_in(t : Float32) : Float32; (1 - Math.cos(t * Math::PI / 2)).to_f32; end
    def sine_out(t : Float32) : Float32; Math.sin(t * Math::PI / 2).to_f32; end
    def sine_in_out(t : Float32) : Float32; (-(Math.cos(Math::PI * t) - 1) / 2).to_f32; end
    def expo_out(t : Float32) : Float32; t >= 1 ? 1_f32 : (1 - 2 ** (-10 * t)).to_f32; end
    def expo_in(t : Float32) : Float32; t <= 0 ? 0_f32 : (2 ** (10 * t - 10)).to_f32; end
    def back_out(t : Float32) : Float32
      c1 = 1.70158_f32; c3 = c1 + 1
      (1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)).to_f32
    end
    def back_in(t : Float32) : Float32
      c1 = 1.70158_f32; c3 = c1 + 1
      (c3 * t * t * t - c1 * t * t).to_f32
    end
    def elastic_out(t : Float32) : Float32
      return t if t <= 0 || t >= 1
      c4 = (2 * Math::PI) / 3
      ((2 ** (-10 * t)) * Math.sin((t * 10 - 0.75) * c4) + 1).to_f32
    end
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
    def bounce_in(t : Float32) : Float32; 1 - bounce_out(1 - t); end

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

  # Interpolates values over time. Tweens are driven by the engine loop, or by
  # `Tween.update_all(dt)` manually.
  #
  #   Tween.to(2.0, ease: :quad_out) { |t| sprite.position = start.lerp(target, t) }
  #   Tween.value(0, 100, 1.5) { |v| bar.width = v }
  #   Tween.sequence { |s| s.wait(1); s.to(0.5) { |t| ... }; s.call { done } }
  class Tween
    @@active = [] of Tween

    getter duration : Float32
    getter elapsed = 0_f32
    getter? finished = false
    property? paused = false
    property? loop = false
    property? ping_pong = false
    property delay : Float32
    @ease : Proc(Float32, Float32)
    @on_update : Proc(Float32, Nil)?
    @on_complete = [] of ->

    def initialize(duration : Number, ease : Symbol | Proc(Float32, Float32) = :linear, delay : Number = 0, &block : Float32 ->)
      @duration = duration.to_f32
      @delay = delay.to_f32
      @ease = ease.is_a?(Symbol) ? Ease.by_name(ease) : ease
      @on_update = block
    end

    # Start a tween where the block receives eased progress 0..1.
    def self.to(duration : Number, ease : Symbol | Proc(Float32, Float32) = :linear, delay : Number = 0, &block : Float32 ->) : Tween
      new(duration, ease, delay, &block).start
    end

    # Tween a numeric value.
    def self.value(from : Number, to : Number, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Float32 ->) : Tween
      a = from.to_f32; b = to.to_f32
      to(duration, ease, delay) { |t| block.call(a + (b - a) * t) }
    end

    def self.value(from : Vec2, to : Vec2, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Vec2 ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    def self.value(from : Vec3, to : Vec3, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Vec3 ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    def self.value(from : Color, to : Color, duration : Number, ease : Symbol = :linear, delay : Number = 0, &block : Color ->) : Tween
      to(duration, ease, delay) { |t| block.call(from.lerp(to, t)) }
    end

    # Call a block after `seconds`.
    def self.after(seconds : Number, &block : ->) : Tween
      t = new(0, :linear, seconds) { }
      t.on_complete(&block)
      t.start
    end

    def self.sequence(&) : Sequence
      s = Sequence.new
      yield s
      s.start
      s
    end

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

    def stop : Nil
      @@active.delete(self)
    end

    def on_complete(&block : ->) : self
      @on_complete << block
      self
    end

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

    def self.active_count : Int32; @@active.size; end
    def self.clear : Nil; @@active.clear; end

    # A chain of steps run one after another.
    class Sequence
      @steps = [] of Tween
      @index = 0
      @started = false
      getter? finished = false
      @on_complete = [] of ->

      def to(duration : Number, ease : Symbol = :linear, &block : Float32 ->) : self
        @steps << Tween.new(duration, ease, &block)
        self
      end

      def wait(seconds : Number) : self
        @steps << Tween.new(seconds) { }
        self
      end

      def call(&block : ->) : self
        t = Tween.new(0) { }
        t.on_complete(&block)
        @steps << t
        self
      end

      def on_complete(&block : ->) : self
        @on_complete << block
        self
      end

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
