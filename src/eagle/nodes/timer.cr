module Eagle
  # Counts down and emits `timeout`. Use it for spawn waves, cooldowns and delayed events
  # that should pause with the scene tree.
  #
  # ```
  # class Spawner < Node2D
  #   def ready : Nil
  #     add(Timer.new(2.0, autostart: true) { spawn_enemy }) # every 2 seconds
  #     add(Timer.new(30.0, one_shot: true, autostart: true) { puts "boss!" })
  #   end
  #
  #   def spawn_enemy : Nil
  #     add(Sprite2D.new(Texture.new(Image.circle(8, Color::RED)), v2(rand * 400, 0)))
  #   end
  # end
  # ```
  #
  # For a one-off delay that doesn't need a node, `Tween.after` is shorter.
  class Timer < Node
    # Seconds between timeouts.
    property wait_time : Float32
    # Stop after the first timeout instead of repeating.
    property? one_shot : Bool
    # Start automatically when the timer enters the tree.
    property? autostart : Bool
    # Seconds until the next timeout.
    getter time_left : Float32 = 0_f32
    # True while counting down.
    getter? running = false
    # Freezes the countdown.
    property? paused = false
    # Count down in fixed steps (`physics_process`) instead of per frame.
    property? physics = false

    signal timeout

    # Creates a timer and connects the block to `timeout`.
    def initialize(wait_time : Number = 1.0, @one_shot = false, @autostart = false, name : String = "", &block : ->)
      super(name)
      @wait_time = wait_time.to_f32
      on_timeout(&block)
    end

    # Creates a timer.
    def initialize(wait_time : Number = 1.0, @one_shot = false, @autostart = false, name : String = "")
      super(name)
      @wait_time = wait_time.to_f32
    end

    # Starts the timer if `autostart` is set.
    def ready : Nil
      start if @autostart
    end

    # Starts or restarts the countdown, optionally with a new wait time. Returns self.
    def start(time : Number? = nil) : self
      @wait_time = time.to_f32 if time
      @time_left = @wait_time
      @running = true
      @paused = false
      self
    end

    # Stops the countdown.
    def stop : Nil
      @running = false
      @time_left = 0_f32
    end

    # True when not counting down.
    def stopped? : Bool; !@running; end
    # Fraction of the wait that has passed, from 0 to 1. Handy for cooldown bars.
    def progress : Float32; @wait_time <= 0 ? 1_f32 : 1 - @time_left / @wait_time; end

    # Counts down each frame. Called by the engine.
    def process(dt : Float32) : Nil
      tick(dt) unless @physics
    end

    # Counts down each fixed step when `physics` is set. Called by the engine.
    def physics_process(dt : Float32) : Nil
      tick(dt) if @physics
    end

    private def tick(dt : Float32)
      return unless @running && !@paused
      @time_left -= dt
      while @time_left <= 0 && @running
        if @one_shot
          @running = false
          @time_left = 0_f32
          emit_timeout
        else
          @time_left += @wait_time
          emit_timeout
          break if @wait_time <= 0
        end
      end
    end
  end
end
