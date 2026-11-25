# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require "digest"
require_relative "../../../lib/monadic/workspace/ids"
require_relative "../../../lib/monadic/workbench/image_tool"
require_relative "../../../lib/monadic/history/serializer"
require_relative "../../../lib/monadic/utils/websocket"

# The images of the work screen an image edit handed to its provider: kept
# as sent and recorded for the reply's message only when the generator
# posted its request, taken or refused as it says.
RSpec.describe Monadic::Workbench::EditInputs do
  def png(salt = "")
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00".b * 4 + salt.b
  end

  around do |example|
    Dir.mktmpdir("edit-inputs-spec") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:tool) { Monadic::Workbench::ImageTool }
  let(:sent) { Monadic::Workbench::Sent }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:user) { { "role" => "user", "text" => "make it red", "request_id" => request_id } }
  let(:session) do
    { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "ImageGeneratorOpenAI" }, messages: [user] }
  end
  let(:workbench) do
    Monadic::Workbench::Caller.new(chat_id: chat, epoch: Monadic::Workspace::Chats.epoch(chat), request_id: request_id,
                                   session: session, tab: "tab-1", generation: 1)
  end
  let(:drawn) do
    [Monadic::Workbench::BoardEdit::Input.new(role: "original", bytes: png("original"), content_type: "image/png"),
     Monadic::Workbench::BoardEdit::Input.new(role: "reference", bytes: png("reference"), content_type: "image/png")]
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Store).to receive(:default).and_return(Monadic::Workbench::Store.new(File.join(@state, "workbench")))
  end

  after { sent::PENDING_LOCK.synchronize { sent::PENDING.clear } }

  def run(said) = tool.run_job(workbench, drawn: drawn) { |_out, _inputs| said }
  def sha(salt) = Digest::SHA256.hexdigest(png(salt))

  it "keeps the original and the reference, and records them for the reply's message, when the request was posted" do
    run('{"success":true,"posted":true,"images":[]}')
    records = described_class.seal(request_id)
    expect(records.map { |r| r.values_at("role", "sha256", "state") })
      .to eq([["original", sha("original"), "sent"], ["reference", sha("reference"), "sent"]])
    expect(records.map { |r| r["call"] }.uniq.size).to eq(1)
    expect(sent.read(chat, sha("reference"))).to eq(png("reference"))
    expect(sent::PENDING).not_to have_key(chat.to_s)
    expect(sent.named_by([{ described_class::KEY => records }])).to eq([sha("original"), sha("reference")])
  end

  it "records a refused request as refused, and keeps nothing when nothing was posted" do
    run('{"success":false,"posted":true,"message":"blocked"}')
    expect(described_class.seal(request_id).map { |r| r["state"] }).to eq(%w[refused refused])
    other = Monadic::Workspace::Ids.generate(:request)
    allow(workbench).to receive(:request_id).and_return(other)
    run('{"success":false,"message":"no key"}')
    expect(described_class.seal(other)).to eq([])
    expect(sent.read(chat, sha("original"))).to eq(png("original"))
  end

  it "sends nothing when the chat keeps too much" do
    run('{"success":true,"posted":true}')
    described_class.seal(request_id)
    stub_const("#{sent}::LIMIT_BYTES", 10)
    ran = false
    out = tool.run_job(workbench, drawn: drawn) { ran = true }
    expect(out).to start_with("❌")
    expect(ran).to be(false)
  end

  it "puts the records on the user's message when the reply ends without one" do
    host = Class.new { include WebSocketHelper }.new
    run('{"success":true,"posted":true}')
    host.send(:workbench_edits_without_reply, request_id)
    expect(user[described_class::KEY].map { |r| r["role"] }).to eq(%w[original reference])
    expect(described_class.seal(request_id)).to eq([])
  end

  it "is kept by the history with its message, and nothing of another form" do
    records = [{ "call" => "e_#{'a' * 16}", "role" => "original", "sha256" => "b" * 64, "content_type" => "image/png",
                 "state" => "sent" },
               { "call" => "x", "role" => "original", "sha256" => "b" * 64, "content_type" => "image/png", "state" => "sent" }]
    expect(described_class.clean(records).size).to eq(1)
    kept = Monadic::History::Serializer.message({ "role" => "assistant", "text" => "done", described_class::KEY => records })
    expect(kept[described_class::KEY].size).to eq(1)
  end
end
