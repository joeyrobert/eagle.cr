module Eagle
  # Type-safe observer (a Godot-style signal). Declare with the `signal` macro:
  #
  #   class Player < Node2D
  #     signal hit(damage : Int32)
  #     signal died
  #   end
  #   player.on_hit { |dmg| ... }      # or player.hit.connect { ... }
  #   player.emit_hit(3)               # or player.hit.emit(3)
  class Emitter(*T)
    @handlers = [] of Proc(*T, Nil)
    @once = [] of Proc(*T, Nil)

    def connect(&block : *T -> Nil) : Proc(*T, Nil)
      @handlers << block
      block
    end

    # Handler runs a single time then disconnects itself.
    def once(&block : *T -> Nil) : Proc(*T, Nil)
      @handlers << block
      @once << block
      block
    end

    def disconnect(handler : Proc(*T, Nil)) : Nil
      @handlers.delete(handler)
      @once.delete(handler)
    end

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

    def clear : Nil
      @handlers.clear
      @once.clear
    end

    def size : Int32; @handlers.size; end
    def connected? : Bool; !@handlers.empty?; end
    def empty? : Bool; @handlers.empty?; end
  end
end

# Declares a signal on any class (see `Eagle::Emitter`). Defined at top level so
# it works inside every class, not just Eagle nodes.
macro signal(decl)
  {% if decl.is_a?(Call) %}
    {% name = decl.name %}
    {% types = decl.args.map(&.type) %}
    getter {{name}} : ::Eagle::Emitter({{types.splat}}) { ::Eagle::Emitter({{types.splat}}).new }
    def emit_{{name}}(*args) : Nil; {{name}}.emit(*args); end
    def on_{{name}}(&block : {{types.splat}} -> Nil) : Proc({{ (types + [Nil]).join(", ").id }}); {{name}}.connect(&block); end
  {% else %}
    {% raise "signal expects `signal name` or `signal name(arg : Type, ...)`" %}
  {% end %}
end
