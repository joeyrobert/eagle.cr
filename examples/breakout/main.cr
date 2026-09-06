require "../../src/eagle"
include Eagle

# Breakout: move the paddle with the mouse or arrow keys / gamepad. Space launches.
class Breakout < App
  W = 800; H = 600
  record Brick, rect : Rect, color : Color, hp : Int32

  @paddle : Rect = Rect.new(350, 560, 100, 14)
  @ball : Vec2 = Vec2.new(400, 540)
  @vel = Vec2::ZERO
  @radius = 7_f32
  @bricks = [] of Brick
  @score = 0
  @lives = 3
  @level = 1
  @launched = false
  @fx = Particles2D.new(amount: 0)
  @snd_hit : Sound? = nil
  @snd_break : Sound? = nil
  @snd_lose : Sound? = nil
  @shake = Camera2D.new(current: true)
  @game_over = false

  def load
    Input.map "left", Key::Left, Key::A, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::Right, Key::D, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "launch", Key::Space, GamepadButton::A, MouseButton::Left
    @snd_hit = Sound.tone(600, 0.04, Sound::Wave::Square, 0.25)
    @snd_break = Sound.tone(300, 0.08, Sound::Wave::Saw, 0.3)
    @snd_lose = Sound.tone(120, 0.4, Sound::Wave::Triangle, 0.4)
    @fx.lifetime = 0.5; @fx.speed = 60..220; @fx.spread = Math::PI; @fx.gravity = v2(0, 500)
    @fx.scale_start = 0.4; @fx.scale_end = 0.0; @fx.blend = GPU::BlendMode::Additive
    @shake.position = v2(W / 2, H / 2)
    SceneTree.root.add(@shake, @fx)
    build_level
  end

  def build_level
    @bricks.clear
    cols = 10; rows = 4 + @level
    bw = (W - 40) / cols; bh = 22
    rows.times do |r|
      cols.times do |c|
        next if @level > 1 && (r + c) % 7 == 0
        hp = r < 2 && @level > 1 ? 2 : 1
        @bricks << Brick.new(Rect.new(20 + c * bw + 2, 60 + r * (bh + 4), bw - 4, bh), Color.hsv(r * 30 + @level * 40, 0.75, 1), hp)
      end
    end
    reset_ball
  end

  def reset_ball
    @launched = false
    @vel = Vec2::ZERO
    @ball = v2(@paddle.center.x, @paddle.y - @radius - 1)
  end

  def update(dt : Float32)
    return if @game_over
    px = @paddle.x
    px += Input.axis("left", "right") * 520 * dt
    px = Input.mouse.x - @paddle.w / 2 if Input.mouse_delta != Vec2::ZERO
    @paddle = Rect.new(px.clamp(0_f32, W - @paddle.w), @paddle.y, @paddle.w, @paddle.h)
    if !@launched
      @ball = v2(@paddle.center.x, @paddle.y - @radius - 1)
      if Input.pressed?("launch")
        @launched = true
        @vel = Vec2.from_angle(-Math::PI / 2 + (rand - 0.5), 330 + @level * 30)
      end
      return
    end
    steps = 4
    steps.times { step(dt / steps) }
    if @bricks.empty?
      @level += 1
      build_level
    end
  end

  private def step(dt)
    @ball += @vel * dt
    if @ball.x - @radius < 0 || @ball.x + @radius > W
      @vel = v2(-@vel.x, @vel.y); @ball = v2(@ball.x.clamp(@radius, W - @radius), @ball.y); @snd_hit.try(&.play(pitch: 1.5))
    end
    if @ball.y - @radius < 40
      @vel = v2(@vel.x, -@vel.y); @ball = v2(@ball.x, 40 + @radius); @snd_hit.try(&.play(pitch: 1.5))
    end
    if @ball.y > H + 20
      @lives -= 1
      @snd_lose.try(&.play)
      @shake.shake(8, 0.3)
      if @lives <= 0
        @game_over = true
      else
        reset_ball
      end
      return
    end
    # paddle
    if @vel.y > 0 && circle_rect?(@ball, @radius, @paddle)
      t = ((@ball.x - @paddle.center.x) / (@paddle.w / 2)).clamp(-1_f32, 1_f32)
      speed = @vel.length * 1.01
      @vel = Vec2.from_angle(-Math::PI / 2 + t * 1.1, speed)
      @ball = v2(@ball.x, @paddle.y - @radius - 0.5)
      @snd_hit.try(&.play)
    end
    # bricks
    @bricks.each_with_index do |b, i|
      next unless circle_rect?(@ball, @radius, b.rect)
      # decide bounce axis by penetration
      dx = @ball.x - b.rect.center.x; dy = @ball.y - b.rect.center.y
      px = b.rect.w / 2 + @radius - dx.abs; py = b.rect.h / 2 + @radius - dy.abs
      if px < py
        @vel = v2(-@vel.x, @vel.y); @ball += v2(Mathf.sign(dx) * px, 0)
      else
        @vel = v2(@vel.x, -@vel.y); @ball += v2(0, Mathf.sign(dy) * py)
      end
      if b.hp > 1
        @bricks[i] = Brick.new(b.rect, b.color.darken(0.4), b.hp - 1)
        @snd_hit.try(&.play(pitch: 0.8))
      else
        @bricks.delete_at(i)
        @score += 10 * @level
        @snd_break.try(&.play)
        @fx.position = b.rect.center
        @fx.color_over_life = [b.color, b.color.with_alpha(0)]
        @fx.emit(25)
        @shake.shake(2, 0.1)
      end
      break
    end
  end

  private def circle_rect?(c : Vec2, r : Float32, rect : Rect) : Bool
    cx = c.x.clamp(rect.x, rect.right); cy = c.y.clamp(rect.y, rect.bottom)
    (c - v2(cx, cy)).length_squared <= r * r
  end

  def input(e : Event)
    if e.is_a?(KeyEvent) && e.pressed? && e.key == Key::R && @game_over
      @score = 0; @lives = 3; @level = 1; @game_over = false
      build_level
    end
  end

  def draw(g : Graphics)
    g.rect(0, 40, W, 2, color: Color::GRAY)
    @bricks.each do |b|
      g.rounded_rect(b.rect.x, b.rect.y, b.rect.w, b.rect.h, 4, color: b.color)
      g.rounded_rect(b.rect.x, b.rect.y, b.rect.w, b.rect.h / 2, 4, color: Color::WHITE.with_alpha(0.15))
    end
    g.rounded_rect(@paddle.x, @paddle.y, @paddle.w, @paddle.h, 6, color: Color.hex("#4fd1c5"))
    g.circle(@ball, @radius, color: Color::WHITE)
    g.print("score #{@score}   lives #{@lives}   level #{@level}", 12, 10, Color::WHITE)
    g.print("press space / click to launch", W / 2, 300, Color::GRAY, align: TextAlign::Center) unless @launched || @game_over
    g.print("GAME OVER — R to restart", W / 2, 300, Color::RED, align: TextAlign::Center) if @game_over
  end
end

Eagle.run(Breakout, title: "Eagle Breakout", width: Breakout::W, height: Breakout::H)
