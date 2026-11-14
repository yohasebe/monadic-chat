# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "shellwords"
require_relative "../../../lib/monadic/adapters/media_generation_helper"

# In a chat, a video generator saves into a run folder of the chat's folder
# (--out-dir), and the video is shown on the work screen; without a chat, it
# saves at the top of the shared folder as before.
RSpec.describe "Videos kept in the chat's folder", :no_api do
  around do |example|
    Dir.mktmpdir("video-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:workbench) { Struct.new(:chat_id).new(Monadic::Workspace::Ids.generate(:chat)) }
  let(:commands) { [] }

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Utils::ProgressBroadcaster).to receive(:with_progress) { |**_, &block| block.call }
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
  end

  # The generator: it saves a video in the folder it is given (or reports
  # nothing saved) and prints its JSON.
  def generator(host, name, saves: true)
    allow(host).to receive(:send_command) do |command:, container:, &block|
      args = Shellwords.split(command)
      commands << args
      out = args.include?("--out-dir") ? args[args.index("--out-dir") + 1] : @data
      File.binwrite(File.join(out, name), "MP4") if saves
      json = saves ? { success: true, filename: name }.to_json : { success: false, message: "refused" }.to_json
      block ? block.call(json, "", double(success?: saves)) : json
    end
  end

  shared_examples "a video generator" do
    it "saves the video in a run folder of the chat's folder and shows it" do
      generator(host, "v.mp4")
      result = JSON.parse(call(workbench: workbench))
      expect(result["path"]).to match(%r{\Aconversations/[^/]+/artifacts/j_[a-z0-9]+/v\.mp4\z})
      expect(File.join(@data, result["path"])).to eq(File.join(commands.first[commands.first.index("--out-dir") + 1], "v.mp4"))
      expect(result["notice"]).to include(result["path"], "work screen")
      expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(result["path"], workbench)
      expect(Dir.children(@data)).to eq(["conversations"])
    end

    it "leaves no run folder when nothing was saved" do
      generator(host, "v.mp4", saves: false)
      call(workbench: workbench)
      expect(Dir.glob(File.join(@data, "conversations/*/artifacts/*"))).to be_empty
    end

    it "saves at the top of the shared folder without a chat" do
      generator(host, "v.mp4")
      result = JSON.parse(call)
      expect(result).not_to have_key("path")
      expect(commands.first).not_to include("--out-dir")
      expect(File.exist?(File.join(@data, "v.mp4"))).to be true
    end
  end

  describe "Gemini" do
    let(:host) { Class.new(MonadicApp) { include GeminiHelper }.new }

    def call(**opts)
      host.generate_video_with_gemini(prompt: "a boat", **opts)
    end

    it_behaves_like "a video generator"
  end

  describe "Grok" do
    let(:host) { Class.new { include MonadicHelper }.new }

    def call(**opts)
      host.generate_video_with_grok_imagine(prompt: "a boat", **opts)
    end

    it_behaves_like "a video generator"
  end

  it "makes the server's line for a video on the work screen, escaped" do
    expect(Monadic::Workbench::ChatOutput.chat_line("The video", "conversations/a<b>/v.mp4"))
      .to eq("<p>The video is on the work screen beside the chat: <code>conversations/a&lt;b&gt;/v.mp4</code></p>")
  end
end
