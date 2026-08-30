require "../spec_helper"

describe Eagle::Codecs::WAV do
  it "round-trips 16-bit stereo" do
    samples = Slice(Float32).new(200) { |i| Math.sin(i * 0.1).to_f32 * 0.5_f32 }
    buf = AudioBuffer.new(22050, 2, samples)
    data = Codecs::WAV.encode(buf)
    Codecs::WAV.wav?(data).should be_true
    back = Codecs::WAV.decode(data)
    back.sample_rate.should eq 22050
    back.channels.should eq 2
    back.frames.should eq 100
    200.times { |i| back.samples[i].should be_close(samples[i], 1e-4) }
  end

  it "decodes 8-bit, 24-bit, 32-bit and float formats" do
    le = IO::ByteFormat::LittleEndian
    make = ->(fmt : Int32, bits : Int32, body : Bytes) do
      io = IO::Memory.new
      io.write("RIFF".to_slice); io.write_bytes(0_u32, le); io.write("WAVE".to_slice)
      io.write("fmt ".to_slice); io.write_bytes(16_u32, le); io.write_bytes(fmt.to_u16, le)
      io.write_bytes(1_u16, le); io.write_bytes(8000_u32, le); io.write_bytes((8000 * bits // 8).to_u32, le)
      io.write_bytes((bits // 8).to_u16, le); io.write_bytes(bits.to_u16, le)
      io.write("data".to_slice); io.write_bytes(body.size.to_u32, le); io.write(body)
      io.to_slice
    end
    Codecs::WAV.decode(make.call(1, 8, Bytes[128, 255, 0])).samples.to_a.should eq [0_f32, 127 / 128_f32, -1_f32]
    b24 = Bytes[0, 0, 0x40, 0, 0, 0xC0]
    s24 = Codecs::WAV.decode(make.call(1, 24, b24)).samples
    s24[0].should be_close(0.5, 1e-5); s24[1].should be_close(-0.5, 1e-5)
    b32 = Bytes.new(8); le.encode(1073741824_i32, b32[0, 4]); le.encode(-2147483648_i32, b32[4, 4])
    s32 = Codecs::WAV.decode(make.call(1, 32, b32)).samples
    s32[0].should be_close(0.5, 1e-6); s32[1].should eq -1
    f32 = Bytes.new(4); le.encode(0.25_f32, f32)
    Codecs::WAV.decode(make.call(3, 32, f32)).samples[0].should eq 0.25_f32
    expect_raises(AssetError) { Codecs::WAV.decode(make.call(1, 12, Bytes[0, 0])) }
  end
end

describe Eagle::Sound do
  it "generates tones with the right frequency" do
    s = Sound.tone(440, 0.5, attack: 0, release: 0)
    s.duration.should be_close(0.5, 1e-3)
    buf = s.buffer
    crossings = 0
    (1...buf.frames).each { |i| crossings += 1 if buf.samples[i - 1] < 0 && buf.samples[i] >= 0 }
    crossings.should be_close(220, 2)
    buf.samples.max.should be_close(0.5, 0.01)
    Sound.tone(100, 0.1, Sound::Wave::Square, attack: 0).buffer.samples[10].abs.should be_close(0.5, 0.01)
    Sound.tone(100, 0.1, Sound::Wave::Noise).buffer.samples.size.should eq 4800
  end

  it "applies attack/release envelopes" do
    s = Sound.tone(1000, 0.1, attack: 0.05, release: 0.05, volume: 1)
    s.buffer.samples[0].abs.should be < 0.01
    s.buffer.samples[-1].abs.should be < 0.05
  end

  it "saves and loads" do
    s = Sound.tone(220, 0.05)
    path = File.tempname("eagle", ".wav")
    s.save(path)
    Sound.decode(File.read(path).to_slice).buffer.frames.should eq s.buffer.frames
  end
end

describe Eagle::Audio do
  before_each { Audio.reset }

  it "mixes voices with volume, pan and pitch" do
    s = Sound.generate(1.0) { |t| 0.5_f32 } # constant DC
    v = s.play(volume: 0.5, pan: -1)
    Audio.voice_count.should eq 1
    buf = Audio.render(10)
    buf[0].should be_close(0.25, 1e-4) # left: 0.5 * 0.5 * sqrt(1)
    buf[1].should be_close(0, 1e-4)    # right silent
    v.pan = 0
    buf = Audio.render(10)
    buf[0].should be_close(0.25 * Math.sqrt(0.5), 1e-4)
    v.pitch = 2
    v.position = 0
    Audio.render(24010) # half the frames at double speed consumes the whole sound
    v.finished?.should be_true
    Audio.voice_count.should eq 0
  end

  it "loops and stops" do
    s = Sound.generate(0.01) { |t| 1_f32 } # 480 frames
    v = s.play(loop: true)
    Audio.render(2000)
    v.finished?.should be_false
    v.position.should be < 0.01
    v.stop
    Audio.render(1)
    Audio.voice_count.should eq 0
  end

  it "emits finished and respects buses" do
    s = Sound.generate(0.001) { |t| 1_f32 }
    done = false
    v = s.play(bus: "sfx")
    v.on_finished { done = true }
    Audio.bus("sfx").volume = 0.5
    buf = Audio.render(10)
    buf[0].should be_close(0.5 * Math.sqrt(0.5), 1e-4)
    Audio.render(1000)
    done.should be_true
    Audio.master.muted = true
    s.play
    Audio.render(4)[0].should eq 0
  end

  it "soft clips" do
    s = Sound.generate(0.01) { |t| 1_f32 }
    3.times { s.play(pan: -1) }
    Audio.render(4)[0].should eq 1
  end

  it "fades out" do
    s = Sound.generate(1.0) { |t| 1_f32 }
    v = s.play
    v.fade(0, 0.01)
    Audio.render(1000)
    v.finished?.should be_true
  end

  it "steals voices past the limit" do
    Audio.max_voices = 2
    s = Sound.generate(1.0) { |t| 1_f32 }
    a = s.play; b = s.play; c = s.play
    a.finished?.should be_true
    Audio.voice_count.should eq 2
    Audio.max_voices = 64
  end

  it "runs procedural streams" do
    st = TestStream.new
    Audio.add_stream(st)
    Audio.render(4)[0].should eq 0.25_f32
    st.stop
    Audio.render(4)[0].should eq 0
  end
end

class TestStream < Eagle::AudioStream
  def fill(buf : Slice(Float32), frames : Int32, sample_rate : Int32) : Nil
    frames.times { |i| buf[i * 2] += 0.25_f32; buf[i * 2 + 1] += 0.25_f32 }
  end
end

describe Eagle::AudioPlayer do
  before_each { SceneTree.reset; Audio.reset }

  it "plays on ready with autoplay and stops when leaving the tree" do
    s = Sound.generate(1.0) { |t| 1_f32 }
    p = AudioPlayer.new(s, autoplay: true, volume: 0.5)
    SceneTree.root.add(p)
    p.playing?.should be_true
    Audio.voice_count.should eq 1
    p.free
    Audio.render(1)
    Audio.voice_count.should eq 0
  end

  it "attenuates 2D players by distance" do
    s = Sound.generate(1.0) { |t| 1_f32 }
    p = AudioPlayer2D.new(s, position: v2(400, 0), max_distance: 800)
    SceneTree.root.add(p)
    p.effective_volume.should be_close(0.5, 1e-4)
    p.effective_pan.should be_close(400 / 600.0, 1e-4)
    p.play
    p.process(0.016_f32)
    p.voice.not_nil!.volume.should be_close(0.5, 1e-4)
  end
end
