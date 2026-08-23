module Eagle
  class Sound
    def self.decode(data : Bytes, hint : String = "") : Sound
      raise AssetError.new("Audio not implemented yet")
    end
  end

  module Audio
    def self.init(platform : Platform::Base) : Nil; end
    def self.update : Nil; end
    def self.shutdown : Nil; end
  end
end
