module Eagle
  # A node with a 2D transform. Children inherit the transform.
  class Node2D < Node
    property position : Vec2 = Vec2::ZERO
    property rotation : Float32 = 0_f32
    property scale : Vec2 = Vec2::ONE
    # Tint multiplied into this node and its descendants.
    property modulate : Color = Color::WHITE
    # When false, the node ignores its parent's transform (screen-space).
    property? top_level = false

    def initialize(name : String = "", @position = Vec2::ZERO, @rotation = 0_f32, @scale = Vec2::ONE)
      super(name)
    end

    def x : Float32; @position.x; end
    def y : Float32; @position.y; end
    def x=(v : Number); @position = Vec2.new(v, @position.y); end
    def y=(v : Number); @position = Vec2.new(@position.x, v); end
    def rotation_degrees : Float32; Mathf.rad2deg(@rotation); end
    def rotation_degrees=(d : Number); @rotation = Mathf.deg2rad(d); end
    def scale=(s : Number); @scale = Vec2.new(s); end
    def scale=(s : Vec2); @scale = s; end
    def position=(p : Vec2); @position = p; end

    def translate(v : Vec2) : Nil; @position += v; end
    def translate(x : Number, y : Number) : Nil; @position += Vec2.new(x, y); end
    def rotate(rad : Number) : Nil; @rotation += rad; end

    # Local transform (relative to the parent).
    def transform : Transform2D
      Transform2D.trs(@position, @rotation, @scale)
    end

    def transform=(t : Transform2D)
      @position = t.translation
      @rotation = t.rotation
      @scale = t.scale
    end

    # Transform relative to the world (root), following parent Node2Ds.
    def global_transform : Transform2D
      return transform if @top_level
      if (p = parent_2d)
        p.global_transform * transform
      else
        transform
      end
    end

    def global_position : Vec2; global_transform.translation; end

    def global_position=(p : Vec2)
      if (par = parent_2d) && !@top_level
        @position = par.global_transform.inverse * p
      else
        @position = p
      end
    end

    def global_rotation : Float32; global_transform.rotation; end
    def global_scale : Vec2; global_transform.scale; end

    # Nearest ancestor that is a Node2D.
    def parent_2d : Node2D?
      p = @parent
      while p
        return p if p.is_a?(Node2D)
        return nil if p.is_a?(CanvasLayer)
        p = p.parent
      end
      nil
    end

    def to_local(global : Vec2) : Vec2; global_transform.inverse * global; end
    def to_global(local : Vec2) : Vec2; global_transform * local; end

    # Direction vectors in world space.
    def right : Vec2; Vec2.from_angle(global_rotation); end
    def down : Vec2; right.perpendicular; end
    def forward : Vec2; right; end

    def look_at(target : Vec2) : Nil
      d = target - global_position
      @rotation = d.angle - (global_rotation - @rotation)
    end

    def distance_to(other : Node2D) : Float32; global_position.distance(other.global_position); end
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

  # Children of a CanvasLayer are drawn in screen space, ignoring the camera.
  # Use it for HUDs and menus. Higher `layer` draws later.
  class CanvasLayer < Node
    property layer : Int32 = 1
    property offset : Vec2 = Vec2::ZERO

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
