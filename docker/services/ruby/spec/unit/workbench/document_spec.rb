# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/document"
require_relative "../../../lib/monadic/utils/websocket/message_editor"

# A long text written over turns as sections: each a file made by its
# reply, put together in one document, each section as written last, and
# made again when a turn is deleted.
RSpec.describe Monadic::Workbench::Document do
  around do |example|
    Dir.mktmpdir("workbench-document-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:store) { Monadic::Workbench::Store.new(File.join(@state, "workbench")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, _ws_generation: 1, messages: [],
      parameters: { "app_name" => "NovelWriterOpenAI" } }
  end
  let(:editor) { Class.new { include WebSocketHelper }.new }

  before do
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == "tab-1" ? 1 : nil }
    WebSocketHelper::Replies.reset!
    Monadic::Workbench::Shown.reset!
    Monadic::Workbench::Made.reset!
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  # One reply that writes sections ([section, text] pairs) of document,
  # then ends with its message. Returns the message.
  def reply(document, *writes)
    id = Monadic::Workspace::Ids.generate(:request)
    handle, = WebSocketHelper::Replies.open(request_id: id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    caller = Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: id,
                                            session: session, tab: "tab-1", generation: 1)
    @last = writes.map do |section, text|
      described_class.write(session: session, workbench: caller, app_name: "NovelWriterOpenAI",
                            document: document, section: section, content: text)
    end
    message = { "mid" => "m#{session[:messages].size}", "role" => "assistant",
                "workbench_made" => Monadic::Workbench::Made.seal(id),
                "workbench_shown" => Monadic::Workbench::Shown.seal(id) }
    session[:messages] << message
    message
  end

  def text(path)
    File.read(File.join(@data, path))
  end

  def bodies(path)
    text(path).scan(/^###### § (\S+)\n\n(.*?)\n/m)
  end

  it "puts the sections together in the order first written, under the title, with a mark between them" do
    reply("The Long Night", ["1", "It was dark."], ["2", "It grew darker."])
    path = @last.last[:path]
    expect(path).to match(%r{\Aconversations/[^/]+/documents/the-long-night\.md\z})
    expect(text(path)).to start_with("# The Long Night\n")
    expect(bodies(path)).to eq([["1", "It was dark."], ["2", "It grew darker."]])
    expect(text(path)).to include("\n---\n")
    expect(@last.map { |r| r[:shown] }).to all(be true)
  end

  it "shows each section as the newest turn wrote it, in its first place" do
    reply("Story", ["1", "First draft."], ["2", "Second part."])
    reply("Story", ["1", "Rewritten opening."])
    expect(bodies(@last.last[:path])).to eq([["1", "Rewritten opening."], ["2", "Second part."]])
  end

  it "shows the earlier version again when the turn that rewrote a section is deleted" do
    reply("Story", ["1", "First draft."])
    rewrite = reply("Story", ["1", "Rewritten opening."], ["2", "New part."])
    path = @last.last[:path]
    session[:messages].delete(rewrite)
    expect(editor.trash_made_files(session, rewrite)).not_to be_empty
    editor.rebuild_documents(session)
    expect(bodies(path)).to eq([["1", "First draft."]])
    expect(text(path)).to start_with("# Story\n")
  end

  it "removes a document whose every section was deleted, and takes it off the work screen" do
    only = reply("Draft", ["draft", "Dear Tanaka,"])
    path = @last.first[:path]
    board = Monadic::Workbench::Board.for(chat, store: store)
    expect(board.snapshot[:items].map { |i| i[:path] }).to include(path)
    session[:messages].delete(only)
    editor.trash_made_files(session, only)
    editor.rebuild_documents(session)
    expect(File.exist?(File.join(@data, path))).to be false
    expect(board.snapshot[:items].map { |i| i[:path] }).not_to include(path)
  end

  it "lists every version of a document's sections, with the turn that wrote it" do
    reply("Draft", ["draft", "First."])
    session[:messages] << { "mid" => "u", "role" => "user", "text" => "shorter" }
    reply("Draft", ["draft", "Second."])
    path = @last.first[:path]
    versions = described_class.versions(session, path)
    expect(versions.map { |v| [v["section"], v["turn"]] }).to eq([["draft", 1], ["draft", 2]])
    expect(versions.map { |v| text(v["path"]) }).to eq(["First.", "Second."])
  end

  it "lists nothing for a path that is not a document of the chat" do
    reply("Draft", ["draft", "First."])
    expect(described_class.versions(session, "conversations/other/documents/draft.md")).to eq([])
    expect(described_class.versions(session, @last.first[:section_path])).to eq([])
    expect(described_class.versions({}, @last.first[:path])).to eq([])
  end

  it "leaves out a section whose file is gone" do
    first = reply("Story", ["1", "One."], ["2", "Two."])
    FileUtils.rm(File.join(@data, @last.first[:section_path]))
    expect(bodies(described_class.rebuild(described_class.folder_of(@last.first[:path]), "story",
                                          described_class.made_lists(session)))).to eq([["2", "Two."]])
    expect(first["workbench_made"].size).to eq(2)
  end

  it "keeps two documents of one chat apart" do
    reply("Story", ["1", "Story text."])
    reply("Notes", ["1", "A note."])
    folder = described_class.folder_of(@last.first[:path])
    expect(bodies(File.join(folder, "documents", "story.md"))).to eq([["1", "Story text."]])
    expect(bodies(File.join(folder, "documents", "notes.md"))).to eq([["1", "A note."]])
  end

  it "records a line for the reply's message that opens the document at its section" do
    message = reply("Story", ["2", "Two."])
    expect(message["workbench_shown"]).to contain_exactly(include("path" => @last.first[:path], "section" => "2"))
  end

  it "names a document and a section of any language by letters, digits and hyphens only" do
    expect(described_class.slug("My Story: Part 1!", 60)).to eq("my-story-part-1")
    expect(described_class.slug("吾輩は猫である", 60)).to match(/\Ah-\h{12}\z/)
    expect(described_class.slug("../../etc", 40)).to eq("etc")
    reply("吾輩は猫である", ["第一章", "吾輩は猫である。"])
    expect(File.basename(@last.first[:section_path])).to match(/\Ah-\h{12}--h-\h{12}\.md\z/)
    expect(text(@last.first[:path])).to start_with("# 吾輩は猫である\n")
  end

  it "takes only what the chat's folder made, and refuses what is empty or without a chat" do
    expect(Monadic::Workbench::Made.clean(["../outside/a.md", "/etc/passwd", "elsewhere/x.md"])).to be_nil
    expect { described_class.write(session: session, workbench: nil, app_name: "X", document: "", section: "1", content: "x") }
      .to raise_error(described_class::Refused)
    expect { described_class.write(session: session, workbench: nil, app_name: "X", document: "S", section: "1", content: " ") }
      .to raise_error(described_class::Refused)
    expect { described_class.write(session: {}, workbench: nil, app_name: "X", document: "S", section: "1", content: "x") }
      .to raise_error(described_class::Refused, /no chat folder/)
  end
end
