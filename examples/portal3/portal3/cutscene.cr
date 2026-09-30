module Portal3
  # Scripted sequences: the opening, the card between chambers and the closing. A
  # cutscene is a list of beats on a clock, each either moving the camera or putting a
  # line on screen. Any key skips to the end.
  class Cutscene
    # A camera pose for one beat. `look` is a world point the camera turns to.
    record Shot, from : Vec3, to : Vec3, look : Vec3

    # One timed piece of a cutscene. A beat with no camera move just holds the frame
    # and shows its caption.
    record Beat, at : Float32, for : Float32, caption : String?, shot : Shot?

    # Fires once, part way through a beat, so a sequence can change the world at the
    # right moment rather than all at the start.
    alias Trigger = Proc(Nil)

    record Step, at : Float32, trigger : Trigger?

    getter name : String
    getter? finished = false

    @beats : Array(Beat)
    @steps : Array(Step)
    @length = 0_f32
    @time = 0_f32
    @index = 0
    @fired = 0

    def initialize(@name : String, beats : Array(Beat), steps : Array(Step) = [] of Step)
      @beats = beats.sort_by(&.at)
      @steps = steps.sort_by(&.at)
      if last = @beats.last?
        @length = last.at + last.for
      end
    end

    def length : Float32
      @length
    end

    def time : Float32
      @time
    end

    # The shot for right now, or nil where the camera should be left alone.
    def current_shot : Cutscene::Shot?
      active_beat.try(&.shot)
    end

    # How far through the running shot we are, 0 to 1, so the camera can travel
    # across the beat rather than sitting at its end.
    def shot_progress : Float32
      beat = active_beat
      return 0.0_f32 unless beat && beat.for > 0
      ((@time - beat.at) / beat.for).clamp(0.0_f32, 1.0_f32)
    end

    private def active_beat : Cutscene::Beat?
      @beats.reverse_each.find { |beat| @time >= beat.at && @time < beat.at + beat.for }
    end

    # The line that should be on screen right now.
    def current_caption : String?
      @beats.reverse_each.find { |beat| beat.caption && @time >= beat.at && @time < beat.at + beat.for }
        .try(&.caption)
    end

    # True once a line has been up long enough to have been read, which is when the
    # player is allowed to skip.
    def skippable? : Bool
      @time > 0.8_f32
    end

    # Jumps to the end, firing everything still pending so nothing is left half done.
    def skip : Nil
      fire_pending
      @time = @length
      @finished = true
    end

    def update(dt : Float32) : Bool
      @time += dt
      fire_pending
      @finished = true if @time >= @length
      @finished
    end

    # Runs any trigger whose time has arrived. Index based, so holding skip does not
    # fire the same trigger twice.
    private def fire_pending : Nil
      while @fired < @steps.size && @time >= @steps[@fired].at
        @steps[@fired].trigger.try(&.call)
        @fired += 1
      end
    end

    # ------------------------------------------------------------------- scripts

    # The opening. A wide shot of an empty chamber, the lights coming up, and the
    # announcer explaining why you are there.
    def self.intro : Cutscene
      new("intro", [
        Beat.new(0.0_f32, 3.0_f32, "Subject: test subject 3271.",
          Shot.new(v3(-4.4, 4.4, -4.4), v3(-3.2, 3.8, -3.2), v3(0.5, 0.0, 0.5))),
        Beat.new(3.0_f32, 3.2_f32, "You have been awake for six hours.",
          Shot.new(v3(4.4, 4.2, 4.4), v3(3.2, 3.6, 3.2), v3(-0.5, 0.0, -0.5))),
        Beat.new(6.2_f32, 3.2_f32, "The device in your hand is a portal device.",
          Shot.new(v3(4.2, 3.4, 4.2), v3(3.4, 2.6, 3.4), v3(-1.0, 0.0, -1.0))),
        Beat.new(9.4_f32, 3.4_f32, "Please proceed to the first chamber.",
          Shot.new(v3(-4.2, 2.6, 3.8), v3(-2.8, 2.0, 2.2), v3(1.5, 0.4, -1.5))),
        Beat.new(12.8_f32, 3.0_f32, "Try not to die. The paperwork is a nightmare.", nil),
      ])
    end

    # Between chambers: one line over a black card.
    def self.interstitial(index : Int32, title : String) : Cutscene
      new("interstitial", [
        Beat.new(0.0_f32, 2.2_f32, title, nil),
      ])
    end

    # The closing, after the last chamber.
    def self.outro : Cutscene
      new("outro", [
        Beat.new(0.0_f32, 3.0_f32, "Congratulations. You passed.",
          Shot.new(v3(9.0, 5.0, 7.0), v3(6.0, 3.6, 5.0), v3(0, 0.5, 0))),
        Beat.new(3.0_f32, 3.4_f32, "I would like to say you were the best subject.",
          Shot.new(v3(-9.0, 3.6, 6.0), v3(-6.0, 2.6, 4.0), v3(0, 0.8, 0))),
        Beat.new(6.4_f32, 4.0_f32, "You were not the best subject.", nil),
        Beat.new(10.4_f32, 4.0_f32, "Thank you for participating.", nil),
      ])
    end
  end
end
