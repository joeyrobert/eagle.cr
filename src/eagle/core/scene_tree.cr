module Eagle
  # The global tree of nodes that Eagle updates and draws every frame.
  #
  # Everything you add under `SceneTree.root` gets its `process`, `physics_process`,
  # `draw` and `input` hooks called automatically. Use `change_scene` to switch between
  # screens such as a title menu and a level, and groups to reach many nodes at once.
  #
  # ```
  # class Level < Node2D
  #   def ready : Nil
  #     3.times { |i| add(Sprite2D.new(Texture.new(Image.circle(8, Color::RED)), v2(100 + i * 50, 100)).add_to_group("enemies")) }
  #   end
  # end
  #
  # SceneTree.change_scene(Level.new)
  # SceneTree.call_group("enemies") { |n| n.queue_free }
  # SceneTree.paused = true # stops nodes whose process_mode is Pausable or Inherit
  # ```
  module SceneTree
    # The node at the top of the tree. It is always in the tree.
    class RootNode < Node
      def initialize
        super("root")
        @in_tree = true
      end
    end

    @@root : Node = RootNode.new
    @@paused = false
    @@deferred = [] of ->
    @@groups = {} of String => Array(Node)
    @@current_scene : Node? = nil

    # The top node. Add your scenes and global nodes (HUD, music player) here.
    def self.root : Node; @@root; end
    # True while the tree is paused.
    def self.paused? : Bool; @@paused; end
    # Pauses or resumes the tree. Paused nodes skip `process` and `physics_process` but still draw.
    # Nodes with `ProcessMode::Always` keep running, which suits pause menus.
    def self.paused=(v : Bool); @@paused = v; end

    # The scene set by `change_scene`, if any.
    def self.current_scene : Node?; @@current_scene; end

    # Replaces the current scene with *scene* at the end of the frame. The old scene is removed.
    # Safe to call from inside the old scene's callbacks.
    def self.change_scene(scene : Node) : Nil
      defer do
        @@current_scene.try(&.free)
        @@current_scene = scene
        @@root.add(scene)
      end
    end

    # Replaces the current scene immediately. Prefer `change_scene` unless you know no callbacks are running.
    def self.change_scene!(scene : Node) : Nil
      @@current_scene.try(&.free)
      @@current_scene = scene
      @@root.add(scene)
    end

    # Adds *node* to the root. Same as `SceneTree.root.add(node)`.
    def self.add(node : Node) : Node; @@root.add(node); end

    # Runs the block at the end of the current frame, after all nodes have processed.
    # Use it to change the tree safely from inside a callback.
    def self.defer(&block : ->) : Nil
      @@deferred << block
    end

    # :nodoc:
    def self.flush_deferred : Nil
      until @@deferred.empty?
        list = @@deferred
        @@deferred = [] of ->
        list.each(&.call)
      end
    end

    # Every node in the tree that belongs to the group *name*.
    def self.group(name : String) : Array(Node)
      @@groups[name]? || [] of Node
    end

    # Yields every node in the group. Safe even if the block removes nodes.
    def self.call_group(name : String, & : Node ->) : Nil
      group(name).dup.each { |n| yield n }
    end

    # :nodoc:
    def self.register_group(name : String, node : Node) : Nil
      list = @@groups[name] ||= [] of Node
      list << node unless list.includes?(node)
    end

    # :nodoc:
    def self.unregister_group(name : String, node : Node) : Nil
      @@groups[name]?.try(&.delete(node))
    end

    # :nodoc:
    def self.dispatch_input(event : Event) : Nil
      @@root.input_tree(event)
    end

    # Total number of nodes under the root, for debug overlays.
    def self.node_count : Int32
      n = 0
      @@root.each_descendant { n += 1 }
      n
    end

    # :nodoc:
    def self.reset : Nil
      @@root.clear_children
      @@root = RootNode.new
      @@paused = false
      @@deferred.clear
      @@groups.clear
      @@current_scene = nil
      Camera2D.reset
      Camera3D.reset
      Physics3D.reset
      Control.reset_focus
    end
  end
end
