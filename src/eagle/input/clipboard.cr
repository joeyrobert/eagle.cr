module Eagle
  # The system clipboard as text, the same on desktop and in the browser.
  #
  # On desktop it reads and writes the OS clipboard. In the browser the clipboard is guarded:
  # writing works from a click or key press (call it from an input handler), and reading returns
  # the last text the page copied or the player pasted into it. Where no clipboard is available
  # (before the engine starts, or in headless tests) it falls back to an in-memory copy, so
  # copy then paste still round-trips inside the game.
  #
  # ```
  # Clipboard.text = "invite code 1234"
  # puts Clipboard.text # => invite code 1234
  # ```
  module Clipboard
    @@memory = ""

    # The clipboard text, or an empty string when there is none.
    def self.text : String
      if pf = Eagle.platform?
        pf.clipboard
      else
        @@memory
      end
    end

    # Puts *s* on the clipboard.
    def self.text=(s : String) : String
      @@memory = s
      Eagle.platform?.try(&.clipboard=(s))
      s
    end

    # True when there is text on the clipboard.
    def self.text? : Bool
      !text.empty?
    end
  end
end
