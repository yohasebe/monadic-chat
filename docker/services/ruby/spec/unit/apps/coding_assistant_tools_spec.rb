require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../apps/coding_assistant/coding_assistant_tools"

RSpec.describe CodingAssistantTools do
  let(:app) { Class.new { include CodingAssistantTools }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:me) { Struct.new(:chat_id, :session).new(chat, { parameters: { 'app_name' => 'CodingAssistantOpenAI' } }) }

  around do |example|
    Dir.mktmpdir('coding-shared-') do |directory|
      @data_dir = File.realpath(directory)
      @state_dir = File.join(@data_dir, '..', File.basename(@data_dir) + '-state')
      example.run
    ensure
      FileUtils.rm_rf(@state_dir)
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data_dir)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state_dir)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
  end

  it "writes into the chat's work folder, reads it back by name, and lists it" do
    written = app.write_file_to_shared_folder(filepath: "output.txt", content: "new content", workbench: me)
    expect(written).to include(success: true, action: "created")
    expect(written[:saved_as]).to match(%r{\Aconversations/[^/]+/work/output\.txt\z})
    expect(app.read_file_from_shared_folder(filepath: "output.txt", workbench: me)[:content]).to eq("new content")
    expect(app.list_files_in_shared_folder(workbench: me)[:files].map { |file| file[:name] }).to eq(["output.txt"])
    expect(Dir.children(@data_dir)).to eq(["conversations"])
  end

  it "reads a file the user put in the shared folder" do
    File.write(File.join(@data_dir, 'test.txt'), 'test content')
    expect(app.read_file_from_shared_folder(filepath: File.join(@data_dir, "test.txt"), workbench: me)[:content]).to eq("test content")
    expect(app.read_file_from_shared_folder(filepath: "test.txt", workbench: me)[:content]).to eq("test content")
    expect(app.read_file_from_shared_folder(filepath: "nonexistent.txt", workbench: me)[:error]).to include("not found")
  end

  it "refuses a path out of the shared folder" do
    result = app.write_file_to_shared_folder(filepath: "../../../etc/passwd", content: "malicious", workbench: me)
    expect(result[:success]).to be(false)
    expect(Dir.children(@data_dir)).to eq(["conversations"]).or eq([])
  end
end

RSpec.describe CodingAssistantGrokTools do
  let(:test_class) do
    Class.new do
      include CodingAssistantGrokTools
      include Monadic::Agents::GrokCodeAgent
    end
  end

  let(:app) { test_class.new }

  describe "#grok_code_agent" do
    before do
      allow(app).to receive(:has_grok_code_access?).and_return(true)
      allow(app).to receive(:call_grok_code).and_return({
        success: true,
        code: "generated code",
        model: "grok-code-fast-1"
      })
    end

    it "calls Grok-Code agent with correct parameters" do
      result = app.grok_code_agent(
        task: "Write a function",
        context: "Web app",
        files: []
      )
      expect(result[:success]).to be true
      expect(result[:model]).to eq("grok-code-fast-1")
    end
  end
end