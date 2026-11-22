# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"
require_relative "../../../../lib/monadic/adapters/vendors/ollama_helper"
require_relative "../../../../lib/monadic/adapters/vendors/cohere_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"

# What every provider's reader of a streamed reply does, whatever the chunks
# the reply arrives in: the text comes whole, every call of a round is run,
# and an error inside the stream ends the reply as that error with no tool run.
require_relative "../../../support/stream_contract"

RSpec.describe "Reading a streamed reply (every provider)" do
  def sse(objects)
    objects.map { |o| "data: #{JSON.generate(o)}\n\n" }.join
  end

  def chunked(stream, size)
    stream.b.bytes.each_slice(size).map { |s| s.pack("C*") }
  end

  def call_names(tools)
    Array(tools).map { |t| t["name"] || t.dig("function", "name") || t.dig(:function, :name) }
  end

  # name => [format, stream encoder, reader]. A reader takes the chunks and
  # returns [text shown, names of the calls run, error shown or nil].
  def self.readers
    {
      "OpenAI Chat Completions" => [StreamContract::ChatCompletions, :sse, lambda do |spec, chunks|
        spec.read_with(OpenAIHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "OpenAI Responses" => [StreamContract::Responses, :sse, lambda do |spec, chunks|
        spec.read_with(OpenAIHelper, chunks) do |helper, session, res, sink|
          helper.process_responses_api_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "DeepSeek" => [StreamContract::ChatCompletions, :sse, lambda do |spec, chunks|
        spec.read_with(DeepSeekHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "Gemini" => [StreamContract::Gemini, :sse, lambda do |spec, chunks|
        spec.read_with(GeminiHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "Cohere" => [StreamContract::Cohere, :ndjson, lambda do |spec, chunks|
        spec.read_with(CohereHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "Claude" => [StreamContract::Claude, :sse, lambda do |spec, chunks|
        spec.read_with(ClaudeHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "Grok" => [StreamContract::Responses, :sse, lambda do |spec, chunks|
        spec.read_with(GrokHelper, chunks) do |helper, session, res, sink|
          helper.process_responses_api_data(app: "SpecApp", session: session, query: {}, res: res, call_depth: 0, &sink)
        end
      end],
      "Ollama" => [StreamContract::Ollama, :ndjson, lambda do |spec, chunks|
        spec.read_with(OllamaHelper, chunks) do |helper, session, res, sink|
          helper.process_json_data("SpecApp", session, res, 0, &sink)
        end
      end],
      "Mistral" => [StreamContract::ChatCompletions, :sse, ->(spec, chunks) { spec.read_mistral(chunks) }]
    }
  end

  # Mistral runs each call itself inside api_request, so the request is
  # made, with the stream as its answer, and a plain answer after a round.
  def read_mistral(chunks)
    helper = Class.new(MonadicApp) { include MistralHelper }.new
    ran = []
    unless @tool_app
      allow(helper).to receive(:invoke_mistral_tool_function) do |_app, _session, _call, name|
        ran << name
        [{ "role" => "tool", "tool_call_id" => "x", "name" => name, "content" => "done" }, false, nil]
      end
    end
    answers = [chunks, [sse(StreamContract::ChatCompletions.text(["ok"])), "data: [DONE]\n\n"]]
    chain = double("http")
    %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
    allow(chain).to receive(:post) do
      lines = answers.shift || answers.last
      body = Object.new.tap { |o| o.define_singleton_method(:each) { |&blk| lines.each { |l| blk.call(l.dup) } } }
      double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
    end
    allow(HTTP).to receive(:headers).and_return(chain)
    allow(HTTP).to receive(:timeout).and_return(chain)
    stub_const("CONFIG", { "MISTRAL_API_KEY" => "k" })
    stub_const("APPS", { "SpecApp" => double("app", settings: {}) }) unless @tool_app
    session = new_session
    session[:parameters].merge!("model" => "mistral-medium-latest", "message" => "Go",
                                "context_size" => "5", "max_tokens" => "1000", "temperature" => "0.5")
    session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
    @session = session
    shown = +""
    error = nil
    @reply = helper.api_request("user", session) do |e|
      next unless e.is_a?(Hash)

      shown << e["content"].to_s if e["type"] == "fragment" && ran.empty?
      error = e["content"] if e["type"] == "error"
    end
    [shown, ran, error]
  end

  # @tool_app: when set, the round runs the app's real tools (the stream's
  # calls are offered to it) and the reply the helper returned is kept.
  def read_with(helper_module, chunks)
    helper = Class.new(MonadicApp) { include helper_module }.new
    ran = nil
    unless @tool_app
      allow(helper).to receive(:process_functions) do |*args|
        ran = args[2]
        [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }]
      end
    end
    allow(helper).to receive(:api_request).and_return([]) if @tool_app
    session = new_session
    @session = session
    shown = +""
    error = nil
    sink = proc do |e|
      next unless e.is_a?(Hash)

      shown << e["content"].to_s if e["type"] == "fragment"
      error = e["content"] if e["type"] == "error"
    end
    @reply = yield(helper, session, chunks, sink)
    [shown, call_names(ran), error]
  end

  def new_session
    session = { parameters: { "app_name" => "SpecApp", "model" => "m" }, messages: [], call_depth_per_turn: 0 }
    return session unless @tool_app

    session[Monadic::Workspace::Chats::SESSION_KEY] = @chat
    Monadic::Utils::ToolDispatchGuard.record!(session, "SpecApp", StreamContract::CALLS.map { |name, _| { "name" => name } })
    session
  end

  def encode(kind, objects)
    kind == :ndjson ? objects.map { |o| "#{JSON.generate(o)}\n" }.join : sse(objects)
  end

  readers.each do |name, (format, kind, reader)|
    describe name do
      [1, 3, 64, 1_000_000].each do |size|
        it "shows the whole text with chunks of #{size} bytes" do
          shown, = reader.call(self, chunked(encode(kind, format.text(StreamContract::TEXT)), size))
          expect(shown).to eq(StreamContract::TEXT.join)
        end

        it "runs every call of a round with chunks of #{size} bytes" do
          _shown, ran, = reader.call(self, chunked(encode(kind, format.calls(StreamContract::CALLS)), size))
          expect(ran).to eq(StreamContract::CALLS.map(&:first))
        end
      end

      it "ends the reply as the stream's error and runs no call that came before it" do
        stream = encode(kind, format.calls(StreamContract::CALLS).first(1) + [format.error(StreamContract::ERROR)])
        _shown, ran, error = reader.call(self, [stream])
        expect(ran).to be_empty
        expect(error).to include(StreamContract::ERROR)
      end
    end
  end

  # A tool that put an image on the work screen for this reply.
  class OfferApp
    attr_reader :ran

    def initialize(offer)
      @offer = offer
      @ran = []
    end

    def settings
      { "tools" => StreamContract::CALLS.map do |name, _|
        { "type" => "function", "function" => { "name" => name, "parameters" => { "type" => "object", "properties" => {} } } }
      end }
    end

    def first_tool(**)
      @ran << "first_tool"
      @offer
    end

    def second_tool(**)
      @ran << "second_tool"
      "done"
    end
  end

  readers.each do |name, (format, kind, reader)|
    it "#{name}: ends the reply with the image a call put on the work screen, and runs no other call" do
      @chat = Monadic::Workspace::Ids.generate(:chat)
      request = Monadic::Workspace::RequestContext.new(chat_id: @chat)
      offer = Monadic::Workbench::Offered.new(chat_id: @chat, request_id: request.request_id, item_id: "i_1",
                                              path: "image.png", entry: { "id" => "a_1" })
      @tool_app = OfferApp.new(offer)
      stub_const("APPS", { "SpecApp" => @tool_app })
      stub_const("CONFIG", CONFIG.merge("MISTRAL_API_KEY" => "k")) if name == "Mistral"
      Monadic::Workspace::RequestContext.with(request) do
        reader.call(self, [encode(kind, format.calls(StreamContract::CALLS))])
      end
      expect(@tool_app.ran).to eq(["first_tool"])
      expect(Monadic::Workbench::Offer.ended_reply?(@reply)).to be(true)
    end
  end

  # Tools that each made an image for the model (a screenshot).
  class ImageApp < OfferApp
    def first_tool(**)
      @ran << "first_tool"
      { _image: "first.png", saved: true }
    end

    def second_tool(**)
      @ran << "second_tool"
      { _image: "second.png", saved: true }
    end
  end

  readers.each do |name, (format, kind, reader)|
    # DeepSeek's API takes no images.
    next if name == "DeepSeek"

    it "#{name}: gives the model the images of every call of a round" do
      @chat = Monadic::Workspace::Ids.generate(:chat)
      @tool_app = ImageApp.new(nil)
      stub_const("APPS", { "SpecApp" => @tool_app })
      stub_const("CONFIG", CONFIG.merge("MISTRAL_API_KEY" => "k")) if name == "Mistral"
      allow(Monadic::Utils::ToolImageUtils).to receive(:encode_image_for_api) do |file|
        { media_type: "image/png", base64_data: "IMAGE_OF_#{File.basename(file, '.png').upcase}" }
      end
      allow(OllamaHelper).to receive(:fetch_model_capabilities).and_return({ capabilities: %w[completion tools vision] })
      reader.call(self, [encode(kind, format.calls(StreamContract::CALLS))])
      # Sent with the results, or waiting to go with the next request.
      sent = @session[:parameters].inspect
      waiting = Array(@session[:pending_tool_images])
      expect(@tool_app.ran).to eq(%w[first_tool second_tool])
      expect(%w[first second].select { |n| sent.include?("IMAGE_OF_#{n.upcase}") || waiting.include?("#{n}.png") })
        .to eq(%w[first second])
    end
  end

  # A tool that only answers.
  class PlainApp < OfferApp
    def first_tool(**)
      @ran << "first_tool"
      "done"
    end
  end

  it "Mistral: sends a round's thinking back with its calls" do
    @chat = Monadic::Workspace::Ids.generate(:chat)
    @tool_app = PlainApp.new(nil)
    stub_const("APPS", { "SpecApp" => @tool_app })
    stub_const("CONFIG", CONFIG.merge("MISTRAL_API_KEY" => "k"))
    thought = { "id" => "r", "choices" => [{ "index" => 0, "delta" => { "content" => [
      { "type" => "thinking", "thinking" => [{ "type" => "text", "text" => "Look it up first." }] }
    ] } }] }
    read_mistral([sse([thought] + StreamContract::ChatCompletions.calls(StreamContract::CALLS.first(1)))])
    rounds = Array(@session[:parameters]["earlier_tool_rounds"]).map(&:first) + [@session[:parameters]["tool_calls_message"]]
    content = rounds.compact.first["content"]
    expect(content).to include({ "type" => "thinking", "thinking" => [{ "type" => "text", "text" => "Look it up first." }] })
  end
end
