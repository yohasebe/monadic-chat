# frozen_string_literal: true

require "spec_helper"
require "json"
require "base64"
require_relative "../../../lib/monadic/adapters/base_vendor_helper"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/workbench/look"

# A request that holds looks: what a helper puts in it, the check right
# before it is sent, and how far its looks went.
RSpec.describe "a request holding looks of the work screen" do
  IMG = "look_#{'a' * 16}".freeze
  TXT = "look_#{'b' * 16}".freeze

  let(:helper) { Class.new { include BaseVendorHelper }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, parameters: {}, messages: [] } }
  let(:ledger) do
    Monadic::Workbench::Look::Ledger.for(chat, Monadic::Workspace::Chats.epoch(chat), request_id, session: session)
  end
  let(:ok) { double(status: HTTP::Response::Status.new(200)) }
  let(:failed) { double(status: HTTP::Response::Status.new(500)) }

  def png
    "\x89PNG\r\n\x1A\n".b + [13].pack("N") + "IHDR".b + [2, 2].pack("NN") + "\x08\x02\x00\x00\x00".b + "\x00" * 4
  end

  # One image look and one text look, answering the calls c1 and c2.
  def looks
    image = Monadic::Workbench::Look::ImageValue.checked(png, source: "workbench_file")
    picture = ledger.add(id: IMG, item_id: "i_1", kind: "image", name: "a.png", path: "a.png", version: "a" * 64,
                         scope: "visible", image: image, result: %({"status":"looked","observation_id":"#{IMG}"}),
                         caption: "The image below is #{IMG}")
    words = ledger.add(id: TXT, item_id: "i_2", kind: "text", name: "n.txt", path: "n.txt", version: "b" * 64,
                       scope: "whole", text: "secret words", result: %({"status":"looked","observation_id":"#{TXT}","text":"secret words"}))
    ledger.bind(picture, "c1")
    ledger.bind(words, "c2")
    [picture, words]
  end

  def state_of(id)
    ledger.records.find { |r| r["id"] == id }["state"]
  end

  def tool(id, text = "result")
    { "role" => "tool", "tool_call_id" => id, "content" => text }
  end

  def build(messages)
    helper.with_workbench_looks(messages, session, tool_id: helper.method(:chat_tool_call_id)) do |list|
      helper.chat_look_message(list)
    end
  end

  # One post of body (the looks put in the request are checked).
  def post(body, response = ok, model: "m", on: session, &block)
    helper.post_with_workbench_looks(on, provider: "openai", model: model, &(block || -> { response }))
  end

  around do |example|
    Monadic::Workbench::Look::Ledger.reset!
    context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id)
    Monadic::Workspace::RequestContext.with(context) { example.run }
  end

  before do
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with("m", "vision_capability").and_return(true)
    allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with("text-only", "vision_capability").and_return(false)
  end

  describe "building" do
    it "puts each image after the results it answers, and holds the text looks too" do
      picture, words = looks
      out = build([tool("c1"), tool("c2"), { "role" => "assistant", "content" => "x" }])
      expect(out.map { |m| m["role"] }).to eq(%w[tool tool user assistant])
      expect(JSON.generate(out[2])).to include(Base64.strict_encode64(png), IMG)
      expect([state_of(picture), state_of(words)]).to eq(%w[embedded embedded])
    end

    it "brings back the looks of earlier rounds when only the last round's results are sent" do
      looks
      out = build([tool("c3")])
      text = JSON.generate(out.last)
      expect(text).to include(Base64.strict_encode64(png), "secret words")
      expect(out.first).to eq(tool("c3"))
    end
  end

  describe "posting" do
    let(:body) { looks && { "messages" => build([tool("c1"), tool("c2", %({"observation_id":"#{TXT}"}))]) } }

    it "settles every look the request holds: sent on success" do
      post(body)
      expect([state_of(IMG), state_of(TXT)]).to eq(%w[sent sent])
    end

    it "is refused by the provider, then sent when the same request is sent again" do
      post(body, failed)
      expect(state_of(IMG)).to eq("refused")
      post(body)
      expect(state_of(IMG)).to eq("sent")
    end

    it "is unknown when the connection fails, and sent when a retry is taken" do
      expect { post(body) { raise HTTP::TimeoutError, "timed out" } }.to raise_error(HTTP::TimeoutError)
      expect(state_of(IMG)).to eq("unknown")
      post(body)
      expect(state_of(IMG)).to eq("sent")
    end

    it "is unknown when the thread is stopped while posting" do
      sent_body = body
      started = Queue.new
      thread = Thread.new do
        Monadic::Workspace::RequestContext.with(Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id)) do
          post(sent_body) do
            started << true
            sleep
          end
        rescue StandardError => e
          started << e
        end
      end
      expect(started.pop(timeout: 5)).to be(true)
      thread.kill
      thread.join
      expect(state_of(IMG)).to eq("unknown")
    end

    {
      "the chat became Private" => ->(s, _) { s[Monadic::History::Policy::SESSION_KEY] = Monadic::History::Policy::PRIVATE },
      "the chat was reset" => ->(_, c) { Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS[c] += 1 } },
      "the tab is in another chat" => ->(s, _) { s[:chat_id] = Monadic::Workspace::Ids.generate(:chat) }
    }.each do |what, change|
      it "sends nothing when #{what} after the request was built" do
        sent_body = body
        change.call(session, chat)
        posted = false
        expect do
          post(sent_body) do
            posted = true
            ok
          end
        end.to raise_error(Monadic::Workbench::Look::Withheld)
        expect(posted).to be(false)
        expect([state_of(IMG), state_of(TXT)]).to eq(%w[unsent unsent])
      end
    end

    it "checks again when the same body is sent again after it was sent" do
      post(body)
      session[Monadic::History::Policy::SESSION_KEY] = Monadic::History::Policy::PRIVATE
      expect { post(body) }.to raise_error(Monadic::Workbench::Look::Withheld)
    end

    it "checks each try of a request the shared retry loop sends" do
      sent_body = body
      http = double("http")
      allow(http).to receive(:timeout).and_return(http)
      tries = 0
      allow(http).to receive(:post) do
        tries += 1
        session[Monadic::History::Policy::SESSION_KEY] = Monadic::History::Policy::PRIVATE
        failed
      end
      allow(helper).to receive(:sleep)
      %i[open_timeout write_timeout read_timeout].each { |name| allow(helper).to receive(name).and_return(1) }
      expect do
        helper.post_json_with_retries(http, "https://example.invalid", sent_body, max_retries: 3, retry_delay: 0,
                                      looks: { session: session, provider: "openai", model: "m" })
      end.to raise_error(Monadic::Workbench::Look::Withheld)
      expect(tries).to eq(1)
    end

    it "reads a session that is not a Hash, as the server's is" do
      sent_body = body
      rack_like = Class.new do
        def initialize(data) = (@data = data)
        def [](key) = @data[key.to_sym]
        def []=(key, value)
          @data[key.to_sym] = value
        end

        def key?(key) = @data.key?(key.to_sym)
      end.new(session)
      expect(post(sent_body, on: rack_like)).to eq(ok)
      expect(state_of(IMG)).to eq("sent")
    end

    it "sends no image to a model that does not take images" do
      sent_body = body
      expect { post(sent_body, model: "text-only") }.to raise_error(Monadic::Workbench::Look::Withheld)
    end

    it "lets a request whose looks are all text go to a model that does not take images" do
      words = ledger.add(id: TXT, item_id: "i_2", kind: "text", name: "n.txt", path: "n.txt", version: "b" * 64,
                         scope: "whole", text: "words", result: %({"status":"looked","observation_id":"#{TXT}"}))
      ledger.bind(words, "c2")
      sent_body = { "messages" => build([tool("c2")]) }
      expect(post(sent_body, model: "text-only")).to eq(ok)
      expect(state_of(TXT)).to eq("sent")
    end

    # What the body's text says does not decide: the looks a helper put in
    # a request of the reply do.
    {
      "the ids in it were masked" => ->(text) { text.gsub(/look_[0-9a-f]{16}/, "[MASKED]") },
      "the captions were rewritten" => ->(text) { text.gsub(/The image below is [^"]*/, "An image") },
      "it is a copy of it" => ->(text) { text }
    }.each do |what, change|
      it "checks a body that holds looks when #{what}" do
        sent_body = JSON.parse(change.call(JSON.generate(body)))
        session[Monadic::History::Policy::SESSION_KEY] = Monadic::History::Policy::PRIVATE
        posted = false
        expect { post(sent_body) { posted = true } }.to raise_error(Monadic::Workbench::Look::Withheld)
        expect(posted).to be(false)
      end
    end

    it "does not send a body that holds looks after they were let go, also once their ledger is gone" do
      sent_body = body
      Monadic::Workbench::Look::Ledger.take(request_id)
      expect { post(sent_body) }.to raise_error(Monadic::Workbench::Look::Withheld, /let go/)
      Monadic::Workbench::Look::Ledger.reset!
      expect { post(sent_body) }.to raise_error(Monadic::Workbench::Look::Withheld, /let go/)
    end

    it "posts as before when the request holds no look" do
      looks
      expect(post({ "messages" => [{ "role" => "user", "content" => "hi" }] })).to eq(ok)
    end
  end

  describe "the tools offered" do
    it "leaves no tool list and no tool choice when the look was the only tool and is not offered" do
      allow(Monadic::Utils::ModelSpec).to receive(:tool_capability?).and_return(true)
      body = { "tools" => [{ "function_declarations" => [{ "name" => "look_at_workbench" }] }],
               "tool_choice" => "auto" }
      helper.offer_tools!(body, session, "App", provider: "gemini", model: "text-only")
      expect(body).not_to have_key("tools")
      expect(body).not_to have_key("tool_choice")
      expect(Monadic::Utils::ToolDispatchGuard.allowed?(session, "App", "look_at_workbench")).to be(false)
    end
  end

  describe "logs" do
    it "name what a look read instead of writing it" do
      looks
      result = Monadic::Workbench::Look::Result.new(observation_id: TXT, text: "secret words")
      expect(helper.workbench_loggable(result)).to eq("[look_at_workbench result #{TXT}]")
      body = build([tool("c1"), tool("c2", %({"status":"looked","observation_id":"#{TXT}","text":"secret words"}))])
      logged = JSON.generate(helper.workbench_loggable(body))
      expect(logged).not_to include(Base64.strict_encode64(png))
      expect(logged).not_to include("secret words")
      expect(logged).to include(IMG)
    end
  end
end
