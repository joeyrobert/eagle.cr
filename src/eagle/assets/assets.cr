require "base64"

module Eagle
  # Embed every file under `dir` (relative to the project root) into the
  # executable at compile time. Loading then works with no files on disk,
  # required for single-file exports and web builds.
  #
  #   Eagle.embed_assets("assets")
  #   Texture.load("res://player.png")   # served from memory
  macro embed_assets(dir = "assets")
    {{ run("./embed_list", dir) }}
  end

  # Asset loading and caching. Paths may be absolute, relative to the assets
  # root, or `res://`-prefixed. The root is found from (in order):
  # `EAGLE_ASSETS`, `Config#assets_dir`, an `assets/` folder next to the
  # executable, or `assets/` in the working directory, falling back to cwd.
  module Assets
    @@root : String? = nil
    @@textures = {} of String => Texture
    @@images = {} of String => Image
    @@shaders = {} of String => Shader
    @@sounds = {} of String => Sound
    @@fonts = {} of String => Font
    @@meshes = {} of String => Mesh
    @@search_paths = [] of String
    @@embedded = {} of String => String # path -> base64 (decoded lazily)
    @@embedded_bytes = {} of String => Bytes

    # :nodoc: called by generated code from `Eagle.embed_assets`
    def self.register_embedded(path : String, base64 : String) : Nil
      @@embedded[path] = base64
    end

    def self.embedded?(p : String) : Bool
      @@embedded.has_key?(p.lchop("res://"))
    end

    def self.embedded_paths : Array(String); @@embedded.keys; end

    private def self.embedded_bytes(p : String) : Bytes?
      key = p.lchop("res://")
      return nil unless (b64 = @@embedded[key]?)
      @@embedded_bytes[key] ||= Base64.decode(b64)
    end

    def self.root : String
      @@root ||= detect_root
    end

    def self.root=(path : String?)
      @@root = path
    end

    def self.add_search_path(path : String) : Nil
      @@search_paths << path
    end

    private def self.detect_root : String
      {% if flag?(:wasm32) %}
        return "/"
      {% end %}
      if env = ENV["EAGLE_ASSETS"]?
        return env
      end
      candidates = [] of String
      if pf = Eagle.platform?
        candidates << File.join(pf.base_path, "assets")
      end
      candidates << File.join(Dir.current, "assets")
      candidates << Dir.current
      candidates.each { |c| return c if Dir.exists?(c) }
      Dir.current
    end

    # Resolve a path to an absolute file path (does not check existence).
    def self.path(p : String) : String
      p = p.lchop("res://")
      return p if File.exists?(p) && (Path[p].absolute? || p.starts_with?('.'))
      return p if Path[p].absolute?
      full = File.join(root, p)
      return full if File.exists?(full)
      @@search_paths.each do |sp|
        cand = File.join(sp, p)
        return cand if File.exists?(cand)
      end
      return p if File.exists?(p)
      full
    end

    def self.exists?(p : String) : Bool
      return true if embedded?(p)
      {% if flag?(:wasm32) %}
        false
      {% else %}
        File.exists?(path(p))
      {% end %}
    end

    def self.read(p : String) : String
      String.new(read_bytes(p))
    end

    def self.read_bytes(p : String) : Bytes
      if b = embedded_bytes(p)
        return b
      end
      {% if flag?(:wasm32) %}
        raise AssetError.new("Asset not found: #{p} (web builds only see embedded assets; use Eagle.embed_assets)")
      {% else %}
        full = path(p)
        raise AssetError.new("Asset not found: #{p} (looked in #{full})") unless File.exists?(full)
        File.read(full).to_slice
      {% end %}
    end

    def self.image(p : String) : Image
      @@images[p] ||= Image.decode(read_bytes(p), p)
    end

    def self.texture(p : String, filter : GPU::Filter = Texture.default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false) : Texture
      key = "#{p}|#{filter}|#{wrap}|#{mipmaps}"
      @@textures[key] ||= Texture.new(Image.decode(read_bytes(p), p), filter, wrap, mipmaps, path: p)
    end

    def self.shader(p : String) : Shader
      @@shaders[p] ||= Shader.parse(read(p))
    end

    def self.sound(p : String) : Sound
      @@sounds[p] ||= Sound.decode(read_bytes(p), p)
    end

    def self.font(p : String, size : Number) : Font
      @@fonts["#{p}|#{size}"] ||= TrueTypeFont.new(read_bytes(p), size.to_f32)
    end

    def self.mesh(p : String) : Mesh
      @@meshes[p] ||= Mesh.decode(read(p), p)
    end

    # Forget cached assets (GPU objects are disposed).
    def self.clear : Nil
      @@textures.each_value(&.dispose)
      @@shaders.each_value(&.dispose)
      @@meshes.each_value(&.dispose)
      @@textures.clear; @@images.clear; @@shaders.clear; @@sounds.clear; @@fonts.clear; @@meshes.clear
      @@embedded_bytes.clear
      Texture.reset_shared
      Font.reset_shared
    end

    # Drop a single cached entry so the next load re-reads the file.
    def self.invalidate(p : String) : Nil
      @@images.delete(p); @@sounds.delete(p); @@meshes.delete(p)
      @@textures.reject! { |k, _| k.starts_with?("#{p}|") }
      @@shaders.delete(p)
      @@fonts.reject! { |k, _| k.starts_with?("#{p}|") }
    end
  end
end
