require "../../src/eagle"

module EagleRocketBall
  include Eagle

  # Every sound is synthesized at startup, so the game ships no assets.
  class Sfx
    getter hit : Sound
    getter bounce : Sound
    getter pad_small : Sound
    getter pad_big : Sound
    getter jump : Sound
    getter dodge : Sound
    getter demo : Sound
    getter horn : Sound
    getter roar : Sound
    getter whistle : Sound
    getter save : Sound
    getter beep : Sound
    getter go : Sound
    getter ui_move : Sound
    getter ui_ok : Sound
    getter ui_back : Sound
    getter engine : Sound
    getter boost_loop : Sound
    getter crowd : Sound
    getter music : Sound

    def initialize
      rng = Random.new(11)
      @hit = Sound.generate(0.28) { |t| ((Math.sin(Math::TAU * (70 + 260 * Math.exp(-t * 45)) * t) * Math.exp(-t * 16) * 0.8) + (rng.rand * 2 - 1) * Math.exp(-t * 70) * 0.45).to_f32 }
      @bounce = Sound.generate(0.18) { |t| (Math.sin(Math::TAU * (60 + 140 * Math.exp(-t * 50)) * t) * Math.exp(-t * 22) * 0.7).to_f32 }
      @pad_small = Sound.generate(0.16) { |t| (Math.sin(Math::TAU * (t < 0.07 ? 880 : 1320) * t) * Math.exp(-t * 14) * 0.35).to_f32 }
      @pad_big = Sound.generate(0.55) { |t| ((Math.sin(Math::TAU * (300 + 900 * t) * t) * 0.35 + Math.sin(Math::TAU * (600 + 1800 * t) * t) * 0.12) * Math.exp(-t * 4)).to_f32 }
      @jump = Sound.generate(0.2) { |t| ((Math.sin(Math::TAU * (180 + 700 * t) * t) * 0.3 + (rng.rand * 2 - 1) * 0.12) * Math.exp(-t * 11)).to_f32 }
      @dodge = Sound.generate(0.32) { |t| ((Math.sin(Math::TAU * (150 + 1200 * t) * t) * 0.3 + (rng.rand * 2 - 1) * 0.28 * Math.exp(-t * 6)) * Math.exp(-t * 8)).to_f32 }
      @demo = Sound.generate(0.8) { |t| ((rng.rand * 2 - 1) * Math.exp(-t * 5) * 0.55 + Math.sin(Math::TAU * (70 - 30 * t) * t) * Math.exp(-t * 6) * 0.7).to_f32 }
      @horn = Sound.generate(1.7) do |t|
        env = Math.min(1.0, t / 0.04) * Math.exp(-t * 1.6)
        saw = ->(f : Float64) { 2 * ((f * t) % 1.0) - 1 }
        ((saw.call(233.1) + saw.call(293.7) + saw.call(349.2) + saw.call(116.5) * 0.8) * 0.13 * env).to_f32
      end
      @roar = Sound.generate(2.6) { |t| ((rng.rand * 2 - 1) * Math.sin(Math::PI * t / 2.6) ** 0.7 * 0.32).to_f32 }
      @whistle = Sound.generate(1.0) { |t| (Math.sin(Math::TAU * (2500 + Math.sin(t * 60) * 90) * t) * Math.min(1.0, t * 30) * Math.exp(-t * 2.5) * 0.3).to_f32 }
      @save = Sound.generate(0.4) { |t| ((Math.sin(Math::TAU * 520 * t) + Math.sin(Math::TAU * 780 * t)) * Math.exp(-t * 9) * 0.22).to_f32 }
      @beep = Sound.tone(660, 0.2, Sound::Wave::Square, 0.25)
      @go = Sound.tone(990, 0.45, Sound::Wave::Square, 0.28)
      @ui_move = Sound.tone(1000, 0.04, Sound::Wave::Triangle, 0.25)
      @ui_ok = Sound.tone(1500, 0.09, Sound::Wave::Triangle, 0.3)
      @ui_back = Sound.tone(520, 0.08, Sound::Wave::Triangle, 0.28)
      # Loops use whole numbers of cycles so they repeat without a click.
      @engine = Sound.generate(0.5) do |t|
        f = 56.0
        (1..5).sum { |k| Math.sin(Math::TAU * f * k * t + k * 0.7) / k * 0.5 }.to_f32 * 0.35_f32
      end
      @boost_loop = Sound.generate(0.6) do |t|
        (0...40).sum { |i| Math.sin(Math::TAU * (90 + i * 22) / 0.6 * t + i * 2.3) / (1 + i * 0.09) }.to_f32 * 0.018_f32
      end
      @crowd = Sound.generate(2.0) do |t|
        (0...50).sum { |i| Math.sin(Math::TAU * (110 + i * 13.5) * t + i * 1.7) * (0.6 + 0.4 * Math.sin(Math::TAU * (i % 4 + 1) * 0.5 * t + i)) }.to_f32 * 0.012_f32
      end
      @music = Sfx.build_music
    end

    # A 4-bar synth loop at 128 bpm: kick, off-beat hats, bass, and a plucky arpeggio.
    def self.build_music : Sound
      beat = 60.0 / 128
      roots = [55.0, 43.65, 65.41, 49.0]
      chords = [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
      pattern = [0, 1, 2, 1, 0, 2, 1, 2]
      state = 1234_u32
      Sound.generate(16 * beat, sample_rate: 22050) do |t|
        bp = t / beat
        bar = (bp / 4).to_i % 4
        bt = (bp - bp.floor) * beat
        s = Math.sin(Math::TAU * (45 * bt + 110 * (1 - Math.exp(-28 * bt)) / 28)) * Math.exp(-bt * 9) * 0.8
        e8 = ((bp * 2) - (bp * 2).floor) * beat / 2
        if (bp * 2).floor.to_i.odd?
          state = state &* 1664525_u32 &+ 1013904223_u32
          s += ((state >> 16) / 32768.0 - 1) * Math.exp(-e8 * 60) * 0.2
        end
        note = roots[bar]
        s += (Math.sin(Math::TAU * note * t) + 0.35 * Math.sin(Math::TAU * note * 2 * t)) * Math.exp(-e8 * 7) * 0.32
        idx = (bp * 4).floor.to_i
        e16 = ((bp * 4) - (bp * 4).floor) * beat / 4
        f = chords[bar][pattern[idx % 8] % 3] * (idx % 4 == 3 ? 2 : 1)
        s += (Math.sin(Math::TAU * f * t) + Math.sin(Math::TAU * f * 3 * t) / 3 + Math.sin(Math::TAU * f * 5 * t) / 5) * Math.exp(-e16 * 13) * 0.11
        s += Math.sin(Math::TAU * chords[bar][0] * 0.5 * t) * 0.035
        (s * 0.7).clamp(-1.0, 1.0).to_f32
      end
    end
  end
end
