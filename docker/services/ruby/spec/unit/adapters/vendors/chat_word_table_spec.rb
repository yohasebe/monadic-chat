# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"
require_relative "../../../../lib/monadic/adapters/vendors/ollama_helper"
require_relative "../../../../lib/monadic/utils/privacy/words"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/tts_text_extractor"

# A chat with a word table on the vendors whose requests take the shape of
# a chat request (messages with roles, tool calls and tool results): what
# is sent, what a tool is given, and what the reply is put back with.
RSpec.describe "A chat with a word table on a chat-shaped vendor" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:helper) { Class.new { include BaseVendorHelper }.new }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }

  before { table.confirm!("Ada Lovelace", "PERSON") }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  describe "the request body" do
    it "sends a model's reasoning as it wrote it, in a thinking part or beside its text" do
      snapshot = table.snapshot
      budget = Monadic::Utils::Privacy::WordTable::Budget.new
      thinking = { "role" => "assistant", "content" => [
        { "type" => "thinking", "thinking" => [{ "type" => "text", "text" => "<<PERSON_1>> or Ada Lovelace" }] },
        { "type" => "text", "text" => "Ada Lovelace wrote <<PERSON_1>>" }
      ] }
      expect(helper.hide_words_in_item(thinking, snapshot, budget)["content"]).to eq([
        { "type" => "thinking", "thinking" => [{ "type" => "text", "text" => "<<PERSON_1>> or <<PERSON_1>>" }] },
        { "type" => "text", "text" => "<<PERSON_1>> wrote ‹‹PERSON_1››" }
      ])
      reasoning = { "role" => "assistant", "content" => nil, "reasoning_content" => "Ask <<PERSON_1>>, Ada Lovelace",
                    "tool_calls" => [{ "id" => "c1", "type" => "function",
                                       "function" => { "name" => "f", "arguments" => { "who" => "Ada Lovelace" } } }] }
      hidden = helper.hide_words_in_item(reasoning, snapshot, budget)
      expect(hidden["reasoning_content"]).to eq("Ask <<PERSON_1>>, <<PERSON_1>>")
      expect(hidden["content"]).to be_nil
      expect(hidden.dig("tool_calls", 0, "function", "arguments")).to eq("who" => "<<PERSON_1>>")
    end
  end

  shared_examples "a round of tool calls" do |tools_in_parameters: false|
    let(:tools_in_parameters) { tools_in_parameters }
    let(:sent) { [] }
    let(:tool_app) do
      Class.new(MonadicApp) do
        attr_reader :given

        def settings
          { "tools" => %w[read_file_from_shared_folder write_file_to_shared_folder].map do |name|
            { "type" => "function",
              "function" => { "name" => name, "parameters" => { "type" => "object", "properties" => {} } } }
          end }
        end

        def read_file_from_shared_folder(filepath:)
          (@given ||= []) << filepath
          "Notes by Ada Lovelace"
        end

        def write_file_to_shared_folder(filepath:, content:, mode: "write")
          (@given ||= []) << [filepath, content, mode]
          "written"
        end
      end.new
    end

    before do
      stub_const("APPS", { "SpecApp" => tool_app })
      stub_const("CONFIG", config)
      allow(chat).to receive(:sleep)
      session[:parameters] = { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                               "message" => "Read the notes of Ada Lovelace", "temperature" => "0.5" }
      session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
      # Ollama takes the tools from the chat's parameters.
      session[:parameters]["tools"] = tool_app.settings["tools"] if tools_in_parameters
    end

    def chunks(lines)
      Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| lines.each { |line| blk.call(line.dup) } } }
    end

    def run_round(name, arguments)
      replies = [calling(name, arguments), answering("<<PERSON_1>> kept notes.")]
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post) do |_uri, json:|
        words.check_sending!
        sent << JSON.parse(JSON.generate(json))
        double("res", status: HTTP::Response::Status.new(200), body: chunks(replies.shift), code: 200, headers: {})
      end
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
      chat.api_request("user", session) { |_| }
    end

    it "gives a tool that reads the shared folder the words of its path, and hides what it gives back" do
      result = run_round("read_file_from_shared_folder", { "filepath" => "<<PERSON_1>> notes.txt" })
      expect(tool_app.given).to eq(["Ada Lovelace notes.txt"])
      expect(sent.size).to eq(2)
      expect(JSON.generate(sent)).not_to include("Ada Lovelace")
      expect(JSON.generate(sent.last)).to include("Notes by <<PERSON_1>>")
      reply = Array(result).last
      expect(words.restore_reply(reply, reply_text(reply))).to eq("Ada Lovelace kept notes.")
    end

    it "gives a tool that writes the placeholders as the model wrote them" do
      run_round("write_file_to_shared_folder", { "filepath" => "<<PERSON_1>>.txt", "content" => "About <<PERSON_1>>" })
      expect(tool_app.given).to eq([["<<PERSON_1>>.txt", "About <<PERSON_1>>", "write"]])
    end

    it "sends nothing when the table changes after the request was made" do
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post) do |_uri, json:|
        table.confirm!("Eve", "PERSON")
        words.check_sending!
        sent << json
        double("res", status: HTTP::Response::Status.new(200), body: chunks([]), code: 200, headers: {})
      end
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
      out = []
      begin
        chat.api_request("user", session) { |r| out << r }
      rescue Monadic::Utils::Privacy::Outbound::Refused => e
        out << e.message
      end
      expect(sent).to be_empty
      expect(out.to_s).to include("changed while the request was being sent")
    end
  end

  def sse(event)
    "data: #{JSON.generate(event)}\n\n"
  end

  def reply_text(reply)
    reply.dig("choices", 0, "message", "content") || reply.dig("message", "content")
  end

  describe "on Mistral" do
    let(:chat) { Class.new(MonadicApp) { include MistralHelper }.new }
    let(:model) { Monadic::Utils::ModelSpec.get_provider_models("mistral", "chat")&.first }
    let(:config) { { "MISTRAL_API_KEY" => "k" } }

    def calling(name, arguments)
      call = { "index" => 0, "id" => "call_1", "type" => "function",
               "function" => { "name" => name, "arguments" => JSON.generate(arguments) } }
      [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "tool_calls" => [call] } }]),
       sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "tool_calls" }]),
       "data: [DONE]\n\n"]
    end

    def answering(text)
      [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => text } }]),
       sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }]),
       "data: [DONE]\n\n"]
    end

    it_behaves_like "a round of tool calls"
  end

  describe "on DeepSeek" do
    let(:chat) { Class.new(MonadicApp) { include DeepSeekHelper }.new }
    let(:model) { Monadic::Utils::ModelSpec.get_provider_models("deepseek", "chat")&.first }
    let(:config) { { "DEEPSEEK_API_KEY" => "k" } }

    def calling(name, arguments)
      call = { "index" => 0, "id" => "call_1", "type" => "function",
               "function" => { "name" => name, "arguments" => JSON.generate(arguments) } }
      [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => nil, "tool_calls" => [call] } }]),
       sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "tool_calls" }]),
       "data: [DONE]\n\n"]
    end

    def answering(text)
      [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => text } }]),
       sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }]),
       "data: [DONE]\n\n"]
    end

    it_behaves_like "a round of tool calls"

    describe "text it wrote before calling a tool" do
      let(:sent) { [] }
      let(:tool_app) do
        Class.new(MonadicApp) do
          attr_reader :given

          def settings
            { "tools" => [{ "type" => "function", "function" => { "name" => "read_file_from_shared_folder",
                                                                  "parameters" => { "type" => "object", "properties" => {} } } }] }
          end

          def read_file_from_shared_folder(filepath:)
            (@given ||= []) << filepath
            "Notes"
          end
        end.new
      end

      before do
        stub_const("APPS", { "SpecApp" => tool_app })
        stub_const("CONFIG", config)
        allow(chat).to receive(:sleep)
        session[:parameters] = { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                                 "message" => "Read the notes of Ada Lovelace", "temperature" => "0.5" }
        session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
      end

      def round(first)
        replies = [first, answering("Done.")]
        chain = double("http")
        %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
        allow(chain).to receive(:post) do |_uri, json:|
          sent << JSON.parse(JSON.generate(json))
          lines = replies.shift
          body = Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| lines.each { |l| blk.call(l.dup) } } }
          double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
        end
        allow(HTTP).to receive(:headers).and_return(chain)
        allow(HTTP).to receive(:timeout).and_return(chain)
        shown = []
        chat.api_request("user", session) { |r| shown << r }
        shown
      end

      def expect_kept_as_a_reply(shown)
        expect(tool_app.given).to eq(["Ada Lovelace notes.txt"])
        kept = session[:messages].find { |m| m["role"] == "assistant" && m["text"].include?("Checking") }
        expect(kept["text"]).to eq("Checking Ada Lovelace now.")
        expect(shown.find { |r| r["type"] == "html" }.dig("content", "text")).to eq("Checking Ada Lovelace now.")
        expect(sent.size).to eq(2)
        expect(JSON.generate(sent.last)).to include("Checking <<PERSON_1>> now.")
        expect(JSON.generate(sent)).not_to include("Ada Lovelace")
        expect(JSON.generate(sent)).not_to include("‹‹")
      end

      it "is kept with the words put back, and sent again with the placeholders, before a tool call" do
        call = { "index" => 0, "id" => "call_1", "type" => "function",
                 "function" => { "name" => "read_file_from_shared_folder",
                                 "arguments" => JSON.generate("filepath" => "<<PERSON_1>> notes.txt") } }
        expect_kept_as_a_reply(round(
          [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => "Checking <<PERSON_1>> now." } }]),
           sse("choices" => [{ "index" => 0, "delta" => { "tool_calls" => [call] } }]),
           sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "tool_calls" }]),
           "data: [DONE]\n\n"]
        ))
      end

      it "is kept with the words put back, and sent again with the placeholders, before a call written as text" do
        text = 'Checking <<PERSON_1>> now.<|DSML|function_calls><|DSML|invoke name="read_file_from_shared_folder">' \
               '<|DSML|param name="filepath"><<PERSON_1>> notes.txt</|DSML|param></|DSML|invoke></|DSML|function_calls>'
        expect_kept_as_a_reply(round(
          [sse("choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => text } }]),
           sse("choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }]),
           "data: [DONE]\n\n"]
        ))
      end
    end
  end

  describe "on Ollama" do
    let(:chat) { Class.new(MonadicApp) { include OllamaHelper }.new }
    let(:model) { "spec-model" }
    let(:config) { {} }

    before do
      allow(OllamaHelper).to receive(:find_endpoint).and_return("http://ollama.invalid/api")
      allow(chat).to receive(:list_models).and_return([])
      allow(OllamaHelper).to receive(:fetch_model_capabilities)
        .and_return({ capabilities: %w[completion tools], context_length: nil, fetched_at: Time.now })
    end

    def calling(name, arguments)
      call = { "function" => { "name" => name, "arguments" => arguments } }
      ["#{JSON.generate('model' => model, 'message' => { 'role' => 'assistant', 'content' => '', 'tool_calls' => [call] }, 'done' => false)}\n",
       "#{JSON.generate('model' => model, 'message' => { 'role' => 'assistant', 'content' => '' }, 'done' => true)}\n"]
    end

    def answering(text)
      ["#{JSON.generate('model' => model, 'message' => { 'role' => 'assistant', 'content' => text }, 'done' => false)}\n",
       "#{JSON.generate('model' => model, 'message' => { 'role' => 'assistant', 'content' => '' }, 'done' => true)}\n"]
    end

    it_behaves_like "a round of tool calls", tools_in_parameters: true
  end
end
