require "../../src/eagle"
require "./chess"
include Eagle

# Chess: click a piece then a destination. You play White; the AI plays Black.
# Keys: U undo, R restart, N new game vs human (two players), 1-4 set AI depth.
class ChessGame < App
  SIZE = 72
  ORIGIN = v2(60, 40)

  @board = Chess::Board.new
  @ai = Chess::AI.new(3)
  @selected : Int32? = nil
  @legal = [] of Chess::Move
  @status = ""
  @vs_ai = true
  @thinking = false
  @last : Chess::Move? = nil
  @move_sound : Sound? = nil
  @capture_sound : Sound? = nil
  @font : Font? = nil

  def load
    @move_sound = Sound.tone(440, 0.06, Sound::Wave::Triangle, 0.4)
    @capture_sound = Sound.tone(220, 0.12, Sound::Wave::Square, 0.3)
    ttf = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"].find { |p| File.exists?(p) }
    @font = Font.load(ttf, 40) if ttf
    update_status
  end

  def square_at(p : Vec2) : Int32?
    l = p - ORIGIN
    return nil if l.x < 0 || l.y < 0 || l.x >= SIZE * 8 || l.y >= SIZE * 8
    f = (l.x / SIZE).to_i; r = 7 - (l.y / SIZE).to_i
    r * 8 + f
  end

  def square_pos(i : Int32) : Vec2
    ORIGIN + v2((i % 8) * SIZE, (7 - i // 8) * SIZE)
  end

  def input(e : Event)
    return if @thinking
    if e.is_a?(MouseButtonEvent) && e.pressed? && e.button.left?
      sq = square_at(e.position)
      return unless sq
      if (sel = @selected) && (mv = @legal.find { |m| m.to == sq })
        play(mv)
      else
        s = @board[sq]
        if !s.empty? && s.side == @board.turn
          @selected = sq
          @legal = @board.legal_moves_from(sq)
        else
          @selected = nil; @legal.clear
        end
      end
    elsif e.is_a?(KeyEvent) && e.pressed?
      case e.key
      when Key::U then undo
      when Key::R then restart
      when Key::N then @vs_ai = !@vs_ai; update_status
      when Key::Num1, Key::Num2, Key::Num3, Key::Num4
        @ai.depth = e.key.value - Key::Num1.value + 1; update_status
      end
    end
  end

  def play(m : Chess::Move)
    capture = !@board[m.to].empty? || m.en_passant?
    # promote to queen by default
    m = Chess::Move.new(m.from, m.to, Chess::Piece::Queen) unless m.promotion.none?
    @board.play(m)
    @last = @board.history.last
    (capture ? @capture_sound : @move_sound).try(&.play)
    @selected = nil; @legal.clear
    update_status
    if @vs_ai && @board.turn.black? && !@board.game_over?
      @thinking = true
      @status = "Thinking..."
    end
  end

  def update(dt : Float32)
    if @thinking
      # AI move (blocking for a few ms at depth 3; fine for a demo)
      if mv = @ai.best_move(@board)
        @board.apply(mv)
        @last = mv
        @move_sound.try(&.play(pitch: 0.8))
      end
      @thinking = false
      update_status
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def undo
    n = (@vs_ai && @board.history.size >= 2) ? 2 : 1
    return if @board.history.size < n
    hist = @board.history[0...-n]
    @board = Chess::Board.new
    hist.each { |m| @board.apply(m) }
    @last = hist.last?
    @selected = nil; @legal.clear
    update_status
  end

  def restart
    @board = Chess::Board.new
    @selected = nil; @legal.clear; @last = nil
    update_status
  end

  def update_status
    st = @board.status
    who = @board.turn.white? ? "White" : "Black"
    @status = case st
              when .checkmate? then "Checkmate! #{@board.turn.other.white? ? "White" : "Black"} wins"
              when .stalemate? then "Stalemate"
              when .draw? then "Draw"
              when .check? then "#{who} to move — check!"
              else "#{who} to move"
              end
    @status += "   (vs AI depth #{@ai.depth})" if @vs_ai
  end

  LETTERS = {Chess::Piece::King => "K", Chess::Piece::Queen => "Q", Chess::Piece::Rook => "R", Chess::Piece::Bishop => "B", Chess::Piece::Knight => "N", Chess::Piece::Pawn => "P"}
  GLYPHS = {Chess::Piece::King => "♚", Chess::Piece::Queen => "♛", Chess::Piece::Rook => "♜", Chess::Piece::Bishop => "♝", Chess::Piece::Knight => "♞", Chess::Piece::Pawn => "♟"}

  def draw(g : Graphics)
    light = Color.hex("#f0d9b5"); dark = Color.hex("#b58863")
    64.times do |i|
      p = square_pos(i)
      c = ((i % 8 + i // 8) % 2 == 0) ? dark : light
      if (l = @last) && (l.from == i || l.to == i)
        c = c.lerp(Color.hex("#f6f669"), 0.5)
      end
      c = c.lerp(Color.hex("#4caf50"), 0.5) if @selected == i
      g.rect(p.x, p.y, SIZE, SIZE, color: c)
    end
    if @board.in_check?
      k = square_pos(@board.king_square(@board.turn))
      g.rect(k.x, k.y, SIZE, SIZE, color: Color::RED.with_alpha(0.4))
    end
    @legal.each do |m|
      p = square_pos(m.to) + v2(SIZE / 2, SIZE / 2)
      if @board[m.to].empty? && !m.en_passant?
        g.circle(p, 10, color: Color.new(0, 0, 0, 0.25))
      else
        g.circle(p, SIZE / 2 - 4, DrawMode::Line, color: Color.new(0, 0, 0, 0.3))
      end
    end
    # coordinates
    8.times do |i|
      g.print(('a'.ord + i).chr.to_s, ORIGIN.x + i * SIZE + SIZE - 14, ORIGIN.y + SIZE * 8 + 4, Color::GRAY)
      g.print((8 - i).to_s, ORIGIN.x - 20, ORIGIN.y + i * SIZE + 4, Color::GRAY)
    end
    font = @font
    64.times do |i|
      s = @board[i]
      next if s.empty?
      p = square_pos(i) + v2(SIZE / 2, SIZE / 2)
      fill = s.side.white? ? Color::WHITE : Color.hex("#202020")
      outline = s.side.white? ? Color.hex("#202020") : Color.hex("#e0e0e0")
      if font && font.is_a?(TrueTypeFont) && font.as(TrueTypeFont).ttf.has_glyph?('♚')
        glyph = GLYPHS[s.piece]
        w = font.width(glyph)
        g.print(glyph, p.x - w / 2 + 2, p.y - font.height / 2 + 2, Color.new(0, 0, 0, 0.35), font)
        g.print(glyph, p.x - w / 2, p.y - font.height / 2, fill, font)
      else
        g.circle(p, SIZE * 0.36, color: outline)
        g.circle(p, SIZE * 0.32, color: fill)
        g.print(LETTERS[s.piece], p.x, p.y - 8, outline, scale: 1, align: TextAlign::Center)
      end
    end
    g.print(@status, ORIGIN.x, ORIGIN.y + SIZE * 8 + 28, Color::WHITE)
    g.print("click to move  U undo  R restart  N toggle AI  1-4 AI depth  moves #{@board.history.size}  nodes #{@ai.nodes}", ORIGIN.x, ORIGIN.y + SIZE * 8 + 52, Color::GRAY)
    g.print("FEN #{@board.to_fen}", ORIGIN.x, ORIGIN.y + SIZE * 8 + 76, Color.gray(0.4))
    # captured pieces
    cap = @board.captured.reject(&.empty?)
    x = ORIGIN.x + SIZE * 8 + 30
    g.print("Captured", x, ORIGIN.y, Color::WHITE)
    cap.each_with_index do |c, i|
      g.print(LETTERS[c.piece], x + (i % 6) * 22, ORIGIN.y + 26 + (i // 6) * 22, c.side.white? ? Color::WHITE : Color.gray(0.55))
    end
  end
end

Eagle.run(ChessGame, title: "Eagle Chess", width: 1000, height: 740)
