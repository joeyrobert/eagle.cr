# A complete chess rules engine + alpha-beta AI, independent of rendering.
module Chess
  enum Piece : Int8
    None = 0
    Pawn; Knight; Bishop; Rook; Queen; King
  end

  enum Side : Int8
    White = 0
    Black = 1
    def other : Side; white? ? Black : White; end
  end

  # A square holds a piece + side packed as (side << 3 | piece); 0 = empty.
  struct Square
    getter raw : Int8
    def initialize(@raw : Int8 = 0); end
    def self.of(piece : Piece, side : Side) : Square; new((side.value << 3 | piece.value).to_i8); end
    def empty? : Bool; @raw == 0; end
    def piece : Piece; Piece.new((@raw & 7).to_i8); end
    def side : Side; Side.new((@raw >> 3).to_i8); end
    def ==(o : Square) : Bool; @raw == o.raw; end
    def to_s : String
      return "." if empty?
      c = {Piece::Pawn => 'p', Piece::Knight => 'n', Piece::Bishop => 'b', Piece::Rook => 'r', Piece::Queen => 'q', Piece::King => 'k'}[piece]
      side.white? ? c.upcase.to_s : c.to_s
    end
  end

  struct Move
    getter from : Int32
    getter to : Int32
    getter promotion : Piece
    getter? castle : Bool
    getter? en_passant : Bool
    def initialize(@from, @to, @promotion = Piece::None, @castle = false, @en_passant = false); end
    def ==(o : Move) : Bool; @from == o.from && @to == o.to && @promotion == o.promotion; end
    def to_s : String
      s = Chess.square_name(@from) + Chess.square_name(@to)
      @promotion.none? ? s : s + {Piece::Queen => "q", Piece::Rook => "r", Piece::Bishop => "b", Piece::Knight => "n"}[@promotion]
    end
  end

  def self.square_name(i : Int32) : String
    "#{('a'.ord + i % 8).chr}#{i // 8 + 1}"
  end

  def self.square_index(name : String) : Int32
    (name[0].ord - 'a'.ord) + (name[1].to_i - 1) * 8
  end

  enum Status
    Playing
    Check
    Checkmate
    Stalemate
    Draw
  end

  class Board
    getter squares : Array(Square)
    getter turn : Side
    # castling rights: [white kingside, white queenside, black kingside, black queenside]
    getter castling : Array(Bool)
    getter en_passant : Int32 # target square or -1
    getter halfmove : Int32
    getter fullmove : Int32
    getter history : Array(Move)
    getter captured : Array(Square)

    def initialize
      @squares = Array(Square).new(64, Square.new)
      @turn = Side::White
      @castling = [true, true, true, true]
      @en_passant = -1
      @halfmove = 0
      @fullmove = 1
      @history = [] of Move
      @captured = [] of Square
      setup
    end

    protected def initialize(@squares, @turn, @castling, @en_passant, @halfmove, @fullmove, @history, @captured); end

    def clone : Board
      Board.new(@squares.dup, @turn, @castling.dup, @en_passant, @halfmove, @fullmove, @history.dup, @captured.dup)
    end

    def setup : Nil
      @squares.fill(Square.new)
      back = [Piece::Rook, Piece::Knight, Piece::Bishop, Piece::Queen, Piece::King, Piece::Bishop, Piece::Knight, Piece::Rook]
      8.times do |f|
        @squares[f] = Square.of(back[f], Side::White)
        @squares[8 + f] = Square.of(Piece::Pawn, Side::White)
        @squares[48 + f] = Square.of(Piece::Pawn, Side::Black)
        @squares[56 + f] = Square.of(back[f], Side::Black)
      end
    end

    # Load a FEN position (board, turn, castling, en passant).
    def self.from_fen(fen : String) : Board
      b = new
      b.squares.fill(Square.new)
      parts = fen.split
      rank = 7; file = 0
      parts[0].each_char do |c|
        case c
        when '/' then rank -= 1; file = 0
        when .ascii_number? then file += c.to_i
        else
          piece = {'p' => Piece::Pawn, 'n' => Piece::Knight, 'b' => Piece::Bishop, 'r' => Piece::Rook, 'q' => Piece::Queen, 'k' => Piece::King}[c.downcase]
          b.squares[rank * 8 + file] = Square.of(piece, c.uppercase? ? Side::White : Side::Black)
          file += 1
        end
      end
      b.set_state(parts[1]? == "b" ? Side::Black : Side::White,
        [parts[2]?.try(&.includes?('K')) || false, parts[2]?.try(&.includes?('Q')) || false, parts[2]?.try(&.includes?('k')) || false, parts[2]?.try(&.includes?('q')) || false],
        (parts[3]? && parts[3] != "-") ? Chess.square_index(parts[3]) : -1,
        parts[4]?.try(&.to_i?) || 0, parts[5]?.try(&.to_i?) || 1)
      b
    end

    # :nodoc:
    def set_state(@turn, @castling, @en_passant, @halfmove = 0, @fullmove = 1); end

    def to_fen : String
      rows = (0..7).to_a.reverse.map do |r|
        s = ""; empty = 0
        8.times do |f|
          sq = @squares[r * 8 + f]
          if sq.empty?
            empty += 1
          else
            s += empty.to_s if empty > 0
            empty = 0
            s += sq.to_s
          end
        end
        s += empty.to_s if empty > 0
        s
      end
      c = ""
      c += "K" if @castling[0]; c += "Q" if @castling[1]; c += "k" if @castling[2]; c += "q" if @castling[3]
      c = "-" if c.empty?
      "#{rows.join("/")} #{@turn.white? ? "w" : "b"} #{c} #{@en_passant >= 0 ? Chess.square_name(@en_passant) : "-"} #{@halfmove} #{@fullmove}"
    end

    def [](i : Int32) : Square; @squares[i]; end
    def [](file : Int32, rank : Int32) : Square; @squares[rank * 8 + file]; end

    def king_square(side : Side) : Int32
      @squares.index { |s| !s.empty? && s.piece.king? && s.side == side } || -1
    end

    # Is `sq` attacked by `by`?
    def attacked?(sq : Int32, by : Side) : Bool
      f = sq % 8; r = sq // 8
      # pawns
      dir = by.white? ? -1 : 1 # a white pawn attacks upward, so look one rank below the target
      [-1, 1].each do |df|
        ff = f + df; rr = r + dir
        if (0 <= ff <= 7) && (0 <= rr <= 7)
          s = @squares[rr * 8 + ff]
          return true if !s.empty? && s.side == by && s.piece.pawn?
        end
      end
      # knights
      KNIGHT.each do |(df, dr)|
        ff = f + df; rr = r + dr
        next unless (0 <= ff <= 7) && (0 <= rr <= 7)
        s = @squares[rr * 8 + ff]
        return true if !s.empty? && s.side == by && s.piece.knight?
      end
      # king
      KING.each do |(df, dr)|
        ff = f + df; rr = r + dr
        next unless (0 <= ff <= 7) && (0 <= rr <= 7)
        s = @squares[rr * 8 + ff]
        return true if !s.empty? && s.side == by && s.piece.king?
      end
      # sliders
      slide_attack?(f, r, by, ROOK_DIRS, Piece::Rook) || slide_attack?(f, r, by, BISHOP_DIRS, Piece::Bishop)
    end

    private def slide_attack?(f, r, by, dirs, piece) : Bool
      dirs.each do |(df, dr)|
        ff = f + df; rr = r + dr
        while (0 <= ff <= 7) && (0 <= rr <= 7)
          s = @squares[rr * 8 + ff]
          unless s.empty?
            return true if s.side == by && (s.piece == piece || s.piece.queen?)
            break
          end
          ff += df; rr += dr
        end
      end
      false
    end

    def in_check?(side : Side = @turn) : Bool
      k = king_square(side)
      k >= 0 && attacked?(k, side.other)
    end

    KNIGHT = [{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}]
    KING = [{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}]
    ROOK_DIRS = [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]
    BISHOP_DIRS = [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

    # Pseudo-legal moves for the side to move (may leave the king in check).
    def pseudo_moves : Array(Move)
      moves = [] of Move
      64.times do |i|
        s = @squares[i]
        next if s.empty? || s.side != @turn
        gen_piece(i, s, moves)
      end
      moves
    end

    private def add(moves, from, to)
      moves << Move.new(from, to)
    end

    private def gen_piece(i, s, moves)
      f = i % 8; r = i // 8
      case s.piece
      when .pawn?
        dir = s.side.white? ? 1 : -1
        start = s.side.white? ? 1 : 6
        last = s.side.white? ? 7 : 0
        rr = r + dir
        if (0 <= rr <= 7) && @squares[rr * 8 + f].empty?
          push_pawn(moves, i, rr * 8 + f, rr == last)
          if r == start && @squares[(rr + dir) * 8 + f].empty?
            add(moves, i, (rr + dir) * 8 + f)
          end
        end
        [-1, 1].each do |df|
          ff = f + df
          next unless (0 <= ff <= 7) && (0 <= rr <= 7)
          t = rr * 8 + ff
          target = @squares[t]
          if !target.empty? && target.side != s.side
            push_pawn(moves, i, t, rr == last)
          elsif t == @en_passant
            moves << Move.new(i, t, en_passant: true)
          end
        end
      when .knight?
        KNIGHT.each { |(df, dr)| step(moves, i, f + df, r + dr, s.side) }
      when .king?
        KING.each { |(df, dr)| step(moves, i, f + df, r + dr, s.side) }
        gen_castling(i, s.side, moves)
      when .rook? then slide(moves, i, f, r, s.side, ROOK_DIRS)
      when .bishop? then slide(moves, i, f, r, s.side, BISHOP_DIRS)
      when .queen? then slide(moves, i, f, r, s.side, ROOK_DIRS + BISHOP_DIRS)
      end
    end

    private def push_pawn(moves, from, to, promote)
      if promote
        [Piece::Queen, Piece::Rook, Piece::Bishop, Piece::Knight].each { |p| moves << Move.new(from, to, p) }
      else
        add(moves, from, to)
      end
    end

    private def step(moves, from, ff, rr, side)
      return unless (0 <= ff <= 7) && (0 <= rr <= 7)
      t = @squares[rr * 8 + ff]
      add(moves, from, rr * 8 + ff) if t.empty? || t.side != side
    end

    private def slide(moves, from, f, r, side, dirs)
      dirs.each do |(df, dr)|
        ff = f + df; rr = r + dr
        while (0 <= ff <= 7) && (0 <= rr <= 7)
          t = @squares[rr * 8 + ff]
          if t.empty?
            add(moves, from, rr * 8 + ff)
          else
            add(moves, from, rr * 8 + ff) if t.side != side
            break
          end
          ff += df; rr += dr
        end
      end
    end

    private def gen_castling(i, side, moves)
      rank = side.white? ? 0 : 7
      return unless i == rank * 8 + 4
      return if attacked?(i, side.other)
      ks = side.white? ? @castling[0] : @castling[2]
      qs = side.white? ? @castling[1] : @castling[3]
      if ks && @squares[rank * 8 + 5].empty? && @squares[rank * 8 + 6].empty? && rook_at?(rank * 8 + 7, side) &&
         !attacked?(rank * 8 + 5, side.other) && !attacked?(rank * 8 + 6, side.other)
        moves << Move.new(i, rank * 8 + 6, castle: true)
      end
      if qs && @squares[rank * 8 + 3].empty? && @squares[rank * 8 + 2].empty? && @squares[rank * 8 + 1].empty? && rook_at?(rank * 8, side) &&
         !attacked?(rank * 8 + 3, side.other) && !attacked?(rank * 8 + 2, side.other)
        moves << Move.new(i, rank * 8 + 2, castle: true)
      end
    end

    private def rook_at?(i, side)
      s = @squares[i]
      !s.empty? && s.piece.rook? && s.side == side
    end

    # Fully legal moves.
    def legal_moves : Array(Move)
      pseudo_moves.select { |m| legal?(m) }
    end

    def legal?(m : Move) : Bool
      b = clone
      b.apply(m)
      !b.in_check?(@turn)
    end

    def legal_moves_from(sq : Int32) : Array(Move)
      legal_moves.select { |m| m.from == sq }
    end

    # Apply a move without legality checks (used internally and by AI).
    def apply(m : Move) : Nil
      s = @squares[m.from]
      target = @squares[m.to]
      @captured << (m.en_passant? ? Square.of(Piece::Pawn, @turn.other) : target)
      @halfmove = (s.piece.pawn? || !target.empty?) ? 0 : @halfmove + 1
      @squares[m.to] = m.promotion.none? ? s : Square.of(m.promotion, s.side)
      @squares[m.from] = Square.new
      if m.en_passant?
        cap = m.to + (s.side.white? ? -8 : 8)
        @squares[cap] = Square.new
      end
      if m.castle?
        rank = m.from // 8
        if m.to % 8 == 6
          @squares[rank * 8 + 5] = @squares[rank * 8 + 7]; @squares[rank * 8 + 7] = Square.new
        else
          @squares[rank * 8 + 3] = @squares[rank * 8]; @squares[rank * 8] = Square.new
        end
      end
      # castling rights
      if s.piece.king?
        if s.side.white?
          @castling[0] = @castling[1] = false
        else
          @castling[2] = @castling[3] = false
        end
      end
      [{0, 1, 7, 0}, {56, 3, 63, 2}].each do |(qsq, qi, ksq, ki)|
        @castling[qi] = false if m.from == qsq || m.to == qsq
        @castling[ki] = false if m.from == ksq || m.to == ksq
      end
      # en passant target
      @en_passant = -1
      if s.piece.pawn? && (m.to - m.from).abs == 16
        @en_passant = (m.from + m.to) // 2
      end
      @fullmove += 1 if @turn.black?
      @turn = @turn.other
      @history << m
    end

    # Play a legal move; returns false if illegal.
    def play(m : Move) : Bool
      return false unless legal_moves.any? { |lm| lm == m }
      real = legal_moves.find { |lm| lm == m }.not_nil!
      apply(real)
      true
    end

    def play(from : String, to : String, promotion : Piece = Piece::None) : Bool
      play(Move.new(Chess.square_index(from), Chess.square_index(to), promotion))
    end

    def status : Status
      moves = legal_moves
      check = in_check?
      if moves.empty?
        return check ? Status::Checkmate : Status::Stalemate
      end
      return Status::Draw if @halfmove >= 100 || insufficient_material?
      check ? Status::Check : Status::Playing
    end

    def game_over? : Bool
      st = status
      st.checkmate? || st.stalemate? || st.draw?
    end

    def insufficient_material? : Bool
      pieces = @squares.reject(&.empty?).map(&.piece).reject(&.king?)
      return true if pieces.empty?
      pieces.size == 1 && (pieces[0].bishop? || pieces[0].knight?)
    end

    # Number of leaf nodes at `depth` (perft) — used to validate move generation.
    def perft(depth : Int32) : Int64
      return 1_i64 if depth == 0
      total = 0_i64
      legal_moves.each do |m|
        b = clone
        b.apply(m)
        total += b.perft(depth - 1)
      end
      total
    end

    def to_s(io : IO) : Nil
      7.downto(0) do |r|
        8.times { |f| io << @squares[r * 8 + f].to_s << " " }
        io << "\n"
      end
    end
  end

  # Alpha-beta search with material + piece-square evaluation.
  class AI
    VALUES = {Piece::Pawn => 100, Piece::Knight => 320, Piece::Bishop => 330, Piece::Rook => 500, Piece::Queen => 900, Piece::King => 0, Piece::None => 0}
    # Piece-square bonus: encourage centre control and development (from white's view, rank 0 = bottom).
    PST = {
      Piece::Pawn => [0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, -20, -20, 10, 10, 5, 5, -5, -10, 0, 0, -10, -5, 5, 0, 0, 0, 20, 20, 0, 0, 0, 5, 5, 10, 25, 25, 10, 5, 5, 10, 10, 20, 30, 30, 20, 10, 10, 50, 50, 50, 50, 50, 50, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0],
      Piece::Knight => [-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 5, 5, 0, -20, -40, -30, 5, 10, 15, 15, 10, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 10, 15, 15, 10, 0, -30, -40, -20, 0, 0, 0, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50],
      Piece::Bishop => [-20, -10, -10, -10, -10, -10, -10, -20, -10, 5, 0, 0, 0, 0, 5, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 0, 0, 0, 0, 0, 0, -10, -20, -10, -10, -10, -10, -10, -10, -20],
      Piece::Rook => [0, 0, 0, 5, 5, 0, 0, 0, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 5, 10, 10, 10, 10, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0],
      Piece::Queen => [-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 5, 0, 0, 0, 0, -10, -10, 5, 5, 5, 5, 5, 0, -10, 0, 0, 5, 5, 5, 5, 0, -5, -5, 0, 5, 5, 5, 5, 0, -5, -10, 0, 5, 5, 5, 5, 0, -10, -10, 0, 0, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20],
      Piece::King => [20, 30, 10, 0, 0, 10, 30, 20, 20, 20, 0, 0, 0, 0, 20, 20, -10, -20, -20, -20, -20, -20, -20, -10, -20, -30, -30, -40, -40, -30, -30, -20, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30],
    }

    getter nodes = 0
    property depth : Int32

    def initialize(@depth : Int32 = 3); end

    # Static evaluation from the point of view of the side to move.
    def evaluate(b : Board) : Int32
      score = 0
      64.times do |i|
        s = b[i]
        next if s.empty?
        idx = s.side.white? ? i : (7 - i // 8) * 8 + i % 8
        v = VALUES[s.piece] + PST[s.piece][idx]
        score += s.side.white? ? v : -v
      end
      b.turn.white? ? score : -score
    end

    def best_move(b : Board) : Move?
      @nodes = 0
      moves = order(b, b.legal_moves)
      return nil if moves.empty?
      best = moves[0]; best_score = Int32::MIN
      alpha = -1_000_000; beta = 1_000_000
      moves.each do |m|
        c = b.clone; c.apply(m)
        score = -search(c, @depth - 1, -beta, -alpha)
        if score > best_score
          best_score = score; best = m
        end
        alpha = Math.max(alpha, score)
      end
      best
    end

    private def search(b : Board, depth : Int32, alpha : Int32, beta : Int32) : Int32
      @nodes += 1
      moves = b.legal_moves
      if moves.empty?
        return b.in_check? ? -100_000 - depth : 0
      end
      return evaluate(b) if depth <= 0
      order(b, moves).each do |m|
        c = b.clone; c.apply(m)
        score = -search(c, depth - 1, -beta, -alpha)
        return beta if score >= beta
        alpha = Math.max(alpha, score)
      end
      alpha
    end

    # Captures and promotions first (MVV-LVA).
    private def order(b : Board, moves : Array(Move)) : Array(Move)
      moves.sort_by do |m|
        victim = b[m.to]
        v = victim.empty? ? 0 : VALUES[victim.piece] * 10 - VALUES[b[m.from].piece] // 10
        v += 800 unless m.promotion.none?
        -v
      end
    end
  end
end
