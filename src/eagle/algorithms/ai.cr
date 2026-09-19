module Eagle
  # Stateless steering forces. Combine and clamp the returned accelerations before
  # integrating velocity; this keeps the helpers useful with any entity type.
  #
  # `seek` / `flee` / `arrive` are desired velocities. `separation`, `alignment` and
  # `cohesion` are the three flocking terms; `flock` mixes them with weights.
  #
  # ```
  # pos = v2(10, 10)
  # vel = v2(40, 0)
  # desired = Steering.seek(pos, v2(80, 20), 120)
  # accel = (desired - vel) + Steering.separation(pos, [v2(12, 10)], 20)
  # vel = (vel + accel * dt).limit(120)
  # ```
  module Steering
    def self.seek(position : Vec2, target : Vec2, max_speed : Number) : Vec2
      (target - position).normalized * max_speed
    end

    def self.flee(position : Vec2, threat : Vec2, max_speed : Number) : Vec2
      (position - threat).normalized * max_speed
    end

    def self.arrive(position : Vec2, target : Vec2, max_speed : Number, slow_radius : Number) : Vec2
      offset = target - position
      distance = offset.length
      return Vec2::ZERO if distance == 0
      speed = max_speed.to_f32 * Math.min(1_f32, distance / Math.max(slow_radius.to_f32, 1e-5_f32))
      offset * (speed / distance)
    end

    def self.separation(position : Vec2, neighbors : Enumerable(Vec2), radius : Number) : Vec2
      force = Vec2::ZERO
      radius_sq = radius * radius
      neighbors.each do |other|
        delta = position - other
        distance_sq = delta.length_squared
        force += delta.normalized / Math.max(distance_sq, 1e-4_f32) if distance_sq > 0 && distance_sq < radius_sq
      end
      force
    end

    def self.alignment(velocity : Vec2, neighbor_velocities : Enumerable(Vec2)) : Vec2
      values = neighbor_velocities.to_a
      values.empty? ? Vec2::ZERO : values.sum(Vec2::ZERO) / values.size - velocity
    end

    def self.cohesion(position : Vec2, neighbors : Enumerable(Vec2)) : Vec2
      values = neighbors.to_a
      values.empty? ? Vec2::ZERO : values.sum(Vec2::ZERO) / values.size - position
    end

    def self.flock(position : Vec2, velocity : Vec2, neighbor_positions : Enumerable(Vec2),
                   neighbor_velocities : Enumerable(Vec2), radius : Number,
                   separation_weight = 1.5, alignment_weight = 1.0, cohesion_weight = 1.0) : Vec2
      separation(position, neighbor_positions, radius) * separation_weight +
        alignment(velocity, neighbor_velocities) * alignment_weight +
        cohesion(position, neighbor_positions) * cohesion_weight
    end
  end

  # A small state machine whose callbacks receive the owning context object.
  #
  # Register `on_enter`, `on_update` and `on_exit` for each state, call `start` once,
  # then `update` every frame. `transition` runs the exit and enter callbacks.
  #
  # ```
  # log = [] of String
  # machine = StateMachine(Array(String), Symbol).new(:idle)
  # machine.on_enter(:run) { |ctx| ctx << "go" }
  # machine.on_update(:run) { |ctx, _dt| ctx << "tick" }
  # machine.transition(:run, log)
  # machine.update(log, 0.016)
  # ```
  class StateMachine(Context, State)
    getter state : State

    def initialize(@state : State)
      @enter = {} of State => Proc(Context, Nil)
      @update = {} of State => Proc(Context, Float32, Nil)
      @exit = {} of State => Proc(Context, Nil)
    end

    def on_enter(state : State, &block : Context ->) : self
      @enter[state] = block; self
    end

    def on_update(state : State, &block : Context, Float32 ->) : self
      @update[state] = block; self
    end

    def on_exit(state : State, &block : Context ->) : self
      @exit[state] = block; self
    end

    def start(context : Context) : Nil
      @enter[@state]?.try(&.call(context))
    end

    def update(context : Context, dt : Number) : Nil
      @update[@state]?.try(&.call(context, dt.to_f32))
    end

    def transition(to : State, context : Context) : Nil
      return if to == @state
      @exit[@state]?.try(&.call(context))
      @state = to
      @enter[@state]?.try(&.call(context))
    end
  end

  enum BehaviorStatus
    # The node finished and succeeded.
    Success
    # The node finished and failed.
    Failure
    # The node is still working and should be ticked again next frame.
    Running
  end

  # One node of a behavior tree. `tick` the root each frame with the agent's context.
  abstract class Behavior(Context)
    abstract def tick(context : Context) : BehaviorStatus

    # Clears per-node progress so the tree can run again from the start.
    def reset : Nil; end
  end

  # Leaf that runs a callback and returns its status.
  class BehaviorAction(Context) < Behavior(Context)
    def initialize(&@action : Context -> BehaviorStatus); end

    def tick(context : Context) : BehaviorStatus
      @action.call(context)
    end
  end

  # Leaf that succeeds when the predicate is true and fails otherwise.
  class BehaviorCondition(Context) < Behavior(Context)
    def initialize(&@condition : Context -> Bool); end

    def tick(context : Context) : BehaviorStatus
      @condition.call(context) ? BehaviorStatus::Success : BehaviorStatus::Failure
    end
  end

  # Runs children in order until one fails. Succeeds when every child succeeds.
  class BehaviorSequence(Context) < Behavior(Context)
    def initialize(@children : Array(Behavior(Context)))
      @index = 0
    end

    def tick(context : Context) : BehaviorStatus
      while @index < @children.size
        case status = @children[@index].tick(context)
        when .success? then @index += 1
        when .failure? then reset; return status
        when .running? then return status
        end
      end
      reset
      BehaviorStatus::Success
    end

    def reset : Nil
      @index = 0
      @children.each(&.reset)
    end
  end

  # Tries children in order until one succeeds. Fails when every child fails.
  class BehaviorSelector(Context) < Behavior(Context)
    def initialize(@children : Array(Behavior(Context)))
      @index = 0
    end

    def tick(context : Context) : BehaviorStatus
      while @index < @children.size
        case status = @children[@index].tick(context)
        when .failure? then @index += 1
        when .success? then reset; return status
        when .running? then return status
        end
      end
      reset
      BehaviorStatus::Failure
    end

    def reset : Nil
      @index = 0
      @children.each(&.reset)
    end
  end

  # Swaps success and failure from a child. `Running` is passed through.
  class BehaviorInverter(Context) < Behavior(Context)
    def initialize(@child : Behavior(Context)); end

    def tick(context : Context) : BehaviorStatus
      case status = @child.tick(context)
      when .success? then BehaviorStatus::Failure
      when .failure? then BehaviorStatus::Success
      else                status
      end
    end

    def reset : Nil
      @child.reset
    end
  end

  # Two-player adversarial search with alpha-beta pruning. Pass functions that
  # list moves, apply a move (returning a new state) and score a state. The engine
  # never mutates your objects, so immutable or cloned states both work.
  #
  # ```
  # moves = ->(n : Int32) { n >= 3 ? [] of Int32 : [1, 2] }
  # apply = ->(n : Int32, m : Int32) { n + m }
  # evaluate = ->(n : Int32) { n.to_f64 }
  # result = Minimax.search(0, 2, true, moves, apply, evaluate)
  # result.move # => 2
  # ```
  module Minimax
    # Best move found for the side to play, its score, and how many nodes were visited.
    record Result(M), move : M?, score : Float64, visited : Int32

    # Generic minimax with alpha-beta pruning. State transitions return new values, so
    # callers remain in control of cloning or using immutable game states.
    def self.search(state : S, depth : Int, maximizing : Bool,
                    moves : Proc(S, Array(M)), apply : Proc(S, M, S), evaluate : Proc(S, Float64)) : Result(M) forall S, M
      terminal = ->(_state : S) { false }
      search(state, depth, maximizing, moves, apply, evaluate, terminal)
    end

    def self.search(state : S, depth : Int, maximizing : Bool,
                    moves : Proc(S, Array(M)), apply : Proc(S, M, S), evaluate : Proc(S, Float64),
                    terminal : Proc(S, Bool)) : Result(M) forall S, M
      visited = Pointer(Int32).malloc(1, 0)
      score, move = visit(state, depth.to_i32, maximizing, -Float64::INFINITY, Float64::INFINITY,
        moves, apply, evaluate, terminal, visited)
      Result(M).new(move, score, visited.value)
    end

    private def self.visit(state : S, depth : Int32, maximizing : Bool, alpha : Float64, beta : Float64,
                           moves : Proc(S, Array(M)), apply : Proc(S, M, S), evaluate : Proc(S, Float64),
                           terminal : Proc(S, Bool), visited : Pointer(Int32)) : {Float64, M?} forall S, M
      visited.value += 1
      choices = moves.call(state)
      return {evaluate.call(state), nil} if depth <= 0 || choices.empty? || terminal.call(state)
      best_move = nil.as(M?)
      a = alpha
      b = beta
      best = maximizing ? -Float64::INFINITY : Float64::INFINITY
      choices.each do |move|
        score, _ = visit(apply.call(state, move), depth - 1, !maximizing, a, b, moves, apply, evaluate, terminal, visited)
        if maximizing ? score > best : score < best
          best = score
          best_move = move
        end
        if maximizing
          a = Math.max(a, best)
        else
          b = Math.min(b, best)
        end
        break if b <= a
      end
      {best, best_move}
    end
  end
end
