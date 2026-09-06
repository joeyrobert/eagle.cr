# Snake game logic, independent of rendering.
class SnakeGame
  enum Dir
    Up; Down; Left; Right
    def vec : {Int32, Int32}
      case self
      in Up then {0, -1}
      in Down then {0, 1}
      in Left then {-1, 0}
      in Right then {1, 0}
      end
    end
    def opposite?(o : Dir) : Bool
      v = vec; w = o.vec
      v[0] == -w[0] && v[1] == -w[1]
    end
  end

  getter width : Int32
  getter height : Int32
  getter body : Array({Int32, Int32}) # head first
  getter dir : Dir = Dir::Right
  getter food : {Int32, Int32}
  getter score = 0
  getter? game_over = false
  @next_dir : Dir = Dir::Right
  @grow = 0
  @rng : Random

  def initialize(@width : Int32 = 20, @height : Int32 = 15, seed : Int32? = nil)
    @rng = seed ? Random.new(seed) : Random.new
    cx = @width // 2; cy = @height // 2
    @body = [{cx, cy}, {cx - 1, cy}, {cx - 2, cy}]
    @food = {0, 0}
    place_food
  end

  def head : {Int32, Int32}; @body.first; end

  # Queue a direction change (ignored if it reverses the snake).
  def turn(d : Dir) : Nil
    @next_dir = d unless d.opposite?(@dir)
  end

  def place_food : Nil
    free = [] of {Int32, Int32}
    @height.times { |y| @width.times { |x| free << {x, y} unless @body.includes?({x, y}) } }
    if free.empty?
      @game_over = true
    else
      @food = free[@rng.rand(free.size)]
    end
  end

  # Advance one cell. Returns :moved, :ate, or :died.
  def step : Symbol
    return :died if @game_over
    @dir = @next_dir
    dx, dy = @dir.vec
    nx = head[0] + dx; ny = head[1] + dy
    if nx < 0 || ny < 0 || nx >= @width || ny >= @height
      @game_over = true
      return :died
    end
    tail_moves = @grow == 0
    if @body.includes?({nx, ny}) && !(tail_moves && @body.last == {nx, ny})
      @game_over = true
      return :died
    end
    @body.unshift({nx, ny})
    if @grow > 0
      @grow -= 1
    else
      @body.pop
    end
    if {nx, ny} == @food
      @score += 1
      @grow += 2
      place_food
      return :ate
    end
    :moved
  end

  def length : Int32; @body.size; end
end
