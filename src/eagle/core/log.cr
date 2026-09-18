require "log"

module Eagle
  @@log : ::Log = ::Log.for("eagle")

  # Eagle's logger, a standard Crystal `Log` named "eagle". Set `EAGLE_LOG=debug` for more output.
  #
  # ```
  # Eagle.log.info { "level loaded" }
  # Eagle.log.debug { "spawned enemy" }
  # ```
  def self.log : ::Log
    @@log
  end

  # Sets the log level from the `EAGLE_LOG` environment variable (debug, info, warn, error or off).
  # The default is info. `Eagle.run` calls this for you.
  def self.setup_logging : Nil
    level = case ENV["EAGLE_LOG"]?.try(&.downcase)
            when "debug", "trace" then ::Log::Severity::Debug
            when "warn"           then ::Log::Severity::Warn
            when "error"          then ::Log::Severity::Error
            when "none", "off"    then ::Log::Severity::None
            else                       ::Log::Severity::Info
            end
    ::Log.setup(level, ::Log::IOBackend.new(STDERR, dispatcher: ::Log::DispatchMode::Direct, formatter: ::Log::Formatter.new { |entry, io|
      io << "[eagle " << entry.severity.label.downcase << "] " << entry.message
      if ex = entry.exception
        io << " (" << ex.message << ")"
      end
    }))
  end
end
