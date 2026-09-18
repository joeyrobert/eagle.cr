require "../spec_helper"
require "file_utils"
require "../../src/cli/init"

private alias Init = Eagle::CLI::Init
private alias InitOptions = Eagle::CLI::InitOptions
private alias InitError = Eagle::CLI::InitError

private ROOT = File.expand_path("../..", __DIR__)

private def with_tmpdir(&)
  dir = File.tempname("eagle_init_spec")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

private def answers(*lines : String) : IO::Memory
  IO::Memory.new(lines.join("\n") + "\n")
end

describe Eagle::CLI::Init do
  describe "parse" do
    it "reads every flag" do
      o = Init.parse(["mygame", "--template", "3d", "--size", "1280x720", "--pixel-art", "--no-web", "--no-git", "--ci", "--local", "/tmp/eagle", "--yes"])
      o.name.should eq "mygame"
      o.template.should eq "3d-game"
      {o.width, o.height}.should eq({1280, 720})
      o.pixel_art.should be_true
      o.web.should be_false
      o.git.should be_false
      o.ci.should be_true
      o.local.should eq "/tmp/eagle"
      o.yes?.should be_true
    end

    it "leaves unspecified choices undecided until defaults are resolved" do
      o = Init.parse(["game"])
      o.template.should be_nil
      o.pixel_art.should be_nil
      o.resolve_defaults
      o.template.should eq "2d-game"
      {o.width, o.height}.should eq({960, 540})
      o.pixel_art?.should be_false
      o.web?.should be_true
      o.git?.should be_true
      o.ci?.should be_true
    end

    it "skips CI by default for a local path dependency" do
      Init.parse(["game", "--local", "."]).resolve_defaults.ci?.should be_false
    end

    it "accepts short template names and short flags" do
      Init.parse(["g", "-t", "ui"]).template.should eq "ui-app"
      Init.parse(["g", "-t", "empty", "-s", "320x240", "-y"]).width.should eq 320
    end

    it "uses the current folder for ." do
      o = Init.parse(["."])
      o.dir.should eq "."
      o.name.should eq File.basename(Dir.current)
    end

    it "rejects bad input" do
      expect_raises(InitError, /unknown template/) { Init.parse(["g", "-t", "4d"]) }
      expect_raises(InitError, /960x540/) { Init.parse(["g", "--size", "big"]) }
      expect_raises(InitError, /out of range/) { Init.parse(["g", "--size", "10x10"]) }
      expect_raises(InitError, /unknown option/) { Init.parse(["g", "--bogus"]) }
      expect_raises(InitError, /unexpected arguments/) { Init.parse(["a", "b"]) }
      expect_raises(InitError) { Init.parse(["g", "--template"]) }
    end

    it "has help text listing the flags" do
      Init.parse(["-h"]).help?.should be_true
      Init.help.should contain "--template"
      Init.help.should contain "--local PATH"
    end
  end

  describe "names" do
    it "derives shard, file, module and title names" do
      o = InitOptions.new.tap(&.name = "Space-Dodger_2")
      o.shard_name.should eq "space-dodger_2"
      o.file_name.should eq "space_dodger_2"
      o.module_name.should eq "SpaceDodger2"
      o.title.should eq "Space Dodger 2"
    end

    it "validates names" do
      InitOptions.validate_name("my-game").should eq "my-game"
      expect_raises(InitError) { InitOptions.validate_name("2fast") }
      expect_raises(InitError) { InitOptions.validate_name("my game") }
      expect_raises(InitError) { InitOptions.validate_name("") }
    end
  end

  describe "prompt" do
    it "asks for each undecided choice and takes defaults on empty answers" do
      io = IO::Memory.new
      o = Init.prompt(InitOptions.new, answers("space", "3", "", "y", "n", "", ""), io)
      o.name.should eq "space"
      o.template.should eq "ui-app"
      {o.width, o.height}.should eq({960, 540})
      o.pixel_art?.should be_true
      o.web?.should be_false
      o.git?.should be_true
      o.ci?.should be_true
      io.to_s.should contain "Project name [mygame]"
      io.to_s.should contain "3d-game"
    end

    it "only asks what the flags left open" do
      io = IO::Memory.new
      o = Init.prompt(Init.parse(["g", "-t", "2d", "--size", "640x480", "--no-git", "--no-ci"]), answers("", ""), io)
      o.pixel_art?.should be_false
      o.web?.should be_true
      io.to_s.should_not contain "Project name"
      io.to_s.should_not contain "Template"
      io.to_s.should_not contain "git"
    end

    it "re-asks after an invalid answer" do
      io = IO::Memory.new
      o = Init.prompt(InitOptions.new, answers("9lives", "cat", "4d", "3d", "abc", "800x600", "maybe", "n", "", "", ""), io)
      o.name.should eq "cat"
      o.template.should eq "3d-game"
      o.width.should eq 800
      o.pixel_art?.should be_false
      io.to_s.should contain "must start with a letter"
      io.to_s.should contain "unknown template"
      io.to_s.should contain "answer y or n"
    end

    it "takes the defaults when input ends early" do
      o = Init.prompt(InitOptions.new, IO::Memory.new("9lives\n"), IO::Memory.new)
      o.name.should eq "mygame"
      o.template.should eq "2d-game"
    end
  end

  describe "files" do
    it "generates the project layout" do
      files = Init.files(Init.parse(["my-game", "-y"]))
      files.keys.sort.should eq [".github/workflows/ci.yml", ".gitignore", "README.md", "assets/icon.png", "shard.yml",
                                 "spec/my_game_spec.cr", "spec/spec_helper.cr", "src/main.cr", "src/my_game.cr"]
      files["shard.yml"].as(String).should contain "github: joeyrobert/eagle.cr"
      files["shard.yml"].as(String).should contain "my-game:\n    main: src/main.cr"
      files["src/main.cr"].as(String).should contain %(Eagle.run(MyGame::Game, title: "My Game", width: 960, height: 540))
      files["src/main.cr"].as(String).should contain %(Eagle.embed_assets("assets"))
      files["src/main.cr"].as(String).should_not contain "Nearest"
      files["spec/spec_helper.cr"].as(String).should contain %(require "../src/my_game")
      files[".gitignore"].as(String).should contain "/lib/"
      files["README.md"].as(String).should contain "eagle export web"
      Image.decode(files["assets/icon.png"].as(Bytes)).width.should eq 64
    end

    it "follows the options" do
      files = Init.files(Init.parse(["g", "--local", "/src/eagle", "--no-web", "--pixel-art", "--size", "320x200"]))
      files.has_key?(".github/workflows/ci.yml").should be_false
      files["shard.yml"].as(String).should contain "path: '/src/eagle'"
      main = files["src/main.cr"].as(String)
      main.should_not contain "embed_assets"
      main.should contain "Texture.default_filter = GPU::Filter::Nearest"
      main.should contain "width: 320, height: 200"
    end

    it "quotes local dependency paths safely for YAML" do
      files = Init.files(Init.parse(["g", "--local", "/tmp/Eagle's builds: dev #1"]))
      files["shard.yml"].as(String).should contain "path: '/tmp/Eagle''s builds: dev #1'"
    end

    it "gives every template its own game code and spec" do
      InitOptions::TEMPLATES.keys.map { |t| Init.game_cr(Init.parse(["g", "-t", t]).resolve_defaults) }.uniq.size.should eq 4
      InitOptions::TEMPLATES.keys.map { |t| Init.spec_cr(Init.parse(["g", "-t", t]).resolve_defaults) }.uniq.size.should eq 4
    end
  end

  describe "generate" do
    it "writes the files and refuses to overwrite them" do
      with_tmpdir do |tmp|
        o = Init.parse(["demo", "-y"]).resolve_defaults
        o.dir = File.join(tmp, "demo")
        Init.generate(o).should eq o.dir
        File.read(File.join(tmp, "demo", "shard.yml")).should contain "name: demo"
        File.exists?(File.join(tmp, "demo", "assets", "icon.png")).should be_true
        expect_raises(InitError, /not overwriting/) { Init.generate(o) }
      end
    end

    it "initialises an existing folder that has no clashing files" do
      with_tmpdir do |tmp|
        File.write(File.join(tmp, "notes.txt"), "keep me")
        o = Init.parse(["here", "-y", "--no-ci"]).resolve_defaults
        o.dir = tmp
        Init.generate(o)
        File.read(File.join(tmp, "notes.txt")).should eq "keep me"
        File.exists?(File.join(tmp, "src", "main.cr")).should be_true
      end
    end

    it "produces projects that type-check against the engine, for every template" do
      InitOptions::TEMPLATES.keys.each do |t|
        with_tmpdir do |tmp|
          o = Init.parse(["proj", "-y", "-t", t, "--local", ROOT, t == "empty" ? "--pixel-art" : "--web"]).resolve_defaults
          o.dir = tmp
          Init.generate(o)
          Dir.mkdir_p(File.join(tmp, "lib"))
          File.symlink(ROOT, File.join(tmp, "lib", "eagle")) # what `shards install` does for a path dependency
          err = IO::Memory.new
          status = Process.run("crystal", ["build", "--no-codegen", "src/main.cr", "spec/proj_spec.cr"], chdir: tmp, error: err, output: err)
          fail "#{t} template does not compile:\n#{err}" unless status.success?
        end
      end
    end
  end
end
