require "../gpu_spec_helper"
require "../../examples/checkers/game"

# Drives the real checkers game through the engine loop with scripted input.
module CheckersHarness
  @@game : CheckersGame? = nil
  @@hooked = false

  def self.boot(args = [] of String) : CheckersGame
    unless @@hooked
      Eagle.app.on_input { |e| @@game.try(&.input(e)) }
      Eagle.app.on_update { |dt| @@game.try(&.update(dt)) }
      Eagle.app.on_draw { |g| @@game.try(&.draw(g)) }
      @@hooked = true
    end
    SceneTree.reset; Input.reset; Script.clear; Tween.clear
    g = CheckersGame.new(args)
    @@game = g
    g.load
    3.times { Eagle.step }
    g
  end

  def self.stop : Nil
    @@game = nil
    SceneTree.reset; Tween.clear
  end
end

private def frames(n = 2)
  n.times { Eagle.step }
end

private def settle(g : CheckersGame, seconds = 20.0)
  t = Time.instant
  frames(1)
  while g.busy? && (Time.instant - t).total_seconds < seconds
    Eagle.step
  end
  g.busy?.should be_false
end

private def sq(name)
  Checkers.index(name)
end

private def click_square(g : CheckersGame, name : String)
  Script.click(g.square_center(sq(name)))
  frames
end

private def button(text : String) : Button
  found = nil
  SceneTree.root.each_descendant { |n| found = n if n.is_a?(Button) && n.text == text }
  found.not_nil!
end

private def two_player(rows, turn, forced = true) : CheckersGame
  g = CheckersHarness.boot(["two"])
  g.start_position(Checkers::Board.from_layout(rows, turn, forced))
  frames
  g
end

describe "Checkers game" do
  after_each { CheckersHarness.stop }

  gpu_it "shows the setup screen with forced capture off, and keys change the options" do
    g = CheckersHarness.boot
    g.screen.should eq :setup
    g.forced?.should be_false
    g.players.should eq 1
    g.level.medium?.should be_true
    Script.key(Key::F); Script.key(Key::D); Script.key(Key::C)
    frames(3)
    g.forced?.should be_true
    g.level.advanced?.should be_true
    g.human_side.red?.should be_true
    button("On").color.should eq Theme.default.accent
    button("Off").color.should be_nil
    Script.key(Key::Enter)
    frames(3)
    g.screen.should eq :play
    g.board.forced_capture?.should be_true
    g.ai.level.advanced?.should be_true
    g.bottom_side.red?.should be_true
  end

  gpu_it "starts from the setup screen with the mouse" do
    g = CheckersHarness.boot
    Script.click(button("2 players").global_rect.center); frames
    Script.click(button("On").global_rect.center); frames
    g.players.should eq 2
    button("Red").disabled?.should be_true
    Script.click(button("Start game").global_rect.center); frames(3)
    g.screen.should eq :play
    g.vs_ai?.should be_false
    g.board.forced_capture?.should be_true
  end

  # Regression: the hidden menu's buttons kept taking clicks and keys, so clicking the board
  # where a button used to be (or pressing Space) restarted the game.
  gpu_it "removes the setup widgets once the game starts" do
    g = CheckersHarness.boot
    Script.click(button("2 players").global_rect.center); frames
    spots = ["1 player", "2 players", "Start game", "Medium"].map { |t| button(t).global_rect.center }
    Script.click(button("Start game").global_rect.center); frames(3)
    g.screen.should eq :play
    click_square(g, "b6"); click_square(g, "a5")
    settle(g)
    g.board.history.size.should eq 1
    spots.each { |p| Script.click(p); frames }
    Script.key(Key::Space); Script.key(Key::Enter); frames(3)
    g.screen.should eq :play
    g.board.history.size.should eq 1
  end

  gpu_it "maps clicks to squares in both orientations" do
    {["two"], ["ai"]}.each do |args|
      g = CheckersHarness.boot(args)
      64.times { |i| g.square_at(g.square_center(i)).should eq i }
      bottom_left = g.square_at(CheckersGame::ORIGIN + v2(5, CheckersGame::SIZE * 8 - 5)).not_nil!
      Checkers.dark?(bottom_left).should be_true
      # the bottom player's pieces sit on the bottom rows
      g.board[bottom_left].not_nil!.side.should eq g.bottom_side
      g.square_at(CheckersGame::ORIGIN - v2(1, 1)).should be_nil
    end
    CheckersHarness.boot(["two"]).bottom_side.red?.should be_true
    CheckersHarness.boot(["ai"]).bottom_side.black?.should be_true
  end

  gpu_it "moves by clicking, animates, and blocks input while animating" do
    g = CheckersHarness.boot(["two"])
    g.hint_squares.sort.should eq ["b6", "d6", "f6", "h6"].map { |n| sq(n) }.sort
    click_square(g, "b6")
    g.selected.should eq sq("b6")
    g.target_squares.sort.should eq [sq("a5"), sq("c5")]
    click_square(g, "a5")
    g.animating?.should be_true
    g.board.history.size.should eq 0
    g.hint_squares.should be_empty
    click_square(g, "d6") # ignored while the piece slides
    g.selected.should be_nil
    settle(g)
    g.board.history.map(&.to_s).should eq ["b6-a5"]
    g.board.turn.red?.should be_true
    g.hint_squares.should eq g.board.legal_moves.map(&.from).uniq
  end

  gpu_it "only highlights capturing pieces when captures are forced" do
    rows = ["........", "........", "........", "....b...", "...r....", "........", "r.......", "........"]
    forced = two_player(rows, Checkers::Side::Red, true)
    forced.hint_squares.should eq [sq("d4")]
    forced.status_text.should contain "must capture"
    free = two_player(rows, Checkers::Side::Red, false)
    free.hint_squares.sort.should eq [sq("a2"), sq("d4")]
    free.status_text.should contain "capture available"
    click_square(free, "d4")
    free.target_squares.sort.should eq [sq("c5"), sq("f6")]
  end

  gpu_it "animates each hop of a multi-jump and pops the captured pieces" do
    g = two_player(["........", "........", "........", "........", "...b.b..", "........", "...b.b..", "....r..."], Checkers::Side::Red)
    click_square(g, "e1")
    g.target_squares.sort.should eq [sq("c3"), sq("g3")]
    click_square(g, "c3") # only one chain goes through c3, so it plays out to e5
    visited = [] of Vec2
    max_lift = 0_f32
    faded = false
    t = Time.instant
    while g.animating? && (Time.instant - t).total_seconds < 5
      g.moving_pos.try { |p| visited << p }
      max_lift = Math.max(max_lift, g.lift)
      faded ||= (g.fading[sq("d2")]? || 0) > 0.5 && !g.board[sq("d2")].nil?
      Eagle.step
    end
    max_lift.should be > 0.8
    faded.should be_true
    visited.min_of { |p| (p - g.square_center(sq("c3"))).length }.should be < 12
    visited.last.approx?(g.square_center(sq("e5")), 12).should be_true
    g.board.history.map(&.to_s).should eq ["e1xc3xe5"]
    g.board[sq("d2")].should be_nil
    g.board[sq("f2")].should_not be_nil
  end

  gpu_it "waits for the next landing square when chains split" do
    g = two_player(["........", "........", "...b.b..", "........", "...b....", "..r.....", "......r.", "........"], Checkers::Side::Red)
    g.hint_squares.should eq [sq("c3")]
    click_square(g, "c3")
    click_square(g, "e5")
    settle(g)
    g.partial.should eq [sq("c3"), sq("e5")]
    g.board.history.should be_empty
    g.target_squares.sort.should eq [sq("c7"), sq("g7")]
    g.status_text.should contain "keep jumping"
    click_square(g, "g2") # the chain must be finished with the same piece
    g.partial.should eq [sq("c3"), sq("e5")]
    click_square(g, "g7")
    settle(g)
    g.board.history.map(&.to_s).should eq ["c3xe5xg7"]
    g.board.count(Checkers::Side::Black).should eq 1
  end

  gpu_it "lets the AI reply with a legal move without freezing frames" do
    g = CheckersHarness.boot(["ai"])
    g.human_side.black?.should be_true
    click_square(g, "b6"); click_square(g, "a5")
    t = Time.instant
    worst = 0.0
    frames_run = 0
    while (g.busy? || g.board.history.size < 2) && (Time.instant - t).total_seconds < 20
      f = Time.instant
      Eagle.step
      worst = Math.max(worst, (Time.instant - f).total_seconds)
      frames_run += 1
    end
    g.board.history.size.should eq 2
    worst.should be < 0.1
    frames_run.should be > 5
    replay = Checkers::Board.new(false)
    g.board.history.each { |m| replay.play(m).should be_true }
    g.human_turn?.should be_true
  end

  gpu_it "undoes back to the human's turn in 1-player mode" do
    g = CheckersHarness.boot(["ai"])
    Script.key(Key::U); frames
    g.board.history.should be_empty
    click_square(g, "b6"); click_square(g, "a5")
    settle(g)
    t = Time.instant
    until g.board.history.size == 2 || (Time.instant - t).total_seconds > 10
      Eagle.step
    end
    settle(g)
    Script.key(Key::U); frames
    g.board.history.should be_empty
    g.human_turn?.should be_true
    g.board.forced_capture?.should be_false
  end

  gpu_it "undoes to the human's turn when the AI moved first" do
    g = CheckersHarness.boot
    Script.key(Key::C); Script.key(Key::Enter); frames(3)
    g.human_side.red?.should be_true
    t = Time.instant
    until g.board.history.size == 1 && !g.busy? || (Time.instant - t).total_seconds > 10
      Eagle.step
    end
    Script.key(Key::U); frames
    g.board.history.size.should eq 1 # nothing of yours to take back
    g.human_turn?.should be_true
  end

  gpu_it "ends the game, ignores board clicks, and restarts with R" do
    g = two_player(["........", "........", "........", "........", "....b...", "...r....", "........", "........"], Checkers::Side::Red)
    click_square(g, "d3"); click_square(g, "f5")
    settle(g)
    g.board.status.red_wins?.should be_true
    g.status_text.should eq "Red wins!"
    g.hint_squares.should be_empty
    click_square(g, "f5")
    g.selected.should be_nil
    Script.key(Key::R); frames
    g.board.history.should be_empty
    g.board.count(Checkers::Side::Black).should eq 12
    Script.key(Key::M); frames
    g.screen.should eq :setup
  end
end
