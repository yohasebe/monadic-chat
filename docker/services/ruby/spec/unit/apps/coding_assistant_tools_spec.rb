require "spec_helper"
require "tmpdir"
require_relative "../../../apps/coding_assistant/coding_assistant_tools"

RSpec.describe CodingAssistantTools do
  let(:app) { Class.new { include CodingAssistantTools }.new }

  around do |example|
    Dir.mktmpdir('coding-shared-') do |directory|
      @data_dir = File.realpath(directory)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data_dir)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
  end

  describe "#read_file_from_shared_folder" do
    before { File.write(File.join(@data_dir, 'test.txt'), 'test content') }

    it "reads file from shared folder" do
      result = app.read_file_from_shared_folder(filepath: "test.txt")
      expect(result[:content]).to eq("test content")
      expect(result[:filepath]).to eq("test.txt")
    end

    it "handles absolute paths" do
      result = app.read_file_from_shared_folder(filepath: File.join(@data_dir, "test.txt"))
      expect(result[:content]).to eq("test content")
    end

    it "returns error for non-existent files" do
      result = app.read_file_from_shared_folder(filepath: "nonexistent.txt")
      expect(result[:error]).to include("not found")
    end
  end

  describe "#write_file_to_shared_folder" do
    it "writes file to shared folder" do
      result = app.write_file_to_shared_folder(filepath: "output.txt", content: "new content")
      expect(result[:success]).to be true
      expect(result[:action]).to eq("created")
      expect(File.read(File.join(@data_dir, 'output.txt'))).to eq('new content')
    end

    it "supports append mode" do
      File.write(File.join(@data_dir, 'output.txt'), 'original')
      result = app.write_file_to_shared_folder(filepath: "output.txt", content: "appended", mode: "append")
      expect(result[:action]).to eq("appended")
      expect(File.read(File.join(@data_dir, 'output.txt'))).to eq('originalappended')
    end

    it "validates file paths" do
      result = app.write_file_to_shared_folder(filepath: "../../../etc/passwd", content: "malicious")
      expect(result[:error]).to include("invalid")
      expect(Dir.children(@data_dir)).to be_empty
    end
  end

  describe "#list_files_in_shared_folder" do
    before do
      File.write(File.join(@data_dir, 'file1.txt'), 'text')
      Dir.mkdir(File.join(@data_dir, 'dir1'))
      File.write(File.join(@data_dir, 'dir1/subfile.txt'), 'text')
    end

    it "lists files and directories" do
      result = app.list_files_in_shared_folder
      expect(result[:files]).to be_an(Array)
      expect(result[:directories]).to be_an(Array)
      expect(result[:total_files]).to eq(1)
      expect(result[:total_directories]).to eq(1)
    end

    it "handles subdirectories" do
      result = app.list_files_in_shared_folder(directory: "dir1")
      expect(result[:path]).to eq("/dir1")
      expect(result[:files].map { |file| file[:name] }).to eq(['subfile.txt'])
    end
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