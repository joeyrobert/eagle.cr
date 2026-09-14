require "../spec_helper"
require "compress/zlib"
require "digest/crc32"

describe Eagle::Codecs::Zlib do
  it "round-trips text, binary and repetitive data" do
    inputs = [
      "hello hello hello hello world".to_slice,
      Bytes.new(10000) { |i| (i * 7 % 251).to_u8 },
      Bytes.new(50000, 0_u8),
      Random.new(1).random_bytes(20000),
      Bytes.empty,
      Bytes[1],
    ]
    inputs.each do |data|
      [0, 3, 6, 9].each do |level|
        z = Codecs::Zlib.compress(data, level)
        Codecs::Zlib.decompress(z, data.size).should eq data
      end
    end
    big = Bytes.new(300_000) { |i| ((i // 1000) % 7 + (i % 13)).to_u8 }
    Codecs::Zlib.decompress(Codecs::Zlib.compress(big)).should eq big
    Codecs::Zlib.compress(big).size.should be < big.size // 4
  end

  it "interoperates with the system zlib both ways" do
    data = Bytes.new(40000) { |i| (Math.sin(i / 50.0) * 100 + 128).to_u8 }
    theirs = IO::Memory.new
    Compress::Zlib::Writer.open(theirs) { |w| w.write(data) }
    Codecs::Zlib.decompress(theirs.to_slice).should eq data
    mine = Codecs::Zlib.compress(data)
    back = IO::Memory.new
    Compress::Zlib::Reader.open(IO::Memory.new(mine)) { |r| IO.copy(r, back) }
    back.to_slice.should eq data
  end

  it "computes checksums" do
    Codecs::Zlib.adler32("Wikipedia".to_slice).should eq 0x11E60398
    Codecs::PNG.crc32("The quick brown fox jumps over the lazy dog".to_slice).should eq 0x414FA339
    Codecs::PNG.crc32("abc".to_slice).should eq Digest::CRC32.checksum("abc".to_slice)
  end

  it "rejects corrupt streams" do
    expect_raises(Codecs::Zlib::Error) { Codecs::Zlib.decompress(Bytes[0, 0, 0, 0, 0, 0]) }
    expect_raises(Codecs::Zlib::Error) { Codecs::Zlib.inflate(Bytes[7]) }
  end
end
