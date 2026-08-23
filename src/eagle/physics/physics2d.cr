module Eagle
  module Physics2D
    class World
      def step(dt : Float32) : Nil; end
    end
    @@world = World.new
    def self.world : World; @@world; end
    def self.active? : Bool; false; end
  end
end
