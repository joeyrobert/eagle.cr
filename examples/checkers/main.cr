require "../../src/eagle"
require "./checkers"
include Eagle

# Checkers. Red (bottom) moves first. Captures are mandatory, multi-jumps supported.
# Menu: pick 1 player (vs AI) or 2 players. Keys: R restart, M menu, U undo, 1-8 AI depth.
class CheckersGame < App
  SIZE = 70
  ORIGIN = v2(50, 50)

  @board = Checkers::Board.new
  @ai = Checkers::AI.new(6)
  @selected : Int32? = nil
  @legal = [] of Checkers::Move
  @mode : Symbol = :menu
  @last : Checkers::Move? = nil
  @menu = CanvasLayer.new
  @status = ""
  @snd : Sound? = nil

  def load
    @snd = Sound.tone(330, 0.07, Sound::Wave::Triangle, 0.35)
    SceneTree.root.add(@menu)
    build_menu
    # `checkers ai` / `checkers two` skips the menu
    start(:ai) if ARGV.includes?("ai")
    start(:two) if ARGV.includes?("two")
  end

  def build_menu
    @menu.clear_children
    panel = Panel.new(size: v2(360, 0))
    panel.anchor = Anchor::Center
    panel.fit_content = true
    box = VBox.new(size: v2(340, 0))
    box.position = v2(10, 10)
    box.fit_content = true
    title = Label.new("Checkers", align: TextAlign::Center)
    title.font_scale = 1.5
    box.add(title)
    box.add(Button.new("1 player (vs AI)") { start(:ai) })
    box.add(Button.new("2 players") { start(:two) })
    depth_label = Label.new("AI depth #{@ai.depth}")
    depth = Slider.new(1, 8, @ai.depth, step: 1)
    depth.on_value_changed { |v| @ai.depth = v.to_i; depth_label.text = "AI depth #{v.to_i}" }
    box.add(depth_label, depth)
    panel.add(box)
    @menu.add(panel)
    @menu.visible = true
  end

  def start(mode : Symbol)
    @mode = mode
    @board = Checkers::Board.new
    @selected = nil; @legal.clear; @last = nil
    @menu.visible = false
    update_status
  end

  def square_at(p : Vec2) : Int32?
    l = p - ORIGIN
    return nil if l.x < 0 || l.y < 0 || l.x >= SIZE * 8 || l.y >= SIZE * 8
    (7 - (l.y / SIZE).to_i) * 8 + (l.x / SIZE).to_i
  end

  def square_pos(i : Int32) : Vec2
    ORIGIN + v2((i % 8) * SIZE, (7 - i // 8) * SIZE)
  end

  def human_turn? : Bool
    @mode == :two || @board.turn.red?
  end

  def input(e : Event)
    return if @mode == :menu
    if e.is_a?(MouseButtonEvent) && e.pressed? && e.button.left? && human_turn? && !@board.game_over?
      sq = square_at(e.position)
      return unless sq
      if @selected && (mv = @legal.find { |m| m.to == sq })
        @board.play(mv)
        @last = mv
        @snd.try(&.play)
        @selected = nil; @legal.clear
        update_status
      elsif (c = @board[sq]) && c.side == @board.turn
        @selected = sq
        @legal = @board.legal_moves_from(sq)
      else
        @selected = nil; @legal.clear
      end
    elsif e.is_a?(KeyEvent) && e.pressed?
      case e.key
      when Key::R then start(@mode)
      when Key::M then @mode = :menu; build_menu
      when Key::U then undo
      end
    end
  end

  def undo
    n = (@mode == :ai && @board.history.size >= 2) ? 2 : 1
    return if @board.history.size < n
    hist = @board.history[0...-n]
    @board = Checkers::Board.new
    hist.each { |m| @board.apply(m) }
    @last = hist.last?
    @selected = nil; @legal.clear
    update_status
  end

  def update(dt : Float32)
    if @mode == :ai && @board.turn.black? && !@board.game_over?
      if mv = @ai.best_move(@board)
        @board.apply(mv)
        @last = mv
        @snd.try(&.play(pitch: 0.8))
        update_status
      end
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def update_status
    @status = case @board.status
              when .red_wins? then "Red wins!"
              when .black_wins? then "Black wins!"
              when .draw? then "Draw"
              else "#{@board.turn.red? ? "Red" : "Black"} to move#{@board.legal_moves.first?.try(&.capture?) ? " — must capture" : ""}"
              end
  end

  def draw(g : Graphics)
    return if @mode == :menu
    64.times do |i|
      p = square_pos(i)
      c = Checkers.dark?(i) ? Color.hex("#6b4f3a") : Color.hex("#e8d8c0")
      c = c.lerp(Color::YELLOW, 0.35) if (l = @last) && (l.path.includes?(i))
      c = c.lerp(Color::GREEN, 0.4) if @selected == i
      g.rect(p.x, p.y, SIZE, SIZE, color: c)
    end
    @legal.each { |m| p = square_pos(m.to) + v2(SIZE / 2, SIZE / 2); g.circle(p, 10, color: Color.new(0, 0, 0, 0.3)) }
    64.times do |i|
      c = @board[i]
      next unless c
      p = square_pos(i) + v2(SIZE / 2, SIZE / 2)
      base = c.side.red? ? Color.hex("#c0392b") : Color.hex("#2c2c2c")
      g.circle(p + v2(2, 3), SIZE * 0.38, color: Color.new(0, 0, 0, 0.35))
      g.circle(p, SIZE * 0.38, color: base)
      g.circle(p, SIZE * 0.3, DrawMode::Line, color: base.lighten(0.3))
      g.print("K", p.x, p.y - 8, Color::YELLOW, align: TextAlign::Center) if c.king?
    end
    g.print(@status, ORIGIN.x, ORIGIN.y + SIZE * 8 + 14, Color::WHITE)
    g.print("red #{@board.count(Checkers::Side::Red)}  black #{@board.count(Checkers::Side::Black)}   #{@mode == :ai ? "vs AI depth #{@ai.depth}, nodes #{@ai.nodes}" : "two players"}   U undo  R restart  M menu", ORIGIN.x, ORIGIN.y + SIZE * 8 + 38, Color::GRAY)
  end
end

Eagle.run(CheckersGame, title: "Eagle Checkers", width: 900, height: 700)
