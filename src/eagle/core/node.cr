module Eagle
  # Base of the scene tree. Subclass it and override the lifecycle hooks:
  #   ready / process(dt) / physics_process(dt) / draw(g) / input(event)
  # Node2D / Node3D add transforms; Sprite2D, Camera2D, Label… add behaviour.
  class Node
    enum ProcessMode
      # Follow the parent (root: process when unpaused).
      Inherit
      # Always process, even when the tree is paused.
      Always
      # Never process while paused.
      Pausable
      # Only process while paused.
      WhenPaused
      Disabled
    end

    property name : String
    getter parent : Node? = nil
    getter children = [] of Node
    property? visible = true
    property process_mode = ProcessMode::Inherit
    # Drawing order among siblings (higher draws later / on top).
    property z_index = 0
    getter? in_tree = false
    getter? ready_called = false
    getter groups = Set(String).new
    @queued_free = false

    signal tree_entered
    signal tree_exited
    signal child_added(child : Node)
    signal child_removed(child : Node)

    def initialize(@name : String = "")
      @name = self.class.name.split("::").last if @name.empty?
    end

    # --- overridable hooks ----------------------------------------------------
    # Called once when the node first enters the tree, after its children.
    def ready : Nil; end
    def enter_tree : Nil; end
    def exit_tree : Nil; end
    # Every frame with the variable delta.
    def process(dt : Float32) : Nil; end
    # Fixed-rate updates (Config#fixed_fps).
    def physics_process(dt : Float32) : Nil; end
    # Draw this node. Node2D applies its transform before calling this.
    def draw(g : Graphics) : Nil; end
    # Input events; set `event.handled = true` to stop propagation.
    def input(event : Event) : Nil; end
    def resized(width : Int32, height : Int32) : Nil; end

    # --- tree manipulation ----------------------------------------------------
    def add(child : Node) : Node
      raise Error.new("#{child.name} already has a parent") if child.parent
      raise Error.new("cannot add a node to itself") if child == self
      @children << child
      child.set_parent(self)
      child.propagate_enter(@in_tree)
      emit_child_added(child)
      child
    end

    def add(*children : Node) : Nil
      children.each { |c| add(c) }
    end

    def add_child(child : Node) : Node; add(child); end

    def <<(child : Node) : self
      add(child)
      self
    end

    def remove(child : Node) : Nil
      return unless @children.delete(child)
      child.propagate_exit if @in_tree
      child.set_parent(nil)
      emit_child_removed(child)
    end

    def remove_child(child : Node) : Nil; remove(child); end

    def remove_from_parent : Nil
      @parent.try(&.remove(self))
    end

    # Remove and drop this node at the end of the frame (safe inside callbacks).
    def queue_free : Nil
      return if @queued_free
      @queued_free = true
      SceneTree.defer { remove_from_parent }
    end

    def queued_free? : Bool; @queued_free; end

    # Remove immediately.
    def free : Nil
      remove_from_parent
    end

    def clear_children : Nil
      @children.dup.each { |c| remove(c) }
    end

    def child_count : Int32; @children.size; end
    def first_child : Node?; @children.first?; end

    def child?(name : String) : Node?
      @children.find { |c| c.name == name }
    end

    # Godot-style path lookup: "Player/Sprite", "../Sibling", "/root/Hud".
    def get_node?(path : String) : Node?
      node : Node? = path.starts_with?('/') ? SceneTree.root : self
      path.split('/').each do |part|
        next if part.empty?
        return nil unless node
        node = case part
               when "." then node
               when ".." then node.parent
               when "root" then node == SceneTree.root || (node.parent.nil? && part == "root") ? SceneTree.root : node.child?(part)
               else node.child?(part)
               end
      end
      node
    end

    def get_node(path : String) : Node
      get_node?(path) || raise Error.new("Node not found: #{path} (from #{self.path})")
    end

    def [](path : String) : Node; get_node(path); end
    def []?(path : String) : Node?; get_node?(path); end

    # Typed lookup: `get_node("Sprite", Sprite2D)`
    def get_node(path : String, type : T.class) : T forall T
      n = get_node(path)
      n.as?(T) || raise Error.new("#{path} is a #{n.class}, not #{T}")
    end

    # First descendant (depth-first) whose name matches.
    def find(name : String) : Node?
      each_descendant { |n| return n if n.name == name }
      nil
    end

    # All descendants of a type.
    def find_all(type : T.class) : Array(T) forall T
      out_nodes = [] of T
      each_descendant { |n| out_nodes << n if n.is_a?(T) }
      out_nodes
    end

    def children_of(type : T.class) : Array(T) forall T
      @children.compact_map(&.as?(T))
    end

    def each_child(& : Node ->) : Nil
      @children.each { |c| yield c }
    end

    def each_descendant(&block : Node ->) : Nil
      @children.each do |c|
        block.call(c)
        c.each_descendant(&block)
      end
    end

    def each_ancestor(& : Node ->) : Nil
      p = @parent
      while p
        yield p
        p = p.parent
      end
    end

    def root : Node
      n = self
      while (p = n.parent)
        n = p
      end
      n
    end

    def path : String
      parts = [] of String
      n : Node? = self
      while n
        parts.unshift(n.name)
        n = n.parent
      end
      "/" + parts.join("/")
    end

    def ancestor_of?(node : Node) : Bool
      node.each_ancestor { |a| return true if a == self }
      false
    end

    # --- groups ---------------------------------------------------------------
    def add_to_group(group : String) : self
      @groups << group
      SceneTree.register_group(group, self) if @in_tree
      self
    end

    def remove_from_group(group : String) : Nil
      @groups.delete(group)
      SceneTree.unregister_group(group, self)
    end

    def in_group?(group : String) : Bool; @groups.includes?(group); end

    # --- processing -----------------------------------------------------------
    def can_process? : Bool
      case @process_mode
      in ProcessMode::Always then true
      in ProcessMode::Disabled then false
      in ProcessMode::Pausable then !SceneTree.paused?
      in ProcessMode::WhenPaused then SceneTree.paused?
      in ProcessMode::Inherit then @parent.try(&.can_process?) || (@parent.nil? && !SceneTree.paused?)
      end
    end

    # :nodoc:
    def process_tree(dt : Float32) : Nil
      process(dt) if can_process?
      @children.each { |c| c.process_tree(dt) }
    end

    # :nodoc:
    def physics_process_tree(dt : Float32) : Nil
      physics_process(dt) if can_process?
      @children.each { |c| c.physics_process_tree(dt) }
    end

    # :nodoc:
    def draw_tree(g : Graphics) : Nil
      return unless @visible
      draw_self(g)
      draw_children(g)
    end

    # :nodoc: subclasses (Node2D) override to apply transforms
    protected def draw_self(g : Graphics) : Nil
      draw(g)
    end

    protected def draw_children(g : Graphics) : Nil
      if @children.any? { |c| c.z_index != 0 }
        @children.sort_by(&.z_index).each { |c| c.draw_tree(g) }
      else
        @children.each { |c| c.draw_tree(g) }
      end
    end

    # :nodoc: children get input first (deepest last-added first), like Godot.
    def input_tree(event : Event) : Nil
      @children.reverse_each do |c|
        c.input_tree(event)
        return if event.handled?
      end
      input(event) if can_process?
    end

    # :nodoc:
    def ready_tree : Nil
      @children.each(&.ready_tree)
      unless @ready_called
        @ready_called = true
        ready
      end
    end

    # :nodoc:
    protected def set_parent(p : Node?) : Nil
      @parent = p
    end

    # :nodoc:
    protected def propagate_enter(parent_in_tree : Bool) : Nil
      return unless parent_in_tree
      @in_tree = true
      @groups.each { |g| SceneTree.register_group(g, self) }
      enter_tree
      emit_tree_entered
      @children.each(&.propagate_enter(true))
      unless @ready_called
        @ready_called = true
        ready
      end
    end

    # :nodoc:
    protected def propagate_exit : Nil
      @children.each(&.propagate_exit)
      @groups.each { |g| SceneTree.unregister_group(g, self) }
      exit_tree
      emit_tree_exited
      @in_tree = false
      @queued_free = false
    end

    def to_s(io : IO) : Nil
      io << self.class.name << "(" << @name << ")"
    end

    # Pretty tree dump for debugging.
    def dump(io : IO = STDOUT, indent = 0) : Nil
      io << "  " * indent << self << "\n"
      @children.each(&.dump(io, indent + 1))
    end
  end
end
