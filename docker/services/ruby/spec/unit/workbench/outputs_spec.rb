# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/workbench/outputs"
require_relative "../../../lib/monadic/utils/system_prompt_injector"

# What a chat made, by turn, for whichever app the chat is in, and the
# prompt that names it.
RSpec.describe Monadic::Workbench::Outputs do
  around do |example|
    Dir.mktmpdir("workbench-outputs-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    Monadic::Workbench::Made.reset!
  end


  def new_chat(app = "Chat")
    chat = Monadic::Workspace::Ids.generate(:chat)
    folder = Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: app)
    [chat, folder[:relative_dir]]
  end

  def write(path, text = "x")
    FileUtils.mkdir_p(File.dirname(File.join(@data, path)))
    File.write(File.join(@data, path), text)
  end

  def session_for(chat, messages = [])
    { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: messages, parameters: { "app_name" => "Chat" } }
  end

  describe ".in_chat" do
    it "lists what each reply made, by its turn, the files of a folder made and only what is there" do
      chat, dir = new_chat
      write("#{dir}/artifacts/j_1/chart.png")
      write("#{dir}/artifacts/j_1/table.csv")
      write("#{dir}/workbench/draft.md")
      messages = [
        { "role" => "user", "text" => "a" },
        { "role" => "assistant", "workbench_made" => ["#{dir}/artifacts/j_1"] },
        { "role" => "user", "text" => "b" },
        { "role" => "assistant", "text" => "no files" },
        { "role" => "assistant", "workbench_made" => ["#{dir}/workbench/draft.md", "#{dir}/workbench/gone.md", "/etc/passwd"] }
      ]
      expect(described_class.in_chat(session_for(chat, messages))).to eq([
        { path: "#{dir}/artifacts/j_1/chart.png", turn: 1 },
        { path: "#{dir}/artifacts/j_1/table.csv", turn: 1 },
        { path: "#{dir}/workbench/draft.md", turn: 3 }
      ])
    end

    it "lists a folder with many files as the folder" do
      chat, dir = new_chat
      (described_class::FILES_PER_FOLDER + 1).times { |i| write("#{dir}/artifacts/j_1/site/f#{i}.html") }
      messages = [{ "role" => "assistant", "workbench_made" => ["#{dir}/artifacts/j_1"] }]
      expect(described_class.in_chat(session_for(chat, messages))).to eq([{ path: "#{dir}/artifacts/j_1", turn: 1 }])
    end
  end

  describe "the prompt" do
    it "names the files the chat made, the newest, with their turns" do
      files = (1..(Monadic::Utils::SystemPromptInjector::CHAT_OUTPUTS_LISTED + 2)).map { |i| { path: "c/f#{i}.png", turn: i } }
      text = Monadic::Utils::SystemPromptInjector.chat_outputs_prompt(files)
      expect(text).to include("- c/f32.png (turn 32)")
      expect(text).not_to include("c/f2.png")
      expect(text).to include("and 2 earlier files")
      expect(Monadic::Utils::SystemPromptInjector.chat_outputs_prompt([])).to be_nil
    end

    it "is added for a chat whose replies made files, and not otherwise" do
      chat, dir = new_chat
      write("#{dir}/workbench/draft.md")
      session = session_for(chat, [{ "role" => "assistant", "workbench_made" => ["#{dir}/workbench/draft.md"] }])
      names = Monadic::Utils::SystemPromptInjector.build_injections(session: session).map { |i| i[:name] }
      expect(names.last).to eq(:chat_outputs)
      expect(Monadic::Utils::SystemPromptInjector.build_injections(session: session_for(chat)).map { |i| i[:name] })
        .not_to include(:chat_outputs)
    end
  end
end
