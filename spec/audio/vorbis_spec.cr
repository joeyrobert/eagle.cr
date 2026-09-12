require "../spec_helper"

OGG_DIR = File.join(__DIR__, "..", "fixtures", "ogg")

private def reference(name) : Slice(Float32)
  bytes = File.read(File.join(OGG_DIR, "#{name}.f32")).to_slice
  Slice(Float32).new(bytes.size // 4) { |i| IO::ByteFormat::LittleEndian.decode(Float32, bytes[i * 4, 4]) }
end

# Signal-to-noise ratio in dB of `got` against `want` over the overlapping length.
private def snr(want : Slice(Float32), got : Slice(Float32)) : Float64
  n = Math.min(want.size, got.size)
  sig = 0.0; err = 0.0
  n.times { |i| sig += want[i].to_f64 ** 2; err += (want[i] - got[i]).to_f64 ** 2 }
  err == 0 ? 200.0 : 10 * Math.log10(sig / err)
end

describe Eagle::Codecs::Vorbis do
  it "splits Ogg pages into packets and parses headers" do
    data = File.read(File.join(OGG_DIR, "tone_stereo.ogg")).to_slice
    Codecs::Vorbis.ogg?(data).should be_true
    packets, granule = Codecs::Vorbis.packets(data)
    packets.size.should be > 10
    packets[0][0].should eq 1
    packets[1][0].should eq 3
    packets[2][0].should eq 5
    granule.should be_close(44100 * 1.2, 2048)
    dec = Codecs::Vorbis::Decoder.new(packets[0], packets[2])
    dec.channels.should eq 2
    dec.sample_rate.should eq 44100
    dec.blocksizes[0].should be <= dec.blocksizes[1]
  end

  it "fast IMDCT matches the direct transform" do
    [64, 256, 2048].each do |n|
      im = Codecs::Vorbis::IMDCT.new(n)
      rng = Random.new(n)
      x = Slice(Float32).new(n // 2) { rng.rand(-1.0..1.0).to_f32 }
      a = im.naive(x); b = im.run(x)
      snr(a, b).should be > 80
    end
  end

  it "unpacks Vorbis floats and computes lookup sizes" do
    Codecs::Vorbis.float32_unpack(0x62800001_u32).should be_close(1.0, 1e-6) # exponent 788, mantissa 1
    Codecs::Vorbis.float32_unpack(0xE2800001_u32).should be_close(-1.0, 1e-6)
    Codecs::Vorbis.lookup1_values(8, 3).should eq 2
    Codecs::Vorbis.lookup1_values(25, 2).should eq 5
    Codecs::Vorbis.lookup1_values(100, 2).should eq 10
    Codecs::Vorbis.ilog(0).should eq 0
    Codecs::Vorbis.ilog(7).should eq 3
    Codecs::Vorbis.ilog(8).should eq 4
  end

  # libvorbis-encoded fixtures (oggenc): short/long block switching, stereo coupling, mono, 48 kHz.
  {"lib_sweep_stereo" => 2, "lib_sweep_mono" => 1, "lib_noise_stereo" => 2}.each do |name, channels|
    it "decodes #{name} (libvorbis) bit-exact against ffmpeg's decoder" do
      data = File.read(File.join(OGG_DIR, "#{name}.ogg")).to_slice
      buf = Codecs::Vorbis.decode(data)
      want = reference(name)
      buf.channels.should eq channels
      (buf.samples.size - want.size).abs.should be <= 2 * 2048 * channels
      snr(want, buf.samples).should be > 80
      buf.samples.max.should be <= 1.0
    end
  end

  # ffmpeg's experimental built-in encoder: identical-channel streams decode exactly; its
  # coupled stereo residues disagree with the spec/libvorbis interpretation on the angle
  # channel, so only the magnitude channel is asserted there (see docs/plans roadmap).
  {"tone_stereo" => 40.0, "noise_stereo" => 40.0}.each do |name, min_snr|
    it "decodes #{name} (ffmpeg native encoder, SNR > #{min_snr} dB)" do
      buf = Codecs::Vorbis.decode(File.read(File.join(OGG_DIR, "#{name}.ogg")).to_slice)
      snr(reference(name), buf.samples).should be > min_snr
    end
  end

  it "decodes the ffmpeg-native stereo sweep's magnitude channel" do
    buf = Codecs::Vorbis.decode(File.read(File.join(OGG_DIR, "sweep_stereo.ogg")).to_slice)
    want = reference("sweep_stereo")
    n = Math.min(want.size, buf.samples.size) // 2
    left_want = Slice(Float32).new(n) { |i| want[i * 2] }
    left_got = Slice(Float32).new(n) { |i| buf.samples[i * 2] }
    snr(left_want, left_got).should be > 60
  end

  it "decodes a second of stereo audio quickly" do
    data = File.read(File.join(OGG_DIR, "tone_stereo.ogg")).to_slice
    t = Time.instant
    Codecs::Vorbis.decode(data)
    (Time.instant - t).total_seconds.should be < 2.0 # debug build; ~5 ms in release
  end

  it "loads through Sound and rejects garbage" do
    s = Sound.decode(File.read(File.join(OGG_DIR, "lib_sweep_mono.ogg")).to_slice, "sweep.ogg")
    s.duration.should be_close(0.8, 0.05)
    s.buffer.sample_rate.should eq 22050
    s.buffer.channels.should eq 1
    s2 = Sound.decode(File.read(File.join(OGG_DIR, "tone_stereo.ogg")).to_slice, "tone.ogg")
    s2.duration.should be_close(1.2, 0.1)
    expect_raises(AssetError) { Sound.decode(Bytes[1, 2, 3, 4, 5, 6, 7, 8]) }
  end
end
