# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/utils/privacy/words"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/tts_text_extractor"

# An OpenAI chat that hides its words with a word table: what is sent, and
# what is not.
RSpec.describe "An OpenAI chat with a word table" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:outbound) { Monadic::Utils::Privacy::Outbound }
  let(:helper) { Class.new { include BaseVendorHelper }.new }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }

  before do
    table.confirm!("Ada Lovelace", "PERSON")
    table.confirm!("QUJD", "ORGANIZATION")
  end

  after { words::LOCK.synchronize { words::TABLES.clear } }

  describe "the request body" do
    it "hides the words in the conversation of a chat request, and leaves its form, system text and images" do
      body = {
        "model" => "m",
        "messages" => [
          { "role" => "system", "content" => "Be brief." },
          { "role" => "user", "content" => [{ "type" => "text", "text" => "Who is Ada Lovelace? <<PERSON_1>>" },
                                            { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,QUJD" } }] },
          { "role" => "assistant", "content" => "Ada Lovelace wrote notes.",
            "tool_calls" => [{ "id" => "c1", "type" => "function",
                               "function" => { "name" => "lookup", "arguments" => JSON.generate("who" => "<<PERSON_1>>") } }] },
          { "role" => "tool", "tool_call_id" => "c1", "content" => JSON.generate("name" => "Ada Lovelace", "born" => 1815) }
        ]
      }
      hiding = helper.hide_words_in_request!(body, session)
      expect(hiding).to eq([table, hiding.last])
      messages = body["messages"]
      expect(messages[0]).to eq("role" => "system", "content" => "Be brief.")
      expect(messages[1]["content"][0]["text"]).to eq("Who is <<PERSON_1>>? ‹‹PERSON_1››")
      expect(messages[1]["content"][1]).to eq("type" => "image_url", "image_url" => { "url" => "data:image/png;base64,QUJD" })
      expect(messages[2]["content"]).to eq("<<PERSON_1>> wrote notes.")
      expect(JSON.parse(messages[2]["tool_calls"][0]["function"]["arguments"])).to eq("who" => "<<PERSON_1>>")
      expect(messages[2]["tool_calls"][0]["function"]["name"]).to eq("lookup")
      expect(JSON.parse(messages[3]["content"])).to eq("name" => "<<PERSON_1>>", "born" => 1815)
      expect(messages[3]["tool_call_id"]).to eq("c1")
    end

    it "hides the words in the input of a Responses API request" do
      body = {
        "input" => [
          { "role" => "user", "content" => [{ "type" => "input_text", "text" => "About Ada Lovelace" },
                                            { "type" => "input_image", "image_url" => "data:image/png;base64,QUJD" }] },
          { "role" => "assistant", "content" => [{ "type" => "output_text", "text" => "Ada Lovelace was" }] },
          { "type" => "function_call", "call_id" => "c1", "name" => "lookup", "arguments" => JSON.generate("q" => "<<PERSON_1>>") },
          { "type" => "function_call_output", "call_id" => "c1", "output" => "Ada Lovelace (1815)" }
        ]
      }
      helper.hide_words_in_request!(body, session)
      input = body["input"]
      expect(input[0]["content"][0]["text"]).to eq("About <<PERSON_1>>")
      expect(input[0]["content"][1]["image_url"]).to eq("data:image/png;base64,QUJD")
      expect(input[1]["content"][0]["text"]).to eq("<<PERSON_1>> was")
      expect(JSON.parse(input[2]["arguments"])).to eq("q" => "<<PERSON_1>>")
      expect(input[3]["output"]).to eq("<<PERSON_1>> (1815)")
    end

    it "sends what a model wrote in a round of tool calls with the chat's placeholders, and the stored replies as text" do
      chat = { "messages" => [
        { "role" => "assistant", "content" => "Ada Lovelace, as <<PERSON_1>> in the notes" },
        { "role" => "assistant", "content" => "Looking up <<PERSON_1>>", "tool_calls" => [] }
      ] }
      helper.hide_words_in_request!(chat, session)
      expect(chat["messages"][0]["content"]).to eq("<<PERSON_1>>, as \u2039\u2039PERSON_1\u203A\u203A in the notes")
      expect(chat["messages"][1]["content"]).to eq("Looking up <<PERSON_1>>")

      responses = { "input" => [
        { "role" => "assistant", "content" => [{ "type" => "output_text", "text" => "Ada Lovelace <<PERSON_1>>" }] },
        { "type" => "message", "role" => "assistant", "content" => [{ "type" => "output_text", "text" => "Looking up <<PERSON_1>>" }] }
      ] }
      helper.hide_words_in_request!(responses, session)
      expect(responses["input"][0]["content"][0]["text"]).to eq("<<PERSON_1>> \u2039\u2039PERSON_1\u203A\u203A")
      expect(responses["input"][1]["content"][0]["text"]).to eq("Looking up <<PERSON_1>>")
    end

    it "sends nothing when a word is in a part it does not change" do
      body = { "messages" => [{ "role" => "system", "content" => "Talk about Ada Lovelace." },
                              { "role" => "user", "content" => "hi" }] }
      expect { helper.hide_words_in_request!(body, session) }.to raise_error(outbound::Refused)
    end

    it "makes the request again once when the table changed meanwhile, and sends nothing when it keeps changing" do
      body = { "messages" => [{ "role" => "user", "content" => "Ada Lovelace" }] }
      allow(table).to receive(:revision).and_return(99, table.snapshot.revision)
      expect(helper.hide_words_in_request!(body, session)).not_to be_nil
      expect(body["messages"][0]["content"]).to eq("<<PERSON_1>>")

      allow(table).to receive(:revision).and_return(99)
      expect { helper.hide_words_in_request!({ "messages" => [] }, session) }.to raise_error(outbound::Refused, /kept changing/)
    end

    it "is nothing for a chat without a table" do
      body = { "messages" => [{ "role" => "user", "content" => "Ada Lovelace" }] }
      expect(helper.hide_words_in_request!(body, {})).to be_nil
      expect(body["messages"][0]["content"]).to eq("Ada Lovelace")
    end
  end

  describe "the reply" do
    it "is kept and shown with the placeholders of the request it answers put back" do
      host = Class.new { include WebSocketHelper }.new
      queue = Queue.new
      app = Object.new
      chat_table = table
      app.define_singleton_method(:api_request) do |_role, _session, &_block|
        sent_with = chat_table.snapshot
        # A word marked while the reply was on its way: its placeholder was
        # not in the request, and is not put back in this reply.
        chat_table.confirm!("Eve", "PERSON")
        reply = { "choices" => [{ "message" => { "content" => "<<PERSON_1>> met <<PERSON_2>>. <<PERSON_9>>" },
                                  "finish_reason" => "stop" }] }
        Monadic::Utils::Privacy::Words.note_reply([reply], sent_with)
      end
      app.define_singleton_method(:settings) { {} }
      stub_const("APPS", { "FakeApp" => app })
      session[:parameters] = {}
      session[:messages] = []
      allow(host).to receive(:send_or_broadcast)
      allow(host).to receive(:initialize_token_counting).and_return(nil)
      allow(host).to receive(:sts_session_capable?).and_return(false)
      thread = host.send(:handle_ws_streaming, nil, { "message" => "who?", "app_name" => "FakeApp" }, session, queue)
      wait_for_answer_made(thread)

      reply = queue.pop.dig("responses", 0, "choices", 0, "message", "content")
      expect(reply).to eq("Ada Lovelace met <<PERSON_2>>. <<PERSON_9>>")
    end
  end

  describe "sending it" do
    let(:app) { Struct.new(:settings).new({ "tools" => [], tools: [] }) }
    let(:chat) { Class.new(MonadicApp) { include OpenAIHelper }.new }
    let(:model) { Monadic::Utils::ModelSpec.get_provider_models("openai", "chat")&.first }
    let(:sent) { [] }

    before do
      stub_const("APPS", { "SpecApp" => app })
      stub_const("CONFIG", { "OPENAI_API_KEY" => "k" })
      allow(chat).to receive(:sleep)
      session[:parameters] = { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "100",
                               "message" => "Tell me about Ada Lovelace", "temperature" => "0.5" }
      session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
    end

    def chain_posting(&post)
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post, &post)
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
    end

    it "sends the user's message with the words hidden" do
      chain_posting do |_uri, json:|
        words.check_sending!
        sent << JSON.generate(json)
        double("res", status: HTTP::Response::Status.new(500), body: "{}", code: 500, headers: {})
      end
      chat.api_request("user", session) { |_| }
      expect(sent).not_to be_empty
      expect(sent).to all(include("<<PERSON_1>>"))
      expect(sent.join).not_to include("Ada Lovelace")
    end

    it "notes the snapshot it sent with on the reply it gives" do
      chain_posting do |_uri, json:|
        sent << json
        double("res", status: HTTP::Response::Status.new(200), body: "{}", code: 200, headers: {})
      end
      reply = { "choices" => [{ "message" => { "content" => "<<PERSON_1>>" } }] }
      allow(chat).to receive(:process_json_data).and_return([reply])
      allow(chat).to receive(:process_responses_api_data).and_return([reply])
      chat.api_request("user", session) { |_| }
      table.confirm!("Eve", "PERSON")
      GC.start(full_mark: true, immediate_sweep: true)
      expect(words.restore_reply(reply, "<<PERSON_1>> <<PERSON_2>>")).to eq("Ada Lovelace <<PERSON_2>>")
    end

    describe "a round of tool calls" do
      let(:tool_app) do
        Class.new(MonadicApp) do
          attr_reader :read

          def settings
            { "tools" => %w[read_file_from_shared_folder write_file_to_shared_folder].map do |name|
              { "type" => "function",
                "function" => { "name" => name, "parameters" => { "type" => "object", "properties" => {} } } }
            end }
          end

          def read_file_from_shared_folder(filepath:)
            (@read ||= []) << filepath
            "Notes by Ada Lovelace"
          end

          def write_file_to_shared_folder(filepath:, content:, mode: "write")
            (@read ||= []) << [filepath, content, mode]
            "written"
          end
        end.new
      end

      def stream(events)
        body = events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
        Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| blk.call(body) } }
      end

      def calling(name, arguments)
        item = { "type" => "function_call", "id" => "fc_1", "call_id" => "call_1", "name" => name, "arguments" => arguments }
        [{ "type" => "response.created", "response" => { "id" => "r1", "model" => model } },
         { "type" => "response.output_item.added", "item" => item.merge("arguments" => "") },
         { "type" => "response.output_item.done", "item" => item },
         { "type" => "response.completed", "response" => { "id" => "r1", "model" => model, "status" => "completed" } }]
      end

      def answering(text)
        [{ "type" => "response.created", "response" => { "id" => "r2", "model" => model } },
         { "type" => "response.output_text.delta", "item_id" => "m1", "delta" => text },
         { "type" => "response.output_text.done", "item_id" => "m1", "text" => text },
         { "type" => "response.completed", "response" => { "id" => "r2", "model" => model, "status" => "completed" } }]
      end

      def run_round(name, arguments)
        stub_const("APPS", { "SpecApp" => tool_app })
        replies = [calling(name, arguments), answering("<<PERSON_1>> kept notes.")]
        chain_posting do |_uri, json:|
          words.check_sending!
          sent << JSON.parse(JSON.generate(json))
          double("res", status: HTTP::Response::Status.new(200), body: stream(replies.shift), code: 200, headers: {})
        end
        chat.api_request("user", session) { |_| }
      end

      it "gives a tool that reads the shared folder the words of its path, and hides what it gives back" do
        result = run_round("read_file_from_shared_folder", JSON.generate("filepath" => "<<PERSON_1>> notes.txt"))
        expect(tool_app.read).to eq(["Ada Lovelace notes.txt"])
        expect(sent.size).to eq(2)
        expect(JSON.generate(sent)).not_to include("Ada Lovelace")
        expect(JSON.generate(sent.last)).to include("Notes by <<PERSON_1>>")
        reply = Array(result).last
        expect(words.restore_reply(reply, reply.dig("choices", 0, "message", "content"))).to eq("Ada Lovelace kept notes.")
      end

      it "gives a tool that writes the placeholders as the model wrote them" do
        run_round("write_file_to_shared_folder",
                  JSON.generate("filepath" => "<<PERSON_1>>.txt", "content" => "About <<PERSON_1>>"))
        expect(tool_app.read).to eq([["<<PERSON_1>>.txt", "About <<PERSON_1>>", "write"]])
      end
    end

    it "sends no attempt after the table changed, and reports that nothing was sent" do
      tries = 0
      chain_posting do |_uri, json:|
        tries += 1
        table.confirm!("Eve", "PERSON") if tries == 2
        words.check_sending!
        sent << JSON.generate(json)
        double("res", status: HTTP::Response::Status.new(500), body: "{}", code: 500, headers: {})
      end
      out = []
      chat.api_request("user", session) { |r| out << r }
      expect(sent.size).to eq(1)
      expect(out.to_s).to include("changed while the request was being sent")
    end
  end
end
