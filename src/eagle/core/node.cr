module Eagle
  # The building block of Eagle's scene tree. Everything in a scene is a node: sprites,
  # cameras, bodies, sounds, UI widgets and your own game objects.
  #
  # Nodes form a tree. Adding a node under `SceneTree.root` (directly or through a parent)
  # brings it to life, and Eagle then calls its hooks:
  #
  # * `ready` once, after it and its children have entered the tree
  # * `process(dt)` every frame
  # * `physics_process(dt)` at the fixed rate
  # * `draw(g)` every frame, in tree order, with `z_index` breaking ties among siblings
  # * `input(event)` for each event, deepest node first
  #
  # Subclass a node type and override the hooks you need. Plain `Node` has no position;
  # use `Node2D` or `Node3D` for things that live in space.
  #
  # ```
  # class Blinker < Node2D
  #   @t = 0.0
  #
  #   def ready : Nil
  #     add(Label.new("hello"))
  #   end
  #
  #   def process(dt : Float32) : Nil
  #     @t += dt
  #     self.visible = @t % 1 < 0.5
  #     queue_free if @t > 10
  #   end
  # end
  #
  # blinker = Blinker.new
  # blinker.position = v2(200, 100)
  # SceneTree.root.add(blinker)
  # ```
  #
  # Nodes are found by name with `get_node("Player/Sprite")`, by type with `find_all`, and
  # by group with `add_to_group` plus `SceneTree.group`.
  class Node
    # Whether a node keeps processing while the tree is paused.
    enum ProcessMode
      # Do what the parent does. At the root this means "pause with the tree".
      Inherit
      # Keep processing while paused. Use it for pause menus.
      Always
      # Stop processing while paused.
      Pausable
      # Process only while paused.
      WhenPaused
      # Never process. The node still draws.
      Disabled
    end

    # The node's name, used by `get_node` paths. Defaults to the class name.
    property name : String
    # The parent node, or `nil` if this node hasn't been added anywhere.
    getter parent : Node? = nil
    # Child nodes in the order they were added.
    getter children = [] of Node
    # Hidden nodes and their children are not drawn. They still process.
    property? visible = true
    # Controls behavior while the tree is paused; see `ProcessMode`.
    property process_mode = ProcessMode::Inherit
    # Draw order among siblings: higher values draw later, on top.
    property z_index = 0
    # True while the node is attached, directly or indirectly, to `SceneTree.root`.
    getter? in_tree = false
    # True once `ready` has run. It runs only the first time the node enters the tree.
    getter? ready_called = false
    # Names of the groups this node belongs to.
    getter groups = Set(String).new
    @queued_free = false

    # Emitted each time the node enters the tree. Connect with `on_tree_entered { ... }`.
    signal tree_entered
    # Emitted each time the node leaves the tree.
    signal tree_exited
    # Emitted after a child is added, with the child.
    signal child_added(child : Node)
    # Emitted after a child is removed, with the child.
    signal child_removed(child : Node)

    # Creates a node. When *name* is empty, the class name is used.
    def initialize(@name : String = "")
      @name = self.class.name.split("::").last if @name.empty?
    end

    # --- overridable hooks ----------------------------------------------------
    # Called once, the first time this node enters the tree, after its children are ready.
    # Build child nodes, look up siblings and connect signals here.
    def ready : Nil; end
    # Called every time the node is attached to the tree, before `ready`.
    def enter_tree : Nil; end
    # Called every time the node leaves the tree. Undo anything `enter_tree` did.
    def exit_tree : Nil; end
    # Called every frame with the frame time in seconds. Put per-frame logic here.
    def process(dt : Float32) : Nil; end
    # Called at the fixed rate (`Config#fixed_fps`), after the physics world steps.
    # Move physics bodies and read contacts here.
    def physics_process(dt : Float32) : Nil; end
    # Draws this node. `Node2D` has already applied its transform, so draw around `(0, 0)`.
    def draw(g : Graphics) : Nil; end
    # Receives input events. Set `event.handled = true` to stop them from reaching other nodes.
    def input(event : Event) : Nil; end
    # Called on every node in the tree when the window is resized.
    def resized(width : Int32, height : Int32) : Nil; end

    # --- tree manipulation ----------------------------------------------------
    # Adds *child* as the last child and returns it. If this node is in the tree, the child
    # enters too and gets `ready`. Raises if *child* already has a parent.
    #
    # ```
    # enemy = Node2D.new("Enemy")
    # SceneTree.root.add(enemy).add(Sprite2D.new(Texture.new(Image.circle(8, Color::RED))))
    # ```
    def add(child : Node) : Node
      raise Error.new("#{child.name} already has a parent") if child.parent
      raise Error.new("cannot add a node to itself") if child == self
      @children << child
      child.set_parent(self)
      child.propagate_enter(@in_tree)
      emit_child_added(child)
      child
    end

    # Adds several children in order.
    def add(*children : Node) : Nil
      children.each { |c| add(c) }
    end

    # Same as `add`, for readers coming from Godot.
    def add_child(child : Node) : Node; add(child); end

    # Adds *child* and returns self, so additions can be chained.
    def <<(child : Node) : self
      add(child)
      self
    end

    # Detaches *child* right away. It leaves the tree and gets `exit_tree`. You can add it again later.
    def remove(child : Node) : Nil
      return unless @children.delete(child)
      child.propagate_exit if @in_tree
      child.set_parent(nil)
      emit_child_removed(child)
    end

    # Same as `remove`.
    def remove_child(child : Node) : Nil; remove(child); end

    # Detaches this node from its parent right away.
    def remove_from_parent : Nil
      @parent.try(&.remove(self))
    end

    # Removes this node at the end of the frame. This is the safe way for a node to delete
    # itself from inside `process`, a signal handler or a collision callback.
    def queue_free : Nil
      return if @queued_free
      @queued_free = true
      SceneTree.defer { remove_from_parent }
    end

    # True after `queue_free` and before the removal happens.
    def queued_free? : Bool; @queued_free; end

    # Removes this node right away. Prefer `queue_free` from inside callbacks.
    def free : Nil
      remove_from_parent
    end

    # Removes every child.
    def clear_children : Nil
      @children.dup.each { |c| remove(c) }
    end

    # Number of direct children.
    def child_count : Int32; @children.size; end
    # The first child, or `nil`.
    def first_child : Node?; @children.first?; end

    # The direct child called *name*, or `nil`.
    def child?(name : String) : Node?
      @children.find { |c| c.name == name }
    end

    # Finds a node by path, or returns `nil`. Paths work like file paths:
    # `"Sprite"`, `"Player/Gun"`, `"../Sibling"`, and `"/root/Hud"` from the top.
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

    # Finds a node by path and raises if it doesn't exist.
    def get_node(path : String) : Node
      get_node?(path) || raise Error.new("Node not found: #{path} (from #{self.path})")
    end

    # Short form of `get_node`.
    def [](path : String) : Node; get_node(path); end
    # Short form of `get_node?`.
    def []?(path : String) : Node?; get_node?(path); end

    # Finds a node by path and casts it, so you get a typed result.
    #
    # ```
    # class Player < Node2D
    #   def ready : Nil
    #     add(Label.new("P1", name: "Tag"))
    #     get_node("Tag", Label).text = "Player 1"
    #   end
    # end
    # ```
    def get_node(path : String, type : T.class) : T forall T
      n = get_node(path)
      n.as?(T) || raise Error.new("#{path} is a #{n.class}, not #{T}")
    end

    # The first descendant with this name, searched depth-first.
    def find(name : String) : Node?
      found : Node? = nil
      each_descendant { |n| found = n if found.nil? && n.name == name }
      found
    end

    # Every descendant of the given type.
    #
    # ```
    # SceneTree.root.find_all(Sprite2D).each { |s| s.modulate = Color::RED }
    # ```
    def find_all(type : T.class) : Array(T) forall T
      out_nodes = [] of T
      each_descendant { |n| out_nodes << n if n.is_a?(T) }
      out_nodes
    end

    # Direct children of the given type.
    def children_of(type : T.class) : Array(T) forall T
      @children.compact_map(&.as?(T))
    end

    # Yields each direct child.
    def each_child(& : Node ->) : Nil
      @children.each { |c| yield c }
    end

    # Yields every descendant, depth-first.
    def each_descendant(&block : Node ->) : Nil
      @children.each do |c|
        block.call(c)
        c.each_descendant(&block)
      end
    end

    # Yields the parent, then its parent, up to the root.
    def each_ancestor(& : Node ->) : Nil
      p = @parent
      while p
        yield p
        p = p.parent
      end
    end

    # The topmost ancestor. It is `SceneTree.root` when the node is in the tree.
    def root : Node
      n = self
      while (p = n.parent)
        n = p
      end
      n
    end

    # The node's path from the root, such as `"/root/Level/Player"`.
    def path : String
      parts = [] of String
      n : Node? = self
      while n
        parts.unshift(n.name)
        n = n.parent
      end
      "/" + parts.join("/")
    end

    # True when *node* is somewhere below this one.
    def ancestor_of?(node : Node) : Bool
      p = node.parent
      while p
        return true if p == self
        p = p.parent
      end
      false
    end

    # --- groups ---------------------------------------------------------------
    # Adds this node to a named group and returns self. Groups make it easy to act on many
    # nodes at once with `SceneTree.group` and `SceneTree.call_group`.
    def add_to_group(group : String) : self
      @groups << group
      SceneTree.register_group(group, self) if @in_tree
      self
    end

    # Removes this node from a group.
    def remove_from_group(group : String) : Nil
      @groups.delete(group)
      SceneTree.unregister_group(group, self)
    end

    # True when this node belongs to *group*.
    def in_group?(group : String) : Bool; @groups.includes?(group); end

    # --- processing -----------------------------------------------------------
    # True when this node should run `process` right now, given pause state and `process_mode`.
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

    # Prints the subtree with indentation, which is handy when debugging.
    def dump(io : IO = STDOUT, indent = 0) : Nil
      io << "  " * indent << self << "\n"
      @children.each(&.dump(io, indent + 1))
    end
  end
end
