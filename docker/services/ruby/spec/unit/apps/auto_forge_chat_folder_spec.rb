# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../apps/auto_forge/auto_forge"
require_relative "../../../lib/monadic/utils/websocket/message_editor"

# AutoForge keeps its projects in the folder of the chat the reply runs for:
# the turn that makes a project owns it, and a turn that changes it can be
# taken back.
RSpec.describe "AutoForge projects in the chat's folder" do
  around do |example|
    Dir.mktmpdir("autoforge-chat-folder-") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:paths) { AutoForge::Utils::PathConfig }
  let(:made) { Monadic::Workbench::Made }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat, messages: [] } }

  before do
    WebSocketHelper::Replies.reset!
    Monadic::Workbench::Shown.reset!
    made.reset!
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(paths).to receive(:current_chat).and_return({ id: chat, epoch: 1 })
  end

  after { Monadic::Workspace::Ledger.clear_unsettled! }

  # A running reply, as the server runs a tool for it.
  def reply
    request_id = Monadic::Workspace::Ids.generate(:request)
    handle, = WebSocketHelper::Replies.open(request_id: request_id, chat_id: chat, tab: "tab-1", generation: 1)
    handle.attach(Thread.current)
    handle.begin!
    allow(Monadic::Workspace::RequestContext).to receive(:current).and_return(Struct.new(:request_id).new(request_id))
    request_id
  end

  def relative(path)
    path.delete_prefix("#{@data}/")
  end

  it "makes a project in the chat's auto_forge folder, as made by the turn" do
    request_id = reply
    project = AutoForgeUtils.create_project_directory("Todo App")
    expect(relative(project[:path])).to match(%r{\Aconversations/[^/]+/auto_forge/Todo App_\d{8}_\d{6}\z})
    expect(made.seal(request_id)).to eq([relative(project[:path])])
    expect(AutoForgeUtils.list_projects.map { |p| p[:name] }).to eq([project[:name]])
  end

  it "refuses to make a project without a chat, and lists none" do
    allow(paths).to receive(:current_chat).and_return(nil)
    expect { AutoForgeUtils.create_project_directory("App") }.to raise_error(AutoForgeUtils::ProjectCreationError, /chat/)
    expect(AutoForgeUtils.list_projects).to eq([])
  end

  it "keeps a project an earlier turn made before a later turn changes it, and puts it back when that turn is deleted" do
    reply
    project = AutoForgeUtils.create_project_directory("App")
    File.write(File.join(project[:path], "index.html"), "v1")

    request_id = reply
    paths.before_change(project[:path])
    File.write(File.join(project[:path], "index.html"), "v2")
    made.seal(request_id)
    message = { "mid" => "m2", "role" => "assistant", made::REVISIONS_KEY => made.seal_revisions(request_id) }

    editor = Class.new { include WebSocketHelper }.new
    expect(editor.trash_made_files(session, message)).to eq([relative(project[:path])])
    expect(File.read(File.join(project[:path], "index.html"))).to eq("v1")
  end

  it "finds the chat's project by its path, its name, or as the newest" do
    reply
    older = AutoForgeUtils.create_project_directory("Older", { type: "web" })
    allow(Time).to receive(:now).and_return(Time.now + 5)
    newer = AutoForgeUtils.create_project_directory("Newer", { type: "web" })
    expect(AutoForgeUtils.current_project[:path]).to eq(newer[:path])
    expect(AutoForgeUtils.current_project(name: "older")[:path]).to eq(older[:path])
    expect(AutoForgeUtils.current_project(path: older[:path])[:path]).to eq(older[:path])
    expect(AutoForgeUtils.current_project(path: File.join(@data, "elsewhere"))).to be_nil
  end

  it "changes the chat's project of the same name rather than making another" do
    reply
    own = AutoForgeUtils.create_project_directory("App")
    orchestrator = AutoForge::Orchestrator.new({})
    expect(orchestrator.send(:resolve_project_context, { name: "app" })).to include(path: own[:path], existing: true)
    allow(Time).to receive(:now).and_return(Time.now + 5)
    fresh = orchestrator.send(:resolve_project_context, { name: "App", reset: true })
    expect(fresh[:existing]).to be_falsey
    expect(fresh[:path]).not_to eq(own[:path])
  end

  it "takes no project outside this chat's auto_forge folder" do
    reply
    own = AutoForgeUtils.create_project_directory("App")
    other = File.join(@data, "conversations", "other", "auto_forge", "App_1")
    FileUtils.mkdir_p(other)
    orchestrator = AutoForge::Orchestrator.new({})
    context = ->(path) { orchestrator.send(:existing_project_context, { name: "App", project_path: path }) }
    expect(context.call(own[:path])).to include(existing: true)
    expect(context.call(other)).to be_nil
  end
end
