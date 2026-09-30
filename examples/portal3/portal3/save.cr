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

    # Probes that a save can actually be written, rather than assuming it.
    def self.check_writable : Nil
      probe = SaveData.write_text("version:1\n")
      return if probe
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

    # A save has to go to a file when the platform has a filesystem, and to the
    # platform's own store when it does not. A browser answers ENOTCAPABLE to every
    # file open, so there the file is tried first, fails, and the store takes over.
    def self.read_text : String?
      file = SaveData.path
      begin
        return File.read(file) if File.exists?(file)
      rescue
      end
      if pf = Eagle.platform?
        begin
          return pf.storage_read(STORAGE_KEY)
        rescue
        end
      end
      nil
    end

    # Writes to the file first, and to the platform's own store when that fails.
    # Neither can be relied on, and neither failure should stop the game.
    def self.write_text(text : String) : Bool
      begin
        File.write(SaveData.path, text)
        return true
      rescue
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
    def self.path : String
      override = ENV["PORTAL3_SAVE"]?
      return override if override && !override.empty?
      candidates = ["portal3.save", File.join(home, ".portal3.save")]
      candidates.find { |c| writable?(c) } || candidates.first
    end

    private def self.home : String
      ENV["HOME"]? || "."
    end

    private def self.writable?(file : String) : Bool
      dir = File.dirname(file)
      return true if File.exists?(file)
      Dir.mkdir_p(dir)
      probe = File.join(dir, ".portal3_probe")
      File.write(probe, "")
      File.delete(probe)
      true
    rescue
      false
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
