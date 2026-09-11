module Eagle
  # The global scene tree. `SceneTree.root` is the top node; add your scenes to it.
  module SceneTree
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

    def self.root : Node; @@root; end
    def self.paused? : Bool; @@paused; end
    def self.paused=(v : Bool); @@paused = v; end

    # The "main" scene: replaces the previous one (like Godot's change_scene).
    def self.current_scene : Node?; @@current_scene; end

    def self.change_scene(scene : Node) : Nil
      defer do
        @@current_scene.try(&.free)
        @@current_scene = scene
        @@root.add(scene)
      end
    end

    def self.change_scene!(scene : Node) : Nil
      @@current_scene.try(&.free)
      @@current_scene = scene
      @@root.add(scene)
    end

    def self.add(node : Node) : Node; @@root.add(node); end

    # Run a block at the end of the current frame.
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

    def self.group(name : String) : Array(Node)
      @@groups[name]? || [] of Node
    end

    # Call a method on every node in a group.
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
