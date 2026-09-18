require "base64"

module Eagle
  # Bakes every file under *dir* into the executable at compile time, so the game runs with
  # no files beside it. Web builds need this, because the browser can't read your disk.
  # Put it at the top level of your main file:
  #
  # ```crystal
  # Eagle.embed_assets("assets")
  # Texture.load("res://player.png") # served from memory
  # ```
  #
  # Paths inside *dir* become `res://` paths.
  macro embed_assets(dir = "assets")
    {{ run("./embed_list", dir) }}
  end

  # Loads and caches game files: images, textures, sounds, fonts, shaders and meshes.
  #
  # Each loader caches by path, so asking for the same file twice returns the same object
  # and costs nothing. The `load` methods on `Texture`, `Sound`, `Font`, `Shader` and `Mesh`
  # all go through here.
  #
  # Paths can be absolute, relative to the assets folder, or prefixed with `res://`. The
  # assets folder is found in this order:
  #
  # 1. the `EAGLE_ASSETS` environment variable
  # 2. `Config#assets_dir`
  # 3. an `assets/` folder next to the executable
  # 4. an `assets/` folder in the working directory
  # 5. the working directory itself
  #
  # Files embedded with `Eagle.embed_assets` take priority over the disk.
  #
  # ```
  # tex = Assets.texture("res://sprites/hero.png")
  # level = Assets.read("res://levels/1.txt")
  # Assets.invalidate("res://levels/1.txt") # re-read on the next load, for hot reload
  # ```
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

    # True when *p* was embedded with `Eagle.embed_assets`.
    def self.embedded?(p : String) : Bool
      @@embedded.has_key?(p.lchop("res://"))
    end

    # Every embedded path.
    def self.embedded_paths : Array(String); @@embedded.keys; end

    private def self.embedded_bytes(p : String) : Bytes?
      key = p.lchop("res://")
      return nil unless (b64 = @@embedded[key]?)
      @@embedded_bytes[key] ||= Base64.decode(b64)
    end

    # The assets folder that relative and `res://` paths resolve against.
    def self.root : String
      @@root ||= detect_root
    end

    # Sets the assets folder. `nil` goes back to auto-detection.
    def self.root=(path : String?)
      @@root = path
    end

    # Adds another folder to search when a file isn't in the assets folder, such as a mod folder.
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

    # The file path *p* resolves to, without checking that it exists.
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

    # True when the asset exists, embedded or on disk.
    def self.exists?(p : String) : Bool
      return true if embedded?(p)
      {% if flag?(:wasm32) %}
        false
      {% else %}
        File.exists?(path(p))
      {% end %}
    end

    # Reads a text file.
    def self.read(p : String) : String
      String.new(read_bytes(p))
    end

    # Reads a binary file. Raises `AssetError` when it doesn't exist.
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

    # Loads and caches an `Image`.
    def self.image(p : String) : Image
      @@images[p] ||= Image.decode(read_bytes(p), p)
    end

    # Loads and caches a `Texture`. The cache key includes the path only, so the first load decides the filter.
    def self.texture(p : String, filter : GPU::Filter = Texture.default_filter, wrap : GPU::Wrap = GPU::Wrap::Clamp, mipmaps : Bool = false) : Texture
      key = "#{p}|#{filter}|#{wrap}|#{mipmaps}"
      @@textures[key] ||= Texture.new(Image.decode(read_bytes(p), p), filter, wrap, mipmaps, path: p)
    end

    # Loads and caches a `Shader`.
    def self.shader(p : String) : Shader
      @@shaders[p] ||= Shader.parse(read(p))
    end

    # Loads and caches a `Sound` (WAV or Ogg Vorbis).
    def self.sound(p : String) : Sound
      @@sounds[p] ||= Sound.decode(read_bytes(p), p)
    end

    # Loads and caches a TrueType `Font` at a pixel size.
    def self.font(p : String, size : Number) : Font
      @@fonts["#{p}|#{size}"] ||= TrueTypeFont.new(read_bytes(p), size.to_f32)
    end

    # Loads and caches a `Mesh` from an OBJ file.
    def self.mesh(p : String) : Mesh
      @@meshes[p] ||= Mesh.decode(read(p), p)
    end

    # Forgets every cached asset and frees GPU objects. Use it between levels that share nothing,
    # or before reloading everything.
    def self.clear : Nil
      @@textures.each_value(&.dispose)
      @@shaders.each_value(&.dispose)
      @@meshes.each_value(&.dispose)
      @@textures.clear; @@images.clear; @@shaders.clear; @@sounds.clear; @@fonts.clear; @@meshes.clear
      @@embedded_bytes.clear
      Texture.reset_shared
      Font.reset_shared
    end

    # Forgets one cached entry, so the next load reads the file again.
    def self.invalidate(p : String) : Nil
      @@images.delete(p); @@sounds.delete(p); @@meshes.delete(p)
      @@textures.reject! { |k, _| k.starts_with?("#{p}|") }
      @@shaders.delete(p)
      @@fonts.reject! { |k, _| k.starts_with?("#{p}|") }
    end
  end
end
