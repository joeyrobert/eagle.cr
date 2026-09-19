require "../../src/eagle"
include Eagle

# Tiny game driven by script/web-input-check.sh: one focused text field.
class InputCheck < App
  def load
    layer = CanvasLayer.new
    SceneTree.root.add(layer)
    field = TextInput.new("", "", position: v2(10, 10), size: v2(300, 30))
    layer.add(field)
    field.grab_focus
  end
end

Eagle.run(InputCheck, title: "input check", width: 400, height: 100)
