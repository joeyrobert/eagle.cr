require "../spec_helper"

private def rms(buf : Slice(Float32), channel : Int32, from : Int32 = 0) : Float64
  n = buf.size // 2
  sum = 0.0
  (from...n).each { |i| sum += buf[i * 2 + channel].to_f64 ** 2 }
  Math.sqrt(sum / (n - from))
end

private def crossings(buf : Slice(Float32), channel : Int32) : Int32
  c = 0
  (1...buf.size // 2).each { |i| c += 1 if buf[(i - 1) * 2 + channel] < 0 && buf[i * 2 + channel] >= 0 }
  c
end

private def onset(buf : Slice(Float32), channel : Int32) : Int32
  (0...buf.size // 2).find { |i| buf[i * 2 + channel].abs > 1e-4 } || -1
end

private def dc : Sound
  Sound.generate(2.0) { |t| 0.5_f32 }
end

private def noise : Sound
  Sound.tone(1, 2.0, Sound::Wave::Noise, volume: 0.5, attack: 0, release: 0)
end

private def listen_from(position : Vec3 = Vec3::ZERO) : Camera3D
  cam = Camera3D.new(position: position)
  SceneTree.root.add(cam)
  cam
end

describe Eagle::Spatial3D do
  before_each { SceneTree.reset; Audio.reset }

  it "computes each distance model and clamps to min and max distance" do
    {Attenuation::Inverse, Attenuation::Linear, Attenuation::Exponential}.each do |m|
      g = ->(d : Float64) { Spatial3D.distance_gain(m, d, 2, 50, 1) }
      g.call(0.5).should eq 1
      g.call(2.0).should eq 1
      g.call(5.0).should be < g.call(3.0)
      g.call(40.0).should be < g.call(10.0)
      g.call(80.0).should eq g.call(50.0)
      g.call(1000.0).should eq g.call(50.0)
    end
    Spatial3D.distance_gain(Attenuation::Inverse, 4, 2, 50, 1).should be_close(0.5, 1e-5)
    Spatial3D.distance_gain(Attenuation::Linear, 26, 2, 50, 1).should be_close(0.5, 1e-5)
    Spatial3D.distance_gain(Attenuation::Linear, 50, 2, 50, 1).should eq 0
    Spatial3D.distance_gain(Attenuation::Exponential, 8, 2, 50, 2).should be_close(1 / 16.0, 1e-5)
    Spatial3D.distance_gain(Attenuation::Inverse, 6, 2, 50, 2).should be < Spatial3D.distance_gain(Attenuation::Inverse, 6, 2, 50, 1)
  end

  it "attenuates rendered output with distance per model" do
    listen_from
    {Attenuation::Inverse, Attenuation::Linear, Attenuation::Exponential}.each do |m|
      levels = [1, 4, 16, 64].map do |d|
        Audio.reset
        v = Audio.play_at(dc, v3(0, 0, -d), attenuation: m, min_distance: 2, max_distance: 32)
        buf = Audio.render(256)
        v.stop
        buf[255 * 2].to_f64
      end
      levels[0].should be_close(0.5 * Math.sqrt(0.5), 1e-3) # inside min_distance: full volume, centered
      levels[1].should be < levels[0]
      levels[2].should be < levels[1]
      levels[3].should be <= levels[2]
      levels[3].should be_close(0.5 * Math.sqrt(0.5) * Spatial3D.distance_gain(m, 32, 2, 32, 1), 1e-3)
    end
  end

  it "is louder in the ear facing the source" do
    listen_from
    right = Audio.play_at(noise, v3(5, 0, 0))
    buf = Audio.render(4800)
    rms(buf, 1).should be > rms(buf, 0) * 3
    right.stop
    left = Audio.play_at(noise, v3(-5, 0, 0))
    buf = Audio.render(4800)
    rms(buf, 0).should be > rms(buf, 1) * 3
    left.stop
    ahead = Audio.play_at(noise, v3(0, 0, -5))
    buf = Audio.render(4800)
    rms(buf, 0).should be_close(rms(buf, 1), rms(buf, 0) * 0.01)
  end

  it "muffles sources behind the listener" do
    listen_from
    front = Audio.play_at(noise, v3(0, 0, -3))
    f = Audio.render(4800)
    front_level = rms(f, 0, 100)
    front.stop
    back = Audio.play_at(noise, v3(0, 0, 3))
    b = Audio.render(4800)
    back_level = rms(b, 0, 100)
    back_level.should be < front_level * 0.75
    rms(b, 0, 100).should be_close(rms(b, 1, 100), back_level * 0.01)
    # a low tone is barely shadowed, so the difference is mostly high frequencies
    back.stop
    low = Sound.tone(60, 2, volume: 0.5, attack: 0, release: 0)
    lf = Audio.play_at(low, v3(0, 0, -3)); lfb = Audio.render(4800); lf.stop
    lb = Audio.play_at(low, v3(0, 0, 3)); lbb = Audio.render(4800); lb.stop
    (rms(lbb, 0, 100) / rms(lfb, 0, 100)).should be > back_level / front_level
  end

  it "delays the far ear by an interaural time difference" do
    listen_from
    v = Audio.play_at(dc, v3(4, 0, 0))
    buf = Audio.render(256)
    onset(buf, 1).should eq 0
    itd = onset(buf, 0)
    expected = Spatial3D::MAX_ITD * Audio.sample_rate * (4 / Math.sqrt(16 + Spatial3D::NEAR_FIELD ** 2))
    itd.should be_close(expected, 1.5)
    itd.should be > 20
    v.spatial.not_nil!.delay_left.should be_close(expected / Audio.sample_rate, 1e-6)
    v.spatial.not_nil!.delay_right.should eq 0
    v.stop
    Audio.play_at(dc, v3(-4, 0, 0))
    buf = Audio.render(256)
    onset(buf, 0).should eq 0
    onset(buf, 1).should eq itd
  end

  it "swaps ears when the listener turns around" do
    cam = listen_from
    v = Audio.play_at(noise, v3(5, 0, 0))
    buf = Audio.render(4800)
    rms(buf, 1).should be > rms(buf, 0) * 3
    cam.rotate_y(Math::PI)
    Audio.render(1024) # glide to the new targets
    buf = Audio.render(4800)
    rms(buf, 0).should be > rms(buf, 1) * 3
    cam.rotate_y(Math::PI / 2) # now facing +x: the source is straight ahead
    Audio.render(1024)
    buf = Audio.render(4800)
    rms(buf, 0).should be_close(rms(buf, 1), rms(buf, 0) * 0.01)
    v.stop
  end

  it "prefers a current AudioListener3D over the camera" do
    listen_from(v3(100, 0, 0))
    Audio.listener.position.should eq v3(100, 0, 0)
    ears = AudioListener3D.new(position: v3(0, 0, 0))
    ears.rotate_y(Math::PI)
    SceneTree.root.add(ears)
    ears.current?.should be_true
    Audio.listener.position.should eq Vec3::ZERO
    Audio.play_at(noise, v3(5, 0, 0))
    buf = Audio.render(4800)
    rms(buf, 0).should be > rms(buf, 1) * 3 # listener turned around: +x is on the left
    ears.free
    AudioListener3D.current.should be_nil
    Audio.listener.position.should eq v3(100, 0, 0)
  end

  it "shifts pitch with doppler only when enabled" do
    listen_from
    Audio.speed_of_sound = 100
    tone = Sound.tone(500, 2, volume: 0.5, attack: 0, release: 0)
    counts = [{Vec3::ZERO, false}, {v3(0, 0, 30), true}, {v3(0, 0, -30), true}, {v3(0, 0, 30), false}].map do |(vel, on)|
      Audio.reset
      Audio.speed_of_sound = 100
      v = Audio.play_at(tone, v3(0, 0, -20), velocity: vel, doppler: on)
      buf = Audio.render(48000)
      v.stop
      crossings(buf, 0)
    end
    counts[0].should be_close(500, 2)
    counts[1].should be_close(500 * 100 / 70.0, 5)  # approaching: higher
    counts[2].should be_close(500 * 100 / 130.0, 5) # receding: lower
    counts[3].should eq counts[0]
  end

  it "applies doppler from listener motion" do
    cam = listen_from
    Audio.speed_of_sound = 100
    Audio.track_listener(0.1_f32)
    cam.position = v3(0, 0, -3) # 30 units/s toward the source
    Audio.track_listener(0.1_f32)
    Audio.listener.velocity.z.should be_close(-30, 1e-3)
    v = Audio.play_at(Sound.tone(500, 2, attack: 0, release: 0), v3(0, 0, -50), doppler: true)
    Audio.render(16)
    v.spatial.not_nil!.doppler_pitch.should be_close(1.3, 1e-3)
  end

  it "glides parameter changes without clicks" do
    listen_from
    v = Audio.play_at(dc, v3(-5, 0, 0), min_distance: 10)
    first = Audio.render(800).dup
    sp = v.spatial.not_nil!
    sp.position = v3(5, 0, 0) # jump from hard left to hard right
    second = Audio.render(800).dup
    sp.position = v3(0, 0, -40) # then far away
    third = Audio.render(800).dup
    all = Slice(Float32).new(first.size * 3)
    first.copy_to(all); second.copy_to(all + first.size); third.copy_to(all + first.size * 2)
    jump = 0_f32
    2.times { |ch| (100...all.size // 2).each { |i| jump = Math.max(jump, (all[i * 2 + ch] - all[(i - 1) * 2 + ch]).abs) } }
    jump.should be < 0.002
    (first[799 * 2] - third[799 * 2]).abs.should be > 0.2 # it did move
  end

  it "leaves non-spatial voices untouched" do
    listen_from(v3(10, 0, 0))
    dc.play(volume: 0.5, pan: -1)
    Audio.render(10)[0].should be_close(0.25, 1e-4)
  end
end

describe Eagle::AudioPlayer3D do
  before_each { SceneTree.reset; Audio.reset }

  it "follows its node and measures velocity" do
    listen_from
    holder = Node3D.new(position: v3(-6, 0, 0))
    p = AudioPlayer3D.new(noise, loop: true, autoplay: true, max_distance: 50)
    holder.add(p)
    SceneTree.root.add(holder)
    p.playing?.should be_true
    buf = Audio.render(4800)
    rms(buf, 0).should be > rms(buf, 1) * 3
    holder.position = v3(6, 0, 0)
    p.process(0.5_f32)
    p.velocity.should eq v3(24, 0, 0)
    p.voice.not_nil!.spatial.not_nil!.position.should eq v3(6, 0, 0)
    Audio.render(1024)
    buf = Audio.render(4800)
    rms(buf, 1).should be > rms(buf, 0) * 3
    p.doppler = true; p.min_distance = 2; p.attenuation = Attenuation::Linear
    p.process(0.5_f32)
    sp = p.voice.not_nil!.spatial.not_nil!
    sp.doppler?.should be_true
    sp.min_distance.should eq 2
    sp.attenuation.should eq Attenuation::Linear
    holder.free
    Audio.render(1)
    Audio.voice_count.should eq 0
  end
end
