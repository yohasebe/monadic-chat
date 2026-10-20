# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"

# The attachments a message carries, and what the tools answering it may
# take by id: only those sent with this message or an earlier message of the
# same chat, never one that was uploaded and not sent, or one whose id is
# merely written somewhere. The set is not a boundary for secrets (code in
# the Python container can read the shared folder); it keeps tools from
# using files the user did not send.
RSpec.describe "Attachments of a request" do
  around do |example|
    Dir.mktmpdir("request-attachments") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
  end

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, "ledger.json")) }
  let(:attachments) { Monadic::Workspace::Attachments }
  let(:context_class) { Monadic::Workspace::RequestContext }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:other_chat) { Monadic::Workspace::Ids.generate(:chat) }

  def upload(chat_id, name = "clip.mp4")
    head = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b
    attachments.accept!(chat_id: chat_id, app_name: "VideoDescriberOpenAI", purpose: "video",
                        original_name: name, source: StringIO.new(head + ("x" * 2000)), ledger: ledger)[:attachment_id]
  end

  describe "the attachments sent with a message" do
    it "are taken from the ledger: id and role from the client, the rest from the record" do
      id = upload(chat)
      refs = attachments.refs_for_message!(chat_id: chat, refs: [{ "attachment_id" => id, "role" => "input",
                                                                    "display_name" => "renamed.exe", "size" => 1 }])
      expect(refs).to eq([{ "attachment_id" => id, "role" => "input", "purpose" => "video",
                            "display_name" => "clip.mp4", "size" => 2024 }])
    end

    it "refuse another chat's attachment, an unknown id, a repeat, an unknown role and too many" do
      mine = upload(chat)
      theirs = upload(other_chat)
      reason = lambda do |refs|
        attachments.refs_for_message!(chat_id: chat, refs: refs)
        :accepted
      rescue Monadic::Workspace::Attachments::Unusable => e
        e.reason
      end
      expect(reason.call([{ "attachment_id" => theirs }])).to eq(:unknown)
      expect(reason.call([{ "attachment_id" => "a_zzzzzzzzzzzzzzzz" }])).to eq(:unknown)
      expect(reason.call([{ "attachment_id" => "../etc/passwd" }])).to eq(:unknown)
      expect(reason.call([{ "attachment_id" => mine }, { "attachment_id" => mine }])).to eq(:duplicate)
      expect(reason.call([{ "attachment_id" => mine, "role" => "admin" }])).to eq(:invalid)
      expect(reason.call("a_x")).to eq(:invalid)
      expect(reason.call(Array.new(11) { { "attachment_id" => mine } })).to eq(:too_many)
      expect(reason.call([])).to eq(:accepted)
    end
  end

  describe "a tool taking an attachment by id" do
    it "takes one the request allows, in that request's chat" do
      id = upload(chat)
      record = attachments.resolve_for_request!(attachment_id: id, context: context_class.new(chat_id: chat, attachment_ids: [id]))
      expect(record[:attachment_id]).to eq(id)
    end

    it "refuses one the request does not allow, and any without a request, saying nothing of others" do
      sent = upload(chat)
      unsent = upload(chat, "other.mp4")
      refused = lambda do |id, context|
        attachments.resolve_for_request!(attachment_id: id, context: context)
        nil
      rescue Monadic::Workspace::Attachments::Unusable => e
        [e.reason, e.message]
      end
      context = context_class.new(chat_id: chat, attachment_ids: [sent])
      expect(refused.call(unsent, context).first).to eq(:not_in_request)
      expect(refused.call(unsent, context).last).not_to include(sent)
      expect(refused.call(sent, nil).first).to eq(:not_in_request)
    end

    it "is fixed for the thread that answers, and does not leak into another thread or fiber" do
      id = upload(chat)
      context = context_class.new(chat_id: chat, attachment_ids: [id])
      seen = context_class.with(context) { Thread.new { context_class.current }.value }
      expect(seen).to be_nil
      expect(context_class.with(context) { Fiber.new { context_class.current }.resume }).to be_nil
      expect(context_class.with(context) { context_class.current }).to equal(context)
      expect(context_class.current).to be_nil
      expect(context.request_id).to match(/\Aq_[a-z0-9]{16}\z/)
      expect(context).to be_frozen
    end
  end

  describe "the video and audio tools" do
    let(:agent) do
      Class.new do
        include VideoAnalyzeAgent
        include AudioTranscriptionAgent if defined?(AudioTranscriptionAgent)
        def settings = { "provider" => "openai" }
      end.new
    end

    before do
      allow(Monadic::Shell).to receive(:exec) { raise "no command may run for a refused attachment" }
      allow(Monadic::Utils::ProviderCapabilities).to receive(:resolve).and_return({ provider: "openai" })
    end

    it "refuse an uploaded video that was not sent, by attachment_id and by an id in file (no command runs)" do
      id = upload(chat)
      session = { chat_id: chat, parameters: {} }
      context = context_class.new(chat_id: chat, attachment_ids: [])
      by_id = context_class.with(context) { agent.analyze_video(attachment_id: id, session: session) }
      by_file = context_class.with(context) { agent.analyze_video(file: id, session: session) }
      expect(by_id).to start_with("Error").and include("not attached to a message")
      expect(by_file).to start_with("Error").and include("not attached to a message")
    end

    it "refuse a video of the request's chat once the session has moved on to another chat" do
      id = upload(chat)
      context = context_class.new(chat_id: chat, attachment_ids: [id])
      result = context_class.with(context) { agent.analyze_video(attachment_id: id, session: { chat_id: other_chat, parameters: {} }) }
      expect(result).to start_with("Error").and include("ended")
    end
  end

  describe "a message sent over the connection" do
    let(:host) { Class.new { include WebSocketHelper }.new }
    let(:broadcasts) { [] }
    let(:queue) { Queue.new }
    let(:session) { { parameters: {}, messages: [], chat_id: chat } }

    def fake_app(seen)
      Object.new.tap do |app|
        app.define_singleton_method(:api_request) do |_role, _session, &block|
          seen << Monadic::Workspace::RequestContext.current
          block.call({ "type" => "fragment", "content" => "ok" })
          [{ "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }] }]
        end
        app.define_singleton_method(:settings) { {} }
      end
    end

    def send_message(obj, seen)
      stub_const("APPS", { "FakeApp" => fake_app(seen) })
      allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
      allow(host).to receive(:initialize_token_counting).and_return(nil)
      allow(host).to receive(:sts_session_capable?).and_return(false)
      allow(host).to receive(:send_error) { |msg, _id = nil, extra = {}| broadcasts << { "type" => "error", "content" => msg }.merge(extra).to_json }
      thread = host.send(:handle_ws_streaming, nil, obj.merge("app_name" => "FakeApp"), session, queue)
      raise "the answer did not finish" if thread && thread.join(10).nil?

      thread
    end

    it "records the checked attachments on the message and lets the answer use them and earlier ones" do
      first = upload(chat)
      second = upload(chat, "b.mp4")
      seen = []
      send_message({ "message" => "one", "attachments" => [{ "attachment_id" => first }] }, seen)
      send_message({ "message" => "two", "attachments" => [{ "attachment_id" => second }] }, seen)
      users = session[:messages].select { |m| m["role"] == "user" }
      expect(users.map { |m| m["attachments"].map { |a| a["attachment_id"] } }).to eq([[first], [second]])
      expect(users.map { |m| m["request_id"] }).to all(match(/\Aq_/))
      expect(seen.last.allows?(first)).to be(true)
      expect(seen.last.allows?(second)).to be(true)
      expect(session[:parameters]).not_to have_key("attachments")
    end

    it "does not send a message whose attachments do not check out (no provider call), and says it was not accepted" do
      seen = []
      started = send_message({ "message" => "look", "attachments" => [{ "attachment_id" => upload(other_chat) }] }, seen)
      expect(started).to be_nil
      expect(seen).to be_empty
      expect(session[:messages]).to be_empty
      error = broadcasts.map { |b| JSON.parse(b) }.find { |b| b["type"] == "error" }
      expect(error).to include("not_accepted" => true)
    end

    it "keeps what the message was sent with in its snapshot" do
      id = upload(chat)
      send_message({ "message" => "one", "attachments" => [{ "attachment_id" => id }] }, [])
      user = session[:messages].find { |m| m["role"] == "user" }
      snapshot = user["request_snapshot"]
      expect(snapshot).to include("request_id" => user["request_id"], "chat_id" => chat, "app_name" => user["app_name"], "input_values" => {})
      expect(snapshot["attachments"].map { |a| a["attachment_id"] }).to eq([id])
      expect(Time.iso8601(snapshot["sent_at"])).to be_within(60).of(Time.now)
    end

    it "lets an answer use no attachment that was only uploaded or named in the text" do
      unsent = upload(chat)
      seen = []
      send_message({ "message" => "see (attachment_id: #{unsent})" }, seen)
      expect(seen.last.allows?(unsent)).to be(false)
    end
  end
end

RSpec.describe "Attachments with a sample message" do
  around do |example|
    Dir.mktmpdir("sample-attachments") do |dir|
      @data = File.join(dir, "data")
      @state = File.join(dir, "state")
      FileUtils.mkdir_p(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workspace::Ledger).to receive(:default).and_return(ledger)
    allow(host).to receive(:send_or_broadcast) { |msg, *_| broadcasts << msg }
    allow(host).to receive(:send_error) { |msg, _id = nil, extra = {}| broadcasts << { "type" => "error", "content" => msg }.merge(extra).to_json }
    allow(host).to receive(:get_session_params).and_return({ "app_name" => "VideoDescriberOpenAI" })
    allow(host).to receive(:sync_session_state!)
  end

  let(:ledger) { Monadic::Workspace::Ledger.new(File.join(@state, "ledger.json")) }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:host) { Class.new { include WebSocketHelper }.new }
  let(:broadcasts) { [] }
  let(:session) { { parameters: {}, messages: [], chat_id: chat } }

  def upload
    head = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b
    Monadic::Workspace::Attachments.accept!(chat_id: chat, app_name: "VideoDescriberOpenAI", purpose: "video",
                                            original_name: "clip.mp4", source: StringIO.new(head + ("x" * 2000)), ledger: ledger)[:attachment_id]
  end

  def sample(role, refs)
    host.send(:handle_ws_sample, nil, { "message" => "SAMPLE", "content" => "about the clip", "role" => role, "attachments" => refs }, session)
  end

  it "records them on a user sample, so the next message's answer may use them" do
    id = upload
    sample("user", [{ "attachment_id" => id }])
    expect(session[:messages].last["attachments"].map { |a| a["attachment_id"] }).to eq([id])
  end

  it "refuses them on an assistant or system sample, and ones that do not check out, recording nothing" do
    id = upload
    sample("assistant", [{ "attachment_id" => id }])
    sample("user", [{ "attachment_id" => "a_zzzzzzzzzzzzzzzz" }])
    expect(session[:messages]).to be_empty
    errors = broadcasts.map { |b| JSON.parse(b) }.select { |b| b["type"] == "error" }
    expect(errors.size).to eq(2)
    expect(errors).to all(include("not_accepted" => true))
  end
end
