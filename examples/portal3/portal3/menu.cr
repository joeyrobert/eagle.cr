module Portal3
  # The game's front end: main menu, chamber select, settings and pause. It lives on a
  # canvas layer over the 3D scene, so the chamber keeps running behind the menus and
  # returning to play is instant.
  class Menus
    enum Screen
      None
      Main
      ChamberSelect
      Settings
      Pause
    end

    getter screen = Screen::None
    getter layer = CanvasLayer.new("menu", 10)

    @save : SaveData
    @settings_return : Screen = Screen::Main
    @built = [] of Node

    # Callbacks the game assigns after construction. Crystal allows only one block
    # parameter per method, and these are clearer as properties anyway.
    property on_start : Proc(Int32, Nil) = ->(_index : Int32) { }
    property on_quit_to_menu : Proc(Nil) = -> { }
    property on_resume : Proc(Nil) = -> { }
    property on_settings_changed : Proc(SaveData, Nil) = ->(_save : SaveData) { }

    def initialize(@save : SaveData)
      SceneTree.root.add(@layer)
    end

    def showing? : Bool
      @screen != Screen::None
    end

    # Shows a screen. `from` is where the back button on settings should return to.
    def show(screen : Screen, from : Screen = Screen::Main) : Nil
      @settings_return = from if screen == Screen::Settings
      clear
      @screen = screen
      case screen
      when Screen::Main          then build_main
      when Screen::ChamberSelect then build_chamber_select
      when Screen::Settings      then build_settings
      when Screen::Pause         then build_pause
      else                            @screen = Screen::None
      end
    end

    def hide : Nil
      clear
      @screen = Screen::None
    end

    # Drops every control built for the current screen.
    private def clear : Nil
      @built.each &.remove_from_parent
      @built.clear
    end

    private def add(node : Control) : Control
      @layer.add(node)
      @built << node
      node
    end

    # A full-screen scrim, so text stays readable over whatever the chamber is doing.
    private def scrim(alpha : Float64 = 0.85) : Nil
      panel = Panel.new(size: v2(Window.width, Window.height))
      panel.color = Color.new(0.02, 0.03, 0.07, alpha)
      panel.show_border = false
      add(panel)
    end

    private def heading(text : String, scale : Float32 = 2.0_f32, y : Float32 = 0.16_f32) : Nil
      label = Label.new(text, size: v2(Window.width, 60))
      label.align = TextAlign::Center
      label.font_scale = scale
      label.color = Color.hex("#dfe9f5")
      label.position = v2(0, Window.height * y)
      add(label)
    end

    private def button(text : String, &block : ->) : Eagle::Button
      Eagle::Button.new(text, size: v2(320, 44)) { block.call }
    end

    # A centred column of controls, with a gap between each.
    private def column(y : Float32, width : Float32 = 320) : VBox
      box = VBox.new(size: v2(width, 0))
      box.fit_content = true
      box.position = v2((Window.width - width) / 2, Window.height * y)
      box
    end

    # ------------------------------------------------------------------ screens

    private def build_main : Nil
      scrim
      heading("PORTAL 3", 3.0_f32, 0.16_f32)
      list = column(0.40_f32)
      continue_label = @save.unlocked > 1 ? "Continue (Chamber #{@save.unlocked - 1})" : "Play"
      list.add(button(continue_label) do
        @save.save
        @on_start.call({@save.unlocked - 1, 0}.max)
      end)
      list.add(button("Chambers") { show(Screen::ChamberSelect) })
      list.add(button("Settings") { show(Screen::Settings) })
      list.add(button("Quit") { @on_quit_to_menu.call; Eagle.quit })
      add(list)
    end

    private def build_pause : Nil
      scrim(0.72)
      heading("Paused", 2.0_f32, 0.24_f32)
      list = column(0.38_f32)
      list.add(button("Resume") { @on_resume.call })
      list.add(button("Settings") { show(Screen::Settings, Screen::Pause) })
      list.add(button("Main Menu") do
        @save.save
        @on_quit_to_menu.call
        show(Screen::Main)
      end)
      add(list)
    end

    private def build_chamber_select : Nil
      scrim
      heading("Select a chamber", 1.6_f32, 0.08_f32)
      columns = 4
      cell = v2(170, 64)
      grid = GridContainer.new(columns, size: v2(cell.x * columns, cell.y * rows_for(columns)))
      grid.position = v2((Window.width - cell.x * columns) / 2, Window.height * 0.18)
      Levels::COUNT.times do |i|
        locked = i >= @save.unlocked
        done = i < @save.completed.size && @save.completed[i]
        text = locked ? "Chamber #{i}\nLocked" : (done ? "Chamber #{i}\nCleared" : "Chamber #{i}")
        b = Eagle::Button.new(text, size: cell)
        b.disabled = locked
        b.on_pressed { @save.save; @on_start.call(i) }
        grid.add(b)
      end
      add(grid)
      back = button("Back") { show(Screen::Main) }
      back.position = v2((Window.width - 320) / 2, grid.position.y + cell.y * rows_for(columns) + 24)
      add(back)
    end

    private def rows_for(columns : Int32) : Int32
      (Levels::COUNT + columns - 1) // columns
    end

    private def build_settings : Nil
      scrim
      heading("Settings", 1.6_f32, 0.08_f32)
      list = column(0.16_f32, 440)

      list.add(caption("Mouse sensitivity"))
      sensitivity = Slider.new(0.2, 3.0, @save.mouse_sensitivity, 0.05, size: v2(440, 28))
      sensitivity.on_value_changed do |value|
        @save.mouse_sensitivity = value
        @on_settings_changed.call(@save)
      end
      list.add(sensitivity)

      list.add(caption("Volume"))
      volume = Slider.new(0.0, 1.0, @save.volume, 0.05, size: v2(440, 28))
      volume.on_value_changed do |value|
        @save.volume = value
        Audio.volume = value
      end
      list.add(volume)

      list.add(caption("Field of view"))
      fov = Slider.new(60.0, 110.0, @save.fov, 1.0, size: v2(440, 28))
      fov.on_value_changed do |value|
        @save.fov = value
        @on_settings_changed.call(@save)
      end
      list.add(fov)

      invert = CheckBox.new("Invert vertical look", @save.invert_y)
      invert.on_toggled do |on|
        @save.invert_y = on
        @on_settings_changed.call(@save)
      end
      list.add(invert)

      list.add(button("Back") { @save.save; show(@settings_return) })
      add(list)
    end

    private def caption(text : String) : Label
      label = Label.new(text, size: v2(440, 20))
      label.color = Color.gray(0.8)
      label
    end
  end
end
