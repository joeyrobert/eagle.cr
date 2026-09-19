require "../spec_helper"

describe Eagle::Clipboard do
  it "round-trips through the in-memory fallback without a platform" do
    Clipboard.text = "hello"
    Clipboard.text.should eq "hello"
    Clipboard.text?.should be_true
    Clipboard.text = ""
    Clipboard.text?.should be_false
  end
end

describe "TextInput input methods" do
  it "shows composition text and clears it when committed" do
    t = TextInput.new("ab")
    t.gui_input(CompositionEvent.new("にほ")).should be_true
    t.preedit.should eq "にほ"
    t.text.should eq "ab"
    t.gui_input(CompositionEvent.new(""))
    t.gui_input(TextEvent.new("日本"))
    t.preedit.should eq ""
    t.text.should eq "ab日本"
    t.caret.should eq 4
  end

  it "drops the preedit when a text event arrives mid-composition" do
    t = TextInput.new
    t.gui_input(CompositionEvent.new("k"))
    t.gui_input(TextEvent.new("x"))
    t.preedit.should eq ""
    t.text.should eq "x"
  end

  it "pastes, copies and cuts through clipboard events" do
    t = TextInput.new("abc")
    t.gui_input(ClipboardEvent.new(ClipboardAction::Paste, "12\n3"))
    t.text.should eq "abc123"
    t.gui_input(ClipboardEvent.new(ClipboardAction::Copy))
    Clipboard.text.should eq "abc123"
    Clipboard.text = "old"
    t.gui_input(ClipboardEvent.new(ClipboardAction::Cut))
    Clipboard.text.should eq "abc123"
    t.text.should eq ""
    t.caret.should eq 0
  end

  it "copies and pastes with the keyboard shortcuts" do
    t = TextInput.new("xyz")
    ctrl = KeyMod::Ctrl
    t.gui_input(KeyEvent.new(Key::C, true, false, ctrl))
    Clipboard.text.should eq "xyz"
    t.gui_input(KeyEvent.new(Key::V, true, false, ctrl))
    t.text.should eq "xyzxyz"
    t.gui_input(KeyEvent.new(Key::X, true, false, ctrl))
    t.text.should eq ""
    t.gui_input(KeyEvent.new(Key::C, true, false, KeyMod::None)).should be_false
  end

  it "never copies password fields" do
    t = TextInput.new("secret")
    t.password = true
    Clipboard.text = "keep"
    t.gui_input(ClipboardEvent.new(ClipboardAction::Copy))
    t.gui_input(ClipboardEvent.new(ClipboardAction::Cut))
    Clipboard.text.should eq "keep"
    t.text.should eq "secret"
  end

  it "delivers injected text and composition events to a focused field" do
    SceneTree.reset
    t = TextInput.new
    SceneTree.root.add(t)
    t.grab_focus
    SceneTree.dispatch_input(CompositionEvent.new("か"))
    t.preedit.should eq "か"
    SceneTree.dispatch_input(TextEvent.new("漢"))
    t.text.should eq "漢"
    t.release_focus
    t.preedit.should eq ""
  end
end
