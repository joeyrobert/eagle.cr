require "../spec_helper"
require "../../examples/checkers/checkers"

private def layout(rows, turn = Checkers::Side::Red, forced = true)
  Checkers::Board.from_layout(rows, turn, forced)
end

private def names(moves)
  moves.map(&.to_s).sort
end

private def sq(name)
  Checkers.index(name)
end

# Plays a full game between two AIs and checks every move against the rules.
private def play_game(red : Checkers::AI, black : Checkers::AI, forced : Bool, max_plies = 300) : Checkers::Status
  b = Checkers::Board.new(forced)
  max_plies.times do
    break if b.game_over?
    ai = b.turn.red? ? red : black
    m = ai.best_move(b).not_nil!
    b.legal_moves.includes?(m).should be_true
    b.play(m).should be_true
  end
  b.status
end

describe Checkers::Board do
  it "starts with 12 pieces each, Black to move, and 7 opening moves" do
    b = Checkers::Board.new
    b.count(Checkers::Side::Red).should eq 12
    b.count(Checkers::Side::Black).should eq 12
    b.turn.black?.should be_true
    b.legal_moves.size.should eq 7
    b.legal_moves.none?(&.capture?).should be_true
    b.legal_moves.all? { |m| m.to // 8 < m.from // 8 }.should be_true # black moves down
    Checkers.dark?(sq("a1")).should be_true
    Checkers.dark?(sq("h1")).should be_false
  end

  it "moves men diagonally forward only and kings both ways" do
    red = layout(["........", "........", "........", "........", "...r....", "........", "........", "........"])
    names(red.legal_moves).should eq ["d4-c5", "d4-e5"]
    black = layout(["........", "........", "........", "........", "...b....", "........", "........", "........"], Checkers::Side::Black)
    names(black.legal_moves).should eq ["d4-c3", "d4-e3"]
    king = layout(["........", "........", "........", "........", "...R....", "........", "........", "........"])
    names(king.legal_moves).should eq ["d4-c3", "d4-c5", "d4-e3", "d4-e5"]
  end

  it "only lets men capture forward, kings capture backwards" do
    man = layout(["........", "........", "........", "........", "...r....", "..b.....", "........", "........"])
    man.legal_moves.none?(&.capture?).should be_true
    king = layout(["........", "........", "........", "........", "...R....", "..b.....", "........", "........"])
    names(king.legal_moves).should eq ["d4xb2"]
  end

  it "forces captures and supports multi-jumps" do
    b = layout(["........", "........", "...b.b..", "........", "...b....", "..r.....", "........", "........"])
    names(b.legal_moves).should eq ["c3xe5xc7", "c3xe5xg7"]
    b.play("c3xe5").should be_false # a chain must be finished
    b.play("c3xe5xg7").should be_true
    b.count(Checkers::Side::Black).should eq 1
    b[sq("g7")].not_nil!.side.red?.should be_true
  end

  it "makes captures optional when forced capture is off, but chains must still be finished" do
    rows = ["........", "........", "...b.b..", "........", "...b....", "..r.....", "........", "........"]
    b = layout(rows, forced: false)
    names(b.legal_moves).should eq ["c3-b4", "c3xe5xc7", "c3xe5xg7"]
    b.play("c3xe5").should be_false
    b.play("c3-b4").should be_true
    b.count(Checkers::Side::Black).should eq 3
    b.forced_capture?.should be_false
    layout(rows).forced_capture?.should be_true
  end

  it "lets the player choose between chains that end on the same square" do
    b = layout(["........", "........", "........", "........", "...b.b..", "........", "...b.b..", "....r..."])
    names(b.legal_moves).should eq ["e1xc3xe5", "e1xg3xe5"]
    left = b.clone
    left.play("e1xc3xe5").should be_true
    left[sq("d2")].should be_nil
    left[sq("f2")].should_not be_nil
    right = b.clone
    right.play("e1xg3xe5").should be_true
    right[sq("f2")].should be_nil
    right[sq("d2")].should_not be_nil
  end

  it "crowns kings, which move backwards, and ends the move on crowning" do
    b = layout(["........", "..b.b...", ".....r..", "........", "........", "........", "........", "........"])
    # after f6xd8 the new king could jump c7, but crowning ends the turn
    b.legal_moves.map(&.to_s).should eq ["f6xd8"]
    b.play("f6xd8").should be_true
    b[sq("d8")].not_nil!.king?.should be_true
    b[sq("c7")].should_not be_nil
    b.turn.black?.should be_true
  end

  it "lets a king continue a chain through its starting square" do
    b = layout(["........", "........", ".b.b....", "........", ".b.b....", "..R.....", "........", "........"])
    names(b.legal_moves).should eq ["c3xa5xc7xe5xc3", "c3xe5xc7xa5xc3"]
    b.play("c3xe5xc7xa5xc3").should be_true
    b.count(Checkers::Side::Black).should eq 0
    b[sq("c3")].not_nil!.king?.should be_true
  end

  it "detects wins when a side has no pieces or no moves" do
    b = layout(["........", "........", "........", "........", "........", "........", ".b......", "....r..."], Checkers::Side::Black)
    b.status.playing?.should be_true
    stuck = layout(["........", "........", "........", "........", "........", "........", ".b......", "r.r....."], Checkers::Side::Black)
    stuck.status.red_wins?.should be_true
    lost = layout(["........", "........", "........", "........", "........", "........", "........", "........"])
    lost.status.black_wins?.should be_true
    blocked = layout(["........", "........", "........", "........", "........", ".b.b....", "b.b.....", ".r......"])
    blocked.status.black_wins?.should be_true
  end

  it "draws after 40 quiet moves each, resetting on captures and man moves" do
    b = layout([".R......", "........", "........", "........", "........", "........", "........", "......B."])
    b.quiet_moves = Checkers::QUIET_LIMIT - 1
    b.play("b8-a7").should be_true
    b.status.draw?.should be_true
    b.draw_reason.not_nil!.should contain "40"
    m = layout(["........", "........", "........", "....b...", "........", "........", ".r......", "........"])
    m.quiet_moves = 50
    m.play("b2-a3").should be_true
    m.quiet_moves.should eq 0
  end

  it "prefers a win over the quiet-move draw" do
    stuck = layout(["........", "........", "........", "........", "........", "........", ".b......", "r.r....."], Checkers::Side::Black)
    stuck.quiet_moves = Checkers::QUIET_LIMIT
    stuck.status.red_wins?.should be_true
  end

  it "draws on threefold repetition" do
    b = layout(["........", "........", "........", "........", "........", "........", ".......B", "R......."])
    2.times do
      b.status.playing?.should be_true
      b.play("a1-b2").should be_true
      b.play("h2-g3").should be_true
      b.play("b2-a1").should be_true
      b.play("g3-h2").should be_true
    end
    b.repetitions.should eq 3
    b.status.draw?.should be_true
    b.draw_reason.not_nil!.should contain "repetition"
  end

  it "undoes moves exactly" do
    b = Checkers::Board.new(false)
    start = b.to_s
    b.play("b6-a5").should be_true
    after_one = b.to_s
    b.play("c3-b4").should be_true
    b.undo.not_nil!.to_s.should eq "c3-b4"
    b.to_s.should eq after_one
    b.turn.red?.should be_true
    b.undo
    b.to_s.should eq start
    b.turn.black?.should be_true
    b.history.should be_empty
    b.undo.should be_nil
    b.forced_capture?.should be_false
  end

  it "prints moves in interpolation" do
    "#{Checkers::Move.new([sq("c3"), sq("d4")])}".should eq "c3-d4"
  end
end

describe Checkers::AI do
  it "takes a winning capture" do
    b = layout(["........", "........", "........", "........", "....b...", "...r....", "........", "........"], Checkers::Side::Black)
    Checkers::AI::Level.each do |level|
      Checkers::AI.new(level, seed: 1).best_move(b).not_nil!.capture?.should be_true
    end
  end

  it "avoids handing over a piece" do
    # Red to move: c3-d4 would be captured by e5; b4 is safe.
    b = layout(["........", "........", "........", "....b...", "........", "..r.....", "........", "........"])
    Checkers::AI.new(Checkers::AI::Level::Medium, seed: 1).best_move(b).not_nil!.to_s.should eq "c3-b4"
    Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 1).best_move(b).not_nil!.to_s.should eq "c3-b4"
  end

  it "respects the forced capture setting" do
    # c3xe5 loses two men to d6xf4xh2, so the AI declines it when captures are optional.
    rows = ["........", "..b.....", "...b....", "........", "...b....", "..r...r.", ".r......", "........"]
    forced = layout(rows)
    Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 1).best_move(forced).not_nil!.to_s.should eq "c3xe5"
    free = layout(rows, forced: false)
    m = Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 1).best_move(free).not_nil!
    m.capture?.should be_false
    free.legal_moves.includes?(m).should be_true
  end

  it "gives the same move whether it thinks at once or across frames" do
    b = Checkers::Board.new
    b.play("b6-a5"); b.play("c3-b4"); b.play("a5xc3")
    whole = Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 5).best_move(b)
    ai = Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 5)
    ai.start(b)
    slices = 0
    until ai.step(97)
      slices += 1
    end
    slices.should be > 10
    ai.result.should eq whole
  end

  it "time-boxes thinking" do
    ai = Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 2)
    ai.start(Checkers::Board.new)
    t = Time.instant
    ai.think(0.005)
    (Time.instant - t).total_seconds.should be < 0.05
  end

  it "only plays legal moves at every level, with and without forced capture" do
    Checkers::AI::Level.each do |level|
      {true, false}.each do |forced|
        red = Checkers::AI.new(level, seed: 11)
        red.node_limit = Math.min(red.node_limit, 5_000)
        play_game(red, Checkers::AI.new(Checkers::AI::Level::Beginner, seed: 12), forced, 120)
      end
    end
  end

  it "Advanced beats Beginner in most seeded games" do
    wins = 0
    games = 6
    games.times do |i|
      adv = Checkers::AI.new(Checkers::AI::Level::Advanced, seed: 100 + i)
      adv.node_limit = 10_000 # a fraction of its real budget keeps the spec fast
      beg = Checkers::AI.new(Checkers::AI::Level::Beginner, seed: 200 + i)
      adv_red = i.even?
      status = adv_red ? play_game(adv, beg, i % 3 == 0) : play_game(beg, adv, i % 3 == 0)
      wins += 1 if (adv_red && status.red_wins?) || (!adv_red && status.black_wins?)
    end
    wins.should be >= games - 1
  end

  it "Medium beats Beginner more often than not" do
    wins = 0
    4.times do |i|
      med = Checkers::AI.new(Checkers::AI::Level::Medium, seed: 300 + i)
      beg = Checkers::AI.new(Checkers::AI::Level::Beginner, seed: 400 + i)
      status = i.even? ? play_game(med, beg, true) : play_game(beg, med, true)
      wins += 1 if (i.even? && status.red_wins?) || (i.odd? && status.black_wins?)
    end
    wins.should be >= 3
  end
end
