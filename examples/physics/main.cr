require "../../src/eagle"
include Eagle

# Physics + particles playground. Click to spawn boxes/balls; watch them pile up.
class Playground < App
  @spawned = 0
  @fx = Particles2D.new(amount: 0, position: v2(400, 300))

  def load
    root = SceneTree.root
    root.add(StaticBody2D.new(position: v2(400, 580)).box(760, 40).tap(&.debug = true))
    root.add(StaticBody2D.new(position: v2(20, 300)).box(40, 600).tap(&.debug = true))
    root.add(StaticBody2D.new(position: v2(780, 300)).box(40, 600).tap(&.debug = true))
    ramp = StaticBody2D.new(position: v2(250, 420))
    ramp.rotation = 0.3
    ramp.box(300, 20)
    ramp.debug = true
    root.add(ramp)
    30.times { |i| spawn(v2(150 + (i % 10) * 50, 50 + (i // 10) * 60)) }
    @fx.lifetime = 0.8
    @fx.speed = 100..250
    @fx.spread = Math::PI
    @fx.gravity = v2(0, 400)
    @fx.scale_start = 1.5
    @fx.scale_end = 0.2
    @fx.color_over_life = [Color::YELLOW, Color::ORANGE, Color::RED.with_alpha(0)]
    @fx.blend = GPU::BlendMode::Additive
    root.add(@fx)
    Timer.new(0.7) { @fx.position = v2(rand(200..600), rand(100..300)); @fx.emit(60) }.start.tap { |t| root.add(t) }
  end

  def spawn(at : Vec2)
    b = RigidBody2D.new(position: at)
    if (@spawned += 1).odd?
      b.circle(rand(10..20))
    else
      s = rand(18..36)
      b.box(s, s)
    end
    b.restitution = 0.3
    b.rotation = (rand * 3).to_f32
    b.debug = true
    b.modulate = Color.hsv(@spawned * 25, 0.7, 1)
    SceneTree.root.add(b)
  end

  def input(e : Event)
    if e.is_a?(MouseButtonEvent) && e.pressed?
      spawn(e.position)
    end
  end

  def draw(g : Graphics)
    g.print("click to spawn  bodies #{Physics2D.world.bodies.size}  fps #{Clock.fps.round}  particles #{@fx.alive_count}", 10, 10, Color::WHITE)
  end
end

Eagle.run(Playground, title: "Eagle physics", width: 800, height: 600)
