# frozen_string_literal: true

require_relative "../../spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require_relative "../../../lib/monadic/utils/tts_text_extractor"
require_relative "../../../lib/monadic/utils/websocket"
require_relative "../../../lib/monadic/workspace"
require_relative "../../../lib/monadic/shared_tools/workbench_tools"
require_relative "../../../lib/monadic/workbench/look/availability"
require "base64"

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
  # The tool the made-up replies call (a test may name another).
  define_method(:called_tool) { @called_tool || called_tool }
  # The arguments the made-up replies give the tool they call.
  def called_args = (@tool_args || {})[called_tool] || {}

  def sse(events, named: false)
    events.map { |e| (named ? "event: #{e['type']}\n" : "") + "data: #{JSON.generate(e)}\n\n" }.join
  end

  def responses_stream(call)
    if call
      item = { "type" => "function_call", "id" => "fc_#{called_tool}", "call_id" => "c_#{called_tool}", "name" => called_tool,
               "arguments" => JSON.generate(called_args) }
      return sse([{ "type" => "response.output_item.added", "item" => item.merge("arguments" => "") },
                  { "type" => "response.output_item.done", "item" => item },
                  { "type" => "response.completed", "response" => { "id" => "r1", "output" => [item] } }], named: true)
    end
    sse([{ "type" => "response.output_text.delta", "item_id" => "m1", "delta" => "Done." },
         { "type" => "response.output_text.done", "item_id" => "m1", "text" => "Done." },
         { "type" => "response.completed", "response" => { "id" => "r2" } }], named: true)
  end

  def responses_reply(call)
    if call
      item = { "type" => "function_call", "id" => "fc_#{called_tool}", "call_id" => "c_#{called_tool}", "name" => called_tool,
               "arguments" => JSON.generate(called_args) }
      return JSON.generate({ "output" => [item] })
    end
    JSON.generate({ "output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "Done." }] }] })
  end

  def chat_stream(call)
    delta = if call
              { "tool_calls" => [{ "index" => 0, "id" => "c_#{called_tool}", "type" => "function",
                                   "function" => { "name" => called_tool, "arguments" => JSON.generate(called_args) } }] }
            else
              { "content" => "Done." }
            end
    sse([{ "id" => "x", "choices" => [{ "index" => 0, "delta" => { "role" => "assistant" }.merge(delta), "finish_reason" => nil }] },
         { "id" => "x", "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => call ? "tool_calls" : "stop" }] }]) +
      "data: [DONE]\n\n"
  end

  def claude_stream(call)
    block, delta = if call
                     [{ "type" => "tool_use", "id" => "t_#{called_tool}", "name" => called_tool, "input" => {} },
                      { "type" => "input_json_delta", "partial_json" => JSON.generate(called_args) }]
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
    part = call ? { "functionCall" => { "name" => called_tool, "args" => called_args } } : { "text" => "Done." }
    "[#{JSON.pretty_generate({ 'candidates' => [{ 'content' => { 'role' => 'model', 'parts' => [part] },
                                                  'finishReason' => 'STOP' }] })}\n]"
  end

  def cohere_stream(call)
    events = [{ "type" => "message-start", "delta" => { "message" => { "role" => "assistant" } } }]
    events += if call
                [{ "type" => "tool-call-start",
                   "delta" => { "message" => { "tool_calls" => { "id" => "c_#{called_tool}", "type" => "function",
                                                                 "function" => { "name" => called_tool, "arguments" => "" } } } } },
                 { "type" => "tool-call-delta",
                   "delta" => { "message" => { "tool_calls" => { "function" => { "arguments" => JSON.generate(called_args) } } } } },
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
                { "role" => "assistant", "content" => "", "tool_calls" => [{ "function" => { "name" => called_tool, "arguments" => called_args } }] }
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
      double(status: HTTP::Response::Status.new(200), body: reply_body(replies.shift), headers: {})
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
      double(status: HTTP::Response::Status.new(200), body: reply_body(replies.shift), headers: {})
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

  # The work screen observation: two messages sent through the page's
  # handler with a file open on the workbench and selected in the tab.
  def run_observed_conversation(mod, provider, key, first_reply, second_reply, first_message: "Define it", images: nil,
                                vision: false, shown_file: ["notes.txt", "one\ntwo\n"], look: false,
                                takes_images: true, chain: nil, reset_after_tool: false, browser: false)
    dir = Dir.mktmpdir("observation-body-")
    data = File.join(dir, "data")
    FileUtils.mkdir_p([data, File.join(dir, "state")])
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(File.join(dir, "state"))
    allow(Monadic::Workbench::Store).to receive(:default).and_return(Monadic::Workbench::Store.new(File.join(dir, "state", "workbench")))
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(tab) { tab == "tab-1" ? 1 : nil }
    Thread.current[:websocket_session_id] = "tab-1"
    chat = Monadic::Workspace::Ids.generate(:chat)
    File.binwrite(File.join(data, shown_file[0]), shown_file[1])
    item, = if browser
              # The chat's browser, selected in the tab (its picture is the test's).
              Monadic::Workbench::Board.for(chat).add_browser(
                instance: "inst-1", origin: { actor: :agent, source: :browser, tab: "tab-1", generation: 1 },
                epoch: Monadic::Workspace::Chats.epoch(chat)
              )
            else
              Monadic::Workbench::Board.for(chat).add_file(
                path: shown_file[0], origin: { actor: :user, source: :panel, tab: "tab-1", generation: 1 },
                epoch: Monadic::Workspace::Chats.epoch(chat)
              )
            end

    models = Monadic::Utils::ModelSpec.get_provider_models(provider, "chat") || []
    model = (vision ? models.find { |m| Monadic::Utils::ModelSpec.get_model_property(m, "vision_capability") } : models.first) ||
            "llama3"
    names = [reader_tool_name, *(chain || [called_tool]), *(look ? ["look_at_workbench"] : [])].uniq
    tools = names.map { |name| tool_definition(name) }
    calls = @tool_calls
    # The chat the tool runs in (it may be reset while the reply goes on).
    held = {}
    tool_owner = Module.new do
      define_method(:look_up_term) do |**|
        calls << :ran
        if reset_after_tool
          chat = held[:session][:chat_id]
          Monadic::Workspace::Chats::EPOCHS_LOCK.synchronize { Monadic::Workspace::Chats::EPOCHS[chat] += 1 }
        end
        "term found"
      end
    end
    stub_const("CONFIG", key ? { key => "k" } : {})
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with(Monadic::Utils::CapabilityNotes::FLAG).and_return("OtherApp")
    app = Class.new(MonadicApp) { include mod }.new
    app.extend(tool_owner)
    app.extend(MonadicSharedTools::WorkbenchTools) if look
    app_settings = { "provider" => provider, "tools" => tools }
    app.define_singleton_method(:settings) { app_settings }
    stub_const("APPS", { "NotesApp" => app })
    allow(app).to receive(:sleep)
    bodies = []
    replies = []
    answer = lambda do |body|
      bodies << JSON.parse(JSON.generate(body))
      double(status: HTTP::Response::Status.new(200), body: reply_body(replies.shift), headers: {})
    end
    http = double("http")
    allow(http).to receive(:timeout).and_return(http)
    allow(http).to receive(:headers).and_return(http)
    allow(http).to receive(:post) { |_uri, json: nil, **| answer.call(json) }
    allow(HTTP).to receive(:headers).and_return(http)
    allow(HTTP).to receive(:timeout).and_return(http)
    # The real retry loop posts through the fake client: each post is checked
    # for what it holds of the work screen.
    if mod == OllamaHelper
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://ollama.invalid")
      allow(app).to receive(:list_models).and_return([model])
      # The local server's own report of the model: it takes images when
      # the test asks for a model that does.
      allow(OllamaHelper).to receive(:fetch_model_capabilities)
        .and_return(look && takes_images ? { capabilities: %w[tools vision] } : nil)
    end

    host = Class.new { include WebSocketHelper }.new
    allow(host).to receive(:send_or_broadcast)
    allow(host).to receive(:initialize_token_counting).and_return(nil)
    allow(host).to receive(:sts_session_capable?).and_return(false)
    allow(host).to receive(:detect_language).and_return("en")
    session = { parameters: {}, chat_id: chat, _ws_generation: 1,
                messages: [{ "role" => "system", "text" => "S", "active" => true }] }
    held[:session] = session
    page = { "app_name" => "NotesApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
             "tools" => tools.to_json, "temperature" => "0.5", "prompt_suffix" => "Answer briefly." }
    app_settings["prompt_suffix"] = "Answer briefly."
    # As the page says of a model that takes images.
    page["vision_capability"] = true if vision
    shown = { "item_id" => item["id"], "version" => item.dig("file", "sha256"), "range" => nil, "note" => "not_shown" }
    queue = Queue.new
    Thread.current[:rack_session] = session
    # As when the page's connection opens: its work is the chat's.
    Monadic::Utils::Privacy::EgressGuard.for_chat(session)
    # The tools the first message's reply calls, one request each, then
    # its answer.
    first_turn = (chain || [called_tool]).each_with_index.map do |name, at|
      @called_tool = name
      # A request after a tool's result is answered as the provider answers
      # those (Grok: not streamed).
      send(at.zero? ? first_reply : second_reply, true)
    end
    [[first_message, images, first_turn + [send(second_reply, false)]],
     ["And the next one", nil, [send(second_reply, false)]]].each do |message, sent_images, turn_replies|
      replies.push(*turn_replies)
      sent = page.merge("message" => message, "workbench_range" => shown)
      sent["images"] = sent_images if sent_images
      thread = host.send(:handle_ws_streaming, nil, sent, session, queue)
      host.send(:handle_ws_html, nil, { "type" => "HTML" }, session, thread, queue)
    end
    [bodies, session, item]
  ensure
    Monadic::Utils::Privacy::EgressGuard.for_chat(nil)
    Thread.current[:rack_session] = nil
    Thread.current[:websocket_session_id] = nil
    Monadic::Workbench::Board.reset!
    FileUtils.rm_rf(dir) if dir
  end

  observation_tag = "<work_screen_observation>"

  # A PNG of one pixel.
  pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

  # The model looks at the image selected in the work screen: the image
  # goes in the request that returns the tool's result, after it, and in no
  # other request; the chat keeps a record of the look and no bytes.
  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: gives the model the image it looked at, after the result, once" do
      @called_tool = "look_at_workbench"
      bodies, session, item = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                        shown_file: ["shot.png", Base64.decode64(pixel)],
                                                        look: true, vision: true)
      expect(JSON.generate(bodies.first)).to include("look_at_workbench")
      expect(bodies.size).to eq(3)
      expect(bodies.map { |b| JSON.generate(b).scan(pixel[0, 40]).size }).to eq([0, 1, 0])
      after_tool = JSON.generate(bodies[1])
      expect(after_tool.index(pixel[0, 40])).to be > after_tool.index("observation_id")
      expect(after_tool).to include(item.dig("file", "sha256")[0, 12])
      expect(JSON.generate(session[:messages])).not_to include(pixel[0, 40])
      reply = session[:messages].find { |m| m["role"] == "assistant" }
      expect(reply["workbench_looks"]).to match([a_hash_including("kind" => "image", "name" => "shot.png", "state" => "sent")])
      expect(JSON.generate(session[:parameters])).not_to include(pixel[0, 40])
    end
  end

  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: keeps the image it looked at in the next request of the reply, after another tool" do
      logs = []
      allow(Monadic::Utils::ExtraLogger).to receive(:enabled?).and_return(true)
      allow(Monadic::Utils::ExtraLogger).to receive(:log) { |msg = nil, &blk| logs << (blk ? blk.call : msg).to_s }
      allow(Monadic::Utils::ExtraLogger).to receive(:log_json) { |label, data| logs << "#{label} #{JSON.generate(data)}" }
      allow(DebugHelper).to receive(:debug) { |msg, **| logs << msg.to_s }
      bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                   shown_file: ["shot.png", Base64.decode64(pixel)], look: true,
                                                   vision: true, chain: ["look_at_workbench", called_tool])
      expect(@tool_calls).to eq([:ran])
      expect(bodies.size).to eq(4)
      expect(bodies.map { |b| JSON.generate(b).scan(pixel[0, 40]).size }).to eq([0, 1, 1, 0])
      expect(JSON.generate(bodies[2])).to include("term found")
      reply = session[:messages].find { |m| m["role"] == "assistant" }
      expect(reply["workbench_looks"]).to match([a_hash_including("state" => "sent")])
      # Nor does its image reach a log.
      expect(logs.join("\n")).not_to include(pixel[0, 40])
    end
  end

  # The chat is reset after the image went to the model, while the reply
  # goes on: no later request of the reply is sent with it, whatever its
  # text says of the look.
  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: sends no later request of the reply holding the image once the chat is reset" do
      bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                   shown_file: ["shot.png", Base64.decode64(pixel)], look: true,
                                                   vision: true, chain: ["look_at_workbench", called_tool],
                                                   reset_after_tool: true)
      expect(@tool_calls.first).to eq(:ran)
      expect(bodies.map { |b| JSON.generate(b).scan(pixel[0, 40]).size }.first(2)).to eq([0, 1])
      expect(bodies.drop(2).map { |b| JSON.generate(b) }).to all(satisfy { |text| !text.include?(pixel[0, 40]) })
      looks = session[:messages].filter_map { |m| m["workbench_looks"] }.flatten
      expect(looks).to match([a_hash_including("state" => "sent")])
    end
  end

  # A look at a PDF gives the part of the page in view (an image the tab
  # cut), the page's text and the selected text together: each request of
  # the reply after it holds the image and the texts, once, and no log
  # holds any of them.
  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: keeps a PDF look's image and texts in the requests of the reply after it, and out of the logs" do
      logs = []
      allow(Monadic::Utils::ExtraLogger).to receive(:enabled?).and_return(true)
      allow(Monadic::Utils::ExtraLogger).to receive(:log) { |msg = nil, &blk| logs << (blk ? blk.call : msg).to_s }
      allow(Monadic::Utils::ExtraLogger).to receive(:log_json) { |label, data| logs << "#{label} #{JSON.generate(data)}" }
      allow(DebugHelper).to receive(:debug) { |msg, **| logs << msg.to_s }
      page_text = "PAGE-TEXT-#{SecureRandom.hex(4)}"
      selected = "SELECTED-#{SecureRandom.hex(4)}"
      allow(Monadic::Workbench::PdfText).to receive(:extract).and_return(
        Monadic::Workbench::PdfText::Pages.new(pages: [{ page: 1, text: page_text, cut: false }], total_pages: 1,
                                               stopped_at: nil)
      )
      capture = Monadic::Workbench::Capture
      transport = capture.transport
      capture.transport = lambda do |_tab, _generation, _chat, json|
        id = JSON.parse(json)["id"]
        answer = { "range" => { "page" => 1, "pages" => 1 }, "note" => nil, "image" => pixel,
                   "crop" => { "x" => 0, "y" => 0, "width" => 10, "height" => 10, "sent_width" => 1, "sent_height" => 1 },
                   "selection_text" => selected }
        Thread.new { capture.reading(id, 2) { answer } }
        true
      end
      begin
        bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                     shown_file: ["paper.pdf", "%PDF-1.4\n%%EOF\n"], look: true,
                                                     vision: true, chain: ["look_at_workbench", called_tool])
      ensure
        capture.transport = transport
      end
      expect(bodies.size).to eq(4)
      texts = bodies.map { |b| JSON.generate(b) }
      expect(texts.map { |t| t.scan(pixel[0, 40]).size }).to eq([0, 1, 1, 0])
      expect(texts[1]).to include(page_text, selected)
      expect(texts[2]).to include(page_text, selected)
      reply = session[:messages].find { |m| m["role"] == "assistant" }
      expect(reply["workbench_looks"]).to match([a_hash_including("kind" => "pdf", "image" => true, "state" => "sent",
                                                                   "source" => "workbench_capture")])
      expect(JSON.generate(session[:messages])).not_to include(page_text, selected)
      all_logs = logs.join("\n")
      expect(all_logs).not_to include(pixel[0, 40])
      expect(all_logs).not_to include(page_text)
      expect(all_logs).not_to include(selected)
    end
  end

  # A look at the chat's browser gives a picture of its viewport: it goes
  # in the request that returns the tool's result, once, and the chat keeps
  # the page's title and address without its query.
  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: gives the model a picture of the browser it looked at, once" do
      @called_tool = "look_at_workbench"
      allow(Monadic::WorkScreen).to receive(:available?).and_return(true)
      allow(MonadicSharedTools::BrowserOwner).to receive(:view) do |chat|
        MonadicSharedTools::BrowserOwner::View.new(chat, Monadic::Workspace::Chats.epoch(chat), "inst-1", "sess-1", "W1")
      end
      allow_any_instance_of(Monadic::WorkScreen::BrowserBinding).to receive(:broken).and_return(nil)
      allow(Monadic::WorkScreen::Snapshot).to receive(:take).and_return(
        { png: Base64.decode64(pixel), url: "https://example.com/page?token=SECRET", title: "Example page",
          crop: { "x" => 0, "y" => 0, "width" => 10, "height" => 10, "sent_width" => 1, "sent_height" => 1 } }
      )
      bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply, look: true,
                                                                                                  vision: true, browser: true)
      expect(bodies.size).to eq(3)
      expect(bodies.map { |b| JSON.generate(b).scan(pixel[0, 40]).size }).to eq([0, 1, 0])
      expect(JSON.generate(bodies[1])).to include("https://example.com/page")
      expect(JSON.generate(bodies)).not_to include("SECRET")
      reply = session[:messages].find { |m| m["role"] == "assistant" }
      expect(reply["workbench_looks"]).to match([a_hash_including("kind" => "browser", "source" => "workbench_browser",
                                                                   "name" => "Example page", "state" => "sent")])
    end
  end

  # What a look read reaches no log: the logs of a whole conversation (an
  # image look, a text look, another tool, the answer, the next message)
  # name the looks and hold none of what they read.
  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: writes nothing a look read to the logs" do
      logs = []
      allow(Monadic::Utils::ExtraLogger).to receive(:enabled?).and_return(true)
      allow(Monadic::Utils::ExtraLogger).to receive(:log) { |msg = nil, &blk| logs << (blk ? blk.call : msg).to_s }
      allow(Monadic::Utils::ExtraLogger).to receive(:log_json) { |label, data| logs << "#{label} #{JSON.generate(data)}" }
      allow(DebugHelper).to receive(:debug) { |msg, **| logs << msg.to_s }
      @tool_args = { "look_at_workbench" => { "scope" => "whole" } }
      secret = "SECRET-LOOK-TEXT-#{SecureRandom.hex(4)}"
      bodies, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                          shown_file: ["notes.txt", "#{secret}\n"], look: true, vision: true,
                                          chain: ["look_at_workbench", called_tool])
      expect(JSON.generate(bodies[1])).to include(secret)
      expect(logs).not_to be_empty
      expect(logs.join("\n")).not_to include(secret)
    end
  end

  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: does not offer the look to a model not known to take images, and does not run it when called" do
      @called_tool = "look_at_workbench"
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).with(anything, "vision_capability").and_return(nil)
      bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                   shown_file: ["shot.png", Base64.decode64(pixel)], look: true,
                                                   takes_images: false)
      expect(JSON.generate(bodies.first)).not_to include("look_at_workbench")
      expect(bodies.map { |b| JSON.generate(b) }.join).not_to include(pixel[0, 40])
      expect(session[:messages].map { |m| m["workbench_looks"] }.compact).to be_empty
    end
  end

  providers.each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: adds what the work screen shows to the user's message once in each request, and keeps it out of the chat" do
      bodies, session, item = run_observed_conversation(mod, provider, key, first_reply, second_reply)
      expect(@tool_calls).to eq([:ran])
      expect(bodies.size).to eq(3)
      counts = bodies.map { |body| JSON.generate(body).scan(observation_tag).size }
      expect(counts).to eq([1, 1, 1])
      # The request that returns the tool's result keeps the user's message
      # before the result.
      after_tool = JSON.generate(bodies[1])
      expect(after_tool.index("Define it")).to be < after_tool.index("term found")
      bodies.each do |body|
        expect(system_text(body)).not_to include(observation_tag)
      end
      first = JSON.generate(bodies.first)
      expect(first.index(observation_tag)).to be > first.index("Define it")
      # A suffix the app adds to the message does not take its place.
      expect(first.scan("Answer briefly.").size).to be <= 1
      expect(first).to include(item["id"], "not_shown")
      # The next message's request carries only that message's observation,
      # after its text.
      last = JSON.generate(bodies.last)
      expect(last.index(observation_tag)).to be > last.index("And the next one")
      expect(JSON.generate(session[:messages])).not_to include("work_screen")
      expect(session[:parameters]).not_to have_key("workbench_range")
    end
  end

  providers.slice(OpenAIHelper, ClaudeHelper, GeminiHelper, OllamaHelper, CohereHelper).each do |mod, (provider, key, first_reply, second_reply)|
    it "#{mod.name}: adds what the work screen shows to a message of an image only, recorded under its request" do
      image = { "title" => "dot.png", "type" => "image/png", "data" => "data:image/png;base64,#{pixel}" }
      bodies, session, = run_observed_conversation(mod, provider, key, first_reply, second_reply,
                                                   first_message: "", images: [image], vision: true)
      expect(bodies.size).to eq(3)
      expect(bodies.map { |body| JSON.generate(body).scan(observation_tag).size }).to eq([1, 1, 1])
      expect(JSON.generate(bodies.first)).to include(pixel[0, 40])
      # The request that returns the tool's result keeps the image too.
      expect(JSON.generate(bodies[1])).to include(pixel[0, 40])
      first_turn = session[:messages].find { |m| m["role"] == "user" }
      expect(first_turn["request_id"]).to match(/\Aq_/)
      expect(JSON.generate(session[:messages])).not_to include("work_screen")
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
