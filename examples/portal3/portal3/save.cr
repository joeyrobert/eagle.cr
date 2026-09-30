module Portal3
  # Everything that survives closing the game: how far the player has got, their
  # settings, and a little history for the stats screen.
  #
  # The file is a small line-based format rather than JSON so it stays readable and
  # hand-editable, and so a corrupt line costs one setting rather than the whole file.
  class SaveData
    # Set once at startup if the game could not write its save anywhere. The player is
    # told, because a browser with storage blocked would otherwise lose their progress
    # silently every session.
    @@saving_broken = false

    def self.saving_broken? : Bool
      @@saving_broken
    end

    # Checks that a save can actually be written, without touching the real one.
    def self.check_writable : Nil
      if file_backed?
        probe = SaveData.default_path + ".probe"
        begin
          File.write(probe, "1")
          File.delete(probe)
          @@saving_broken = false
          return
        rescue
          @@saving_broken = true
          return
        end
      end
      if pf = Eagle.platform?
        begin
          pf.storage_write(PROBE_KEY, "1")
          ok = pf.storage_read(PROBE_KEY) == "1"
          pf.storage_write(PROBE_KEY, "")
          @@saving_broken = !ok
          return
        rescue
          @@saving_broken = true
          return
        end
      end
      @@saving_broken = true
    end

    # How many chambers have been unlocked. Chamber 0 is always available.
    property unlocked : Int32 = 1
    property deaths : Int32 = 0
    property chambers_done : Int32 = 0
    property play_time : Float64 = 0.0
    property seen_intro : Bool = false

    property mouse_sensitivity : Float32 = 1.0_f32
    property invert_y : Bool = false
    property volume : Float32 = 0.8_f32
    property fov : Float32 = 75.0_f32

    # Chambers the player has finished, so the select screen can mark them.
    property completed = Array(Bool).new(Levels::COUNT, false)

    # The key used when the platform can store things itself. A browser has no
    # writable filesystem at all: the engine's JS shim answers ENOTCAPABLE to every
    # file open, so `File.write` cannot persist anything there. Platform storage is
    # what a save has to use on the web.
    STORAGE_KEY = "portal3.save"

    # Used to check that a save can actually be written. It must never be the real
    # save's key: writing the probe used to overwrite the player's progress before it
    # was read, which silently reset the game on every launch.
    PROBE_KEY = "portal3.probe"

    # Whether this platform has a usable filesystem at all.
    #
    # A browser does not, and merely asking is fatal: the WASI layer answers
    # ENOTCAPABLE to a file open and raises trying to create a directory that is not
    # there, which took the whole game down on the first frame. So the question is
    # asked once, defensively, and the answer cached.
    @@file_backed : Bool? = nil

    def self.file_backed? : Bool
      return @@file_backed.not_nil! unless @@file_backed.nil?
      @@file_backed = begin
        # A directory that is there is as much as can be checked safely here; whether
        # the write itself succeeds is settled by write_text, which is already guarded.
        Dir.exists?(File.dirname(default_path))
      rescue
        false
      end
    end

    # A save goes to a file where there is one, and to the platform's own store where
    # there is not. Neither is assumed to work: the browser can also refuse storage,
    # in which case the game runs and simply cannot remember anything.
    def self.read_text : String?
      if file_backed?
        begin
          return File.read(default_path) if File.exists?(default_path)
        rescue
        end
      end
      if pf = Eagle.platform?
        begin
          return pf.storage_read(STORAGE_KEY)
        rescue
        end
      end
      nil
    end

    def self.write_text(text : String) : Bool
      if file_backed?
        begin
          File.write(default_path, text)
          return true
        rescue
        end
      end
      if pf = Eagle.platform?
        begin
          pf.storage_write(STORAGE_KEY, text)
          return true
        rescue
        end
      end
      false
    end

    # Where the game writes on platforms that have a filesystem. A folder that is not
    # writable is skipped, so a read-only install still runs.
    def self.default_path : String
      override = ENV["PORTAL3_SAVE"]?
      return override if override && !override.empty?
      "portal3.save"
    end

    # Kept for the settings screen, which reports where a save lives.
    def self.path : String
      default_path
    end

    def self.load : SaveData
      data = SaveData.new
      text = read_text
      return data unless text
      text.each_line do |line|
        key, _, value = line.partition(':')
        next if value.empty?
        value = value.strip
        case key
        when "unlocked"      then data.unlocked = value.to_i
        when "deaths"        then data.deaths = value.to_i
        when "chambers_done" then data.chambers_done = value.to_i
        when "play_time"     then data.play_time = value.to_f64
        when "seen_intro"    then data.seen_intro = value == "true"
        when "sensitivity"   then data.mouse_sensitivity = value.to_f32
        when "invert_y"      then data.invert_y = value == "true"
        when "volume"        then data.volume = value.to_f32
        when "fov"           then data.fov = value.to_f32
        when "completed"     then data.read_completed(value)
        end
      end
      data
    rescue
      # A save we cannot read should not stop the game from starting.
      SaveData.new
    end

    def save : Nil
      # Losing progress is better than crashing on exit, so a failed write is ignored.
      SaveData.write_text(serialise)
    end

    # Reads the comma-separated flags back into the completion list.
    def read_completed(value : String) : Nil
      @completed = Array(Bool).new(Levels::COUNT, false)
      value.split(',').each_with_index do |flag, i|
        @completed[i] = true if i < @completed.size && flag == "1"
      end
    end

    private def serialise : String
      String.build do |io|
        io << "version:1\n"
        io << "unlocked:#{@unlocked}\n"
        io << "deaths:#{@deaths}\n"
        io << "chambers_done:#{@chambers_done}\n"
        io << "play_time:#{@play_time.round(1)}\n"
        io << "seen_intro:#{@seen_intro}\n"
        io << "sensitivity:#{@mouse_sensitivity.round(3)}\n"
        io << "invert_y:#{@invert_y}\n"
        io << "volume:#{@volume.round(3)}\n"
        io << "fov:#{@fov.round(1)}\n"
        io << "completed:" << @completed.map { |done| done ? "1" : "0" }.join(',') << '\n'
      end
    end

    # Records a finished chamber, unlocking the next one.
    def complete_chamber(index : Int32) : Nil
      @completed[index] = true if index < @completed.size
      @chambers_done = @completed.count(true)
      wanted = index + 2
      @unlocked = wanted if wanted > @unlocked
      @unlocked = Levels::COUNT if @unlocked > Levels::COUNT
    end

    # Play time as a short human string, for the stats panel.
    def played : String
      total = @play_time.to_i
      hours = total / 3600
      minutes = (total % 3600) / 60
      hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m"
    end
  end
end
