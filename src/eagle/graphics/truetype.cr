module Eagle
  class TrueTypeFont < Font
    def initialize(data : Bytes, size : Float32)
      raise AssetError.new("TrueType not implemented yet")
    end
    def glyph(char : Char) : Glyph?; nil; end
    def line_height : Float32; 0_f32; end
    def texture : Texture; Texture.white; end
  end
end
