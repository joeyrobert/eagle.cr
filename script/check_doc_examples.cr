# Type-checks every Crystal example inside the doc comments under src/.
# Usage: crystal run script/check_doc_examples.cr [-- path-filter]
# Examples that define classes, modules or methods are wrapped in a module; the rest run inside a method
# that receives `g : Graphics` and `dt : Float32`, which is what draw and update callbacks get.
require "file_utils"

ROOT   = File.expand_path("..", __DIR__)
OUT    = File.join(ROOT, ".doccheck")
filter = ARGV[0]?

record Example, file : String, line : Int32, code : String

examples = [] of Example
Dir.glob(File.join(ROOT, "src/**/*.cr")).sort.each do |path|
  next if filter && !path.includes?(filter)
  lines = File.read_lines(path)
  i = 0
  while i < lines.size
    if lines[i] =~ /^\s*#\s?```(\w*)\s*$/
      lang = $1
      start = i + 1
      body = [] of String
      i += 1
      while i < lines.size && lines[i] !~ /^\s*#\s?```\s*$/
        body << lines[i].sub(/^\s*# ?/, "")
        i += 1
      end
      examples << Example.new(path.lchop(ROOT + "/"), start, body.join("\n")) if lang.empty? || lang == "crystal" || lang == "cr"
    end
    i += 1
  end
end


# Crystal only type-checks methods that are called, so call every method the example defines
# with placeholder arguments of the declared types.
def exercise(code : String) : String
  calls = [] of String
  klass = nil
  k = 0
  code.each_line do |line|
    if m = line.match(/^class (\w+)/)
      klass = m[1]
    elsif line =~ /^(struct|module|enum)\b/
      klass = nil
    elsif line.starts_with?("end")
      klass = nil
    elsif (m = line.match(/^(  )?def ([a-z_]\w*[?!=]?)(?:\((.*)\))?/)) && !line.includes?("&")
      nested = !m[1]?.nil?
      next if nested && klass.nil?
      next if !nested && line.starts_with?(" ")
      name = m[2]
      next if name == "initialize"
      params = (m[3]? || "").split(",").map(&.strip).reject(&.empty?)
      next unless params.all? { |a| a.includes?(" : ") }
      vars = params.map_with_index do |a, i|
        type = a.split(" : ", 2)[1].split(" = ")[0].strip
        k += 1
        calls << "  __v#{k} = uninitialized #{type}"
        "__v#{k}"
      end
      recv = nested ? "#{klass}.allocate" : "self"
      calls << "  #{recv}.#{name}(#{vars.join(", ")})"
    end
  end
  calls.empty? ? "" : "  if rand > 2\n#{calls.join("\n")}\n  end\n"
end

FileUtils.rm_rf(OUT)
Dir.mkdir_p(OUT)
examples.each_with_index do |ex, n|
  toplevel = ex.code.lines.any? { |l| l =~ /^(abstract |private )?(class|struct|module|def|enum|macro)\b/ }
  wrapped = if toplevel
              "module DocExample#{n}\n  extend self\n#{ex.code}\n#{exercise(ex.code)}end\n"
            else
              "def doc_example_#{n}(g : Graphics, dt : Float32)\n#{ex.code}\nend\n__g = uninitialized Graphics\ndoc_example_#{n}(__g, 0_f32)\n"
            end
  File.write(File.join(OUT, "ex#{n}.cr"), "require \"../src/eagle\"\ninclude Eagle\n#{wrapped}")
end

failures = Channel({Int32, String}).new
queue = Channel(Int32).new(examples.size)
examples.size.times { |n| queue.send(n) }
queue.close
8.times do
  spawn do
    while (n = queue.receive?)
      err = IO::Memory.new
      ok = Process.run("crystal", ["build", "--no-codegen", "--no-color", File.join(OUT, "ex#{n}.cr"), "-o", File::NULL], chdir: ROOT, error: err, output: err).success?
      failures.send({n, ok ? "" : err.to_s})
    end
  end
end

bad = 0
examples.size.times do
  n, err = failures.receive
  next if err.empty?
  bad += 1
  ex = examples[n]
  msg = err.lines.select { |l| l.starts_with?("Error") || l =~ /^\s*\d+ \|/ || l.includes?("ex#{n}.cr") }.first(6).join("\n")
  puts "#{ex.file}:#{ex.line}\n#{msg}\n"
end
FileUtils.rm_rf(OUT)
puts "#{examples.size - bad}/#{examples.size} doc examples type-check"
exit(bad == 0 ? 0 : 1)
