module Eagle
  class Mesh
    def self.decode(text : String, hint : String = "") : Mesh
      raise AssetError.new("Mesh loading not implemented yet")
    end
    def dispose : Nil; end
  end
end
