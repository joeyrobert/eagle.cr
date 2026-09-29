require "../../src/eagle/math/math"

module EagleRocketBall
  include Eagle

  # Team colors a player can pick: name and hex.
  PALETTE = [
    {"Azure", "#2f8dff"}, {"Orange", "#ff8a1f"}, {"Crimson", "#ff3b4d"}, {"Lime", "#7be03a"},
    {"Violet", "#a05cff"}, {"Cyan", "#26e6d9"}, {"Gold", "#ffd21f"}, {"Pink", "#ff5fb0"},
  ]

  # Player preferences, shared by every screen. Nothing is written to disk so the game also runs in a browser.
  module Settings
    class_property master : Float32 = 0.8_f32
    class_property music : Float32 = 0.5_f32
    class_property effects : Float32 = 0.9_f32
    class_property fov : Float32 = 90_f32
    class_property distance : Float32 = 1_f32
    class_property? shake = true
    class_property? ball_cam = true
    class_property? minimap = true
    class_property blue : Int32 = 0
    class_property orange : Int32 = 1

    # A team's color, moving the orange team on when both picked the same one so the teams stay distinguishable.
    def self.team_color(team : Int32) : Color
      i = team == 0 ? @@blue : @@orange
      i = (@@blue + 1) % PALETTE.size if team == 1 && @@orange == @@blue
      Color.hex(PALETTE[i][1])
    end

    def self.team_color_name(team : Int32) : String
      i = team == 0 ? @@blue : @@orange
      i = (@@blue + 1) % PALETTE.size if team == 1 && @@orange == @@blue
      PALETTE[i][0]
    end
  end
end
