module Eagle
  # Colors, fonts and sizes shared by UI controls. Assign a theme to any control and every
  # control below it uses it. `Theme.default` is a dark theme, and `light` gives a light variant.
  #
  # ```
  # theme = Theme.default.light
  # theme.accent = Color.hex("#c98a12")
  # theme.corner_radius = 0
  # theme.font = Font.load("res://fonts/Inter.ttf", 18)
  #
  # menu = Panel.new
  # menu.theme = theme # everything inside the menu uses it
  # ```
  class Theme
    # Font for all controls. `nil` uses `Font.default`.
    property font : Font? = nil
    # Text scale for all controls.
    property font_scale : Float32 = 1_f32
    # Text color.
    property text : Color = Color.hex("#e8e8ec")
    # Text color for disabled controls.
    property text_disabled : Color = Color.hex("#7a7a85")
    # Panel background.
    property panel : Color = Color.hex("#2a2d36")
    # Panel border.
    property panel_border : Color = Color.hex("#3d414d")
    # Button background.
    property button : Color = Color.hex("#3b4252")
    # Button background under the mouse.
    property button_hover : Color = Color.hex("#4c566a")
    # Button background while pressed.
    property button_pressed : Color = Color.hex("#2e3440")
    # Button border.
    property button_border : Color = Color.hex("#5b6478")
    # Highlight color for sliders, progress bars and checked boxes.
    property accent : Color = Color.hex("#5e9cff")
    # Text drawn on top of the accent color.
    property accent_text : Color = Color::WHITE
    # Color of the focus ring.
    property focus : Color = Color.hex("#8fbaff")
    # Text field background.
    property input_bg : Color = Color.hex("#1e2129")
    # Slider and progress bar track color.
    property track : Color = Color.hex("#3d414d")
    # Default container padding.
    property padding : Float32 = 8_f32
    # Default gap between children in containers.
    property spacing : Float32 = 6_f32
    # Corner rounding for panels and buttons. 0 gives square corners.
    property corner_radius : Float32 = 4_f32
    # Border thickness. 0 hides borders.
    property border_width : Float32 = 1_f32
    # Default height of buttons, fields and sliders.
    property control_height : Float32 = 32_f32

    @@default : Theme? = nil

    # The shared default theme. Change it to restyle every control that has no theme of its own.
    def self.default : Theme
      @@default ||= Theme.new
    end

    # Replaces the default theme.
    def self.default=(t : Theme); @@default = t; end

    # The font in effect.
    def font_or_default : Font; @font || Font.default; end

    # A copy of this theme with light colors.
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
