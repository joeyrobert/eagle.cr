# Checkers (English draughts) rules + AI, independent of rendering.
# 8x8 board, dark squares only, forced captures, multi-jumps, kings.
module Checkers
  enum Side : Int8
    Red = 0   # moves up (increasing row)
    Black = 1 # moves down
    def other : Side; red? ? Black : Red; end
  end

  struct Cell
    getter side : Side
    getter? king : Bool
    def initialize(@side, @king = false); end
    def crowned : Cell; Cell.new(@side, true); end
  end

  struct Move
    getter path : Array(Int32)       # squares visited (from ... to)
    getter captures : Array(Int32)   # captured squares
    def initialize(@path, @captures = [] of Int32); end
    def from : Int32; @path.first; end
    def to : Int32; @path.last; end
    def capture? : Bool; !@captures.empty?; end
    def to_s : String; @path.map { |i| Checkers.name(i) }.join(capture? ? "x" : "-"); end
    def ==(o : Move) : Bool; @path == o.path; end
  end

  def self.name(i : Int32) : String; "#{('a'.ord + i % 8).chr}#{i // 8 + 1}"; end
  def self.index(name : String) : Int32; (name[0].ord - 'a'.ord) + (name[1].to_i - 1) * 8; end
  def self.dark?(i : Int32) : Bool; (i % 8 + i // 8).even?; end

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
    getter quiet_moves = 0 # moves without capture/crowning (draw at 40 each side)

    def initialize
      @cells = Array(Cell?).new(64, nil)
      @turn = Side::Red
      setup
    end

    protected def initialize(@cells, @turn, @history, @quiet_moves); end

    def clone : Board; Board.new(@cells.dup, @turn, @history.dup, @quiet_moves); end

    def setup : Nil
      @cells.fill(nil)
      64.times do |i|
        next unless Checkers.dark?(i)
        r = i // 8
        @cells[i] = Cell.new(Side::Red) if r < 3
        @cells[i] = Cell.new(Side::Black) if r > 4
      end
    end

    # Layout from 8 text rows, top row first: r/R red (R = king), b/B black, . empty
    def self.from_layout(rows : Array(String), turn : Side = Side::Red) : Board
      b = new
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
    def set_turn(@turn); end

    def [](i : Int32) : Cell?; @cells[i]; end
    def count(side : Side) : Int32; @cells.count { |c| c && c.side == side }; end

    private def dirs(c : Cell) : Array({Int32, Int32})
      return [{1, 1}, {-1, 1}, {1, -1}, {-1, -1}] if c.king?
      c.side.red? ? [{1, 1}, {-1, 1}] : [{1, -1}, {-1, -1}]
    end

    # All legal moves (captures are mandatory).
    def legal_moves : Array(Move)
      captures = [] of Move
      simple = [] of Move
      64.times do |i|
        c = @cells[i]
        next unless c && c.side == @turn
        jumps(i, c, [i], [] of Int32, captures)
        next unless captures.empty?
        dirs(c).each do |(df, dr)|
          f = i % 8 + df; r = i // 8 + dr
          next unless (0 <= f <= 7) && (0 <= r <= 7)
          t = r * 8 + f
          simple << Move.new([i, t]) if @cells[t].nil?
        end
      end
      captures.empty? ? simple : captures
    end

    private def jumps(i, c, path, caps, out_moves)
      found = false
      dirs(c).each do |(df, dr)|
        f = i % 8 + df; r = i // 8 + dr
        f2 = f + df; r2 = r + dr
        next unless (0 <= f2 <= 7) && (0 <= r2 <= 7)
        mid = r * 8 + f; t = r2 * 8 + f2
        m = @cells[mid]
        next unless m && m.side != c.side && !caps.includes?(mid)
        next unless @cells[t].nil? || t == path.first
        found = true
        # stop multi-jump when a man reaches the king row
        last_row = c.side.red? ? 7 : 0
        if !c.king? && r2 == last_row
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

    def apply(m : Move) : Nil
      c = @cells[m.from].not_nil!
      @cells[m.from] = nil
      m.captures.each { |x| @cells[x] = nil }
      last_row = c.side.red? ? 7 : 0
      crowned = !c.king? && m.to // 8 == last_row
      @cells[m.to] = crowned ? c.crowned : c
      @quiet_moves = (m.capture? || crowned) ? 0 : @quiet_moves + 1
      @history << m
      @turn = @turn.other
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
      return Status::Draw if @quiet_moves >= 80
      if legal_moves.empty?
        return @turn.red? ? Status::BlackWins : Status::RedWins
      end
      Status::Playing
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

  class AI
    property depth : Int32
    getter nodes = 0

    def initialize(@depth = 6); end

    def evaluate(b : Board) : Int32
      score = 0
      64.times do |i|
        c = b[i]
        next unless c
        v = c.king? ? 300 : 100
        # advancement bonus for men
        r = i // 8
        v += (c.side.red? ? r : 7 - r) * 3 unless c.king?
        # edge safety
        v += 4 if i % 8 == 0 || i % 8 == 7
        score += c.side.red? ? v : -v
      end
      b.turn.red? ? score : -score
    end

    def best_move(b : Board) : Move?
      @nodes = 0
      moves = b.legal_moves
      return nil if moves.empty?
      return moves[0] if moves.size == 1
      best = moves[0]; best_score = Int32::MIN
      alpha = -1_000_000; beta = 1_000_000
      moves.each do |m|
        c = b.clone; c.apply(m)
        s = -search(c, @depth - 1, -beta, -alpha)
        if s > best_score
          best_score = s; best = m
        end
        alpha = Math.max(alpha, s)
      end
      best
    end

    private def search(b : Board, depth : Int32, alpha : Int32, beta : Int32) : Int32
      @nodes += 1
      moves = b.legal_moves
      return -100_000 - depth if moves.empty?
      # extend search while captures are available (quiescence)
      return evaluate(b) if depth <= 0 && !moves[0].capture?
      return evaluate(b) if depth <= -4
      moves.each do |m|
        c = b.clone; c.apply(m)
        s = -search(c, depth - 1, -beta, -alpha)
        return beta if s >= beta
        alpha = Math.max(alpha, s)
      end
      alpha
    end
  end
end
