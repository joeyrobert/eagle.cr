# Roguelike core: procedural dungeon, shadowcasting FOV, turn-based combat.
# Independent of rendering so it can be unit tested.
module Rogue
  enum Tile : UInt8
    Wall
    Floor
    Door
    StairsDown
    def walkable? : Bool; !wall?; end
    def opaque? : Bool; wall? || door?; end
  end

  record Room, x : Int32, y : Int32, w : Int32, h : Int32 do
    def center : {Int32, Int32}; {x + w // 2, y + h // 2}; end
    def intersects?(o : Room, pad = 1) : Bool
      x - pad < o.x + o.w && x + w + pad > o.x && y - pad < o.y + o.h && y + h + pad > o.y
    end
  end

  class Entity
    property name : String
    property x : Int32
    property y : Int32
    property hp : Int32
    property max_hp : Int32
    property attack : Int32
    property defense : Int32
    property glyph : Char
    property? player : Bool
    property xp_value : Int32 = 0
    property sight : Int32 = 6

    def initialize(@name, @x, @y, @hp, @attack, @defense, @glyph, @player = false, @xp_value = 0)
      @max_hp = @hp
    end

    def alive? : Bool; @hp > 0; end
    def pos : {Int32, Int32}; {@x, @y}; end
  end

  class Item
    enum Kind
      Potion
      Gold
      Sword
      Shield
    end
    property kind : Kind
    property x : Int32
    property y : Int32
    property value : Int32
    def initialize(@kind, @x, @y, @value = 1); end
    def glyph : Char
      case @kind
      in Kind::Potion then '!'
      in Kind::Gold then '$'
      in Kind::Sword then '/'
      in Kind::Shield then ']'
      end
    end
  end

  class Dungeon
    getter width : Int32
    getter height : Int32
    getter tiles : Array(Tile)
    getter rooms = [] of Room
    getter explored : Array(Bool)
    getter visible : Array(Bool)
    getter rng : Random

    def initialize(@width, @height, seed : Int32 = 1, room_attempts = 40)
      @rng = Random.new(seed)
      @tiles = Array(Tile).new(@width * @height, Tile::Wall)
      @explored = Array(Bool).new(@width * @height, false)
      @visible = Array(Bool).new(@width * @height, false)
      generate(room_attempts)
    end

    def [](x : Int32, y : Int32) : Tile
      in_bounds?(x, y) ? @tiles[y * @width + x] : Tile::Wall
    end

    def []=(x : Int32, y : Int32, t : Tile); @tiles[y * @width + x] = t; end
    def in_bounds?(x, y) : Bool; x >= 0 && y >= 0 && x < @width && y < @height; end
    def walkable?(x, y) : Bool; self[x, y].walkable?; end
    def visible?(x, y) : Bool; in_bounds?(x, y) && @visible[y * @width + x]; end
    def explored?(x, y) : Bool; in_bounds?(x, y) && @explored[y * @width + x]; end

    private def generate(attempts)
      attempts.times do
        w = @rng.rand(4..10); h = @rng.rand(3..7)
        x = @rng.rand(1..(@width - w - 2)); y = @rng.rand(1..(@height - h - 2))
        room = Room.new(x, y, w, h)
        next if @rooms.any? { |r| r.intersects?(room) }
        carve(room)
        if last = @rooms.last?
          corridor(last.center, room.center)
        end
        @rooms << room
      end
      # doors where corridors meet room walls, stairs in the last room
      cx, cy = @rooms.last.center
      self[cx, cy] = Tile::StairsDown
      place_doors
    end

    private def carve(r : Room)
      (r.y...r.y + r.h).each { |yy| (r.x...r.x + r.w).each { |xx| self[xx, yy] = Tile::Floor } }
    end

    private def corridor(a, b)
      x, y = a
      tx, ty = b
      if @rng.rand < 0.5
        until x == tx; self[x, y] = Tile::Floor if self[x, y].wall?; x += x < tx ? 1 : -1; end
        until y == ty; self[x, y] = Tile::Floor if self[x, y].wall?; y += y < ty ? 1 : -1; end
      else
        until y == ty; self[x, y] = Tile::Floor if self[x, y].wall?; y += y < ty ? 1 : -1; end
        until x == tx; self[x, y] = Tile::Floor if self[x, y].wall?; x += x < tx ? 1 : -1; end
      end
      self[x, y] = Tile::Floor if self[x, y].wall?
    end

    private def place_doors
      @rooms.each do |r|
        # scan the room's outline for corridor openings
        (r.x - 1..r.x + r.w).each do |xx|
          [r.y - 1, r.y + r.h].each do |yy|
            self[xx, yy] = Tile::Door if self[xx, yy].floor? && corridor_cell?(xx, yy) && @rng.rand < 0.6
          end
        end
        (r.y - 1..r.y + r.h).each do |yy|
          [r.x - 1, r.x + r.w].each do |xx|
            self[xx, yy] = Tile::Door if self[xx, yy].floor? && corridor_cell?(xx, yy) && @rng.rand < 0.6
          end
        end
      end
    end

    private def corridor_cell?(x, y) : Bool
      h = self[x - 1, y].wall? && self[x + 1, y].wall?
      v = self[x, y - 1].wall? && self[x, y + 1].wall?
      h || v
    end

    # All walkable tiles reachable from (x, y) via 4-neighbour moves.
    def reachable_from(x, y) : Set({Int32, Int32})
      seen = Set({Int32, Int32}).new
      stack = [{x, y}]
      while p = stack.pop?
        next if seen.includes?(p)
        seen << p
        px, py = p
        [{1, 0}, {-1, 0}, {0, 1}, {0, -1}].each do |(dx, dy)|
          nx = px + dx; ny = py + dy
          stack << {nx, ny} if walkable?(nx, ny) && !seen.includes?({nx, ny})
        end
      end
      seen
    end

    def walkable_count : Int32; @tiles.count(&.walkable?); end

    # Symmetric shadowcasting FOV (recursive, 8 octants).
    def compute_fov(ox, oy, radius) : Nil
      @visible.fill(false)
      mark_visible(ox, oy)
      8.times { |oct| cast_light(ox, oy, radius, 1, 1.0, 0.0, oct) }
    end

    private def mark_visible(x, y)
      return unless in_bounds?(x, y)
      @visible[y * @width + x] = true
      @explored[y * @width + x] = true
    end

    MULT = [[1, 0, 0, -1, -1, 0, 0, 1], [0, 1, -1, 0, 0, -1, 1, 0], [0, 1, 1, 0, 0, -1, -1, 0], [1, 0, 0, 1, -1, 0, 0, -1]]

    private def cast_light(cx, cy, radius, row, start : Float64, finish : Float64, oct)
      return if start < finish
      xx = MULT[0][oct]; xy = MULT[1][oct]; yx = MULT[2][oct]; yy = MULT[3][oct]
      r2 = radius * radius
      (row..radius).each do |j|
        dx = -j - 1; dy = -j
        blocked = false
        new_start = start
        while dx <= 0
          dx += 1
          x = cx + dx * xx + dy * xy
          y = cy + dx * yx + dy * yy
          l_slope = (dx - 0.5) / (dy + 0.5)
          r_slope = (dx + 0.5) / (dy - 0.5)
          if start < r_slope
            next
          elsif finish > l_slope
            break
          end
          mark_visible(x, y) if dx * dx + dy * dy < r2
          if blocked
            if self[x, y].opaque?
              new_start = r_slope
              next
            else
              blocked = false
              start = new_start
            end
          elsif self[x, y].opaque? && j < radius
            blocked = true
            cast_light(cx, cy, radius, j + 1, start, l_slope, oct)
            new_start = r_slope
          end
        end
        break if blocked
      end
    end

    # Simple BFS path (4-neighbour) avoiding `blocked` cells; returns the next step or nil.
    def next_step(from : {Int32, Int32}, to : {Int32, Int32}, blocked : Set({Int32, Int32}) = Set({Int32, Int32}).new) : {Int32, Int32}?
      return nil if from == to
      prev = {} of {Int32, Int32} => {Int32, Int32}
      queue = Deque{from}
      seen = Set{from}
      found = false
      while (cur = queue.shift?)
        if cur == to
          found = true
          break
        end
        cx, cy = cur
        [{1, 0}, {-1, 0}, {0, 1}, {0, -1}].each do |(dx, dy)|
          n = {cx + dx, cy + dy}
          next if seen.includes?(n) || !walkable?(n[0], n[1]) || (blocked.includes?(n) && n != to)
          seen << n
          prev[n] = cur
          queue << n
        end
        break if seen.size > 4000
      end
      return nil unless found
      step = to
      while prev[step]? != from
        step = prev[step]? || return nil
      end
      step
    end
  end

  class Game
    getter dungeon : Dungeon
    getter player : Entity
    getter monsters = [] of Entity
    getter items = [] of Item
    getter messages = [] of String
    getter level = 1
    getter turns = 0
    getter gold = 0
    getter xp = 0
    getter char_level = 1
    getter? game_over = false
    getter? won = false
    getter rng : Random
    property seed : Int32

    MAX_LEVEL = 5

    def initialize(@seed : Int32 = 1, width = 60, height = 34)
      @rng = Random.new(@seed)
      @width = width; @height = height
      @dungeon = Dungeon.new(width, height, @seed)
      sx, sy = @dungeon.rooms.first.center
      @player = Entity.new("You", sx, sy, 20, 4, 1, '@', true)
      populate
      log("Welcome to the dungeon. Find the stairs (>) on level #{MAX_LEVEL}.")
      @dungeon.compute_fov(@player.x, @player.y, @player.sight)
    end

    def log(msg : String)
      @messages << msg
      @messages.shift if @messages.size > 50
    end

    private def populate
      @monsters.clear; @items.clear
      @dungeon.rooms.each_with_index do |room, i|
        next if i == 0
        count = @rng.rand(0..(1 + @level // 2))
        count.times do
          x = @rng.rand(room.x...room.x + room.w); y = @rng.rand(room.y...room.y + room.h)
          next if @monsters.any? { |m| m.x == x && m.y == y }
          kind = @rng.rand(0..2) + (@level >= 3 ? 1 : 0)
          m = case kind
              when 0 then Entity.new("rat", x, y, 4, 2, 0, 'r', xp_value: 3)
              when 1 then Entity.new("goblin", x, y, 7, 3, 1, 'g', xp_value: 6)
              when 2 then Entity.new("orc", x, y, 12, 5, 1, 'o', xp_value: 12)
              else Entity.new("troll", x, y, 20, 7, 2, 'T', xp_value: 25)
              end
          @monsters << m
        end
        if @rng.rand < 0.7
          x = @rng.rand(room.x...room.x + room.w); y = @rng.rand(room.y...room.y + room.h)
          r = @rng.rand
          @items << (r < 0.45 ? Item.new(Item::Kind::Gold, x, y, @rng.rand(5..25)) : r < 0.85 ? Item.new(Item::Kind::Potion, x, y, 8) : r < 0.93 ? Item.new(Item::Kind::Sword, x, y, 1) : Item.new(Item::Kind::Shield, x, y, 1))
        end
      end
    end

    def monster_at(x, y) : Entity?; @monsters.find { |m| m.alive? && m.x == x && m.y == y }; end
    def item_at(x, y) : Item?; @items.find { |i| i.x == x && i.y == y }; end

    # Player action: move/attack in a direction. Returns true if a turn passed.
    def move_player(dx : Int32, dy : Int32) : Bool
      return false if @game_over
      nx = @player.x + dx; ny = @player.y + dy
      if m = monster_at(nx, ny)
        attack(@player, m)
      elsif @dungeon.walkable?(nx, ny)
        @player.x = nx; @player.y = ny
        pick_up
      else
        return false
      end
      end_turn
      true
    end

    def wait_turn : Nil
      end_turn
    end

    def descend : Bool
      return false unless @dungeon[@player.x, @player.y].stairs_down?
      @level += 1
      if @level > MAX_LEVEL
        @won = true; @game_over = true
        log("You escape the dungeon with #{@gold} gold. You win!")
        return true
      end
      @dungeon = Dungeon.new(@width, @height, @seed * 31 + @level)
      sx, sy = @dungeon.rooms.first.center
      @player.x = sx; @player.y = sy
      populate
      log("You descend to level #{@level}.")
      @dungeon.compute_fov(@player.x, @player.y, @player.sight)
      true
    end

    private def pick_up
      if item = item_at(@player.x, @player.y)
        @items.delete(item)
        case item.kind
        in Item::Kind::Gold then @gold += item.value; log("You pick up #{item.value} gold.")
        in Item::Kind::Potion
          heal = Math.min(item.value, @player.max_hp - @player.hp)
          @player.hp += heal
          log("You drink a potion and heal #{heal}.")
        in Item::Kind::Sword then @player.attack += 2; log("You found a sword! Attack +2.")
        in Item::Kind::Shield then @player.defense += 1; log("You found a shield! Defense +1.")
        end
      end
    end

    def attack(a : Entity, d : Entity) : Nil
      dmg = Math.max(0, a.attack + @rng.rand(0..2) - d.defense)
      d.hp -= dmg
      if a.player?
        log(dmg > 0 ? "You hit the #{d.name} for #{dmg}." : "You miss the #{d.name}.")
        if !d.alive?
          log("The #{d.name} dies.")
          gain_xp(d.xp_value)
        end
      else
        log(dmg > 0 ? "The #{a.name} hits you for #{dmg}." : "The #{a.name} misses.")
        if !d.alive?
          @game_over = true
          log("You die on level #{@level} after #{@turns} turns.")
        end
      end
    end

    private def gain_xp(n)
      @xp += n
      while @xp >= @char_level * 10
        @xp -= @char_level * 10
        @char_level += 1
        @player.max_hp += 5; @player.hp = @player.max_hp; @player.attack += 1
        log("You reach level #{@char_level}!")
      end
    end

    private def end_turn
      @turns += 1
      @monsters.reject! { |m| !m.alive? }
      @dungeon.compute_fov(@player.x, @player.y, @player.sight)
      occupied = @monsters.map(&.pos).to_set
      @monsters.each do |m|
        next if @game_over
        dist = (m.x - @player.x).abs + (m.y - @player.y).abs
        if dist == 1
          attack(m, @player)
        elsif @dungeon.visible?(m.x, m.y) && dist <= 8
          occupied.delete(m.pos)
          if step = @dungeon.next_step(m.pos, @player.pos, occupied)
            if step != @player.pos
              m.x, m.y = step
            end
          end
          occupied << m.pos
        elsif @rng.rand < 0.3
          dx, dy = [{1, 0}, {-1, 0}, {0, 1}, {0, -1}][@rng.rand(4)]
          nx = m.x + dx; ny = m.y + dy
          if @dungeon.walkable?(nx, ny) && !occupied.includes?({nx, ny}) && {nx, ny} != @player.pos
            occupied.delete(m.pos); m.x = nx; m.y = ny; occupied << m.pos
          end
        end
      end
      # regenerate slowly
      @player.hp = Math.min(@player.max_hp, @player.hp + 1) if @turns % 10 == 0 && !@game_over
    end
  end
end
