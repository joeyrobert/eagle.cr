module Eagle
  # A typed event that other code can subscribe to. This is Eagle's version of a Godot signal.
  #
  # You normally create emitters with the `signal` macro, which adds three methods to your class:
  # `name` returns the `Emitter`, `on_name { ... }` connects a handler and `emit_name(...)` fires it.
  # Handlers receive the declared arguments with their types checked at compile time.
  #
  # Signals keep nodes decoupled. A player can announce that it died without knowing
  # about the HUD, the score or the sound system.
  #
  # ```
  # class Player < Node2D
  #   signal hit(damage : Int32)
  #   signal died
  #
  #   @hp = 3
  #
  #   def damage(amount : Int32) : Nil
  #     @hp -= amount
  #     emit_hit(amount)
  #     emit_died if @hp <= 0
  #   end
  # end
  #
  # player = Player.new
  # player.on_hit { |dmg| puts "ouch, #{dmg}" }
  # player.died.once { puts "game over" } # runs a single time
  # player.damage(3)
  # ```
  class Emitter(*T)
    @handlers = [] of Proc(*T, Nil)
    @once = [] of Proc(*T, Nil)

    # Adds a handler and returns it, so you can `disconnect` it later.
    def connect(&block : *T -> Nil) : Proc(*T, Nil)
      @handlers << block
      block
    end

    # Adds a handler that runs on the next emit only, then disconnects itself.
    def once(&block : *T -> Nil) : Proc(*T, Nil)
      @handlers << block
      @once << block
      block
    end

    # Removes a handler returned by `connect` or `once`.
    def disconnect(handler : Proc(*T, Nil)) : Nil
      @handlers.delete(handler)
      @once.delete(handler)
    end

    # Calls every connected handler with *args*. Handlers may connect or disconnect others while this runs.
    def emit(*args : *T) : Nil
      return if @handlers.empty?
      # Iterate a copy so handlers may connect/disconnect during emission.
      @handlers.dup.each do |h|
        h.call(*args)
        if @once.includes?(h)
          @once.delete(h)
          @handlers.delete(h)
        end
      end
    end

    # Removes every handler.
    def clear : Nil
      @handlers.clear
      @once.clear
    end

    # Number of connected handlers.
    def size : Int32; @handlers.size; end
    # True when at least one handler is connected.
    def connected? : Bool; !@handlers.empty?; end
    # True when no handlers are connected.
    def empty? : Bool; @handlers.empty?; end
  end
end

# Declares a signal on a class. See `Eagle::Emitter` for the full story.
#
# `signal hit(damage : Int32)` generates `hit` (the emitter), `on_hit { |damage| ... }`
# and `emit_hit(damage)`. Leave off the parentheses for a signal without arguments.
# It works in any class, not only nodes.
macro signal(decl)
  {% if decl.is_a?(Call) %}
    {% name = decl.name %}
    {% types = decl.args.map(&.type) %}
    @_sig_{{name}} : ::Eagle::Emitter({{types.splat}})? = nil
    def {{name}} : ::Eagle::Emitter({{types.splat}}); @_sig_{{name}} ||= ::Eagle::Emitter({{types.splat}}).new; end
    def emit_{{name}}(*args) : Nil; {{name}}.emit(*args); end
    def on_{{name}}(&block : {{types.splat}} -> Nil) : Proc({{ (types + [Nil]).join(", ").id }}); {{name}}.connect(&block); end
  {% else %}
    {% raise "signal expects `signal name` or `signal name(arg : Type, ...)`" %}
  {% end %}
end
