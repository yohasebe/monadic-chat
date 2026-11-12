# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"

# A file Claude made for a reply (a document from a skill): kept in a run
# folder of the chat's folder and shown on the work screen when it can be,
# or in documents/ for a reply without a chat folder.
RSpec.describe "a file Claude made for a reply" do
  around do |example|
    Dir.mktmpdir("claude-provider-file-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    stub_const("MonadicApp::LOCAL_SHARED_VOL", @data)
    allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
  end

  let(:host) { Class.new { include ClaudeHelper }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "DocumentGeneratorClaude" } } }
  let(:workbench) { Struct.new(:chat_id, :request_id).new(chat, nil) }

  it "is kept in a run folder of the chat's folder under its own last name, and shown when it can be" do
    allow(Monadic::Workbench::Caller).to receive(:current).with(session).and_return(workbench)
    allow(Monadic::Workbench::ChatOutput).to receive(:show).and_return(true)
    kept = host.send(:keep_provider_file, session, "%PDF-1.4", "../x/report.pdf")
    expect(kept[:relative]).to match(%r{\Aconversations/[^/]+/artifacts/j_[a-z0-9]+/report\.pdf\z})
    expect(File.read(File.join(@data, kept[:relative]))).to eq("%PDF-1.4")
    expect(kept).to include(size: 8, shown: true)
    expect(Monadic::Workbench::ChatOutput).to have_received(:show).with(kept[:relative], workbench)
    expect(Dir.exist?(File.join(@data, "documents"))).to be false
  end

  it "says when the work screen did not show it (an Office file)" do
    allow(Monadic::Workbench::Caller).to receive(:current).and_return(workbench)
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return("❌ The file was not shown")
    kept = host.send(:keep_provider_file, session, "PK", "slides.pptx")
    expect(kept[:relative]).to end_with("/slides.pptx")
    expect(kept[:shown]).to be false
  end

  it "goes to documents/ when the reply has no chat folder" do
    allow(Monadic::Workbench::Caller).to receive(:current).and_return(nil)
    kept = host.send(:keep_provider_file, {}, "PK", "book.xlsx")
    expect(File.read(File.join(@data, "documents", "book.xlsx"))).to eq("PK")
    expect(kept[:shown]).to be false
  end
end
