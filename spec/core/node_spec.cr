require "../spec_helper"

class Counter < Node
  getter readies = 0
  getter processes = 0
  getter physics = 0
  getter entered = 0
  getter exited = 0
  getter last_dt = 0_f32
  def ready; @readies += 1; end
  def enter_tree; @entered += 1; end
  def exit_tree; @exited += 1; end
  def process(dt : Float32); @processes += 1; @last_dt = dt; end
  def physics_process(dt : Float32); @physics += 1; end
end

class Handler < Node
  getter got = [] of Event
  property consume = false
  def input(e : Event)
    @got << e
    e.handled = true if @consume
  end
end

class Damageable < Node
  signal hit(damage : Int32)
  signal died
end

describe Eagle::Node do
  before_each { SceneTree.reset }

  it "adds and removes children with lifecycle callbacks" do
    root = SceneTree.root
    a = Counter.new("a")
    b = Counter.new("b")
    a.add(b)
    a.in_tree?.should be_false
    a.readies.should eq 0
    root.add(a)
    a.in_tree?.should be_true
    b.in_tree?.should be_true
    a.readies.should eq 1
    b.readies.should eq 1
    b.entered.should eq 1
    b.parent.should eq a
    a.path.should eq "/root/a"
    b.path.should eq "/root/a/b"
    root.remove(a)
    a.in_tree?.should be_false
    b.exited.should eq 1
    a.parent.should be_nil
    # re-adding does not call ready again
    root.add(a)
    a.readies.should eq 1
    a.entered.should eq 2
  end

  it "rejects double parenting" do
    a = Node.new; b = Node.new
    a.add(b)
    expect_raises(Eagle::Error) { Node.new.add(b) }
    expect_raises(Eagle::Error) { a.add(a) }
  end

  it "finds nodes by path" do
    root = SceneTree.root
    player = Node.new("Player")
    sprite = Node.new("Sprite")
    hud = Node.new("Hud")
    player.add(sprite)
    root.add(player, hud)
    root.get_node("Player/Sprite").should eq sprite
    sprite.get_node("..").should eq player
    sprite.get_node("../../Hud").should eq hud
    sprite.get_node("/root/Hud").should eq hud
    root.get_node?("Nope").should be_nil
    expect_raises(Eagle::Error) { root.get_node("Nope") }
    root["Player"].should eq player
    root.find("Sprite").should eq sprite
    root.get_node("Player", Node).should eq player
  end

  it "processes the tree with process modes and pausing" do
    root = SceneTree.root
    a = Counter.new; b = Counter.new; c = Counter.new
    a.add(b); root.add(a, c)
    c.process_mode = Node::ProcessMode::Always
    root.process_tree(0.5_f32)
    a.processes.should eq 1; b.processes.should eq 1; c.processes.should eq 1
    b.last_dt.should eq 0.5_f32
    SceneTree.paused = true
    root.process_tree(0.5_f32)
    a.processes.should eq 1; b.processes.should eq 1; c.processes.should eq 2
    b.process_mode = Node::ProcessMode::WhenPaused
    root.process_tree(0.5_f32)
    b.processes.should eq 2
    root.physics_process_tree(0.1_f32)
    c.physics.should eq 1
    a.physics.should eq 0
  end

  it "dispatches input children-first and honours handled" do
    root = SceneTree.root
    parent = Handler.new("parent"); child = Handler.new("child")
    parent.add(child); root.add(parent)
    SceneTree.dispatch_input(KeyEvent.new(Key::A, true))
    parent.got.size.should eq 1; child.got.size.should eq 1
    child.consume = true
    SceneTree.dispatch_input(KeyEvent.new(Key::B, true))
    parent.got.size.should eq 1; child.got.size.should eq 2
  end

  it "queue_free removes at end of frame" do
    root = SceneTree.root
    n = Node.new; root.add(n)
    n.queue_free
    n.in_tree?.should be_true
    SceneTree.flush_deferred
    n.in_tree?.should be_false
    root.child_count.should eq 0
  end

  it "tracks groups" do
    root = SceneTree.root
    e1 = Node.new("e1").add_to_group("enemies")
    e2 = Node.new("e2").add_to_group("enemies")
    SceneTree.group("enemies").should be_empty
    root.add(e1, e2)
    SceneTree.group("enemies").should eq [e1, e2]
    e1.in_group?("enemies").should be_true
    e1.free
    SceneTree.group("enemies").should eq [e2]
    e2.remove_from_group("enemies")
    SceneTree.group("enemies").should be_empty
  end

  it "changes scenes" do
    s1 = Node.new("s1"); s2 = Node.new("s2")
    SceneTree.change_scene!(s1)
    SceneTree.current_scene.should eq s1
    SceneTree.change_scene(s2)
    SceneTree.current_scene.should eq s1
    SceneTree.flush_deferred
    SceneTree.current_scene.should eq s2
    s1.in_tree?.should be_false
    s2.in_tree?.should be_true
  end

  it "finds typed descendants and iterates" do
    root = SceneTree.root
    a = Counter.new; b = Handler.new; c = Counter.new
    a.add(c); root.add(a, b)
    root.find_all(Counter).should eq [a, c]
    root.children_of(Handler).should eq [b]
    names = [] of String
    root.each_descendant { |n| names << n.name }
    names.should eq ["Counter", "Counter", "Handler"]
    c.root.should eq root
    a.ancestor_of?(c).should be_true
    c.ancestor_of?(a).should be_false
  end

  it "emits signals" do
    d = Damageable.new
    total = 0
    d.on_hit { |dmg| total += dmg }
    d.emit_hit(3); d.emit_hit(4)
    total.should eq 7
    died = 0
    d.died.connect { died += 1 }
    d.emit_died
    died.should eq 1
    h = d.hit.once { |dmg| total += 100 }
    d.emit_hit(1); d.emit_hit(1)
    total.should eq 109
    d.hit.size.should eq 1
    d.hit.disconnect(d.hit.connect { |x| })
    d.hit.size.should eq 1
    d.hit.clear
    d.hit.connected?.should be_false
  end

  it "emits child_added / tree_entered signals" do
    root = SceneTree.root
    n = Node.new
    added = 0; entered = 0
    root.on_child_added { |c| added += 1 }
    n.on_tree_entered { entered += 1 }
    root.add(n)
    added.should eq 1; entered.should eq 1
  end
end
