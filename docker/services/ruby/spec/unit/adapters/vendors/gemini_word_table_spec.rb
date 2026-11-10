# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"
require_relative "../../../../lib/monadic/utils/privacy/words"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/tts_text_extractor"

# A Gemini chat that hides its words with a word table: what is sent, what
# a tool is given, and what the reply is put back with.
RSpec.describe "A Gemini chat with a word table" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }
  let(:chat) { Class.new(MonadicApp) { include GeminiHelper }.new }

  before { table.confirm!("Ada Lovelace", "PERSON") }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  describe "a turn" do
    let(:snapshot) { table.snapshot }
    let(:budget) { Monadic::Utils::Privacy::WordTable::Budget.new }

    def hide(content)
      chat.send(:hide_words_in_gemini_content, content, snapshot, budget)
    end

    it "sends text as what the chat keeps, and leaves thoughts, signatures and data" do
      user = { "role" => "user", "parts" => [{ "text" => "Ada Lovelace wrote <<PERSON_1>>" },
                                            { "inlineData" => { "mimeType" => "image/png", "data" => "QUJD" } }] }
      expect(hide(user)["parts"]).to eq([{ "text" => "<<PERSON_1>> wrote ‹‹PERSON_1››" }, user["parts"][1]])
      model = { "role" => "model", "parts" => [{ "text" => "About <<PERSON_1>>", "thought" => true },
                                              { "text" => "Ada Lovelace", "thoughtSignature" => "sig" }] }
      expect(hide(model)["parts"]).to eq([model["parts"][0], { "text" => "<<PERSON_1>>", "thoughtSignature" => "sig" }])
      expect(hide({ "role" => "other", "parts" => [{ "text" => "Ada Lovelace" }] })["parts"]).to eq([{ "text" => "Ada Lovelace" }])
    end

    it "sends a call's args as the model wrote them, and a response as data" do
      round = { "role" => "model", "parts" => [
        { "functionCall" => { "name" => "f", "args" => { "who" => "<<PERSON_1>>", "also" => "Ada Lovelace" } },
          "thoughtSignature" => "sig" }
      ] }
      expect(hide(round)["parts"]).to eq([{ "functionCall" => { "name" => "f", "args" => { "who" => "<<PERSON_1>>", "also" => "<<PERSON_1>>" } },
                                            "thoughtSignature" => "sig" }])
      results = { "role" => "user", "parts" => [
        { "functionResponse" => { "name" => "f", "response" => { "name" => "f", "content" => "Notes by Ada Lovelace" } } }
      ] }
      expect(hide(results).dig("parts", 0, "functionResponse", "response"))
        .to eq("name" => "f", "content" => "Notes by <<PERSON_1>>")
    end
  end

  describe "a round of tool calls" do
    let(:sent) { [] }
    let(:model) { Monadic::Utils::ModelSpec.get_provider_models("gemini", "chat")&.first }
    let(:tool_app) do
      Class.new(MonadicApp) do
        attr_reader :given
        attr_accessor :on_read

        def settings
          { "tools" => { "function_declarations" => %w[read_file_from_shared_folder write_file_to_shared_folder].map do |name|
            { "name" => name, "parameters" => { "type" => "object", "properties" => {} } }
          end } }
        end

        def read_file_from_shared_folder(filepath:)
          (@given ||= []) << filepath
          on_read&.call
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
      stub_const("CONFIG", { "GEMINI_API_KEY" => "k" })
      allow(chat).to receive(:sleep)
      session[:parameters] = { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "1000",
                               "message" => "Read the notes of Ada Lovelace", "temperature" => "0.5" }
      session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
    end

    def chunk(first, parts, finish)
      object = { "candidates" => [{ "content" => { "role" => "model", "parts" => parts }, "finishReason" => finish }] }
      "#{first ? '[' : ",\n"}#{JSON.pretty_generate(object)}\n"
    end

    def calling(name, arguments, text: nil)
      parts = [({ "text" => text } if text), { "functionCall" => { "name" => name, "args" => arguments } }].compact
      [chunk(true, parts, "STOP"), "]"]
    end

    def answering(text)
      [chunk(true, [{ "text" => text }], "STOP"), "]"]
    end

    def posting(before_sending: nil, &answer)
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post) do |_uri, json:|
        before_sending&.call
        words.check_sending!
        sent << JSON.parse(JSON.generate(json))
        lines = yield
        body = Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| lines.each { |l| blk.call(l.dup) } } }
        double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
      end
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
    end

    def run_round(name, arguments)
      replies = [calling(name, arguments), answering("<<PERSON_1>> kept notes.")]
      posting { replies.shift }
      chat.api_request("user", session) { |_| }
    end

    it "gives a tool that reads the shared folder the words of its path, and hides what it gives back" do
      result = run_round("read_file_from_shared_folder", { "filepath" => "<<PERSON_1>> notes.txt" })
      expect(tool_app.given).to eq(["Ada Lovelace notes.txt"])
      expect(sent.size).to eq(2)
      expect(JSON.generate(sent)).not_to include("Ada Lovelace")
      expect(JSON.generate(sent.last)).to include("Notes by <<PERSON_1>>")
      reply = Array(result).last
      expect(words.restore_reply(reply, reply.dig("choices", 0, "message", "content"))).to eq("Ada Lovelace kept notes.")
    end

    it "puts back the text before a tool call and the reply after it each with the words of its own request" do
      tool_app.on_read = -> { table.confirm!("Eve", "PERSON") }
      replies = [calling("read_file_from_shared_folder", { "filepath" => "<<PERSON_1>> notes.txt" },
                         text: "Unknown <<PERSON_2>>, <<PERSON_1>>."),
                 answering("Done <<PERSON_2>>.")]
      posting { replies.shift }
      reply = Array(chat.api_request("user", session) { |_| }).last
      expect(words.restore_reply(reply, reply.dig("choices", 0, "message", "content")))
        .to eq("Unknown <<PERSON_2>>, Ada Lovelace.\n\nDone Eve.")
    end

    it "makes the request it sends again for a notebook from the conversation as it was" do
      calls = 0
      allow(chat).to receive(:process_json_data) do
        calls += 1
        calls == 1 ? [{ "gemini_jupyter_retry" => true }] : [{ "choices" => [{ "message" => { "content" => "Hi" } }] }]
      end
      posting { answering("Hi") }
      chat.api_request("user", session) { |_| }
      expect(sent.size).to eq(2)
      expect(JSON.generate(sent.last)).to include("Read the notes of <<PERSON_1>>")
      expect(JSON.generate(sent)).not_to include("‹‹")
      expect(JSON.generate(sent.last)).to include("add the requested code cells")
    end

    it "shows a tool's output as the tool gave it when the model says nothing after it" do
      def tool_app.read_file_from_shared_folder(filepath:)
        (@given ||= []) << filepath
        "literal <<PERSON_1>> in #{filepath}"
      end
      replies = [calling("read_file_from_shared_folder", { "filepath" => "<<PERSON_1>> notes.txt" }), answering("")]
      posting { replies.shift }
      reply = Array(chat.api_request("user", session) { |_| }).last
      text = reply.dig("choices", 0, "message", "content")
      expect(text).to include("literal <<PERSON_1>> in Ada Lovelace notes.txt")
      expect(words.restore_reply(reply, text)).to eq(text)
    end

    it "gives a tool that writes the placeholders as the model wrote them" do
      run_round("write_file_to_shared_folder", { "filepath" => "<<PERSON_1>>.txt", "content" => "About <<PERSON_1>>" })
      expect(tool_app.given).to eq([["<<PERSON_1>>.txt", "About <<PERSON_1>>", "write"]])
    end

    it "sends nothing when the table changes after the request was made" do
      posting(before_sending: -> { table.confirm!("Eve", "PERSON") }) { answering("Hi") }
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
end
