require "spec_helper"
require_relative "../../../apps/coding_assistant/coding_assistant_tools"

RSpec.describe CodingAssistantTools do
  let(:test_class) do
    Class.new do
      include CodingAssistantTools

      # Mock the Environment module
      def self.data_path
        "/test/data"
      end
    end
  end

  let(:app) { test_class.new }

  describe "#read_file_from_shared_folder" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:file?).and_return(true)
      allow(File).to receive(:read).and_return("test content")
      allow(File).to receive(:size).and_return(100)
      allow(File).to receive(:mtime).and_return(Time.now)
      allow(app).to receive(:validate_file_path).and_return(true)
    end

    it "reads file from shared folder" do
      result = app.read_file_from_shared_folder(filepath: "test.txt")
      expect(result[:content]).to eq("test content")
      expect(result[:filepath]).to eq("test.txt")
    end

    it "handles absolute paths" do
      result = app.read_file_from_shared_folder(filepath: "/test/data/test.txt")
      expect(result[:content]).to eq("test content")
    end

    it "returns error for non-existent files" do
      allow(File).to receive(:exist?).and_return(false)
      result = app.read_file_from_shared_folder(filepath: "nonexistent.txt")
      expect(result[:error]).to include("not found")
    end
  end

  describe "#write_file_to_shared_folder" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:directory?).and_return(true)
      allow(File).to receive(:exist?).and_return(false, true) # doesn't exist, then exists after write
      allow(File).to receive(:size).and_return(100)
      allow(File).to receive(:open)
      allow(app).to receive(:validate_file_path).and_return(true)
    end

    it "writes file to shared folder" do
      result = app.write_file_to_shared_folder(
        filepath: "output.txt",
        content: "new content"
      )
      expect(result[:success]).to be true
      expect(result[:action]).to eq("created")
    end

    it "supports append mode" do
      allow(File).to receive(:exist?).and_return(true)
      result = app.write_file_to_shared_folder(
        filepath: "output.txt",
        content: "appended",
        mode: "append"
      )
      expect(result[:action]).to eq("appended")
    end

    it "validates file paths" do
      allow(app).to receive(:validate_file_path).and_return(false)
      result = app.write_file_to_shared_folder(
        filepath: "../../../etc/passwd",
        content: "malicious"
      )
      expect(result[:error]).to include("invalid")
    end
  end

  describe "#list_files_in_shared_folder" do
    before do
      allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
      allow(Dir).to receive(:entries).and_return([".", "..", "file1.txt", "dir1"])
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:directory?).with("/test/data").and_return(true)
      allow(File).to receive(:directory?).with("/test/data/dir1").and_return(true)
      allow(File).to receive(:directory?).with("/test/data/file1.txt").and_return(false)
      allow(File).to receive(:size).and_return(100)
      allow(File).to receive(:mtime).and_return(Time.now)
      allow(Dir).to receive(:entries).with("/test/data/dir1").and_return([".", "..", "subfile.txt"])
      allow(app).to receive(:validate_file_path).and_return(true)
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