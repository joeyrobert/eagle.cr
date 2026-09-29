require "../../src/eagle"

# Renderer-independent tilt maze rules: marble rolling, wall collision, holes and the goal.
# Specs drive this file without opening a window.
module EagleTiltMaze
  include Eagle

  BOARD_HALF  = 8_f32
  BALL_RADIUS = 0.42_f32
  HOLE_RADIUS = 0.58_f32
  START       = Vec2.new(-6.3, 6.1)
  TIME_LIMIT  = 50_f32

  enum State
    Playing
    Won
    Lost
  end

  # An axis-aligned wall on the board, as a center and half extents in board units (x, z).
  record Wall, center : Vec2, half : Vec2

  class Board
    getter walls = [] of Wall
    getter holes = [] of Vec2
    getter goal = Vec2.new(6.2, -6.0)
    getter marble = START
    getter velocity = Vec2::ZERO
    getter tilt = Vec2::ZERO
    getter time_left = TIME_LIMIT
    getter falls = 0
    getter state = State::Playing

    def initialize
      @walls << Wall.new(v2(0, -BOARD_HALF), v2(BOARD_HALF + 0.35, 0.28))
      @walls << Wall.new(v2(0, BOARD_HALF), v2(BOARD_HALF + 0.35, 0.28))
      @walls << Wall.new(v2(-BOARD_HALF, 0), v2(0.28, BOARD_HALF + 0.35))
      @walls << Wall.new(v2(BOARD_HALF, 0), v2(0.28, BOARD_HALF + 0.35))
      # A readable zig-zag route: each barrier leaves a generous gap on one side.
      @walls << Wall.new(v2(-2.2, 4.2), v2(4.6, 0.25))
      @walls << Wall.new(v2(3.0, 1.6), v2(4.7, 0.25))
      @walls << Wall.new(v2(-3.1, -1.2), v2(4.3, 0.25))
      @walls << Wall.new(v2(2.7, -4.0), v2(4.9, 0.25))
      @walls << Wall.new(v2(-5.4, -4.8), v2(0.25, 2.1))
      @walls << Wall.new(v2(4.9, 5.5), v2(0.25, 1.9))
      # Short gateposts make each open route obvious while leaving room to correct a rolling marble.
      @walls << Wall.new(v2(2.7, 3.15), v2(0.25, 0.8))
      @walls << Wall.new(v2(-2.2, 2.65), v2(0.25, 0.8))
      @walls << Wall.new(v2(1.25, -2.55), v2(0.25, 0.8))
      @holes = [v2(-4.7, 5.6), v2(1.9, 5.2), v2(-1.5, 2.7), v2(4.7, 0.1), v2(-4.9, 0.2), v2(0.8, -2.6), v2(-2.8, -5.8), v2(4.3, -5.6)]
    end

    # The board rotation for the current tilt: pushing a direction lowers that side.
    def rotation : Quat
      Quat.from_euler(@tilt.y * 0.15, 0, -@tilt.x * 0.15)
    end

    # Advances the marble by *dt* with *input* (x right, y down the screen, i.e. toward the camera).
    # Returns true when the marble fell into a hole this step.
    def step(input : Vec2, dt : Float32) : Bool
      return false unless @state.playing?
      @tilt = Mathf.damp(@tilt, input, 9, dt)
      @velocity += @tilt * (17 * dt)
      @velocity *= 1 / (1 + 2.4 * dt)
      @velocity = @velocity.normalized * 10 if @velocity.length > 10
      @marble = resolve_walls(@marble + @velocity * dt)
      @time_left -= dt
      fell = @holes.any? { |hole| @marble.distance(hole) < HOLE_RADIUS * 0.72 }
      if fell
        @falls += 1
        @marble = START
        @velocity = Vec2::ZERO
      end
      if @marble.distance(@goal) < 0.7
        @state = State::Won
      elsif @time_left <= 0
        @state = State::Lost
      end
      fell
    end

    # Test hook to place the marble.
    def place(@marble : Vec2, @velocity : Vec2 = Vec2::ZERO) : Nil
    end

    private def resolve_walls(pos : Vec2) : Vec2
      @walls.each do |wall|
        closest = pos.clamp(wall.center - wall.half, wall.center + wall.half)
        delta = pos - closest
        next unless delta.length < BALL_RADIUS
        normal = delta.length > 0.001 ? delta.normalized : v2(0, 1)
        pos += normal * (BALL_RADIUS - delta.length)
        into_wall = @velocity.dot(normal)
        @velocity -= normal * into_wall * 1.5 if into_wall < 0
      end
      pos
    end
  end
end
