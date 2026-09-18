require "../../src/eagle"
require "./checkers"
include Eagle

# Checkers. Black moves first. The setup screen picks 1 or 2 players, your color, the AI level
# and whether captures are forced.
#
# Capture rule: with forced capture off (the default) jumping is optional, but once a piece
# starts jumping it must take every jump the chain offers; with it on, standard rules apply
# and you must capture whenever you can.
#
# Click a glowing piece, then a highlighted square. In a multi-jump, click each landing square
# in turn. Keys: U undo, R restart, M setup screen.
class CheckersGame < App
  SIZE      = 66
  ORIGIN    = v2(36, 60)
  PANEL_X   = ORIGIN.x + SIZE * 8 + 28
  SLIDE     = 0.2  # seconds for a plain move
  HOP       = 0.32 # seconds per jump
  AI_SLICE  = 0.008 # seconds of AI search per frame
  AI_PAUSE  = 0.35  # minimum pause before the AI moves, so its moves are easy to follow
  RED       = Color.hex("#c0392b")
  BLACK     = Color.hex("#2c2c2c")
  GLOW      = Color.hex("#ffd54a")
  LEVELS    = Checkers::AI::Level.values

  getter board = Checkers::Board.new(false)
  getter screen : Symbol = :setup
  getter players = 1
  getter human_side = Checkers::Side::Black
  getter level = Checkers::AI::Level::Medium
  getter? forced = false
  getter last : Checkers::Move? = nil
  getter selected : Int32? = nil
  # Squares visited so far by the selected piece (more than one while a jump chain is in progress).
  getter partial = [] of Int32
  getter? animating = false
  # Where the moving piece is drawn during an animation, and how high it is lifted (0..1).
  getter moving_pos : Vec2? = nil
  getter lift = 0_f32
  # Captured squares fading out, with progress 0..1.
  getter fading = {} of Int32 => Float32
  getter ai : Checkers::AI

  @candidates = [] of Checkers::Move
  @legal = [] of Checkers::Move
  @moving_from : Int32? = nil
  @moving_cell : Checkers::Cell? = nil
  @gen = 0
  @ai_busy = false
  @ai_wait = 0_f32
  @menu = CanvasLayer.new
  @buttons = {} of String => Button
  @rule_label : Label? = nil
  @move_snd : Sound? = nil
  @hop_snd : Sound? = nil
  @pop_snd : Sound? = nil

  def initialize(@args : Array(String) = ARGV)
    @ai = Checkers::AI.new(@level)
  end

  def load
    @move_snd = Sound.tone(330, 0.07, Sound::Wave::Triangle, 0.35)
    @hop_snd = Sound.tone(440, 0.06, Sound::Wave::Triangle, 0.3)
    @pop_snd = Sound.tone(700, 0.05, Sound::Wave::Square, 0.18)
    SceneTree.root.add(@menu)
    # `checkers ai` / `checkers two` skips the setup screen
    if @args.includes?("two")
      @players = 2; start
    elsif @args.includes?("ai")
      start
    else
      show_setup
    end
  end

  # --- setup screen ---

  def show_setup
    cancel_motion
    @screen = :setup
    @menu.clear_children
    @buttons.clear
    panel = Panel.new(size: v2(460, 0))
    panel.anchor = Anchor::Center
    panel.fit_content = true
    box = VBox.new(size: v2(440, 0))
    box.position = v2(10, 10)
    box.fit_content = true
    title = Label.new("Checkers", align: TextAlign::Center)
    title.font_scale = 1.5
    box.add(title)
    grid = GridContainer.new(2)
    box.add(grid)
    option_row(grid, "Players", {"1 player" => "p1", "2 players" => "p2"}) { |id| @players = id == "p1" ? 1 : 2 }
    option_row(grid, "You play", {"Black (first)" => "black", "Red" => "red"}) { |id| @human_side = id == "red" ? Checkers::Side::Red : Checkers::Side::Black }
    option_row(grid, "AI", {"Beginner" => "Beginner", "Medium" => "Medium", "Advanced" => "Advanced"}) { |id| @level = Checkers::AI::Level.parse(id) }
    option_row(grid, "Forced capture", {"Off" => "off", "On" => "on"}) { |id| @forced = id == "on" }
    rule = Label.new("", color: Color.gray(0.75), size: v2(420, 0))
    rule.wrap = true
    @rule_label = rule
    box.add(rule)
    box.add(Button.new("Start game") { start }.tap { |b| @buttons["start"] = b })
    box.add(Label.new("Keys: 1/2 players, C color, D difficulty,", color: Color.gray(0.6)))
    box.add(Label.new("F forced capture, Enter start; Tab + Space pick", color: Color.gray(0.6)))
    panel.add(box)
    @menu.add(panel)
    refresh_setup
  end

  private def option_row(grid, title, options : Hash(String, String), &pick : String ->)
    row = HBox.new
    options.each do |text, id|
      b = Button.new(text) { pick.call(id); refresh_setup }
      @buttons[id] = b
      row.add(b)
    end
    grid.add(Label.new(title, size: v2(0, 32)).tap(&.valign = :center), row)
  end

  private def refresh_setup
    sel = {"p1" => @players == 1, "p2" => @players == 2, "black" => @human_side.black?, "red" => @human_side.red?, "on" => @forced, "off" => !@forced}
    LEVELS.each { |l| sel[l.to_s] = @level == l }
    # the chosen option in each row is drawn in the accent color
    sel.each { |id, on| @buttons[id]?.try(&.color = on ? Theme.default.accent : nil) }
    {"black", "red", "Beginner", "Medium", "Advanced"}.each { |id| @buttons[id]?.try(&.disabled = @players == 2) }
    @rule_label.try(&.text = @forced ? "You must capture when you can." : "Captures are optional, but a jump chain you start must be finished.")
  end

  private def setup_key(e : KeyEvent)
    case e.key
    when Key::Num1 then @players = 1
    when Key::Num2 then @players = 2
    when Key::P    then @players = 3 - @players
    when Key::C    then @human_side = @human_side.other
    when Key::D    then @level = LEVELS[(LEVELS.index(@level).not_nil! + 1) % LEVELS.size]
    when Key::F    then @forced = !@forced
    when Key::Enter, Key::KpEnter
      e.handled = true
      return start
    when Key::Space
      # Space activates the focused button, if any
      return if Control.focused
      e.handled = true
      return start
    else return
    end
    e.handled = true
    refresh_setup
  end

  # --- game flow ---

  def start
    cancel_motion
    # the setup widgets are removed, not hidden: hidden controls would still take clicks and keys
    @menu.clear_children
    @buttons.clear
    @screen = :play
    @board = Checkers::Board.new(@forced)
    @ai = Checkers::AI.new(@level)
    @last = nil
    refresh
  end

  # Starts from a given position (for puzzles and tests).
  def start_position(b : Checkers::Board)
    start
    @board = b
    @forced = b.forced_capture?
    refresh
  end

  def vs_ai? : Bool; @players == 1; end

  def human_turn? : Bool; !vs_ai? || @board.turn == @human_side; end

  def busy? : Bool; @animating || @ai_busy; end

  # The side drawn at the bottom of the board.
  def bottom_side : Checkers::Side; vs_ai? ? @human_side : Checkers::Side::Red; end

  private def refresh
    @selected = nil
    @partial.clear
    @candidates.clear
    @legal = @board.legal_moves
    @ai_wait = AI_PAUSE.to_f32
  end

  private def cancel_motion
    @gen += 1
    @animating = false
    @ai_busy = false
    @moving_pos = nil; @moving_from = nil; @moving_cell = nil
    @lift = 0_f32
    @fading.clear
  end

  # Takes back the last move (in 1-player mode, back to your previous turn).
  def undo
    cancel_motion
    if @partial.size > 1
      return refresh
    end
    if vs_ai?
      return unless @board.history.each_with_index.any? { |_, i| side_of_ply(i) == @human_side }
      loop do
        popped_side = side_of_ply(@board.history.size - 1)
        @board.undo
        break if popped_side == @human_side
      end
    else
      @board.undo
    end
    @last = @board.history.last?
    refresh
  end

  # Which side made the ply at *index* of the history.
  private def side_of_ply(index : Int32) : Checkers::Side
    first = @board.history.size.even? ? @board.turn : @board.turn.other
    index.even? ? first : first.other
  end

  # --- coordinates ---

  def square_pos(i : Int32) : Vec2
    f = i % 8; r = i // 8
    if bottom_side.black?
      f = 7 - f; r = 7 - r
    end
    ORIGIN + v2(f * SIZE, (7 - r) * SIZE)
  end

  def square_center(i : Int32) : Vec2; square_pos(i) + v2(SIZE / 2, SIZE / 2); end

  def square_at(p : Vec2) : Int32?
    l = p - ORIGIN
    return nil if l.x < 0 || l.y < 0 || l.x >= SIZE * 8 || l.y >= SIZE * 8
    f = (l.x / SIZE).to_i; r = 7 - (l.y / SIZE).to_i
    if bottom_side.black?
      f = 7 - f; r = 7 - r
    end
    r * 8 + f
  end

  # --- hints ---

  # Pieces the human can move right now (all glow while nothing is selected).
  def hint_squares : Array(Int32)
    return [] of Int32 unless @screen == :play && human_turn? && !busy? && !@board.game_over?
    return [@partial.first] if @partial.size > 1
    @legal.map(&.from).uniq
  end

  # Squares the selected piece can go to next.
  def target_squares : Array(Int32)
    return [] of Int32 if @selected.nil? || busy?
    n = @partial.size
    @candidates.select { |m| m.path.size > n }.map { |m| m.path[n] }.uniq
  end

  # --- input ---

  def input(e : Event)
    if @screen == :setup
      setup_key(e) if e.is_a?(KeyEvent) && e.pressed?
      return
    end
    if e.is_a?(MouseButtonEvent) && e.pressed? && e.button.left?
      click(e.position)
    elsif e.is_a?(KeyEvent) && e.pressed?
      case e.key
      when Key::R then start
      when Key::M then show_setup
      when Key::U then undo unless @animating
      end
    end
  end

  def click(p : Vec2)
    return unless human_turn? && !busy? && !@board.game_over?
    sq = square_at(p)
    return unless sq
    if @selected && target_squares.includes?(sq)
      extend_path(sq)
    elsif @partial.size > 1
      # a jump chain in progress must be finished with the same piece
    elsif @legal.any? { |m| m.from == sq }
      @selected = sq
      @partial = [sq]
      @candidates = @legal.select { |m| m.from == sq }
    else
      @selected = nil; @partial.clear; @candidates.clear
    end
  end

  private def extend_path(sq : Int32)
    @partial << sq
    n = @partial.size
    @candidates.select! { |m| m.path.size >= n && m.path[0, n] == @partial }
    if @candidates.size == 1
      mv = @candidates.first
      @selected = nil
      animate(mv, n - 2) { commit(mv) }
    else
      # several chains share this landing square: animate this hop and wait for the next click
      mv = @candidates.first
      @selected = nil
      animate(mv, n - 2, n - 1) { @selected = @partial.first }
    end
  end

  private def commit(m : Checkers::Move)
    @board.apply(m)
    @last = m
    @moving_pos = nil; @moving_from = nil; @moving_cell = nil
    @lift = 0_f32
    @fading.clear
    (@board.game_over? ? @pop_snd : @move_snd).try(&.play)
    refresh
  end

  # Animates hops *first*...*last* of *m*: a slide for plain moves, a hop arc for jumps with
  # the captured piece popping away, one hop after another. Input waits until it finishes.
  def animate(m : Checkers::Move, first : Int32 = 0, last : Int32 = m.path.size - 1, &done : ->)
    gen = @gen += 1
    @animating = true
    @moving_from = m.from
    @moving_cell ||= @board[m.from]
    Tween.sequence do |s|
      (first...last).each do |h|
        a = square_center(m.path[h]); b = square_center(m.path[h + 1])
        mid = m.capture? ? m.captures[h] : nil
        s.to(mid ? HOP : SLIDE, :quad_in_out) do |t|
          next unless gen == @gen
          @moving_pos = a.lerp(b, t)
          @lift = mid ? Math.sin(t * Math::PI).to_f32 : 0_f32
          @fading[mid] = ((t - 0.4_f32) / 0.6_f32).clamp(0_f32, 1_f32) if mid
        end
        s.call { (mid ? @hop_snd : nil).try(&.play) if gen == @gen }
      end
      s.call do
        if gen == @gen
          @animating = false
          done.call
        end
      end
    end
  end

  # --- AI ---

  def update(dt : Float32)
    Eagle.quit if Input.pressed?(Key::Escape) && @screen == :play
    return unless @screen == :play && vs_ai? && !human_turn? && !@animating && !@board.game_over?
    unless @ai_busy
      @ai.start(@board.clone)
      @ai_busy = true
    end
    @ai_wait -= dt
    return unless @ai.think(AI_SLICE) && @ai_wait <= 0
    @ai_busy = false
    if mv = @ai.result
      animate(mv) { commit(mv) }
    end
  end

  # --- drawing ---

  def status_text : String
    case @board.status
    when .red_wins?   then winner_text(Checkers::Side::Red)
    when .black_wins? then winner_text(Checkers::Side::Black)
    when .draw?       then "Draw: #{@board.draw_reason}"
    else
      who = side_name(@board.turn)
      text = vs_ai? ? (human_turn? ? "Your move (#{who})" : "AI (#{who}) is thinking...") : "#{who} to move"
      text += @forced ? ", must capture" : ", capture available" if @legal.any?(&.capture?) && human_turn?
      text += ", keep jumping" if @partial.size > 1
      text
    end
  end

  private def winner_text(side : Checkers::Side) : String
    return "#{side_name(side)} wins!" unless vs_ai?
    side == @human_side ? "You win!" : "The AI wins"
  end

  def side_name(s : Checkers::Side) : String; s.red? ? "Red" : "Black"; end

  def draw(g : Graphics)
    return unless @screen == :play
    pulse = (0.5 + 0.5 * Math.sin(Clock.elapsed * 5)).to_f32
    draw_board(g)
    targets = target_squares
    targets.each do |t|
      c = square_center(t)
      g.circle(c, SIZE * 0.2 + pulse * 3, color: GLOW.with_alpha(0.35 + 0.25 * pulse))
      g.circle(c, SIZE * 0.2 + pulse * 3, DrawMode::Line, color: GLOW)
    end
    hints = hint_squares
    64.times do |i|
      c = @board[i]
      next unless c
      next if i == @moving_from
      next if @partial.size > 1 && i == @partial.first
      f = @fading[i]? || 0_f32
      next if f >= 1
      center = square_center(i)
      if hints.includes?(i) && @partial.size <= 1
        strong = @selected == i
        g.circle(center, SIZE * 0.46 + (strong ? 2 : pulse * 2), color: GLOW.with_alpha(strong ? 0.8 : 0.25 + 0.3 * pulse))
      end
      draw_piece(g, center, c, 0_f32, 1 - f, 1 + f * 0.5_f32)
    end
    if cell = moving_cell
      pos = @moving_pos || square_center(@partial.last? || @moving_from || 0)
      if @partial.size > 1 && !@animating
        g.circle(pos, SIZE * 0.46 + 2, color: GLOW.with_alpha(0.8))
      end
      draw_piece(g, pos, cell, @lift, 1_f32, 1_f32)
    end
    draw_panel(g)
    draw_game_over(g) if @board.game_over? && !@animating
  end

  private def moving_cell : Checkers::Cell?
    return @moving_cell if @moving_cell
    return @board[@partial.first] if @partial.size > 1
    nil
  end

  private def draw_board(g : Graphics)
    g.rect(ORIGIN.x - 6, ORIGIN.y - 6, SIZE * 8 + 12, SIZE * 8 + 12, color: Color.hex("#3b2a1e"))
    last = @last
    64.times do |i|
      p = square_pos(i)
      c = Checkers.dark?(i) ? Color.hex("#6b4f3a") : Color.hex("#e8d8c0")
      c = c.lerp(Color::YELLOW, 0.3) if last && last.path.includes?(i)
      g.rect(p.x, p.y, SIZE, SIZE, color: c)
    end
    # file letters and rank numbers from the bottom player's view
    8.times do |k|
      f = square_pos(k).x + SIZE / 2
      r = square_pos(k * 8).y + SIZE / 2
      g.print(('a' + k).to_s, f, ORIGIN.y + SIZE * 8 + 8, Color.gray(0.5), align: TextAlign::Center)
      g.print((k + 1).to_s, ORIGIN.x - 20, r - 7, Color.gray(0.5))
    end
  end

  private def draw_piece(g : Graphics, p : Vec2, c : Checkers::Cell, lift : Float32, alpha : Float32, scale : Float32)
    base = c.side.red? ? RED : BLACK
    r = SIZE * 0.38 * scale * (1 + lift * 0.18)
    up = v2(0, -lift * SIZE * 0.35)
    g.circle(p + v2(2 + lift * 6, 3 + lift * 10), r, color: Color.new(0, 0, 0, 0.35 * alpha * (1 - lift * 0.5)))
    g.circle(p + up, r, color: base.with_alpha(alpha))
    g.circle(p + up, r * 0.78, DrawMode::Line, color: base.lighten(0.3).with_alpha(alpha))
    if c.king?
      g.circle(p + up, r * 0.45, color: GLOW.with_alpha(alpha))
      g.print("K", p.x + up.x, p.y + up.y - 7, BLACK.with_alpha(alpha), align: TextAlign::Center)
    end
  end

  private def draw_panel(g : Graphics)
    x = PANEL_X; y = ORIGIN.y.to_f32
    w = 900 - x - 16
    g.print("Checkers", x, y, Color::WHITE, scale: 1.5)
    y += 40
    mode = vs_ai? ? "You (#{side_name(@human_side)}) vs AI, #{@level.to_s.downcase}" : "Two players"
    g.printf(mode, x, y, w, color: Color.gray(0.8)); y += 44
    turn_color = @board.turn.red? ? RED : BLACK
    g.circle(x + 10, y + 9, 9, color: turn_color)
    g.circle(x + 10, y + 9, 9, DrawMode::Line, color: Color.gray(0.7))
    g.printf(status_text, x + 28, y, w - 28, color: GLOW); y += 70
    g.print("Red #{@board.count(Checkers::Side::Red)}   Black #{@board.count(Checkers::Side::Black)}", x, y, Color.gray(0.8)); y += 34
    rule = @forced ? "Forced capture ON: you must jump when you can." : "Forced capture OFF: jumping is optional, but a chain you start must be finished."
    g.printf(rule, x, y, w, color: Color.gray(0.65)); y += 92
    g.printf("Click a glowing piece, then a glowing square. For a multi-jump click each landing square.", x, y, w, color: Color.gray(0.55)); y += 112
    ["U  undo", "R  restart", "M  setup screen"].each { |k| g.print(k, x, y, Color.gray(0.55)); y += 22 }
  end

  private def draw_game_over(g : Graphics)
    cx = ORIGIN.x + SIZE * 4; cy = ORIGIN.y + SIZE * 4
    g.rounded_rect(cx - 200, cy - 56, 400, 112, 12, color: Color.new(0.05, 0.05, 0.07, 0.88))
    g.print(status_text, cx, cy - 36, GLOW, scale: 1.5, align: TextAlign::Center)
    g.print("R play again   U undo   M setup", cx, cy + 16, Color.gray(0.8), align: TextAlign::Center)
  end
end
