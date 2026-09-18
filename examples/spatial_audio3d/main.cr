require "../../src/eagle"
include Eagle

# Spatial audio demo: looping procedural sound sources placed around a 3D scene. Put on
# headphones and fly around; sources pan between the ears, reach the far ear a little later,
# sound duller from behind and fade with distance. The blue drone orbits with doppler on.
# Controls: WASD/QE move, right-drag or arrows look, left click fires a shot where you point,
# 1-3 switch the distance model, M mutes.
class SpatialAudio < App
  record Source, name : String, mesh : MeshInstance3D, player : AudioPlayer3D, color : Color

  @cam = Camera3D.new(position: v3(0, 1.7, 12))
  @sources = [] of Source
  @drone = Node3D.new(position: v3(0, 2.5, 0))
  @drone_angle = 0_f32
  @shot : Sound = SpatialAudio.shot_sound
  @shots = [] of {Vec3, Float32}
  @model = Attenuation::Inverse

  # A two-second loop: every frequency is a whole number of cycles, so it loops seamlessly.
  def self.hum : Sound
    Sound.generate(2.0) do |t|
      (Math.sin(t * 55 * Math::TAU) * 0.35 + Math.sin(t * 110 * Math::TAU) * 0.15 + ((t * 165) % 1 - 0.5) * 0.12).to_f32
    end
  end

  # Radio beeps: two short pips each second.
  def self.beeper : Sound
    Sound.generate(1.0) do |t|
      local = t % 0.5
      local < 0.08 ? (Math.sin(t * 1200 * Math::TAU) * 0.4 * Math.min(1, (0.08 - local) * 200)).to_f32 : 0_f32
    end
  end

  # A crackling fire: filtered noise with random pops.
  def self.fire : Sound
    rng = Random.new(3)
    lp = 0.0
    Sound.generate(3.0) do |t|
      lp += (rng.rand(-1.0..1.0) - lp) * 0.2
      pop = rng.rand < 0.0015 ? rng.rand(-0.9..0.9) : 0.0
      edge = Math.min(1.0, Math.min(t, 3 - t) * 20) # fade the loop seam
      ((lp * 0.5 + pop) * edge).to_f32
    end
  end

  # The drone's buzz: a triangle with a slow wobble.
  def self.buzz : Sound
    Sound.generate(2.0) do |t|
      ph = (t * 220 + Math.sin(t * Math::TAU * 3) * 0.8) % 1
      tri = ph < 0.5 ? ph * 4 - 1 : 3 - ph * 4
      (tri * 0.3).to_f32
    end
  end

  # A gunshot: a noise burst with a fast decay and a low thump.
  def self.shot_sound : Sound
    rng = Random.new(9)
    Sound.generate(0.5) do |t|
      ((rng.rand(-1.0..1.0) * 0.8 + Math.sin(t * 70 * Math::TAU) * 0.6) * Math.exp(-t * 14)).to_f32
    end
  end

  def load
    root = SceneTree.root
    env = Scene3D.environment
    env.fog(25, 70, Color.hex("#1b2230"))
    env.sky_colors(Color.hex("#0f1522"), Color.hex("#2a3550"), Color.hex("#111418"))
    env.ambient = Color.new(0.22, 0.24, 0.3)
    checker = Texture.new(Image.checkerboard(64, 64, 8, Color.hex("#3a4250"), Color.hex("#2c323d")), wrap: GPU::Wrap::Repeat)
    root.add(MeshInstance3D.new(Mesh.plane(80, 80, 8, uv_scale: 16), Material.new(texture: checker, shininess: 16, specular: 0.05)))
    root.add(DirectionalLight3D.new(v3(-0.4, -1, -0.5), Color.hex("#c8d4ff"), 0.5))

    add_source("generator", SpatialAudio.hum, v3(-8, 0.75, -4), Mesh.cube(1.5), Color.hex("#ff5a4f"), root)
    add_source("radio", SpatialAudio.beeper, v3(8, 0.5, -2), Mesh.box(1.2, 1, 0.6), Color.hex("#5aff8a"), root)
    add_source("fire", SpatialAudio.fire, v3(0, 0.6, -14), Mesh.cone(0.8, 1.4), Color.hex("#ffa640"), root)
    root.add(@drone)
    add_source("drone", SpatialAudio.buzz, Vec3::ZERO, Mesh.sphere(0.45), Color.hex("#5ab4ff"), @drone)
    @sources.last.player.doppler = true
    @sources.last.player.doppler_scale = 2

    root.add(@cam)
    @cam.look_at(v3(0, 1, 0))
  end

  private def add_source(name : String, sound : Sound, pos : Vec3, mesh : Mesh, color : Color, parent : Node) : Nil
    body = MeshInstance3D.new(mesh, Material.new(color, emissive: color * 0.35), position: pos)
    player = AudioPlayer3D.new(sound, loop: true, autoplay: true, max_distance: 40, volume: 0.8)
    player.min_distance = 3
    body.add(player)
    body.add(PointLight3D.new(v3(0, 1.2, 0), color, 1.5, 7))
    parent.add(body)
    @sources << Source.new(name, body, player, color)
  end

  def update(dt : Float32)
    @cam.fly(dt, 6)
    @drone_angle += dt * 0.6
    @drone.position = v3(Math.cos(@drone_angle) * 9, 2.5, Math.sin(@drone_angle) * 9 - 3)
    @sources.each_with_index do |s, i|
      level = s.player.voice.try(&.spatial).try { |sp| sp.gain_left + sp.gain_right } || 0_f32
      s.mesh.scale = 1 + Math.sin(Clock.elapsed * (3 + i)).to_f32 * 0.04 + level * 0.1
    end
    {Key::Num1 => Attenuation::Inverse, Key::Num2 => Attenuation::Linear, Key::Num3 => Attenuation::Exponential}.each do |k, m|
      if Input.pressed?(k)
        @model = m
        @sources.each { |s| s.player.attenuation = m }
      end
    end
    Audio.master.muted = !Audio.master.muted? if Input.pressed?(Key::M)
    if Input.mouse_pressed?(MouseButton::Left)
      ray = @cam.mouse_ray
      t = ray.intersect_plane(Vec3::ZERO, Vec3::UP) || 20_f32
      hit = ray.origin + ray.direction * Math.min(t, 40_f32)
      Audio.play_at(@shot, hit, volume: 0.9, pitch: 0.9 + rand * 0.2, min_distance: 2, max_distance: 80, attenuation: @model)
      @shots << {hit, 0.4_f32}
    end
    @shots = @shots.compact_map { |(p, life)| life > dt ? {p, life - dt} : nil }
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    @shots.each do |(p, life)|
      Scene3D.debug_sphere(p, 0.2_f32 + (0.4_f32 - life) * 4, Color::WHITE)
    end
    @sources.each do |s|
      sp = s.player.voice.try(&.spatial)
      next unless sp
      next unless pt = @cam.world_to_screen(s.mesh.global_position + v3(0, 1.4, 0))
      g.print(s.name, pt.x, pt.y - 30, s.color, align: TextAlign::Center)
      meter(g, pt.x - 42, pt.y - 10, sp.gain_left, "L")
      meter(g, pt.x + 4, pt.y - 10, sp.gain_right, "R")
    end
    g.rect(0, 0, Window.width, 96, color: Color.new(0, 0, 0, 0.55))
    g.print("Spatial audio: wear headphones and fly around. Sources pan, fade with distance,", 10, 10, Color::WHITE)
    g.print("reach the far ear later and sound duller from behind. The drone has doppler.", 10, 28, Color::WHITE)
    g.print("WASD/QE move, right-drag look, click fires a shot, 1-3 distance model, M mute", 10, 48, Color.gray(0.8))
    g.print("model #{@model}   voices #{Audio.voice_count}   #{Audio.master.muted? ? "MUTED" : "click once in a browser to start audio"}", 10, 70, Color.hex("#ffd166"))
  end

  private def meter(g : Graphics, x : Float32, y : Float32, gain : Float32, label : String) : Nil
    g.rect(x, y, 38, 8, color: Color.new(0, 0, 0, 0.6))
    g.rect(x, y, 38 * Math.sqrt(gain.clamp(0_f32, 1_f32)), 8, color: Color.hex("#ffd166")) # sqrt so distant sources still show
    g.print(label, label == "L" ? x - 12 : x + 42, y - 1, Color.gray(0.85))
  end
end

Eagle.run(SpatialAudio, title: "Eagle spatial audio", width: 1024, height: 640, msaa: 4)
