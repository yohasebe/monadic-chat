# frozen_string_literal: true

require_relative "../../spec_helper"
require "json"
require_relative "../../../lib/monadic/utils/tts_text_extractor"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"

# Run by spec/unit/adapters/vendors/capability_notes_request_body_spec.rb in a
# process of its own (no config file, network stopped), not as a unit spec.
#
# The capability note goes into the system prompt each provider is sent:
# once in the request for the user's message and once in the request that
# returns a tool's result, and not at all when the app is not named in the
# flag. Sent through the page's WebSocket handler, it is in each request of
# a conversation once, and never in the recorded chat. The provider's replies
# are made up here (a tool call, then text); each request stops at the HTTP
# client.
RSpec.describe "Capability note in the request body" do
  header = "## What your tools can do now"
  suffix = "Suffix of this app."
  reader_tool = "fetch_text_from_pdf"
  called_tool = "look_up_term"

  providers = {
    OpenAIHelper => ["openai", "OPENAI_API_KEY", :responses_stream, :responses_stream],
    ClaudeHelper => ["anthropic", "ANTHROPIC_API_KEY", :claude_stream, :claude_stream],
    GeminiHelper => ["gemini", "GEMINI_API_KEY", :gemini_stream, :gemini_stream],
    GrokHelper => ["xai", "XAI_API_KEY", :responses_stream, :responses_reply],
    MistralHelper => ["mistral", "MISTRAL_API_KEY", :chat_stream, :chat_stream],
    CohereHelper => ["cohere", "COHERE_API_KEY", :cohere_stream, :cohere_stream],
    DeepSeekHelper => ["deepseek", "DEEPSEEK_API_KEY", :chat_stream, :chat_stream],
    OllamaHelper => ["ollama", nil, :ollama_stream, :ollama_stream]
  }

  # A reply body: read whole, or as one chunk.
  reply_body = Class.new do
    def initialize(text) = (@text = text)
    def each = yield(@text.dup)
    def to_s = @text.dup
    alias_method :to_str, :to_s
  end

  define_method(:reply_body) { |text| reply_body.new(text) }
  define_method(:suffix) { suffix }

  # The system prompt of a request body, in each provider's place for it.
  def system_text(body)
    parts = [body["instructions"], body["system"], body.dig("systemInstruction", "parts"),
             *Array(body["messages"] || body["input"]).select { |m| %w[system developer].include?(m["role"]) }
                                                         .map { |m| m["content"] }]
    flatten_text(parts)
  end

  def flatten_text(value)
    case value
    when String then value
    when Array then value.map { |v| flatten_text(v) }.reject(&:empty?).join("\n")
    when Hash then flatten_text(value["text"])
    else ""
    end
  end
  define_method(:called_tool) { called_tool }

  def sse(events, named: false)
    events.map { |e| (named ? "event: #{e['type']}\n" : "") + "data: #{JSON.generate(e)}\n\n" }.join
  end

  def responses_stream(call)
    if call
      item = { "type" => "function_call", "id" => "fc1", "call_id" => "c1", "name" => called_tool, "arguments" => "{}" }
      return sse([{ "type" => "response.output_item.added", "item" => item.merge("arguments" => "") },
                  { "type" => "response.output_item.done", "item" => item },
                  { "type" => "response.completed", "response" => { "id" => "r1", "output" => [item] } }], named: true)
    end
    sse([{ "type" => "response.output_text.delta", "item_id" => "m1", "delta" => "Done." },
         { "type" => "response.output_text.done", "item_id" => "m1", "text" => "Done." },
         { "type" => "response.completed", "response" => { "id" => "r2" } }], named: true)
  end

  def responses_reply(_call)
    JSON.generate({ "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "Done." }] }] })
  end

  def chat_stream(call)
    delta = if call
              { "tool_calls" => [{ "index" => 0, "id" => "c1", "type" => "function",
                                   "function" => { "name" => called_tool, "arguments" => "{}" } }] }
            else
              { "content" => "Done." }
            end
    sse([{ "id" => "x", "choices" => [{ "index" => 0, "delta" => { "role" => "assistant" }.merge(delta), "finish_reason" => nil }] },
         { "id" => "x", "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => call ? "tool_calls" : "stop" }] }]) +
      "data: [DONE]\n\n"
  end

  def claude_stream(call)
    block, delta = if call
                     [{ "type" => "tool_use", "id" => "t1", "name" => called_tool, "input" => {} },
                      { "type" => "input_json_delta", "partial_json" => "{}" }]
                   else
                     [{ "type" => "text", "text" => "" }, { "type" => "text_delta", "text" => "Done." }]
                   end
    sse([{ "type" => "message_start", "message" => { "id" => "m1", "usage" => { "input_tokens" => 1 } } },
         { "type" => "content_block_start", "index" => 0, "content_block" => block },
         { "type" => "content_block_delta", "index" => 0, "delta" => delta },
         { "type" => "content_block_stop", "index" => 0 },
         { "type" => "message_delta", "delta" => { "stop_reason" => call ? "tool_use" : "end_turn" },
           "usage" => { "output_tokens" => 1 } },
         { "type" => "message_stop" }], named: true)
  end

  def gemini_stream(call)
    part = call ? { "functionCall" => { "name" => called_tool, "args" => {} } } : { "text" => "Done." }
    "[#{JSON.pretty_generate({ 'candidates' => [{ 'content' => { 'role' => 'model', 'parts' => [part] },
                                                  'finishReason' => 'STOP' }] })}\n]"
  end

  def cohere_stream(call)
    events = [{ "type" => "message-start", "delta" => { "message" => { "role" => "assistant" } } }]
    events += if call
                [{ "type" => "tool-call-start",
                   "delta" => { "message" => { "tool_calls" => { "id" => "c1", "type" => "function",
                                                                 "function" => { "name" => called_tool, "arguments" => "" } } } } },
                 { "type" => "tool-call-delta", "delta" => { "message" => { "tool_calls" => { "function" => { "arguments" => "{}" } } } } },
                 { "type" => "tool-call-end" },
                 { "type" => "message-end", "delta" => { "finish_reason" => "TOOL_CALL" } }]
              else
                [{ "type" => "content-delta", "delta" => { "message" => { "content" => { "text" => "Done." } } } },
                 { "type" => "message-end", "delta" => { "finish_reason" => "COMPLETE" } }]
              end
    sse(events, named: true)
  end

  def ollama_stream(call)
    message = if call
                { "role" => "assistant", "content" => "", "tool_calls" => [{ "function" => { "name" => called_tool, "arguments" => {} } }] }
              else
                { "role" => "assistant", "content" => "Done." }
              end
    "#{JSON.generate({ 'message' => message, 'done' => true })}\n"
  end

  def tool_definition(name)
    { "type" => "function", "function" => { "name" => name, "description" => "d",
                                            "parameters" => { "type" => "object", "properties" => {} } } }
  end

  # Runs one user message through the provider: a tool call, the tool, then
  # the answer. Returns the request bodies in the order sent.
  def run_message(mod, provider, key, first_reply, second_reply, flag:, request_ids: [nil])
    model = Monadic::Utils::ModelSpec.get_provider_models(provider, "chat")&.first || "llama3"
    tools = [tool_definition(reader_tool_name), tool_definition(called_tool)]
    calls = @tool_calls
    tool_owner = Module.new { define_method(:look_up_term) { |**| calls << :ran && "term found" } }
    app = Struct.new(:settings).new({ "provider" => provider, "tools" => tools })
    app.extend(tool_owner)
    stub_const("APPS", { "NotesApp" => app })
    stub_const("CONFIG", key ? { key => "k" } : {})
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with(Monadic::Utils::CapabilityNotes::FLAG).and_return(flag)

    helper = Class.new(MonadicApp) { include mod }.new
    helper.extend(tool_owner)
    allow(helper).to receive(:sleep)
    bodies = []
    replies = []
    answer = lambda do |body|
      bodies << JSON.parse(JSON.generate(body))
      double(status: HTTP::Response::Status.new(200), body: reply_body(replies.shift))
    end
    http = double("http")
    allow(http).to receive(:timeout).and_return(http)
    allow(http).to receive(:headers).and_return(http)
    allow(http).to receive(:post) { |_uri, json: nil, **| answer.call(json) }
    allow(HTTP).to receive(:headers).and_return(http)
    allow(HTTP).to receive(:timeout).and_return(http)
    allow(helper).to receive(:post_json_with_retries) { |_http, _uri, body, **| answer.call(body) }
    if mod == OllamaHelper
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://ollama.invalid")
      allow(helper).to receive(:list_models).and_return([model])
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return(nil)
    end

    session = { parameters: { "app_name" => "NotesApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                              "message" => "Define it", "tools" => tools.to_json, "temperature" => "0.5",
                              "system_prompt_suffix" => suffix },
                messages: [{ "role" => "system", "text" => "S", "active" => true },
                           { "role" => "user", "text" => "Define it", "active" => true }] }
    request_ids.each do |request_id|
      replies.push(send(first_reply, true), send(second_reply, false))
      context = request_id && Monadic::Workspace::RequestContext.new(chat_id: "c", request_id: request_id)
      Monadic::Workspace::RequestContext.with(context) do
        helper.api_request("user", session) { |_| nil }
      end
    end
    expect(session[:messages].first["text"]).to eq("S")
    bodies
  end

  define_method(:reader_tool_name) { reader_tool }

  before do
    @tool_calls = []
    allow(Monadic::Utils::ContainerProbe).to receive(:check).and_return({ state: :stopped })
  end

  after { Thread.current[Monadic::Utils::CapabilityNotes::THREAD_KEY] = nil }

  providers.each do |mod, (provider, key, first_reply, second_reply)|
    describe mod.name do
      it "puts the note once in the request for the message and once in the one after the tool" do
        bodies = run_message(mod, provider, key, first_reply, second_reply, flag: "NotesApp")
        expect(@tool_calls).to eq([:ran])
        expect(bodies.size).to eq(2)
        bodies.each do |body|
          system = system_text(body)
          expect(system).to start_with("S")
          expect(system.scan(header).size).to eq(1)
          expect(system).to include("Reading documents with #{reader_tool}: not ready")
          expect(system.scan(suffix).size).to eq(1)
          expect(JSON.generate(body).scan(header).size).to eq(1)
        end
        expect(JSON.generate(bodies.last)).to include("term found")
      end

      it "sends no note, and asks no container, when the flag does not name the app" do
        bodies = run_message(mod, provider, key, first_reply, second_reply, flag: "OtherApp")
        expect(@tool_calls).to eq([:ran])
        expect(bodies.size).to eq(2)
        expect(bodies.map { |b| JSON.generate(b) }.join).not_to include(header)
        expect(bodies.map { |b| system_text(b).scan(suffix).size }).to eq([1, 1])
        expect(Monadic::Utils::ContainerProbe).not_to have_received(:check)
      end
    end
  end

  # Two messages sent the way the page sends them: the WebSocket handler
  # records the user's message and starts the request, and the reply is
  # recorded when the page asks for it (HTML), before the next message.
  def run_conversation(mod, provider, key, first_reply, second_reply)
    model = Monadic::Utils::ModelSpec.get_provider_models(provider, "chat")&.first || "llama3"
    tools = [tool_definition(reader_tool_name), tool_definition(called_tool)]
    calls = @tool_calls
    tool_owner = Module.new { define_method(:look_up_term) { |**| calls << :ran && "term found" } }
    stub_const("CONFIG", key ? { key => "k" } : {})
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with(Monadic::Utils::CapabilityNotes::FLAG).and_return("NotesApp")

    app = Class.new(MonadicApp) { include mod }.new
    app.extend(tool_owner)
    app_settings = { "provider" => provider, "tools" => tools }
    app.define_singleton_method(:settings) { app_settings }
    stub_const("APPS", { "NotesApp" => app })
    allow(app).to receive(:sleep)
    bodies = []
    replies = []
    answer = lambda do |body|
      bodies << JSON.parse(JSON.generate(body))
      double(status: HTTP::Response::Status.new(200), body: reply_body(replies.shift))
    end
    http = double("http")
    allow(http).to receive(:timeout).and_return(http)
    allow(http).to receive(:headers).and_return(http)
    allow(http).to receive(:post) { |_uri, json: nil, **| answer.call(json) }
    allow(HTTP).to receive(:headers).and_return(http)
    allow(HTTP).to receive(:timeout).and_return(http)
    allow(app).to receive(:post_json_with_retries) { |_http, _uri, body, **| answer.call(body) }
    if mod == OllamaHelper
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://ollama.invalid")
      allow(app).to receive(:list_models).and_return([model])
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return(nil)
    end

    host = Class.new { include WebSocketHelper }.new
    allow(host).to receive(:send_or_broadcast)
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    session = { parameters: {}, chat_id: Monadic::Workspace::Ids.generate(:chat),
                messages: [{ "role" => "system", "text" => "S", "active" => true }] }
    page = { "app_name" => "NotesApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
             "tools" => tools.to_json, "temperature" => "0.5", "system_prompt_suffix" => suffix }
    queue = Queue.new
    # The connection's session, as the server sets it when the page connects.
    Thread.current[:rack_session] = session
    [["Define it", [send(first_reply, true), send(second_reply, false)]],
     ["And the next one", [send(second_reply, false)]]].each do |message, turn_replies|
      replies.push(*turn_replies)
      thread = host.send(:handle_ws_streaming, nil, page.merge("message" => message), session, queue)
      host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    end
    [bodies, session]
  ensure
    Thread.current[:rack_session] = nil
  end

  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: through the page's handler, puts the note once in each request of two messages and keeps it out of the chat" do
      bodies, session = run_conversation(mod, provider, key, first_reply, second_reply)
      expect(@tool_calls).to eq([:ran])
      expect(bodies.size).to eq(3)
      bodies.each do |body|
        system = system_text(body)
        expect(system).to start_with("S")
        expect(system.scan(header).size).to eq(1)
        expect(system.scan(suffix).size).to eq(1)
        expect(JSON.generate(body).scan(header).size).to eq(1)
      end
      # The second message's request carries the first exchange as history.
      expect(JSON.generate(bodies.last)).to include("Define it", "And the next one")
      expect(JSON.generate(bodies.last).scan("Done.").size).to eq(1)
      expect(session[:messages].map { |m| m["role"] }).to eq(%w[system user assistant user assistant])
      expect(JSON.generate(session[:messages])).not_to include(header)
      expect(session[:messages].first["text"]).to eq("S")
      # The handler runs each message under a request of its own: the
      # container is asked once for each.
      expect(Monadic::Utils::ContainerProbe).to have_received(:check).with(:python).twice
    end
  end

  it "asks the container once for a message, however many requests it takes, and again for the next message" do
    _, (provider, key, first_reply, second_reply) = providers.first
    bodies = run_message(providers.keys.first, provider, key, first_reply, second_reply, flag: "NotesApp",
                         request_ids: %w[first second])
    expect(bodies.size).to eq(4)
    expect(Monadic::Utils::ContainerProbe).to have_received(:check).with(:python).twice
  end
end
