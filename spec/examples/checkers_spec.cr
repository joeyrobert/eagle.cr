require "../spec_helper"
require "../../examples/checkers/checkers"

describe Checkers::Board do
  it "starts with 12 pieces each and 7 opening moves" do
    b = Checkers::Board.new
    b.count(Checkers::Side::Red).should eq 12
    b.count(Checkers::Side::Black).should eq 12
    b.legal_moves.size.should eq 7
    b.legal_moves.none?(&.capture?).should be_true
  end

  it "forces captures and supports multi-jumps" do
    b = Checkers::Board.from_layout([
      "........",
      "........",
      "...b.b..",
      "........",
      "...b....",
      "..r.....",
      "........",
      "........",
    ])
    moves = b.legal_moves
    moves.all?(&.capture?).should be_true
    moves.map(&.to_s).sort.should eq ["c3xe5xc7", "c3xe5xg7"]
    b.play("c3xe5xg7").should be_true
    b.count(Checkers::Side::Black).should eq 1
    b[Checkers.index("g7")].not_nil!.side.red?.should be_true
  end

  it "crowns kings, which move backwards, and stops jumping when crowned" do
    b = Checkers::Board.from_layout([
      "........",
      "..b.....",
      "...r....",
      "........",
      "........",
      "........",
      "........",
      "........",
    ])
    b.legal_moves.map(&.to_s).should eq ["d6xb8"]
    b.play("d6xb8")
    b[Checkers.index("b8")].not_nil!.king?.should be_true
    k = Checkers::Board.from_layout(["........", "........", "........", "...R....", "........", "........", "........", "........"])
    k.legal_moves.size.should eq 4
  end

  it "detects wins and draws" do
    b = Checkers::Board.from_layout(["........", "........", "........", "........", "........", "........", ".b......", "....r..."], Checkers::Side::Black)
    b.status.playing?.should be_true
    stuck = Checkers::Board.from_layout(["........", "........", "........", "........", "........", "........", ".b......", "r.r....."], Checkers::Side::Black)
    stuck.status.red_wins?.should be_true
    lost = Checkers::Board.from_layout(["........", "........", "........", "........", "........", "........", "........", "........"])
    lost.status.black_wins?.should be_true
    blocked = Checkers::Board.from_layout(["........", "........", "........", "........", "........", ".b.b....", "b.b.....", ".r......"])
    blocked.status.black_wins?.should be_true
  end
end

describe Checkers::AI do
  it "takes a winning capture" do
    b = Checkers::Board.from_layout(["........", "........", "........", "........", "....b...", "...r....", "........", "........"], Checkers::Side::Black)
    ai = Checkers::AI.new(4)
    m = ai.best_move(b).not_nil!
    m.capture?.should be_true
  end

  it "avoids handing over a piece" do
    # Red to move: moving c3-d4 would be captured by e5; b4 is safe.
    b = Checkers::Board.from_layout(["........", "........", "........", "....b...", "........", "..r.....", "........", "........"], Checkers::Side::Red)
    ai = Checkers::AI.new(4)
    ai.best_move(b).not_nil!.to_s.should eq "c3-b4"
  end
end
