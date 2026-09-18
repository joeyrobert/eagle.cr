module Eagle
  # A node with a 2D position, rotation and scale. It is the base of every 2D game object.
  #
  # Children move with their parent: a gun added to a ship turns when the ship turns. Local
  # values (`position`, `rotation`, `scale`) are relative to the parent, and the `global_*`
  # methods give world-space values.
  #
  # ```
  # class Ship < Node2D
  #   def ready : Nil
  #     add(Polygon2D.new([v2(12, 0), v2(-8, -8), v2(-8, 8)], Color::WHITE))
  #     add(Node2D.new("Muzzle", position: v2(14, 0)))
  #   end
  #
  #   def process(dt : Float32) : Nil
  #     rotate(Input.axis("left", "right") * 3 * dt)
  #     translate(forward * 120 * dt)                    # forward follows rotation
  #     muzzle = get_node("Muzzle", Node2D).global_position # where bullets spawn
  #   end
  # end
  # ```
  #
  # `modulate` tints the node and all its children, so fading a whole character out is one
  # line. Set `top_level` to ignore the parent's transform.
  class Node2D < Node
    # Position relative to the parent, in points.
    property position : Vec2 = Vec2::ZERO
    # Rotation relative to the parent, in radians. Positive is clockwise on screen.
    property rotation : Float32 = 0_f32
    # Scale relative to the parent. Negative x mirrors horizontally.
    property scale : Vec2 = Vec2::ONE
    # Color multiplied into this node and all of its children.
    property modulate : Color = Color::WHITE
    # When true, the node ignores its parent's transform and positions itself in world space.
    property? top_level = false

    # Creates a 2D node at *position*.
    def initialize(name : String = "", @position = Vec2::ZERO, @rotation = 0_f32, @scale = Vec2::ONE)
      super(name)
    end

    # The x position.
    def x : Float32; @position.x; end
    # The y position.
    def y : Float32; @position.y; end
    # Sets the x position.
    def x=(v : Number); @position = Vec2.new(v, @position.y); end
    # Sets the y position.
    def y=(v : Number); @position = Vec2.new(@position.x, v); end
    # Rotation in degrees.
    def rotation_degrees : Float32; Mathf.rad2deg(@rotation); end
    # Sets the rotation in degrees.
    def rotation_degrees=(d : Number); @rotation = Mathf.deg2rad(d); end
    # Sets a uniform scale.
    def scale=(s : Number); @scale = Vec2.new(s); end
    # Sets the scale per axis.
    def scale=(s : Vec2); @scale = s; end
    # Sets the position.
    def position=(p : Vec2); @position = p; end

    # Moves the node by *v* in parent space.
    def translate(v : Vec2) : Nil; @position += v; end
    # Moves the node by *x*, *y* in parent space.
    def translate(x : Number, y : Number) : Nil; @position += Vec2.new(x, y); end
    # Adds *rad* radians to the rotation.
    def rotate(rad : Number) : Nil; @rotation += rad; end

    # The local transform built from position, rotation and scale.
    def transform : Transform2D
      Transform2D.trs(@position, @rotation, @scale)
    end

    # Sets position, rotation and scale from a transform.
    def transform=(t : Transform2D)
      @position = t.translation
      @rotation = t.rotation
      @scale = t.scale
    end

    # The transform from this node's space to world space.
    def global_transform : Transform2D
      return transform if @top_level
      if (p = parent_2d)
        p.global_transform * transform
      else
        transform
      end
    end

    # Position in world space.
    def global_position : Vec2; global_transform.translation; end

    # Moves the node so it ends up at *p* in world space.
    def global_position=(p : Vec2)
      if (par = parent_2d) && !@top_level
        @position = par.global_transform.inverse * p
      else
        @position = p
      end
    end

    # Rotation in world space.
    def global_rotation : Float32; global_transform.rotation; end
    # Scale in world space.
    def global_scale : Vec2; global_transform.scale; end

    # The nearest ancestor that is a `Node2D`, or `nil`.
    def parent_2d : Node2D?
      p = @parent
      while p
        return p if p.is_a?(Node2D)
        return nil if p.is_a?(CanvasLayer)
        p = p.parent
      end
      nil
    end

    # Converts a world-space point into this node's local space.
    def to_local(global : Vec2) : Vec2; global_transform.inverse * global; end
    # Converts a local point into world space.
    def to_global(local : Vec2) : Vec2; global_transform * local; end

    # The unit vector this node faces, in world space. Rotation 0 faces right.
    def right : Vec2; Vec2.from_angle(global_rotation); end
    # The unit vector 90° clockwise from `right`.
    def down : Vec2; right.perpendicular; end
    # Same as `right`: the direction the node faces.
    def forward : Vec2; right; end

    # Rotates the node to face a world-space point.
    #
    # ```
    # turret = Node2D.new
    # turret.look_at(Input.mouse)
    # ```
    def look_at(target : Vec2) : Nil
      d = target - global_position
      @rotation = d.angle - (global_rotation - @rotation)
    end

    # Distance to another 2D node, in world space.
    def distance_to(other : Node2D) : Float32; global_position.distance(other.global_position); end
    # Unit vector pointing from this node toward *other*.
    def direction_to(other : Node2D) : Vec2; (other.global_position - global_position).normalized; end

    # :nodoc:
    def draw_tree(g : Graphics) : Nil
      return unless @visible
      g.push
      if @top_level
        g.origin
      end
      g.apply(transform)
      prev_color = g.color
      g.color = prev_color * @modulate
      draw(g)
      draw_children(g)
      g.color = prev_color
      g.pop
    end
  end

  # Draws its children in screen space, above or below the world, and ignores the camera.
  # Use it for HUDs, menus and backgrounds that shouldn't scroll.
  #
  # ```
  # hud = CanvasLayer.new
  # hud.z_index = 10
  # hud.add(Label.new("Score: 0", position: v2(10, 10)))
  # SceneTree.root.add(hud)
  # ```
  #
  # Layers draw in tree order like any other node, so add the HUD after the world, or give it
  # a higher `z_index`, to keep it on top.
  class CanvasLayer < Node
    # A number describing the layer's intended stacking. Eagle doesn't sort by it; use tree order
    # or `z_index` to control what draws on top.
    property layer : Int32 = 1
    # Shifts everything on the layer, in screen points.
    property offset : Vec2 = Vec2::ZERO

    # Creates a layer.
    def initialize(name : String = "", @layer = 1)
      super(name)
    end

    def draw_tree(g : Graphics) : Nil
      return unless @visible
      prev_cam = g.camera
      g.push
      g.camera = nil
      g.translate(@offset) unless @offset.zero?
      draw(g)
      draw_children(g)
      g.pop
      g.camera = prev_cam
    end
  end
end
