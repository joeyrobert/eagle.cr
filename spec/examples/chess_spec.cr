require "../spec_helper"
require "../../examples/chess/chess"

describe Chess::Board do
  it "generates the right number of moves (perft)" do
    b = Chess::Board.new
    b.legal_moves.size.should eq 20
    b.perft(1).should eq 20
    b.perft(2).should eq 400
    b.perft(3).should eq 8902
  end

  it "matches known perft on the Kiwipete position (castling, en passant, promotions)" do
    b = Chess::Board.from_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    b.perft(1).should eq 48
    b.perft(2).should eq 2039
  end

  it "handles promotion and en passant perft position" do
    b = Chess::Board.from_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
    b.perft(1).should eq 14
    b.perft(2).should eq 191
    b.perft(3).should eq 2812
  end

  it "plays moves, detects check, checkmate and stalemate" do
    b = Chess::Board.new
    b.play("e2", "e4").should be_true
    b.play("e2", "e4").should be_false # not white's turn / empty
    b.play("e7", "e5").should be_true
    b.play("f1", "c4").should be_true
    b.play("b8", "c6").should be_true
    b.play("d1", "h5").should be_true
    b.play("g8", "f6").should be_true
    b.status.playing?.should be_true
    b.play("h5", "f7").should be_true
    b.status.checkmate?.should be_true
    b.game_over?.should be_true
    stale = Chess::Board.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    stale.status.stalemate?.should be_true
    check = Chess::Board.from_fen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
    check.status.checkmate?.should be_true # fool's mate
  end

  it "castles, en passants and promotes" do
    b = Chess::Board.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    b.legal_moves.count(&.castle?).should eq 2
    b.play("e1", "g1").should be_true
    b[6].piece.king?.should be_true
    b[5].piece.rook?.should be_true
    b.castling[0].should be_false
    ep = Chess::Board.from_fen("8/8/8/3pP3/8/8/8/k6K w - d6 0 1")
    m = ep.legal_moves.find(&.en_passant?).not_nil!
    ep.play(m).should be_true
    ep[Chess.square_index("d5")].empty?.should be_true
    pr = Chess::Board.from_fen("8/P7/8/8/8/8/8/k6K w - - 0 1")
    pr.play("a7", "a8", Chess::Piece::Queen).should be_true
    pr[Chess.square_index("a8")].piece.queen?.should be_true
    pr.to_fen.should start_with("Q7/8/8/8/8/8/8/k6K b")
  end

  it "round-trips FEN" do
    fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2"
    Chess::Board.from_fen(fen).to_fen.should eq fen
  end
end

describe Chess::AI do
  it "finds mate in one and prefers captures" do
    b = Chess::Board.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
    ai = Chess::AI.new(2)
    m = ai.best_move(b).not_nil!
    m.to_s.should eq "a1a8"
    b.apply(m)
    b.status.checkmate?.should be_true
    c = Chess::Board.from_fen("k7/8/8/3q4/8/8/8/K2R4 w - - 0 1")
    ai.best_move(c).not_nil!.to_s.should eq "d1d5"
    ai.evaluate(Chess::Board.new).should eq 0
  end
end
