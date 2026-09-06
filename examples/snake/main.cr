require "../../src/eagle"
require "./snake"
include Eagle

class SnakeApp < App
  CELL = 32
  @game = SnakeGame.new(24, 16)
  @timer = 0_f32
  @speed = 8_f32 # cells per second
  @snd : Sound? = nil
  @snd_die : Sound? = nil
  @best = 0

  def load
    Input.map "up", Key::Up, Key::W, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::Down, Key::S, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "left", Key::Left, Key::A, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::Right, Key::D, Input.axis(GamepadAxis::LeftX, 1)
    @snd = Sound.tone(700, 0.06, Sound::Wave::Sine, 0.3)
    @snd_die = Sound.tone(110, 0.5, Sound::Wave::Saw, 0.3)
  end

  def update(dt : Float32)
    @game.turn(SnakeGame::Dir::Up) if Input.pressed?("up")
    @game.turn(SnakeGame::Dir::Down) if Input.pressed?("down")
    @game.turn(SnakeGame::Dir::Left) if Input.pressed?("left")
    @game.turn(SnakeGame::Dir::Right) if Input.pressed?("right")
    if @game.game_over?
      if Input.pressed?(Key::Space) || Input.pressed?(Key::Enter)
        @game = SnakeGame.new(24, 16); @speed = 8_f32
      end
      return
    end
    @timer += dt
    while @timer >= 1 / @speed
      @timer -= 1 / @speed
      case @game.step
      when :ate
        @snd.try(&.play(pitch: 1 + @game.score * 0.02))
        @speed += 0.25
        @best = Math.max(@best, @game.score)
      when :died then @snd_die.try(&.play)
      end
    end
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    ox = (Window.width - @game.width * CELL) / 2; oy = 50
    g.rect(ox - 2, oy - 2, @game.width * CELL + 4, @game.height * CELL + 4, DrawMode::Line, Color.gray(0.4))
    @game.height.times { |y| @game.width.times { |x| g.rect(ox + x * CELL, oy + y * CELL, CELL, CELL, color: (x + y).even? ? Color.hex("#1e2230") : Color.hex("#222739")) } }
    fx, fy = @game.food
    g.circle(ox + fx * CELL + CELL / 2, oy + fy * CELL + CELL / 2, CELL * 0.35, color: Color.hex("#ff5d73"))
    n = @game.length
    @game.body.each_with_index do |(x, y), i|
      t = i / n.to_f
      c = Color.hex("#7bed9f").lerp(Color.hex("#2ed573"), t)
      g.rounded_rect(ox + x * CELL + 2, oy + y * CELL + 2, CELL - 4, CELL - 4, 6, color: c)
    end
    g.print("score #{@game.score}   best #{@best}   length #{n}   speed #{@speed.round(1)}", ox, 14, Color::WHITE)
    if @game.game_over?
      g.rect(0, 0, Window.width, Window.height, color: Color.new(0, 0, 0, 0.5))
      g.print("GAME OVER", Window.width / 2, Window.height / 2 - 30, Color::RED, scale: 2, align: TextAlign::Center)
      g.print("press space to restart", Window.width / 2, Window.height / 2 + 20, Color::WHITE, align: TextAlign::Center)
    end
  end
end

Eagle.run(SnakeApp, title: "Eagle Snake", width: 24 * SnakeApp::CELL + 64, height: 16 * SnakeApp::CELL + 100)
