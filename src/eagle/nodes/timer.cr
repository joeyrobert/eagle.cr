module Eagle
  # Counts down and emits `timeout`.
  #
  #   t = Timer.new(2.0, one_shot: true, autostart: true)
  #   t.on_timeout { spawn_enemy }
  class Timer < Node
    property wait_time : Float32
    property? one_shot : Bool
    property? autostart : Bool
    getter time_left : Float32 = 0_f32
    getter? running = false
    property? paused = false
    # Use physics_process (fixed) instead of process.
    property? physics = false

    signal timeout

    def initialize(wait_time : Number = 1.0, @one_shot = false, @autostart = false, name : String = "", &block : ->)
      super(name)
      @wait_time = wait_time.to_f32
      on_timeout(&block)
    end

    def initialize(wait_time : Number = 1.0, @one_shot = false, @autostart = false, name : String = "")
      super(name)
      @wait_time = wait_time.to_f32
    end

    def ready : Nil
      start if @autostart
    end

    def start(time : Number? = nil) : self
      @wait_time = time.to_f32 if time
      @time_left = @wait_time
      @running = true
      @paused = false
      self
    end

    def stop : Nil
      @running = false
      @time_left = 0_f32
    end

    def stopped? : Bool; !@running; end
    def progress : Float32; @wait_time <= 0 ? 1_f32 : 1 - @time_left / @wait_time; end

    def process(dt : Float32) : Nil
      tick(dt) unless @physics
    end

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
