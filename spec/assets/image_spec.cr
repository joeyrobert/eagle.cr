require "../spec_helper"

FIX = File.join(__DIR__, "..", "fixtures")

describe Eagle::Codecs::PNG do
  it "decodes RGBA8" do
    img = Image.load(File.join(FIX, "rgba.png"))
    img.width.should eq 4
    img.height.should eq 2
    img[0, 0].should eq Color::RED
    img[1, 0].should eq Color::GREEN
    img[2, 0].should eq Color::BLUE
    img[3, 0].should eq Color.rgb(255, 255, 255, 128)
    img[1, 1].should eq Color.rgb(10, 20, 30, 40)
    img[3, 1].should eq Color.rgb(1, 2, 3, 4)
  end

  it "decodes all five filter types" do
    ref = Image.load(File.join(FIX, "rgba.png"))
    Image.load(File.join(FIX, "rgba_filtered.png")).should eq ref
    Image.load(File.join(FIX, "rgba_paeth.png")).should eq ref
  end

  it "decodes RGB, gray, 1-bit gray, palette+tRNS, 16-bit, gray+alpha" do
    rgb = Image.load(File.join(FIX, "rgb.png"))
    rgb[0, 0].should eq Color::RED; rgb[1, 0].should eq Color::BLUE
    gray = Image.load(File.join(FIX, "gray.png"))
    gray[0, 0].should eq Color::BLACK; gray[1, 0].should eq Color::WHITE
    g1 = Image.load(File.join(FIX, "gray1.png"))
    g1[0, 0].should eq Color::WHITE; g1[1, 0].should eq Color::BLACK
    pal = Image.load(File.join(FIX, "pal.png"))
    pal[0, 0].should eq Color.rgb(255, 0, 0, 0)
    pal[1, 0].should eq Color::GREEN; pal[2, 0].should eq Color::BLUE; pal[3, 0].should eq Color::WHITE
    r16 = Image.load(File.join(FIX, "rgba16.png"))
    r16[0, 0].should eq Color.rgb(255, 0, 128, 255)
    ga = Image.load(File.join(FIX, "ga.png"))
    ga[0, 0].should eq Color.rgb(100, 100, 100, 50)
  end

  it "decodes Adam7 interlaced images" do
    img = Image.load(File.join(FIX, "interlaced.png"))
    4.times { |y| 4.times { |x| img[x, y].should eq Color.rgb(x * 60, y * 60, x * y * 10) } }
  end

  it "round-trips through the encoder" do
    img = Image.gradient(37, 23, Color::RED, Color::BLUE)
    img[5, 5] = Color.rgb(1, 2, 3, 4)
    data = Codecs::PNG.encode(img)
    Codecs::PNG.png?(data).should be_true
    Codecs::PNG.decode(data).should eq img
  end

  it "rejects garbage" do
    expect_raises(AssetError) { Image.decode(Bytes[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]) }
  end
end

describe Eagle::Codecs::QOI do
  it "round-trips" do
    img = Image.checkerboard(64, 40, 5, Color::RED, Color.rgb(0, 0, 255, 128))
    img[3, 3] = Color.rgb(12, 34, 56, 78)
    img[10, 3] = Color.rgb(13, 35, 57, 78)
    data = Codecs::QOI.encode(img)
    Codecs::QOI.qoi?(data).should be_true
    Codecs::QOI.decode(data).should eq img
  end

  it "round-trips noisy images" do
    rng = Random.new(42)
    img = Image.new(31, 17)
    17.times { |y| 31.times { |x| img[x, y] = Color.rgb(rng.rand(256), rng.rand(256), rng.rand(256), rng.rand(256)) } }
    Codecs::QOI.decode(Codecs::QOI.encode(img)).should eq img
  end
end

describe Eagle::Codecs::BMP do
  it "round-trips" do
    img = Image.gradient(9, 7, Color::GREEN, Color::MAGENTA, horizontal: true)
    Codecs::BMP.decode(Codecs::BMP.encode(img)).should eq img
  end
end

describe Eagle::Image do
  it "saves and loads files by extension" do
    dir = File.tempname("eagle_img")
    Dir.mkdir(dir)
    img = Image.circle(16, Color::CYAN)
    %w(png qoi bmp).each do |ext|
      path = File.join(dir, "c.#{ext}")
      img.save(path)
      Image.load(path).should eq img
    end
  end

  it "blits, subs, flips, resizes, averages" do
    a = Image.new(4, 4, Color::BLACK)
    b = Image.new(2, 2, Color::WHITE)
    a.blit(b, 1, 1)
    a[1, 1].should eq Color::WHITE
    a[0, 0].should eq Color::BLACK
    a.sub(1, 1, 2, 2).should eq b
    a.average.r.should be_close(0.25, 0.01)
    c = Image.new(2, 2); c[0, 0] = Color::RED; c.flip_vertical!
    c[0, 1].should eq Color::RED
    Image.checkerboard(4, 4, 2).resized(2, 2)[0, 0].should eq Color::WHITE
    Image.checkerboard(4, 4, 2).resized(2, 2)[1, 0].should eq Color.rgb(128, 128, 128)
    a.difference(Image.new(4, 4, Color::BLACK)).should be_close(255 * 4 * 3 / 64.0, 0.01)
  end

  it "alpha blends when blitting" do
    a = Image.new(1, 1, Color::BLACK)
    a.blit(Image.new(1, 1, Color.rgb(255, 255, 255, 128)), 0, 0, blend: true)
    a[0, 0].r.should be_close(0.5, 0.01)
  end
end
