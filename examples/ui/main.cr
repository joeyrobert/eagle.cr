require "../../src/eagle"
include Eagle

# UI showcase: containers, buttons, sliders, text input, drop-down, rich text, scroll container, themes, TrueType font.
class UIDemo < App
  @status = Label.new("Ready.")
  @ttf : Font? = nil

  def load
    ttf_path = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Geneva.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"].find { |p| File.exists?(p) }
    if ttf_path
      @ttf = Font.load(ttf_path, 18)
      Theme.default.font = @ttf
    end
    layer = CanvasLayer.new
    SceneTree.root.add(layer)

    panel = Panel.new(size: v2(440, 0))
    panel.anchor = Anchor::Center
    panel.fit_content = true
    vbox = VBox.new(size: v2(420, 0))
    vbox.position = v2(10, 10)
    vbox.fit_content = true
    panel.add(vbox)
    layer.add(panel)

    title = Label.new("Eagle UI", align: TextAlign::Center)
    title.font_scale = 1.4
    vbox.add(title)
    vbox.add(Label.new("Widgets laid out by a VBox inside a centred Panel.", color: Color.gray(0.7)))

    row = HBox.new
    row.add(Button.new("Primary") { @status.text = "Primary pressed" })
    row.add(Button.new("Toggle").tap { |b| b.toggle_mode = true; b.on_toggled { |on| @status.text = "Toggle #{on ? "on" : "off"}" } })
    d = Button.new("Disabled"); d.disabled = true
    row.add(d)
    vbox.add(row)

    vbox.add(CheckBox.new("Enable shadows", true).tap { |c| c.on_toggled { |v| @status.text = "Shadows #{v}" } })
    slider_row = HBox.new
    slabel = Label.new("Volume 50%")
    slider = Slider.new(0, 100, 50, step: 1)
    slider.size_flags = SizeFlags::ExpandX
    slider.on_value_changed { |v| slabel.text = "Volume #{v.to_i}%"; @status.text = "Volume #{v.to_i}" }
    slider_row.add(slider, slabel)
    vbox.add(slider_row)

    bar = ProgressBar.new(0.0)
    vbox.add(bar)
    Tween.value(0, 1, 3.0, ease: :quad_in_out) { |v| bar.value = v }.loop = true

    input = TextInput.new("", "Type your name and press Enter")
    input.on_submitted { |t| @status.text = "Hello, #{t}!" }
    vbox.add(input)

    grid = GridContainer.new(3)
    9.times { |i| grid.add(Button.new("#{i + 1}") { @status.text = "Grid #{i + 1}" }) }
    vbox.add(grid)

    biome = OptionButton.new(["Forest", "Desert", "Ocean", "Tundra"])
    biome.on_item_selected { |i| @status.text = "Biome: #{biome.items[i]}" }
    vbox.add(biome)

    tip = RichTextLabel.new("**Rich text:** [color=#e3a537]colors[/color] and [url=docs][color=#8fbaff]links[/color][/url].")
    tip.on_meta_clicked { |m| @status.text = "Clicked link: #{m}" }
    vbox.add(tip)

    log = VBox.new
    12.times { |i| log.add(Label.new("Log entry #{i + 1}", color: Color.gray(0.8))) }
    scroller = ScrollContainer.new(size: v2(0, 70))
    scroller.min_size = v2(0, 70)
    scroller.add(log)
    vbox.add(scroller)

    theme_row = HBox.new
    theme_row.add(Button.new("Dark") { panel.theme = nil; @status.text = "Dark theme" })
    theme_row.add(Button.new("Light") { panel.theme = Theme.default.light; @status.text = "Light theme" })
    vbox.add(theme_row)
    vbox.add(@status)
  end

  def draw(g : Graphics)
    g.print("fps #{Clock.fps.round}  draw calls #{g.draw_calls}  focused: #{Control.focused.try(&.class.name) || "-"}", 10, Window.height - 24, Color::GRAY)
  end
end

Eagle.run(UIDemo, title: "Eagle UI", width: 900, height: 800)
