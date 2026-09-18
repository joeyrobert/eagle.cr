module Eagle
  # Base class for errors raised by Eagle. Rescue it to catch any engine error.
  class Error < Exception; end
  # Raised when an asset can't be found or decoded: a missing file, a corrupt PNG or an unsupported format.
  class AssetError < Error; end
  # Raised when a shader fails to compile or link. The message includes the driver's error log.
  class ShaderError < Error; end
end
