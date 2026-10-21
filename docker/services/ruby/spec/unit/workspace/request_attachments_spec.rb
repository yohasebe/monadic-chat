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

    describe "with Privacy placeholders in the id" do
      def privacy_session(registry)
        { chat_id: chat, monadic_state: { privacy: { registry: registry, audit: [] } } }
      end

      def masked(id, part, placeholder)
        id.sub(part, placeholder)
      end

      def reason_for(id, context, session)
        attachments.resolve_for_request!(attachment_id: id, context: context, session: session)
        :accepted
      rescue Monadic::Workspace::Attachments::Unusable => e
        e.reason
      end

      it "restores the id from the session's mapping and takes it when the request allows it" do
        id = upload(chat)
        part = id[2, 6]
        session = privacy_session({ "<<PERSON_1>>" => part })
        context = context_class.new(chat_id: chat, attachment_ids: [id])
        record = attachments.resolve_for_request!(attachment_id: masked(id, part, "<<PERSON_1>>"),
                                                  context: context, session: session)
        expect(record[:attachment_id]).to eq(id)
        lightly_mangled = masked(id, part, "<< PERSON_1 >>")
        expect(reason_for(lightly_mangled, context, session)).to eq(:accepted)
      end

      it "refuses a restored id the request does not allow" do
        sent = upload(chat)
        unsent = upload(chat, "other.mp4")
        part = unsent[2, 6]
        session = privacy_session({ "<<PHONE_NUMBER_1>>" => part })
        context = context_class.new(chat_id: chat, attachment_ids: [sent])
        expect(reason_for(masked(unsent, part, "<<PHONE_NUMBER_1>>"), context, session)).to eq(:not_in_request)
      end

      it "refuses what does not restore to an id, even if the request lists it" do
        id = upload(chat)
        part = id[2, 6]
        odd = "a_../../#{id[8..]}"
        session = privacy_session({ "<<PERSON_1>>" => "../../" })
        context = context_class.new(chat_id: chat, attachment_ids: [id, odd])
        expect(reason_for("a_<<PERSON_1>>#{id[8..]}", context, session)).to eq(:not_in_request)
        expect(reason_for(masked(id, part, "<<PERSON_2>>"), context, session)).to eq(:not_in_request)
        expect(reason_for(masked(id, part, "<<PERSON_1>>"), context, nil)).to eq(:not_in_request)
        expect(reason_for(masked(id, part, "<<PERSON_1>>"), context, { chat_id: chat })).to eq(:not_in_request)
      end

      it "refuses, before using its mapping, a session that is no longer the request's chat" do
        id = upload(chat)
        part = id[2, 6]
        moved = privacy_session({ "<<PERSON_1>>" => part }).merge(chat_id: other_chat)
        context = context_class.new(chat_id: chat, attachment_ids: [id])
        expect(attachments).not_to receive(:unmask_id)
        expect(reason_for(masked(id, part, "<<PERSON_1>>"), context, moved)).to eq(:chat_moved_on)
        expect(reason_for(id, context, moved)).to eq(:chat_moved_on)
        expect(reason_for(id, context, { chat_id: chat })).to eq(:accepted)
      end

      it "restores a whole id or several placeholders in one pass, and nothing when one is unknown" do
        id = upload(chat)
        context = context_class.new(chat_id: chat, attachment_ids: [id])
        session = privacy_session({ "<<PERSON_1>>" => id, "<<PERSON_2>>" => id[2, 4], "<<PERSON_3>>" => id[10, 4],
                                    "<<PERSON_4>>" => "<<PERSON_1>>", "<<PERSON_5>>" => 7 })
        two = "#{id[0, 2]}<<PERSON_2>>#{id[6, 4]}<<PERSON_3>>#{id[14..]}"
        expect(reason_for("<<PERSON_1>>", context, session)).to eq(:accepted)
        expect(reason_for(two, context, session)).to eq(:accepted)
        expect(reason_for(two.sub("<<PERSON_3>>", "<<PERSON_9>>"), context, session)).to eq(:not_in_request)
        expect(reason_for("<<PERSON_4>>", context, session)).to eq(:not_in_request)
        expect(reason_for("<<PERSON_5>>", context, session)).to eq(:not_in_request)
        expect(reason_for("<<PERSON_1>>", nil, session)).to eq(:not_in_request)
      end

      it "creates no Privacy state, and still checks the ledger's chat for a restored id" do
        session = { chat_id: chat }
        expect(reason_for("a_<<PERSON_1>>", context_class.new(chat_id: chat, attachment_ids: []), session)).to eq(:not_in_request)
        expect(session).to eq({ chat_id: chat })

        theirs = upload(other_chat)
        listed = context_class.new(chat_id: chat, attachment_ids: [theirs])
        expect(reason_for("<<PERSON_1>>", listed, privacy_session({ "<<PERSON_1>>" => theirs }))).to eq(:unknown)
      end
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

    it "take an id with Privacy placeholders by restoring it from the chat's session" do
      id = upload(chat)
      part = id[2, 6]
      session = { chat_id: chat, parameters: {}, monadic_state: { privacy: { registry: { "<<PERSON_1>>" => part } } } }
      context = context_class.new(chat_id: chat, attachment_ids: [id])
      masked_id = id.sub(part, "<<PERSON_1>>")
      # The video passes the gate and is then refused as audio by its purpose.
      expect { context_class.with(context) { agent.resolve_audio_attachment(masked_id, session) } }
        .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:purpose) }
      expect(attachments).to receive(:resolve_for_request!).with(hash_including(session: session)).and_return({ purpose: "audio" })
      result = context_class.with(context) { agent.analyze_video(attachment_id: masked_id, session: session) }
      expect(result).to include("not a video")
    end

    it "refuse a masked id once the session has moved on, before its mapping is used" do
      id = upload(chat)
      part = id[2, 6]
      moved = { chat_id: other_chat, parameters: {}, monadic_state: { privacy: { registry: { "<<PERSON_1>>" => part } } } }
      context = context_class.new(chat_id: chat, attachment_ids: [id])
      expect(attachments).not_to receive(:unmask_id)
      video = context_class.with(context) { agent.analyze_video(attachment_id: id.sub(part, "<<PERSON_1>>"), session: moved) }
      expect(video).to start_with("Error").and include("ended")
      expect { context_class.with(context) { agent.resolve_audio_attachment(id.sub(part, "<<PERSON_1>>"), moved) } }
        .to raise_error(Monadic::Workspace::Attachments::Unusable) { |e| expect(e.reason).to eq(:chat_moved_on) }
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

    it "records a message of attached files with no text, under its request, with its snapshot" do
      id = upload(chat)
      seen = []
      send_message({ "message" => "", "attachments" => [{ "attachment_id" => id }] }, seen)
      user = session[:messages].find { |m| m["role"] == "user" }
      expect(user).to include("text" => "", "request_id" => seen.last.request_id)
      expect(user["attachments"].map { |a| a["attachment_id"] }).to eq([id])
      expect(user["request_snapshot"]["attachments"].map { |a| a["attachment_id"] }).to eq([id])
      expect(seen.last.allows?(id)).to be(true)
    end

    it "records no user message for a send with no text and no attachments" do
      seen = []
      send_message({ "message" => "" }, seen)
      expect(session[:messages].select { |m| m["role"] == "user" }).to be_empty
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
