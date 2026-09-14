# Crystal 1.21's wasm32-wasi stdlib is incomplete; these shims fill the gaps
# needed to run single-threaded programs in the browser.
{% if flag?(:wasm32) %}
  class Crystal::EventLoop::Wasi < Crystal::EventLoop
    def run(queue : Pointer(Fiber::List), blocking : Bool) : Nil
    end

    def lock?(&) : Bool
      yield
      true
    end

    def interrupt? : Bool
      false
    end
  end

  class Thread
    private def system_name=(name : String) : String
      name
    end
  end

  module Crystal::System::Thread
    private def init_handle
      raise NotImplementedError.new("threads are not available on wasm")
    end
  end

  class Fiber::ExecutionContext::Monitor
    def initialize(@every = DEFAULT_EVERY)
      @thread = Thread.current # no SYSMON thread on wasm
    end
  end

  class Time::Location
    # No zoneinfo on the web; everything is UTC.
    def self.load_local : Location
      UTC
    end
  end

  Fiber::ExecutionContext.init_default_context
{% end %}
