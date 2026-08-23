require "log"

module Eagle
  @@log : ::Log = ::Log.for("eagle")

  def self.log : ::Log
    @@log
  end

  # Configure log level from EAGLE_LOG (debug, info, warn, error). Default: info.
  def self.setup_logging : Nil
    level = case ENV["EAGLE_LOG"]?.try(&.downcase)
            when "debug", "trace" then ::Log::Severity::Debug
            when "warn"           then ::Log::Severity::Warn
            when "error"          then ::Log::Severity::Error
            when "none", "off"    then ::Log::Severity::None
            else                       ::Log::Severity::Info
            end
    ::Log.setup(level, ::Log::IOBackend.new(STDERR, formatter: ::Log::Formatter.new { |entry, io|
      io << "[eagle " << entry.severity.label.downcase << "] " << entry.message
      if ex = entry.exception
        io << " (" << ex.message << ")"
      end
    }))
  end
end
