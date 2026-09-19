module Eagle
  # A seedable random number generator (PCG32) that produces the same sequence on every
  # platform, including WebAssembly.
  #
  # Use it for anything that must be reproducible from a seed: procedural levels, loot
  # tables, replays, daily challenges and specs. Crystal's `Random` is fine for throwaway
  # randomness, but its algorithms may change between compiler versions, while `Rng` is
  # implemented here and will not.
  #
  # `Rng` includes Crystal's `Random` module, so `array.shuffle(rng)`, `array.sample(rng)`
  # and `rng.rand(10)` also work.
  #
  # ```
  # rng = Rng.new(1234)
  # rng.float         # 0.0...1.0
  # rng.float(-5, 5)  # -5.0..5.0
  # rng.int(1, 6)     # 1..6, both ends included
  # rng.chance?(0.25) # true about a quarter of the time
  # rng.pick(["sword", "shield", "potion"])
  # rng.weighted({"common" => 70, "rare" => 25, "epic" => 5})
  # rng.roll("3d6+2") # 5..20
  # rng.gaussian(100, 15)
  # spawn = rng.in_circle(50) + v2(400, 300)
  # ```
  class Rng
    include ::Random

    # The seed this generator started from.
    getter seed : UInt64
    @state : UInt64 = 0_u64
    @inc : UInt64 = 0_u64

    # Creates a generator from *seed*. Different *stream* values give independent
    # sequences for the same seed. Without a seed it starts somewhere unpredictable.
    def initialize(seed : Int = ::Random.rand(UInt32::MAX), stream : Int = 54)
      @seed = seed.to_u64!
      reseed(@seed, stream)
    end

    # Restarts the sequence from *seed*, as if the generator were newly created.
    def reseed(seed : Int, stream : Int = 54) : Nil
      @seed = seed.to_u64!
      @state = 0_u64
      @inc = (stream.to_u64! << 1) | 1_u64
      next_u
      @state = @state &+ @seed
      next_u
    end

    # The next raw 32-bit value. Every other method is built on this.
    def next_u : UInt32
      old = @state
      @state = old &* 6364136223846793005_u64 &+ @inc
      xorshifted = (((old >> 18) ^ old) >> 27).to_u32!
      rot = (old >> 59).to_u32!
      (xorshifted >> rot) | (xorshifted << ((0_u32 &- rot) & 31))
    end

    # A new generator seeded from this one, for giving a subsystem its own stream
    # without disturbing this one by more than three steps.
    def fork : Rng
      Rng.new((next_u.to_u64 << 32) | next_u, next_u)
    end

    # A uniformly distributed integer in `0...n`, without modulo bias.
    def below(n : Int) : Int32
      raise ArgumentError.new("below needs a positive bound, got #{n}") if n <= 0
      bound = n.to_u32
      threshold = (0_u32 &- bound) % bound
      loop do
        r = next_u
        return (r % bound).to_i32 if r >= threshold
      end
    end

    # A float in `0.0...1.0` (never exactly 1).
    def float : Float32
      (next_u >> 8).to_f32 * (1.0_f32 / 16777216)
    end

    # A float between *lo* and *hi*.
    def float(lo : Number, hi : Number) : Float32
      (lo + (hi - lo) * float.to_f64).to_f32
    end

    # A float in `0.0...1.0` with 53 bits of precision, for when `Float32` is too coarse.
    def float64 : Float64
      a = (next_u >> 5).to_u64; b = (next_u >> 6).to_u64
      (a * 67108864 + b).to_f64 * (1.0 / 9007199254740992.0)
    end

    # An integer between *lo* and *hi*, both included.
    def int(lo : Int, hi : Int) : Int32
      lo, hi = hi, lo if hi < lo
      (lo.to_i64 + below(hi.to_i64 - lo.to_i64 + 1)).to_i32
    end

    # An integer from *range*, honouring exclusive ends (`0...10` never returns 10).
    def int(range : Range(Int, Int)) : Int32
      hi = range.exclusive? ? range.end - 1 : range.end
      int(range.begin, hi)
    end

    # True with probability *p* (0 never, 1 always).
    def chance?(p : Number) : Bool
      float < p
    end

    # True or false with equal probability.
    def bool : Bool
      next_u & 1 == 1
    end

    # -1 or 1 with equal probability.
    def sign : Int32
      bool ? 1 : -1
    end

    # A random element of *items*. Raises on an empty collection.
    def pick(items : Indexable(T)) : T forall T
      raise ArgumentError.new("pick from an empty collection") if items.empty?
      items[below(items.size)]
    end

    # A random element of *items*, or `nil` when it is empty.
    def pick?(items : Indexable(T)) : T? forall T
      items.empty? ? nil : items[below(items.size)]
    end

    # An index into *weights* chosen with probability proportional to its weight.
    # Zero and negative weights are never chosen.
    def weighted_index(weights : Indexable(Number)) : Int32
      total = 0.0
      weights.each { |w| total += w if w > 0 }
      raise ArgumentError.new("weighted pick needs a positive weight") if total <= 0
      r = float64 * total
      last = 0
      weights.each_with_index do |w, i|
        next unless w > 0
        last = i
        r -= w
        return i if r < 0
      end
      last
    end

    # An element of *items* chosen with probability proportional to the matching entry in *weights*.
    def weighted(items : Indexable(T), weights : Indexable(Number)) : T forall T
      raise ArgumentError.new("items and weights differ in size") unless items.size == weights.size
      items[weighted_index(weights)]
    end

    # A key of *table* chosen with probability proportional to its value, as in a loot table.
    #
    # ```
    # rng = Rng.new(7)
    # rarity = rng.weighted({:common => 70, :rare => 25, :epic => 5})
    # ```
    def weighted(table : Hash(K, V)) : K forall K, V
      table.keys[weighted_index(table.values)]
    end

    # Shuffles *array* in place (Fisher-Yates) and returns it.
    def shuffle!(array : Array(T)) : Array(T) forall T
      (array.size - 1).downto(1) do |i|
        array.swap(i, below(i + 1))
      end
      array
    end

    # A shuffled copy of *items*.
    def shuffle(items : Enumerable(T)) : Array(T) forall T
      shuffle!(items.to_a)
    end

    # Rolls dice written in the usual notation: `"d20"`, `"3d6+2"`, `"2d8-1"`, `"4d6kh3"`
    # (keep the highest 3), `"1d6+1d4"`. See `Dice`.
    def roll(notation : String) : Int32
      Dice.parse(notation).roll(self)
    end

    # A normally distributed value (Box-Muller). About 68% of results fall within one
    # *stddev* of *mean* and 95% within two.
    def gaussian(mean : Number = 0, stddev : Number = 1) : Float32
      u1 = 1.0 - float64 # (0, 1], keeps the log finite
      u2 = float64
      z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
      (mean + z * stddev).to_f32
    end

    # A random angle in radians, `0...TAU`.
    def angle : Float32
      float * Mathf::TAU
    end

    # A random unit vector in 2D.
    def direction : Vec2
      Vec2.from_angle(angle)
    end

    # A random unit vector in 3D, uniformly distributed over the sphere.
    def direction3 : Vec3
      z = float(-1, 1)
      a = angle
      r = Math.sqrt(Math.max(0_f32, 1 - z * z))
      Vec3.new(r * Math.cos(a), r * Math.sin(a), z)
    end

    # A uniformly distributed point inside a circle of *radius* around the origin.
    def in_circle(radius : Number = 1) : Vec2
      Vec2.from_angle(angle, Math.sqrt(float) * radius)
    end

    # A uniformly distributed point inside *rect*.
    def in_rect(rect : Rect) : Vec2
      Vec2.new(rect.x + float * rect.w, rect.y + float * rect.h)
    end
  end

  # A parsed dice expression such as `"3d6+2"`, which you can roll many times.
  #
  # The notation is a sum of terms. A term is `NdS` (N dice with S sides, N defaults to 1,
  # `d%` means a hundred sides), optionally followed by `khK` or `klK` to keep only the
  # highest or lowest K dice, or a plain integer. Terms join with `+` or `-`, and spaces
  # are ignored. Invalid notation raises `ArgumentError`.
  #
  # Use `Rng#roll` for one-off rolls. Parse once with `Dice.parse` when you roll the same
  # expression every turn, or want to show its range.
  #
  # ```
  # fireball = Dice.parse("8d6")
  # fireball.min     # => 8
  # fireball.max     # => 48
  # fireball.average # => 28.0
  # damage = fireball.roll(Rng.new(99))
  #
  # stats = Dice.parse("4d6kh3") # classic ability score roll
  # ```
  struct Dice
    # One term of a dice expression: *count* dice with *sides* sides (0 sides means the
    # constant *count*), *sign* +1 or -1, and *keep*: positive keeps that many highest dice,
    # negative that many lowest, 0 keeps all.
    record Term, count : Int32, sides : Int32, sign : Int32, keep : Int32

    # The terms, in the order written.
    getter terms : Array(Term)

    # Creates dice from already-parsed terms. Most code uses `Dice.parse`.
    def initialize(@terms : Array(Term)); end

    # Parses *notation*, raising `ArgumentError` when it is malformed.
    def self.parse(notation : String) : Dice
      s = notation.delete(' ').downcase
      bad = -> { ArgumentError.new("bad dice notation #{notation.inspect}") }
      raise bad.call if s.empty?
      terms = [] of Term
      i = 0
      sign = 1
      expect_term = true
      while i < s.size
        c = s[i]
        if c == '+' || c == '-'
          raise bad.call if expect_term && !(terms.empty? && sign == 1)
          sign = c == '-' ? -1 : 1
          i += 1
          expect_term = true
          next
        end
        raise bad.call unless expect_term
        count, i2 = read_int(s, i)
        if i2 < s.size && s[i2] == 'd'
          i = i2 + 1
          count ||= 1
          if i < s.size && s[i] == '%'
            sides = 100
            i += 1
          else
            sides, i = read_int(s, i)
            raise bad.call unless sides
          end
          keep = 0
          if i + 1 < s.size && s[i] == 'k' && (s[i + 1] == 'h' || s[i + 1] == 'l')
            high = s[i + 1] == 'h'
            k, i = read_int(s, i + 2)
            raise bad.call unless k && k > 0
            keep = high ? k : -k
          end
          raise bad.call if sides < 1 || count < 1
          terms << Term.new(count, sides, sign, keep)
        else
          raise bad.call unless count
          i = i2
          terms << Term.new(count, 0, sign, 0)
        end
        sign = 1
        expect_term = false
      end
      raise bad.call if expect_term
      Dice.new(terms)
    end

    private def self.read_int(s : String, i : Int32) : {Int32?, Int32}
      start = i
      while i < s.size && s[i].ascii_number?
        i += 1
      end
      return {nil, i} if i == start
      {s[start...i].to_i, i}
    end

    # Rolls every term and returns the total.
    def roll(rng : Rng) : Int32
      total = 0
      @terms.each do |t|
        if t.sides == 0
          total += t.sign * t.count
        elsif t.keep == 0
          sum = 0
          t.count.times { sum += rng.int(1, t.sides) }
          total += t.sign * sum
        else
          rolls = Array.new(t.count) { rng.int(1, t.sides) }.sort!
          n = Math.min(t.keep.abs, t.count)
          kept = t.keep > 0 ? rolls.last(n) : rolls.first(n)
          total += t.sign * kept.sum
        end
      end
      total
    end

    # The smallest possible total.
    def min : Int32
      @terms.sum { |t| t.sign > 0 ? term_low(t) : -term_high(t) }
    end

    # The largest possible total.
    def max : Int32
      @terms.sum { |t| t.sign > 0 ? term_high(t) : -term_low(t) }
    end

    # The expected total. Exact for plain dice; terms that keep some dice use the midpoint of their range.
    def average : Float64
      @terms.sum do |t|
        v = if t.sides == 0
              t.count.to_f64
            elsif t.keep == 0
              t.count * (t.sides + 1) / 2.0
            else
              (term_low(t) + term_high(t)) / 2.0
            end
        t.sign * v
      end
    end

    private def kept(t : Term) : Int32
      t.keep == 0 ? t.count : Math.min(t.keep.abs, t.count)
    end

    private def term_low(t : Term) : Int32
      t.sides == 0 ? t.count : kept(t)
    end

    private def term_high(t : Term) : Int32
      t.sides == 0 ? t.count : kept(t) * t.sides
    end

    # Writes the normalized notation, such as `3d6+2`.
    def to_s(io : IO) : Nil
      @terms.each_with_index do |t, i|
        io << (t.sign < 0 ? "-" : (i > 0 ? "+" : ""))
        if t.sides == 0
          io << t.count
        else
          io << t.count << 'd' << t.sides
          io << (t.keep > 0 ? "kh" : "kl") << t.keep.abs unless t.keep == 0
        end
      end
    end
  end
end
