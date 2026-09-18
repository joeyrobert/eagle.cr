# Checkers (American checkers / English draughts) rules + AI, independent of rendering.
#
# Rules implemented:
# * 8x8 board, play on the dark squares; a1 (bottom left, Red's side) is dark. Black moves first.
# * Men move and capture diagonally forward only; kings move and capture both ways, one square at a time.
# * A capture chain is one move: after a jump the same piece must keep jumping while it can.
# * A man that reaches the far row is crowned and the move ends there, even mid-chain.
# * Forced capture (the standard rule) is a parameter. When it is off, captures are optional:
#   you may make a plain move instead, but once you start jumping you must finish the chain.
# * A side with no pieces or no legal moves loses.
# * Draws: 40 moves by each side with no capture and no man moved, or the same position with
#   the same side to move occurring three times.
module Checkers
  enum Side : Int8
    Red = 0   # starts on rows 1-3 (bottom), moves up
    Black = 1 # starts on rows 6-8 (top), moves down, moves first

    def other : Side; red? ? Black : Red; end
  end

  struct Cell
    getter side : Side
    getter? king : Bool

    def initialize(@side, @king = false); end

    def crowned : Cell; Cell.new(@side, true); end
  end

  struct Move
    getter path : Array(Int32)     # squares visited (from ... to)
    getter captures : Array(Int32) # captured squares, in jump order

    def initialize(@path, @captures = [] of Int32); end

    def from : Int32; @path.first; end

    def to : Int32; @path.last; end

    def capture? : Bool; !@captures.empty?; end

    def to_s(io : IO) : Nil; io << @path.map { |i| Checkers.name(i) }.join(capture? ? "x" : "-"); end

    def ==(o : Move) : Bool; @path == o.path; end
  end

  RED_DIRS   = [{1, 1}, {-1, 1}]
  BLACK_DIRS = [{1, -1}, {-1, -1}]
  KING_DIRS  = [{1, 1}, {-1, 1}, {1, -1}, {-1, -1}]
  # 40 moves by each side without a capture or a man moving.
  QUIET_LIMIT = 80

  def self.name(i : Int32) : String; "#{('a'.ord + i % 8).chr}#{i // 8 + 1}"; end

  def self.index(name : String) : Int32; (name[0].ord - 'a'.ord) + (name[1].to_i - 1) * 8; end

  def self.dark?(i : Int32) : Bool; (i % 8 + i // 8).even?; end

  def self.last_row(side : Side) : Int32; side.red? ? 7 : 0; end

  enum Status
    Playing
    RedWins
    BlackWins
    Draw
  end

  class Board
    getter cells : Array(Cell?)
    getter turn : Side
    getter history = [] of Move
    # Plies since the last capture or man move; the game is drawn at `QUIET_LIMIT`.
    getter quiet_moves = 0
    # :nodoc: for tests and puzzles
    setter quiet_moves
    # When true a capture must be taken if one exists (standard rules). When false captures are optional.
    getter? forced_capture : Bool
    @keys = [] of String
    @snapshots = [] of {Array(Cell?), Side, Int32}

    def initialize(@forced_capture = true)
      @cells = Array(Cell?).new(64, nil)
      @turn = Side::Black
      setup
    end

    protected def initialize(@cells, @turn, @history, @quiet_moves, @forced_capture, @keys, @snapshots); end

    def clone : Board; Board.new(@cells.dup, @turn, @history.dup, @quiet_moves, @forced_capture, @keys.dup, @snapshots.dup); end

    # A copy with *m* applied, without history. Used by the AI search.
    def child(m : Move) : Board
      b = Board.new(@cells.dup, @turn, [] of Move, @quiet_moves, @forced_capture, [] of String, [] of {Array(Cell?), Side, Int32})
      b.apply(m, record: false)
      b
    end

    def setup : Nil
      @cells.fill(nil)
      64.times do |i|
        next unless Checkers.dark?(i)
        r = i // 8
        @cells[i] = Cell.new(Side::Red) if r < 3
        @cells[i] = Cell.new(Side::Black) if r > 4
      end
      @history.clear
      @snapshots.clear
      @quiet_moves = 0
      @keys = [key]
    end

    # Layout from 8 text rows, top row first: r/R red (R = king), b/B black, . empty
    def self.from_layout(rows : Array(String), turn : Side = Side::Red, forced_capture : Bool = true) : Board
      b = new(forced_capture)
      b.cells.fill(nil)
      rows.each_with_index do |row, ri|
        r = 7 - ri
        row.each_char.with_index do |c, f|
          i = r * 8 + f
          case c
          when 'r' then b.cells[i] = Cell.new(Side::Red)
          when 'R' then b.cells[i] = Cell.new(Side::Red, true)
          when 'b' then b.cells[i] = Cell.new(Side::Black)
          when 'B' then b.cells[i] = Cell.new(Side::Black, true)
          end
        end
      end
      b.set_turn(turn)
      b
    end

    # :nodoc:
    def set_turn(@turn)
      @keys = [key]
    end

    def [](i : Int32) : Cell?; @cells[i]; end

    def count(side : Side) : Int32; @cells.count { |c| c && c.side == side }; end

    # Position fingerprint (pieces + side to move) for repetition detection.
    def key : String
      String.build do |s|
        64.times do |i|
          next unless Checkers.dark?(i)
          c = @cells[i]
          s << (c ? (c.side.red? ? (c.king? ? 'R' : 'r') : (c.king? ? 'B' : 'b')) : '.')
        end
        s << (@turn.red? ? 'r' : 'b')
      end
    end

    # How many times the current position has occurred.
    def repetitions : Int32
      k = @keys.last? || key
      @keys.count(k)
    end

    private def dirs(c : Cell) : Array({Int32, Int32})
      return KING_DIRS if c.king?
      c.side.red? ? RED_DIRS : BLACK_DIRS
    end

    # All legal moves, captures first. With forced capture only captures are returned when any exist.
    def legal_moves : Array(Move)
      captures = [] of Move
      simple = [] of Move
      64.times do |i|
        c = @cells[i]
        next unless c && c.side == @turn
        jumps(i, c, [i], [] of Int32, captures) if can_jump?(i, c)
        next if @forced_capture && !captures.empty?
        dirs(c).each do |(df, dr)|
          f = i % 8 + df; r = i // 8 + dr
          next unless (0 <= f <= 7) && (0 <= r <= 7)
          t = r * 8 + f
          simple << Move.new([i, t]) if @cells[t].nil?
        end
      end
      return captures if @forced_capture && !captures.empty?
      captures.empty? ? simple : captures + simple
    end

    private def can_jump?(i : Int32, c : Cell) : Bool
      dirs(c).any? do |(df, dr)|
        f2 = i % 8 + df * 2; r2 = i // 8 + dr * 2
        next false unless (0 <= f2 <= 7) && (0 <= r2 <= 7)
        m = @cells[(i // 8 + dr) * 8 + i % 8 + df]
        !!(m && m.side != c.side && @cells[r2 * 8 + f2].nil?)
      end
    end

    # Capture chains from *i*. Each chain is maximal: it only ends when no further jump exists or a man is crowned.
    private def jumps(i, c, path, caps, out_moves)
      found = false
      dirs(c).each do |(df, dr)|
        f = i % 8 + df; r = i // 8 + dr
        f2 = f + df; r2 = r + dr
        next unless (0 <= f2 <= 7) && (0 <= r2 <= 7)
        mid = r * 8 + f; t = r2 * 8 + f2
        m = @cells[mid]
        next unless m && m.side != c.side && !caps.includes?(mid)
        # the moving piece has left its start square, so a chain may pass through it again
        next unless @cells[t].nil? || t == path.first
        found = true
        if !c.king? && r2 == Checkers.last_row(c.side)
          out_moves << Move.new(path + [t], caps + [mid])
        else
          jumps(t, c, path + [t], caps + [mid], out_moves)
        end
      end
      out_moves << Move.new(path, caps) if !found && caps.size > 0
    end

    def legal_moves_from(i : Int32) : Array(Move)
      legal_moves.select { |m| m.from == i }
    end

    # Squares holding a piece with at least one legal move.
    def movable_squares : Array(Int32)
      legal_moves.map(&.from).uniq
    end

    # Applies *m* without checking legality. Use `play` for untrusted moves.
    def apply(m : Move, record : Bool = true) : Nil
      @snapshots << {@cells.dup, @turn, @quiet_moves} if record
      c = @cells[m.from].not_nil!
      @cells[m.from] = nil
      m.captures.each { |x| @cells[x] = nil }
      crowned = !c.king? && m.to // 8 == Checkers.last_row(c.side)
      @cells[m.to] = crowned ? c.crowned : c
      @quiet_moves = (m.capture? || !c.king?) ? 0 : @quiet_moves + 1
      @turn = @turn.other
      if record
        @history << m
        @keys << key
      end
    end

    # Takes back the last move. Returns it, or nil when there is nothing to undo.
    def undo : Move?
      snap = @snapshots.pop?
      return nil unless snap
      @cells, @turn, @quiet_moves = snap
      @keys.pop
      @history.pop
    end

    def play(m : Move) : Bool
      real = legal_moves.find { |lm| lm == m }
      return false unless real
      apply(real)
      true
    end

    def play(path : String) : Bool
      squares = path.split(/[-x]/).map { |n| Checkers.index(n) }
      play(Move.new(squares))
    end

    def status : Status
      if legal_moves.empty?
        return @turn.red? ? Status::BlackWins : Status::RedWins
      end
      return Status::Draw if draw_reason
      Status::Playing
    end

    # Why the game is drawn, or nil.
    def draw_reason : String?
      return "40 moves each without a capture or man move" if @quiet_moves >= QUIET_LIMIT
      return "threefold repetition" if repetitions >= 3
      nil
    end

    def game_over? : Bool; !status.playing?; end

    def to_s(io : IO) : Nil
      7.downto(0) do |r|
        8.times do |f|
          c = @cells[r * 8 + f]
          io << (c ? (c.side.red? ? (c.king? ? 'R' : 'r') : (c.king? ? 'B' : 'b')) : (Checkers.dark?(r * 8 + f) ? '.' : ' ')) << ' '
        end
        io << '\n'
      end
    end
  end

  # Alpha-beta AI with iterative deepening and capture quiescence.
  #
  # The search keeps its own explicit stack, so it can be paused after any node and resumed
  # next frame (`think`), which keeps the game responsive on the single-threaded web build.
  # Results depend only on the board, the level and the seed, never on how the work was sliced.
  class AI
    enum Level
      Beginner
      Medium
      Advanced
    end

    MATE = 100_000
    INF  = 1_000_000

    getter level : Level
    # Deepest iteration of the search.
    property max_depth : Int32
    # Search stops after this many nodes and plays the best move found so far.
    property node_limit : Int32
    # Plies of capture-only search past the nominal depth.
    property quiescence : Int32
    # Random +/- noise added to leaf evaluations (in hundredths of a man).
    property noise : Int32
    # Chance of playing a random legal move instead of searching.
    property blunder_chance : Float64
    # Nodes searched for the last move.
    getter nodes = 0
    # Depth of the last completed iteration.
    getter depth_reached = 0

    private class Frame
      property board : Board
      property moves : Array(Move)
      property index = 0
      property alpha : Int32
      property beta : Int32
      property depth : Int32
      property ply : Int32

      def initialize(@board, @moves, @alpha, @beta, @depth, @ply); end
    end

    @rng : Random
    @stack = [] of Frame
    @ret : Int32? = nil
    @root : Board? = nil
    @root_moves = [] of Move
    @best : Move? = nil
    @iter_best : Move? = nil
    @iter_score : Int32 = -INF
    @depth : Int32 = 0
    @result : Move? = nil
    @done = true

    def initialize(@level : Level = Level::Medium, seed : Int = Random.new.rand(UInt32))
      @rng = Random.new(seed.to_u64)
      @max_depth, @node_limit, @quiescence, @noise, @blunder_chance = case @level
                                                                      in .beginner? then {2, 2_000, 0, 60, 0.3}
                                                                      in .medium?   then {4, 20_000, 4, 10, 0.0}
                                                                      in .advanced? then {24, 200_000, 10, 0, 0.0}
                                                                      end
    end

    # Starts a search for *b*. Drive it with `think` or `step` until `thinking?` is false, then read `result`.
    def start(b : Board) : Nil
      @nodes = 0; @depth_reached = 0
      @stack.clear; @ret = nil
      @result = nil; @best = nil; @iter_best = nil
      @root = b
      moves = order(b.legal_moves)
      @root_moves = moves
      @done = false
      if moves.size <= 1
        finish(moves.first?)
      elsif @blunder_chance > 0 && @rng.rand < @blunder_chance
        finish(moves.sample(@rng))
      else
        @best = moves.first
        @depth = 1
        push_root
      end
    end

    def thinking? : Bool; !@done; end

    # The chosen move once thinking is done (nil when there are no legal moves).
    def result : Move?; @result; end

    # Runs the search for at most *seconds* of wall time. Returns true when finished.
    def think(seconds : Float64) : Bool
      deadline = Time.instant + seconds.seconds
      until @done
        step(256)
        break if Time.instant >= deadline
      end
      @done
    end

    # Runs at most *budget* search steps. Returns true when finished.
    def step(budget : Int32) : Bool
      budget.times do
        break if @done
        advance
      end
      @done
    end

    # Searches synchronously and returns the best move.
    def best_move(b : Board) : Move?
      start(b)
      until @done
        step(Int32::MAX)
      end
      @result
    end

    private def finish(m : Move?) : Nil
      @result = m
      @done = true
      @stack.clear
    end

    private def push_root : Nil
      root = @root.not_nil!
      @iter_best = nil; @iter_score = -INF
      @stack << Frame.new(root, @root_moves, -INF, INF, @depth, 0)
    end

    # One unit of work: consume a child's value or expand the next child.
    private def advance : Nil
      if @nodes >= @node_limit
        return finish(@iter_best || @best)
      end
      f = @stack.last
      if v = @ret
        @ret = nil
        s = -v
        if f.ply == 0 && s > @iter_score
          @iter_score = s; @iter_best = f.moves[f.index]
        end
        return pop(f.beta) if s >= f.beta
        f.alpha = s if s > f.alpha
        f.index += 1
      end
      return pop(f.alpha) if f.index >= f.moves.size
      child = f.board.child(f.moves[f.index])
      if leaf = enter(child, f.depth - 1, -f.beta, -f.alpha, f.ply + 1)
        @ret = leaf
      end
    end

    private def pop(value : Int32) : Nil
      @stack.pop
      return @ret = value unless @stack.empty?
      # a root iteration finished
      @best = @iter_best || @best
      @depth_reached = @depth
      if @depth >= @max_depth || @iter_score.abs >= MATE - 1000
        return finish(@best)
      end
      # search the previous best first next time
      if b = @best
        @root_moves = [b] + @root_moves.reject { |m| m == b }
      end
      @depth += 1
      push_root
    end

    # Evaluates a leaf or pushes a frame for an interior node. Returns the value for leaves.
    private def enter(b : Board, depth : Int32, alpha : Int32, beta : Int32, ply : Int32) : Int32?
      @nodes += 1
      moves = b.legal_moves
      return -(MATE - ply) if moves.empty?
      if depth <= 0
        stand = evaluate(b) + jitter
        return stand if depth <= -@quiescence
        caps = moves.select(&.capture?)
        return stand if caps.empty?
        unless b.forced_capture?
          # captures are optional, so the side to move can decline them (stand pat)
          return stand if stand >= beta
          alpha = stand if stand > alpha
        end
        moves = caps
      end
      @stack << Frame.new(b, order(moves), alpha, beta, depth, ply)
      nil
    end

    private def jitter : Int32
      @noise > 0 ? @rng.rand(-@noise..@noise) : 0
    end

    # Longest captures first, then the generator's order.
    private def order(moves : Array(Move)) : Array(Move)
      return moves if moves.none?(&.capture?)
      moves.each_with_index.to_a.sort_by { |(m, i)| {-m.captures.size, i} }.map(&.[0])
    end

    # Static evaluation from the point of view of the side to move.
    def evaluate(b : Board) : Int32
      score = @level.advanced? ? evaluate_advanced(b) : evaluate_basic(b)
      b.turn.red? ? score : -score
    end

    # Material plus a small bonus for advancing men (Red positive).
    def evaluate_basic(b : Board) : Int32
      score = 0
      64.times do |i|
        c = b[i]
        next unless c
        v = c.king? ? 150 : 100 + progress(c.side, i) * 3
        score += c.side.red? ? v : -v
      end
      score
    end

    CENTER = (0..63).map { |i| {18, 20, 27, 29, 34, 36, 43, 45}.includes?(i) }

    # Material, advancement, back-row guard, centre control, mobility, and trading down when ahead (Red positive).
    def evaluate_advanced(b : Board) : Int32
      mat = StaticArray(Int32, 2).new(0)
      pos = StaticArray(Int32, 2).new(0)
      men = 0
      64.times do |i|
        c = b[i]
        next unless c
        s = c.side.value
        f = i % 8; r = i // 8
        if c.king?
          mat[s] += 160
          pos[s] -= 8 if f == 0 || f == 7 || r == 0 || r == 7
        else
          mat[s] += 100
          men += 1
          p = s == 0 ? r : 7 - r
          pos[s] += p * 4
          pos[s] += 12 if p == 0 # guarding the back row keeps the opponent from crowning
          pos[s] += 6 if CENTER[i]
        end
        pos[s] += mobility(b, i, c) * 2
      end
      score = mat[0] - mat[1] + pos[0] - pos[1]
      # when ahead, trading pieces makes the advantage bigger
      score += (mat[0] - mat[1]) * 400 // (mat[0] + mat[1] + 200)
      # in the endgame the side ahead hunts with its kings
      if men <= 4 && mat[0] != mat[1]
        ahead = mat[0] > mat[1] ? Side::Red : Side::Black
        64.times do |k|
          c = b[k]
          next unless c && c.king? && c.side == ahead
          d = nearest_enemy(b, k, ahead) * 3
          score += ahead.red? ? -d : d
        end
      end
      score
    end

    private def progress(side : Side, i : Int32) : Int32
      side.red? ? i // 8 : 7 - i // 8
    end

    private def mobility(b : Board, i : Int32, c : Cell) : Int32
      n = 0
      f = i % 8; r = i // 8
      up = c.king? || c.side.red?
      down = c.king? || c.side.black?
      n += 1 if up && r < 7 && f > 0 && b[i + 7].nil?
      n += 1 if up && r < 7 && f < 7 && b[i + 9].nil?
      n += 1 if down && r > 0 && f > 0 && b[i - 9].nil?
      n += 1 if down && r > 0 && f < 7 && b[i - 7].nil?
      n
    end

    private def nearest_enemy(b : Board, k : Int32, side : Side) : Int32
      best = 14
      64.times do |j|
        c = b[j]
        next unless c && c.side != side
        d = Math.max((j % 8 - k % 8).abs, (j // 8 - k // 8).abs)
        best = d if d < best
      end
      best
    end
  end
end
