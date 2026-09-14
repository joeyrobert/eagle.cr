require "../../src/eagle"
require "./dungeon"
include Eagle

# Dungeon explorer: arrows / WASD / hjkl move & attack, space waits, > descends,
# R restarts. Fog of war, shadowcasting FOV, monsters, items, 5 levels.
class RoguelikeApp < App
  CELL = 20
  @game = Rogue::Game.new((Random.rand * 10000).to_i)
  @font : Font? = nil
  @flash = 0_f32
  @snd_hit : Sound? = nil
  @snd_pick : Sound? = nil

  def load
    ttf = ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"].find { |p| File.exists?(p) }
    @font = Font.load(ttf, 18) if ttf && !ttf.ends_with?(".ttc")
    @snd_hit = Sound.tone(150, 0.08, Sound::Wave::Saw, 0.25)
    @snd_pick = Sound.tone(900, 0.06, Sound::Wave::Sine, 0.25)
    Input.map "left", Key::Left, Key::A, Key::H, Input.axis(GamepadAxis::LeftX, -1)
    Input.map "right", Key::Right, Key::D, Key::L, Input.axis(GamepadAxis::LeftX, 1)
    Input.map "up", Key::Up, Key::W, Key::K, Input.axis(GamepadAxis::LeftY, -1)
    Input.map "down", Key::Down, Key::S, Key::J, Input.axis(GamepadAxis::LeftY, 1)
    Input.map "wait", Key::Space, Key::Period, GamepadButton::B
    Input.map "descend", Key::Period, Key::Enter, GamepadButton::A
  end

  def update(dt : Float32)
    @flash = Math.max(0_f32, @flash - dt)
    before = @game.messages.size
    moved = false
    moved = @game.move_player(-1, 0) if Input.pressed?("left")
    moved = @game.move_player(1, 0) if Input.pressed?("right")
    moved = @game.move_player(0, -1) if Input.pressed?("up")
    moved = @game.move_player(0, 1) if Input.pressed?("down")
    @game.wait_turn if Input.pressed?("wait") && !@game.game_over?
    if Input.pressed?("descend") && Input.shift? || Input.pressed?(Key::Enter)
      @game.descend
    end
    if @game.messages.size > before
      msg = @game.messages.last
      if msg.includes?("hits you")
        @flash = 0.2_f32; @snd_hit.try(&.play)
      elsif msg.includes?("pick up") || msg.includes?("found") || msg.includes?("potion")
        @snd_pick.try(&.play)
      end
    end
    @game = Rogue::Game.new((Random.rand * 10000).to_i) if Input.pressed?(Key::R)
    Eagle.quit if Input.pressed?(Key::Escape)
  end

  def draw(g : Graphics)
    d = @game.dungeon
    ox = 10; oy = 40
    f = @font || g.font
    d.height.times do |y|
      d.width.times do |x|
        next unless d.explored?(x, y)
        vis = d.visible?(x, y)
        t = d[x, y]
        color = case t
                in Rogue::Tile::Wall then Color.hex("#5b6b8a")
                in Rogue::Tile::Floor then Color.hex("#2e3448")
                in Rogue::Tile::Door then Color.hex("#a0703c")
                in Rogue::Tile::StairsDown then Color.hex("#e0c060")
                end
        color = color.darken(0.55) unless vis
        px = ox + x * CELL; py = oy + y * CELL
        case t
        in Rogue::Tile::Wall then g.rect(px, py, CELL, CELL, color: color)
        in Rogue::Tile::Floor then g.rect(px, py, CELL, CELL, color: color); g.rect(px + CELL / 2 - 1, py + CELL / 2 - 1, 2, 2, color: color.lighten(0.2))
        in Rogue::Tile::Door then g.rect(px, py, CELL, CELL, color: Color.hex("#2e3448")); g.rect(px + 4, py + 2, CELL - 8, CELL - 4, color: color)
        in Rogue::Tile::StairsDown then g.rect(px, py, CELL, CELL, color: Color.hex("#2e3448")); g.print(">", px + CELL / 2, py + 2, color, f, align: TextAlign::Center)
        end
      end
    end
    @game.items.each do |it|
      next unless d.visible?(it.x, it.y)
      c = it.kind.gold? ? Color::YELLOW : it.kind.potion? ? Color.hex("#ff6b9d") : Color.hex("#9ad0ff")
      g.print(it.glyph.to_s, ox + it.x * CELL + CELL / 2, oy + it.y * CELL + 2, c, f, align: TextAlign::Center)
    end
    @game.monsters.each do |m|
      next unless d.visible?(m.x, m.y)
      c = {'r' => Color.hex("#c9a27e"), 'g' => Color.hex("#7bd88f"), 'o' => Color.hex("#e07a5f"), 'T' => Color.hex("#c77dff")}[m.glyph]? || Color::WHITE
      g.print(m.glyph.to_s, ox + m.x * CELL + CELL / 2, oy + m.y * CELL + 2, c, f, align: TextAlign::Center)
      g.rect(ox + m.x * CELL + 2, oy + m.y * CELL + CELL - 3, (CELL - 4) * m.hp / m.max_hp, 2, color: Color::RED)
    end
    p = @game.player
    g.print("@", ox + p.x * CELL + CELL / 2, oy + p.y * CELL + 2, Color::WHITE, f, align: TextAlign::Center)
    # HUD
    g.rect(0, 0, Window.width, 32, color: Color.hex("#12141c"))
    g.print("HP #{p.hp}/#{p.max_hp}  ATK #{p.attack}  DEF #{p.defense}  Lv #{@game.char_level} (xp #{@game.xp})  Gold #{@game.gold}  Dungeon #{@game.level}/#{Rogue::Game::MAX_LEVEL}  Turn #{@game.turns}", 10, 8, Color::WHITE)
    g.rect(Window.width - 210, 8, 200, 16, color: Color.gray(0.2))
    g.rect(Window.width - 210, 8, 200 * p.hp / p.max_hp, 16, color: p.hp > p.max_hp / 3 ? Color::GREEN : Color::RED)
    # messages
    my = oy + d.height * CELL + 6
    @game.messages.last(5).each_with_index do |m, i|
      g.print(m, 10, my + i * 18, Color.gray(0.55 + i * 0.1))
    end
    g.print("arrows/WASD/hjkl move · space wait · Enter descend on > · R restart", Window.width - 10, Window.height - 20, Color.gray(0.4), align: TextAlign::Right)
    g.rect(0, 0, Window.width, Window.height, color: Color::RED.with_alpha(@flash * 1.5)) if @flash > 0
    if @game.game_over?
      g.rect(0, 0, Window.width, Window.height, color: Color.new(0, 0, 0, 0.6))
      g.print(@game.won? ? "YOU ESCAPED!" : "YOU DIED", Window.width / 2, Window.height / 2 - 30, @game.won? ? Color::YELLOW : Color::RED, scale: 2, align: TextAlign::Center)
      g.print("press R for a new dungeon", Window.width / 2, Window.height / 2 + 20, Color::WHITE, align: TextAlign::Center)
    end
  end
end

Eagle.run(RoguelikeApp, title: "Eagle Roguelike", width: 60 * RoguelikeApp::CELL + 20, height: 34 * RoguelikeApp::CELL + 160)
