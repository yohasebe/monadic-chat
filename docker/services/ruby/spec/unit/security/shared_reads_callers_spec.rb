# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/adapters/selenium_helper"
require_relative "../../../apps/auto_forge/auto_forge_tools"
require_relative "../../../apps/auto_forge/auto_forge_utils"
require_relative "../../../lib/monadic/workspace"
require "digest"
require_relative "../../../lib/monadic/shared_tools/file_operations"

# The places that read a file of the shared folder for the server, by a name
# a container or a model gave, read nothing behind a link there: a link to the
# config env file sends no key on.
RSpec.describe "Reads from the shared folder" do
  around do |example|
    Dir.mktmpdir("shared-reads") do |dir|
      @root = File.join(dir, "data")
      @outside = File.join(dir, "outside")
      FileUtils.mkdir_p([@root, @outside])
      @secret = File.join(@outside, "env")
      File.write(@secret, "OPENAI_API_KEY=secret\n")
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@root)
  end

  describe "the page a web fetch saved" do
    let(:helper) { Class.new { include MonadicHelper }.new }

    def fetch_saving(name)
      allow(helper).to receive(:sleep)
      allow(helper).to receive(:send_command) do |**_, &block|
        block.call("saved to: /monadic/data/#{name}\n", "", instance_double(Process::Status, success?: true))
      end
      helper.selenium_fetch(url: "https://example.com/")
    end

    it "reads the page it saved" do
      File.write(File.join(@root, "page.md"), "# Page\n")
      expect(fetch_saving("page.md")).to eq("# Page\n")
    end

    it "reads nothing behind a link at the saved name" do
      File.symlink(@secret, File.join(@root, "page.md"))
      result = fetch_saving("page.md")
      expect(result).not_to include("secret")
      expect(result).to start_with("Error occurred")
    end
  end

  describe "AutoForge projects" do
    let(:project) { File.join(@root, "auto_forge", "Tool_20261022") }
    let(:tools) { Class.new { include AutoForgeTools }.new }

    before do
      FileUtils.mkdir_p(project)
      File.write(@secret, "#!/bin/sh\nOPENAI_API_KEY=secret\n")
      allow(AutoForge::Utils::PathConfig).to receive(:project_base_path).and_return(File.dirname(project))
    end

    it "reads a script it made, and none behind a link" do
      File.write(File.join(project, "tool.sh"), "#!/bin/sh\necho hi\n")
      expect(tools.send(:read_cli_script, project)).to eq([File.join(project, "tool.sh"), "#!/bin/sh\necho hi\n"])
      File.delete(File.join(project, "tool.sh"))
      File.symlink(@secret, File.join(project, "tool.sh"))
      expect(tools.send(:read_cli_script, project)).to eq([nil, nil])
    end

    it "takes no project details from behind a link" do
      File.write(@secret, '{"title":"secret"}')
      File.symlink(@secret, File.join(project, ".autoforge.json"))
      listed = AutoForgeUtils.list_projects.find { |p| p[:name] == "Tool_20261022" }
      expect(listed.to_s).not_to include("secret")
    end
  end

  describe "the digests a code run compares" do
    it "covers the plain files and reads nothing behind a link" do
      File.write(File.join(@root, "out.csv"), "a,b\n")
      File.symlink(@secret, File.join(@root, "linked.txt"))
      digests = MonadicApp.allocate.send(:shared_file_digests, @root)
      expect(digests.keys).to eq([File.join(@root, "out.csv")])
    end
  end

  describe "the images the generator scripts send" do
    let(:png) { "\x89PNG\r\n\x1A\n".b + "rest".b }

    before do
      File.binwrite(File.join(@root, "photo.png"), png)
      File.write(File.join(@root, "env.png"), "OPENAI_API_KEY=secret\n")
      File.symlink(@secret, File.join(@root, "linked.png"))
    end

    it "OpenAI: sends bytes with an image signature, typed by it, and no text" do
      script = GeneratorScriptLoader.load("image_generator_openai.rb")
      expect(script.read_local_image(File.join(@root, "photo.png"))).to eq(["image/png", png])
      expect { script.read_local_image(File.join(@root, "env.png")) }.to raise_error(ArgumentError)
      expect { script.read_local_image(File.join(@root, "linked.png")) }.to raise_error(StandardError)
    end

    it "Grok: sends bytes with an image signature, typed by it, and no text" do
      script = GeneratorScriptLoader.load("image_generator_grok.rb")
      expect(script.encode_image_as_data_uri(File.join(@root, "photo.png"))).to start_with("data:image/png;base64,")
      expect { script.encode_image_as_data_uri(File.join(@root, "env.png")) }.to raise_error(ArgumentError)
      expect { script.encode_image_as_data_uri(File.join(@root, "linked.png")) }.to raise_error(StandardError)
    end
  end

  describe "the check that an attachment is unchanged" do
    it "compares the file saved, and nothing behind a link" do
      record = { size: File.size(@secret), sha256: Digest::SHA256.file(@secret).hexdigest }
      saved = File.join(@root, "saved.txt")
      FileUtils.cp(@secret, saved)
      expect(Monadic::Workspace::Attachments.unchanged?(saved, record)).to be(true)
      File.delete(saved)
      File.symlink(@secret, saved)
      expect(Monadic::Workspace::Attachments.unchanged?(saved, record)).to be(false)
    end
  end

  describe "the shared folder listing" do
    it "lists a link as a link, without what is behind it" do
      FileUtils.mkdir_p(File.join(@root, "notes"))
      File.write(File.join(@root, "a.txt"), "a")
      File.symlink(@outside, File.join(@root, "elsewhere"))
      File.symlink(@secret, File.join(@root, "env-link"))
      lister = Class.new { include MonadicSharedTools::FileOperations }.new
      result = lister.list_files_in_shared_folder
      expect(result[:directories].map { |d| d[:name] }).to eq(["notes"])
      expect(result[:files]).to include({ name: "elsewhere", type: "link" }, { name: "env-link", type: "link" })
    end
  end
end
