# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../../lib/monadic/utils/shared_path_guard"
require_relative "../../../lib/monadic/shared_tools/app_creation"

# Writes the Ruby side makes into the shared folder, where code a model runs
# can put links and names: none may land in the folders whose code the
# server loads, and none may carry code into a file the user may later load.
RSpec.describe "Ruby-side writes into the shared folder" do
  let(:guard) { Monadic::Utils::SharedPathGuard }

  around do |example|
    Dir.mktmpdir("shared-writes-") do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "helpers"))
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
  end

  describe "SharedPathGuard.write_file!" do
    it "copies an upload as it streams" do
      io = StringIO.new("a" * 10_000)
      expect(IO).to receive(:copy_stream).with(io, anything).and_call_original # in pieces, not read whole
      guard.write_file!(File.join(@root, "upload.bin"), io, mode: "wb")
      expect(File.size(File.join(@root, "upload.bin"))).to eq(10_000)
    end

    it "does not write through a link a model left in the file's place" do
      File.symlink(File.join(@root, "helpers", "web.rb"), File.join(@root, "web_content.txt"))
      expect { guard.write_file!(File.join(@root, "web_content.txt"), "puts :ran") }
        .to raise_error(guard::InvalidPath)
      expect(File.exist?(File.join(@root, "helpers", "web.rb"))).to be(false)
    end
  end

  describe "a file the provider names (Claude's file download)" do
    it "keeps only the last part of the name" do
      skip "ClaudeHelper not loaded" unless defined?(ClaudeHelper)
      host = Class.new { include ClaudeHelper }.new
      stub_const("MonadicApp::LOCAL_SHARED_VOL", @root)
      host.send(:save_to_documents, "puts :ran", "../helpers/x.rb")
      expect(File.exist?(File.join(@root, "helpers", "x.rb"))).to be(false)
      expect(File.exist?(File.join(@root, "documents", "x.rb"))).to be(true)
    end
  end

  describe "an app template (AppCreation)" do
    let(:tool) { Class.new { include MonadicSharedTools::AppCreation }.new }

    before do
      stub_const("MonadicSharedTools::AppCreation::LOCAL_SHARED_VOL", @root) unless defined?(MonadicSharedTools::AppCreation::LOCAL_SHARED_VOL)
      stub_const("LOCAL_SHARED_VOL", @root)
    end

    it "refuses a name with a line break or a provider that is not a plain name" do
      expect(tool.create_simple_app_template(app_name: "x\n../../helpers/y", display_name: "X")[:success]).to be(false)
      expect(tool.create_simple_app_template(app_name: "my_app", display_name: "X", provider: "../helpers")[:success]).to be(false)
      expect(Dir.children(File.join(@root, "helpers"))).to be_empty
    end

    # Evaluate the file the way the DSL does, with a stand-in that only
    # records calls: text that ended a literal early would run here.
    it "writes the description and name so that loading the file runs none of them" do
      description = "TEXT\n$template_escaped = true\nen <<~'TEXT'\n\#{File.write('#{@root}/PWNED2', 'x')}\nrest"
      display_name = "A\" + `touch #{@root}/PWNED` + \""
      result = tool.create_simple_app_template(app_name: "my_app", display_name: display_name, description: description)
      expect(result[:success]).to be(true)

      calls = []
      recorder = Class.new(BasicObject) do
        define_method(:initialize) { |log| @log = log }
        define_method(:method_missing) do |name, *args, **_kw, &blk|
          @log << [name, args]
          instance_eval(&blk) if blk
          nil
        end
        define_method(:respond_to_missing?) { |*| true }
      end
      recorder.new(calls).instance_eval(File.read(result[:full_path]), result[:full_path])

      expect($template_escaped).to be_nil
      expect(Dir.children(@root)).not_to include("PWNED", "PWNED2")
      expect(calls).to include([:en, [description]])
      expect(calls).to include([:display_name, [display_name]])
    end
  end
end
