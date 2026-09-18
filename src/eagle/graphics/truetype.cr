module Eagle
  # A TrueType font file, parsed in pure Crystal: glyph lookup, metrics, kerning and outlines.
  #
  # Most games use `Font.load`, which wraps this in a `TrueTypeFont`. Use `TrueType`
  # directly for tools, such as inspecting a font or rasterizing glyphs into your own atlas.
  #
  # ```
  # ttf = TrueType.load("res://fonts/Inter.ttf")
  # g_index = ttf.glyph_index('A')
  # bitmap = ttf.rasterize(g_index, 32.0_f32 / ttf.units_per_em)
  # image = bitmap.to_image
  # ```
  #
  # Supports `glyf` outlines, cmap formats 4, 6 and 12, composite glyphs and `kern` table
  # format 0. OpenType CFF fonts (.otf) aren't supported.
  class TrueType
    # :nodoc:
    struct Point
      getter x : Float32
      getter y : Float32
      getter? on_curve : Bool
      def initialize(@x, @y, @on_curve); end
    end

    # A glyph's contours in font units, with its bounding box.
    record GlyphOutline, contours : Array(Array(Point)), xmin : Int32, ymin : Int32, xmax : Int32, ymax : Int32 do
      def empty? : Bool; contours.empty?; end
    end

    # :nodoc:
    record HMetric, advance : Int32, lsb : Int32

    # Font units per em. Multiply by `pixel_size / units_per_em` to convert to pixels.
    getter units_per_em : Int32
    # Height above the baseline, in font units.
    getter ascent : Int32
    # Depth below the baseline, in font units (negative).
    getter descent : Int32
    # Extra gap between lines, in font units.
    getter line_gap : Int32
    # Number of glyphs in the font.
    getter glyph_count : Int32
    # The family name from the font's name table, such as "Inter".
    getter family_name : String = ""

    @data : Bytes
    @tables = {} of String => {Int32, Int32}
    @loca = [] of Int32
    @glyf_offset = 0
    @glyf_length = 0
    @cmap = {} of Int32 => Int32
    @hmtx = [] of HMetric
    @kern = {} of {Int32, Int32} => Int32
    @outline_cache = {} of Int32 => GlyphOutline

    # Parses a font from raw bytes. Raises `AssetError` if it isn't a supported TrueType file.
    def initialize(@data : Bytes)
      parse_directory
      head = table!("head")
      @units_per_em = u16(head + 18).to_i
      index_to_loc = i16(head + 50)
      maxp = table!("maxp")
      @glyph_count = u16(maxp + 4).to_i
      hhea = table!("hhea")
      @ascent = i16(hhea + 4).to_i
      @descent = i16(hhea + 6).to_i
      @line_gap = i16(hhea + 8).to_i
      num_hmetrics = u16(hhea + 34).to_i
      raise AssetError.new("TrueType font has no glyf table (CFF/OpenType outlines are not supported)") unless @tables["glyf"]?
      loca = table!("loca")
      (@glyph_count + 1).times do |i|
        @loca << (index_to_loc == 0 ? u16(loca + i * 2).to_i * 2 : u32(loca + i * 4).to_i)
      end
      @glyf_offset, @glyf_length = @tables["glyf"]
      hmtx = table!("hmtx")
      num_hmetrics.times { |i| @hmtx << HMetric.new(u16(hmtx + i * 4).to_i, i16(hmtx + i * 4 + 2).to_i) }
      parse_cmap
      parse_kern
      parse_name
    end

    # Reads and parses a font file.
    def self.load(path : String) : TrueType
      new(File.read(path).to_slice)
    end

    # --- binary helpers ---
    private def u8(o) : UInt8; @data[o]; end
    private def u16(o) : UInt16; (@data[o].to_u16 << 8) | @data[o + 1]; end
    private def i16(o) : Int16; u16(o).to_i16!; end
    private def u32(o) : UInt32; (u16(o).to_u32 << 16) | u16(o + 2); end

    private def table!(name) : Int32
      (@tables[name]? || raise AssetError.new("TrueType font missing table #{name}"))[0]
    end

    private def parse_directory
      tag = u32(0)
      offset = 0
      if tag == 0x74746366 # 'ttcf' collection: use first font
        offset = u32(12).to_i
      end
      num_tables = u16(offset + 4).to_i
      num_tables.times do |i|
        rec = offset + 12 + i * 16
        name = String.new(@data[rec, 4])
        @tables[name] = {u32(rec + 8).to_i, u32(rec + 12).to_i}
      end
    end

    private def parse_cmap
      cmap = table!("cmap")
      n = u16(cmap + 2).to_i
      best : Int32? = nil
      best_score = -1
      n.times do |i|
        rec = cmap + 4 + i * 8
        platform = u16(rec).to_i; encoding = u16(rec + 2).to_i
        off = u32(rec + 4).to_i
        score = case {platform, encoding}
                when {3, 10} then 4
                when {0, 4}, {0, 6} then 3
                when {3, 1} then 2
                when {0, 3}, {0, 2}, {0, 1}, {0, 0} then 1
                else 0
                end
        if score > best_score
          best_score = score; best = cmap + off
        end
      end
      raise AssetError.new("No usable cmap subtable") unless best
      parse_cmap_subtable(best)
    end

    private def parse_cmap_subtable(o)
      case u16(o)
      when 0
        256.times { |c| g = u8(o + 6 + c).to_i; @cmap[c] = g if g != 0 }
      when 4
        segx2 = u16(o + 6).to_i
        segs = segx2 // 2
        ends = o + 14; starts = ends + segx2 + 2; deltas = starts + segx2; ranges = deltas + segx2
        segs.times do |s|
          e = u16(ends + s * 2).to_i; st = u16(starts + s * 2).to_i
          d = u16(deltas + s * 2).to_i; ro = u16(ranges + s * 2).to_i
          next if st > e
          (st..e).each do |c|
            next if c == 0xFFFF
            g = if ro == 0
                  (c + d) & 0xFFFF
                else
                  addr = ranges + s * 2 + ro + (c - st) * 2
                  next if addr + 1 >= @data.size
                  gi = u16(addr).to_i
                  gi == 0 ? 0 : (gi + d) & 0xFFFF
                end
            @cmap[c] = g if g != 0
          end
        end
      when 6
        first = u16(o + 6).to_i; count = u16(o + 8).to_i
        count.times { |i| g = u16(o + 10 + i * 2).to_i; @cmap[first + i] = g if g != 0 }
      when 12
        ngroups = u32(o + 12).to_i
        ngroups.times do |i|
          g = o + 16 + i * 12
          sc = u32(g).to_i; ec = u32(g + 4).to_i; sg = u32(g + 8).to_i
          next if ec - sc > 65536
          (sc..ec).each { |c| @cmap[c] = sg + (c - sc) }
        end
      else
        raise AssetError.new("Unsupported cmap format #{u16(o)}")
      end
    end

    private def parse_kern
      return unless (t = @tables["kern"]?)
      o = t[0]
      version = u16(o)
      return unless version == 0
      ntables = u16(o + 2).to_i
      p = o + 4
      ntables.times do
        length = u16(p + 2).to_i
        coverage = u16(p + 4)
        if coverage & 0xFF == 0 # format 0, horizontal
          npairs = u16(p + 6).to_i
          q = p + 14
          npairs.times do |i|
            l = u16(q + i * 6).to_i; r = u16(q + i * 6 + 2).to_i; v = i16(q + i * 6 + 4).to_i
            @kern[{l, r}] = v
          end
        end
        p += length
      end
    end

    private def parse_name
      return unless (t = @tables["name"]?)
      o = t[0]
      count = u16(o + 2).to_i
      strings = o + u16(o + 4).to_i
      count.times do |i|
        rec = o + 6 + i * 12
        platform = u16(rec).to_i; name_id = u16(rec + 6).to_i
        len = u16(rec + 8).to_i; off = u16(rec + 10).to_i
        next unless name_id == 1
        bytes = @data[strings + off, len]
        if platform == 1
          @family_name = String.new(bytes)
          break
        elsif platform == 3 || platform == 0
          @family_name = String.build { |io| (len // 2).times { |k| io << ((bytes[k * 2].to_i << 8) | bytes[k * 2 + 1]).chr } }
        end
      end
    rescue
      @family_name = ""
    end

    # --- public metrics ---
    # The glyph index for *char*, or 0 (the missing-glyph box) if the font lacks it.
    def glyph_index(char : Char) : Int32
      @cmap[char.ord]? || 0
    end

    # True when the font has a glyph for *char*.
    def has_glyph?(char : Char) : Bool
      @cmap.has_key?(char.ord)
    end

    # Horizontal advance of a glyph, in font units.
    def advance(glyph : Int32) : Int32
      return 0 if @hmtx.empty?
      (@hmtx[glyph]? || @hmtx.last).advance
    end

    # Left side bearing of a glyph, in font units.
    def left_side_bearing(glyph : Int32) : Int32
      return 0 if @hmtx.empty?
      (@hmtx[glyph]? || @hmtx.last).lsb
    end

    # Kerning between two glyph indices, in font units.
    def kerning(left : Int32, right : Int32) : Int32
      @kern[{left, right}]? || 0
    end

    # Number of kerning pairs in the font.
    def kern_pairs : Int32; @kern.size; end

    # --- outlines ---
    # The contours of a glyph.
    def outline(glyph : Int32) : GlyphOutline
      @outline_cache[glyph] ||= read_outline(glyph, 0)
    end

    private def read_outline(glyph : Int32, depth : Int32) : GlyphOutline
      empty = GlyphOutline.new([] of Array(Point), 0, 0, 0, 0)
      return empty if glyph < 0 || glyph + 1 >= @loca.size || depth > 8
      start = @loca[glyph]; finish = @loca[glyph + 1]
      return empty if finish <= start
      o = @glyf_offset + start
      ncont = i16(o).to_i
      xmin = i16(o + 2).to_i; ymin = i16(o + 4).to_i; xmax = i16(o + 6).to_i; ymax = i16(o + 8).to_i
      if ncont >= 0
        read_simple(o, ncont, xmin, ymin, xmax, ymax)
      else
        read_composite(o, depth, xmin, ymin, xmax, ymax)
      end
    end

    private def read_simple(o, ncont, xmin, ymin, xmax, ymax) : GlyphOutline
      end_pts = Array(Int32).new(ncont) { |i| u16(o + 10 + i * 2).to_i }
      npts = ncont == 0 ? 0 : end_pts.last + 1
      p = o + 10 + ncont * 2
      instr_len = u16(p).to_i
      p += 2 + instr_len
      flags = Array(UInt8).new(npts, 0_u8)
      i = 0
      while i < npts
        f = u8(p); p += 1
        flags[i] = f; i += 1
        if f & 8 != 0
          rep = u8(p); p += 1
          rep.times { break if i >= npts; flags[i] = f; i += 1 }
        end
      end
      xs = Array(Int32).new(npts, 0); ys = Array(Int32).new(npts, 0)
      v = 0
      npts.times do |k|
        f = flags[k]
        if f & 2 != 0
          d = u8(p).to_i; p += 1
          v += (f & 16 != 0) ? d : -d
        elsif f & 16 == 0
          v += i16(p).to_i; p += 2
        end
        xs[k] = v
      end
      v = 0
      npts.times do |k|
        f = flags[k]
        if f & 4 != 0
          d = u8(p).to_i; p += 1
          v += (f & 32 != 0) ? d : -d
        elsif f & 32 == 0
          v += i16(p).to_i; p += 2
        end
        ys[k] = v
      end
      contours = [] of Array(Point)
      s = 0
      end_pts.each do |e|
        pts = [] of Point
        (s..e).each { |k| pts << Point.new(xs[k].to_f32, ys[k].to_f32, flags[k] & 1 != 0) }
        contours << pts unless pts.empty?
        s = e + 1
      end
      GlyphOutline.new(contours, xmin, ymin, xmax, ymax)
    end

    private def read_composite(o, depth, xmin, ymin, xmax, ymax) : GlyphOutline
      p = o + 10
      contours = [] of Array(Point)
      loop do
        flags = u16(p); gi = u16(p + 2).to_i; p += 4
        dx = 0_f32; dy = 0_f32
        if flags & 1 != 0
          if flags & 2 != 0
            dx = i16(p).to_f32; dy = i16(p + 2).to_f32
          end
          p += 4
        else
          if flags & 2 != 0
            dx = @data[p].to_i8!.to_f32; dy = @data[p + 1].to_i8!.to_f32
          end
          p += 2
        end
        a = 1_f32; b = 0_f32; c = 0_f32; d = 1_f32
        if flags & 8 != 0
          a = d = f2dot14(p); p += 2
        elsif flags & 0x40 != 0
          a = f2dot14(p); d = f2dot14(p + 2); p += 4
        elsif flags & 0x80 != 0
          a = f2dot14(p); b = f2dot14(p + 2); c = f2dot14(p + 4); d = f2dot14(p + 6); p += 8
        end
        sub = read_outline(gi, depth + 1)
        sub.contours.each do |cont|
          contours << cont.map { |pt| Point.new(a * pt.x + c * pt.y + dx, b * pt.x + d * pt.y + dy, pt.on_curve?) }
        end
        break if flags & 0x20 == 0
      end
      GlyphOutline.new(contours, xmin, ymin, xmax, ymax)
    end

    private def f2dot14(o) : Float32
      i16(o).to_f32 / 16384_f32
    end

    # --- rasterising ---
    # A rasterized glyph: coverage values from 0 to 1, plus its offset from the pen position.
    record Bitmap, width : Int32, height : Int32, coverage : Slice(Float32), left : Int32, top : Int32 do
      # Converts to a white RGBA image whose alpha is the coverage.
      def to_image : Image
        img = Image.new(width, height)
        px = img.pixels
        coverage.each_with_index do |c, i|
          a = (c.clamp(0_f32, 1_f32) * 255).round.to_u8
          px[i * 4] = 255_u8; px[i * 4 + 1] = 255_u8; px[i * 4 + 2] = 255_u8; px[i * 4 + 3] = a
        end
        img
      end
    end

    # Rasterizes a glyph with anti-aliasing. *scale* is pixels per font unit.
    def rasterize(glyph : Int32, scale : Float32, pad : Int32 = 1) : Bitmap
      out_ = outline(glyph)
      if out_.empty?
        return Bitmap.new(0, 0, Slice(Float32).new(0), 0, 0)
      end
      x0 = (out_.xmin * scale).floor.to_i - pad
      y0 = (out_.ymin * scale).floor.to_i - pad
      x1 = (out_.xmax * scale).ceil.to_i + pad
      y1 = (out_.ymax * scale).ceil.to_i + pad
      w = x1 - x0; h = y1 - y0
      return Bitmap.new(0, 0, Slice(Float32).new(0), 0, 0) if w <= 0 || h <= 0
      acc = Accumulator.new(w, h)
      out_.contours.each do |contour|
        pts = expand_contour(contour)
        next if pts.size < 2
        # emit segments; pts are (on, off, on, off...) with implied on-points expanded
        i = 0
        n = pts.size
        while i < n
          p0 = pts[i]
          p1 = pts[(i + 1) % n]
          if p1.on_curve?
            acc.line(tx(p0, x0, y1, scale), tx(p1, x0, y1, scale))
            i += 1
          else
            p2 = pts[(i + 2) % n]
            acc.quad(tx(p0, x0, y1, scale), tx(p1, x0, y1, scale), tx(p2, x0, y1, scale))
            i += 2
          end
        end
      end
      Bitmap.new(w, h, acc.finish, x0, y1)
    end

    # Insert implied on-curve midpoints so the contour alternates cleanly and starts on-curve.
    private def expand_contour(c : Array(Point)) : Array(Point)
      return c if c.empty?
      pts = [] of Point
      n = c.size
      # rotate to start on an on-curve point (or synthesise one)
      start = c.index(&.on_curve?)
      if start
        ordered = c[start..] + c[...start]
      else
        mid = Point.new((c[0].x + c[1 % n].x) / 2, (c[0].y + c[1 % n].y) / 2, true)
        ordered = [mid] + c[1..] + [c[0]]
      end
      ordered.each_with_index do |p, i|
        if i > 0 && !p.on_curve? && !pts.last.on_curve?
          prev = pts.last
          pts << Point.new((prev.x + p.x) / 2, (prev.y + p.y) / 2, true)
        end
        pts << p
      end
      # close: if last is off-curve and first is on-curve, fine; if last off and first off (impossible after rotation)
      pts
    end

    @[AlwaysInline]
    private def tx(p : Point, x0 : Int32, y1 : Int32, scale : Float32) : {Float32, Float32}
      {p.x * scale - x0, y1 - p.y * scale}
    end

    # :nodoc:
    class Accumulator
      @w : Int32
      @h : Int32
      @a : Slice(Float32)

      def initialize(@w, @h)
        @a = Slice(Float32).new((@w + 2) * (@h + 1) + 4, 0_f32)
      end

      def quad(p0 : {Float32, Float32}, p1 : {Float32, Float32}, p2 : {Float32, Float32})
        dx = (p0[0] - 2 * p1[0] + p2[0]).abs + (p0[1] - 2 * p1[1] + p2[1]).abs
        n = Math.max(1, Math.min(32, (Math.sqrt(dx * 2)).ceil.to_i))
        prev = p0
        (1..n).each do |i|
          t = i / n.to_f32
          mt = 1 - t
          x = mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0]
          y = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
          line(prev, {x, y})
          prev = {x, y}
        end
      end

      def line(p0 : {Float32, Float32}, p1 : {Float32, Float32})
        return if (p0[1] - p1[1]).abs <= 1e-6
        dir = 1_f32
        if p0[1] > p1[1]
          p0, p1 = p1, p0
          dir = -1_f32
        end
        stride = @w + 2
        dxdy = (p1[0] - p0[0]) / (p1[1] - p0[1])
        x = p0[0]
        y0 = p0[1] < 0 ? 0 : p0[1].to_i
        x -= p0[1] * dxdy if p0[1] < 0
        y_end = Math.min(@h, p1[1].ceil.to_i)
        y = y0
        while y < y_end
          linestart = y * stride
          dy = Math.min((y + 1).to_f32, p1[1]) - Math.max(y.to_f32, p0[1])
          xnext = x + dxdy * dy
          d = dy * dir
          x0, x1 = x < xnext ? {x, xnext} : {xnext, x}
          x0floor = x0.floor
          x0i = x0floor.to_i
          x1ceil = x1.ceil
          x1i = x1ceil.to_i
          if x1i <= x0i + 1
            xmf = 0.5_f32 * (x + xnext) - x0floor
            add(linestart + x0i + 1, d - d * xmf)
            add(linestart + x0i + 2, d * xmf)
          else
            s = 1 / (x1 - x0)
            x0f = x0 - x0floor
            a0 = 0.5_f32 * s * (1 - x0f) * (1 - x0f)
            x1f = x1 - x1ceil + 1
            am = 0.5_f32 * s * x1f * x1f
            add(linestart + x0i + 1, d * a0)
            if x1i == x0i + 2
              add(linestart + x0i + 2, d * (1 - a0 - am))
            else
              a1 = s * (1.5_f32 - x0f)
              add(linestart + x0i + 2, d * (a1 - a0))
              xi = x0i + 2
              while xi < x1i - 1
                add(linestart + xi + 1, d * s)
                xi += 1
              end
              a2 = a1 + (x1i - x0i - 3) * s
              add(linestart + x1i, d * (1 - a2 - am))
            end
            add(linestart + x1i + 1, d * am)
          end
          x = xnext
          y += 1
        end
      end

      @[AlwaysInline]
      private def add(i : Int32, v : Float32)
        @a[i] += v if i >= 0 && i < @a.size
      end

      def finish : Slice(Float32)
        out_ = Slice(Float32).new(@w * @h, 0_f32)
        stride = @w + 2
        @h.times do |y|
          acc = 0_f32
          stride.times do |x|
            acc += @a[y * stride + x]
            if x >= 1 && x <= @w
              v = acc.abs
              out_[y * @w + x - 1] = v > 1 ? 1_f32 : v
            end
          end
        end
        out_
      end
    end
  end

  # A `Font` backed by a TrueType file at one pixel size. Glyphs are rasterized on first use.
  # Create one with `Font.load`, which also caches it.
  #
  # ```
  # font = Font.load("res://fonts/Inter.ttf", 24)
  # g.print("Hello", 10, 10, font: font)
  # ```
  class TrueTypeFont < Font
    # The parsed font file.
    getter ttf : TrueType
    # Pixel size the font was loaded at.
    getter size : Float32
    # Distance between baselines, in pixels.
    getter line_height : Float32
    # Height above the baseline, in pixels.
    getter ascent : Float32
    # Depth below the baseline, in pixels.
    getter descent : Float32
    @scale_factor : Float32
    @glyphs = {} of Char => Glyph?
    @atlases = [] of Atlas
    @filter : GPU::Filter

    # :nodoc:
    ATLAS_SIZE = 1024

    private class Atlas
      getter texture : Texture
      getter image : Image
      @x = 0
      @y = 0
      @row_h = 0
      @dirty = false

      def initialize(size : Int32, filter : GPU::Filter)
        @image = Image.new(size, size)
        @texture = Texture.new(@image, filter)
      end

      # Returns the rect where `img` was placed, or nil if full.
      def place(img : Image) : Rect?
        pad = 1
        if @x + img.width + pad > @image.width
          @x = 0
          @y += @row_h + pad
          @row_h = 0
        end
        return nil if @y + img.height + pad > @image.height
        @image.blit(img, @x, @y)
        r = Rect.new(@x, @y, img.width, img.height)
        @x += img.width + pad
        @row_h = Math.max(@row_h, img.height)
        @dirty = true
        r
      end

      def flush : Nil
        return unless @dirty
        @texture.update(@image)
        @dirty = false
      end
    end

    # Creates a font from raw TrueType bytes at *size* pixels.
    def initialize(data : Bytes, size : Number, filter : GPU::Filter = GPU::Filter::Linear)
      @ttf = TrueType.new(data)
      @size = size.to_f32
      @filter = filter
      @scale_factor = @size / @ttf.units_per_em
      @ascent = @ttf.ascent * @scale_factor
      @descent = @ttf.descent * @scale_factor
      @line_height = (@ttf.ascent - @ttf.descent + @ttf.line_gap) * @scale_factor
    end

    # Loads a font file at *size* pixels, without caching. Prefer `Font.load`.
    def self.load(path : String, size : Number, filter : GPU::Filter = GPU::Filter::Linear) : TrueTypeFont
      new(Assets.read_bytes(path), size, filter)
    end

    # The first atlas texture.
    def texture : Texture
      @atlases.first?.try(&.texture) || Texture.white
    end

    # The font's family name.
    def family_name : String; @ttf.family_name; end

    # Kerning between two characters, in pixels.
    def kerning(a : Char, b : Char) : Float32
      @ttf.kerning(@ttf.glyph_index(a), @ttf.glyph_index(b)) * @scale_factor
    end

    # The glyph for *char*, rasterizing it on first use. Returns `nil` if the font lacks it.
    def glyph(char : Char) : Glyph?
      return @glyphs[char] if @glyphs.has_key?(char)
      g = build_glyph(char)
      @glyphs[char] = g
      g
    end

    # Rasterizes glyphs up front so the first frame that uses them doesn't hitch. Covers printable ASCII by default.
    def preload(chars : Enumerable(Char) = (32..126).map(&.chr)) : self
      chars.each { |c| glyph(c) }
      self
    end

    private def build_glyph(char : Char) : Glyph?
      gi = @ttf.glyph_index(char)
      gi = @ttf.glyph_index('?') if gi == 0 && char != '?' && char != ' '
      advance = @ttf.advance(gi) * @scale_factor
      bmp = @ttf.rasterize(gi, @scale_factor)
      if bmp.width == 0 || bmp.height == 0
        # whitespace: an empty region with an advance
        return Glyph.new(TextureRegion.new(atlas_for(1, 1).texture, Rect.new(0, 0, 0, 0)), advance)
      end
      img = bmp.to_image
      atlas = atlas_for(img.width, img.height)
      rect = atlas.place(img)
      unless rect
        atlas = new_atlas
        rect = atlas.place(img) || raise Error.new("Glyph too large for atlas")
      end
      atlas.flush
      # offset: left bearing and baseline. Pen y is the top of the line; baseline = ascent.
      offset = Vec2.new(bmp.left, @ascent - bmp.top)
      Glyph.new(atlas.texture.region(rect), advance, offset)
    end

    private def atlas_for(w, h) : Atlas
      @atlases.last? || new_atlas
    end

    private def new_atlas : Atlas
      a = Atlas.new(ATLAS_SIZE, @filter)
      @atlases << a
      a
    end
  end

  class Font
    # Loads a TrueType font at a pixel size. Cached by path and size, so calling it every frame is cheap.
    def self.load(path : String, size : Number, filter : GPU::Filter = GPU::Filter::Linear) : Font
      Assets.font(path, size)
    end
  end
end
