# Compile-time helper: invoked through `{{ run(...) }}` by `Eagle.embed_assets`.
# Prints Crystal code registering every file under DIR as an embedded asset.
require "base64"

dir = ARGV[0]? || "assets"
root = File.expand_path(dir)
unless Dir.exists?(root)
  puts "# embed_assets: directory #{root} not found"
  exit
end
files = Dir.glob(File.join(root, "**", "*")).select { |f| File.file?(f) }.sort
files.each do |f|
  rel = Path[f].relative_to(root).to_s
  data = File.read(f).to_slice
  puts "::Eagle::Assets.register_embedded(#{rel.inspect}, #{Base64.strict_encode(data).inspect})"
end
puts "# embedded #{files.size} files from #{root}"
