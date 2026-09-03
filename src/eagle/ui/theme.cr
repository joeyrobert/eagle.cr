module Eagle
  # Colours, fonts and metrics shared by UI controls. Assign a Theme to any
  # Control; descendants inherit it. `Theme.default` is a dark theme.
  class Theme
    property font : Font? = nil
    property font_scale : Float32 = 1_f32
    property text : Color = Color.hex("#e8e8ec")
    property text_disabled : Color = Color.hex("#7a7a85")
    property panel : Color = Color.hex("#2a2d36")
    property panel_border : Color = Color.hex("#3d414d")
    property button : Color = Color.hex("#3b4252")
    property button_hover : Color = Color.hex("#4c566a")
    property button_pressed : Color = Color.hex("#2e3440")
    property button_border : Color = Color.hex("#5b6478")
    property accent : Color = Color.hex("#5e9cff")
    property accent_text : Color = Color::WHITE
    property focus : Color = Color.hex("#8fbaff")
    property input_bg : Color = Color.hex("#1e2129")
    property track : Color = Color.hex("#3d414d")
    property padding : Float32 = 8_f32
    property spacing : Float32 = 6_f32
    property corner_radius : Float32 = 4_f32
    property border_width : Float32 = 1_f32
    property control_height : Float32 = 32_f32

    @@default : Theme? = nil

    def self.default : Theme
      @@default ||= Theme.new
    end

    def self.default=(t : Theme); @@default = t; end

    def font_or_default : Font; @font || Font.default; end

    def light : Theme
      t = dup
      t.text = Color.hex("#1c1d22"); t.text_disabled = Color.hex("#9a9aa5")
      t.panel = Color.hex("#f2f3f7"); t.panel_border = Color.hex("#cfd2dc")
      t.button = Color.hex("#e4e6ee"); t.button_hover = Color.hex("#d6d9e3"); t.button_pressed = Color.hex("#c4c8d6")
      t.button_border = Color.hex("#b8bcc9"); t.input_bg = Color::WHITE; t.track = Color.hex("#cfd2dc")
      t
    end
  end
end
