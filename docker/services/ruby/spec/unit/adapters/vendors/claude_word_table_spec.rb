# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/utils/privacy/words"
require_relative "../../../../lib/monadic/utils/websocket"
require_relative "../../../../lib/monadic/utils/tts_text_extractor"

# A Claude chat that hides its words with a word table: what is sent, what
# a tool is given, and what the reply is put back with.
RSpec.describe "A Claude chat with a word table" do
  let(:words) { Monadic::Utils::Privacy::Words }
  let(:session) { {}.tap { |s| Monadic::Workspace::Chats.start_new!(s) } }
  let(:table) { words.start!(session) }
  let(:chat) { Class.new(MonadicApp) { include ClaudeHelper }.new }

  before { table.confirm!("Ada Lovelace", "PERSON") }
  after { words::LOCK.synchronize { words::TABLES.clear } }

  describe "a message" do
    let(:snapshot) { table.snapshot }
    let(:budget) { Monadic::Utils::Privacy::WordTable::Budget.new }

    def hide(message)
      chat.hide_words_in_claude_message(message, snapshot, budget)
    end

    it "sends what the user wrote and the replies the chat keeps as text, and leaves images and documents" do
      user = { "role" => "user", "content" => [
        { "type" => "text", "text" => "Ada Lovelace wrote <<PERSON_1>>", "cache_control" => { "type" => "ephemeral" } },
        { "type" => "image", "source" => { "type" => "base64", "media_type" => "image/png", "data" => "QUJD" } }
      ] }
      expect(hide(user)["content"]).to eq([
        { "type" => "text", "text" => "<<PERSON_1>> wrote ‹‹PERSON_1››", "cache_control" => { "type" => "ephemeral" } },
        user["content"][1]
      ])
      expect(hide({ "role" => "assistant", "content" => "Ada Lovelace" })["content"]).to eq("<<PERSON_1>>")
    end

    it "sends what the model wrote in a round of tool calls as it wrote it, its thinking untouched" do
      round = { "role" => "assistant", "content" => [
        { "type" => "thinking", "thinking" => "About <<PERSON_1>>", "signature" => "sig" },
        { "type" => "text", "text" => "Reading <<PERSON_1>>, Ada Lovelace" },
        { "type" => "tool_use", "id" => "t1", "name" => "f", "input" => { "who" => "<<PERSON_1>>", "also" => "Ada Lovelace" } }
      ] }
      expect(hide(round)["content"]).to eq([
        round["content"][0],
        { "type" => "text", "text" => "Reading <<PERSON_1>>, <<PERSON_1>>" },
        { "type" => "tool_use", "id" => "t1", "name" => "f", "input" => { "who" => "<<PERSON_1>>", "also" => "<<PERSON_1>>" } }
      ])
    end

    it "sends a tool's result as data, its text or the text blocks in it" do
      results = { role: "user", content: [
        { type: "tool_result", tool_use_id: "t1", content: JSON.generate("by" => "Ada Lovelace") },
        { type: "tool_result", tool_use_id: "t2", content: [
          { type: "text", text: "Ada Lovelace" },
          { type: "image", source: { type: "base64", media_type: "image/png", data: "QUJD" } }
        ] }
      ] }
      hidden = hide(results)[:content]
      expect(hidden[0][:content]).to eq(JSON.generate("by" => "<<PERSON_1>>"))
      expect(hidden[1][:content]).to eq([{ type: "text", text: "<<PERSON_1>>" }, results[:content][1][:content][1]])
    end
  end

  describe "a round of tool calls" do
    let(:sent) { [] }
    let(:model) { Monadic::Utils::ModelSpec.get_provider_models("anthropic", "chat")&.first }
    let(:tool_app) do
      Class.new(MonadicApp) do
        attr_reader :given
        attr_accessor :on_read

        def settings
          { "tools" => %w[read_file_from_shared_folder write_file_to_shared_folder].map do |name|
            { "name" => name, "input_schema" => { "type" => "object", "properties" => {} } }
          end }
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
      stub_const("CONFIG", { "ANTHROPIC_API_KEY" => "k" })
      allow(chat).to receive(:sleep)
      session[:parameters] = { "app_name" => "SpecApp", "model" => model, "context_size" => "5", "max_tokens" => "1000",
                               "message" => "Read the notes of Ada Lovelace", "temperature" => "0.5" }
      session[:messages] = [{ "role" => "system", "text" => "S", "active" => true }]
    end

    def sse(event)
      "event: #{event['type']}\ndata: #{JSON.generate(event)}\n\n"
    end

    def calling(name, arguments, text: nil)
      before = if text
                 [sse("type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" }),
                  sse("type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => text }),
                  sse("type" => "content_block_stop", "index" => 0)]
               else
                 []
               end
      index = before.empty? ? 0 : 1
      [sse("type" => "message_start", "message" => { "id" => "m1", "model" => model, "usage" => {} }),
       *before,
       sse("type" => "content_block_start", "index" => index,
           "content_block" => { "type" => "tool_use", "id" => "toolu_1", "name" => name, "input" => {} }),
       sse("type" => "content_block_delta", "index" => index,
           "delta" => { "type" => "input_json_delta", "partial_json" => JSON.generate(arguments) }),
       sse("type" => "content_block_stop", "index" => index),
       sse("type" => "message_delta", "delta" => { "stop_reason" => "tool_use" }, "usage" => {}),
       sse("type" => "message_stop")]
    end

    def answering(text)
      [sse("type" => "message_start", "message" => { "id" => "m2", "model" => model, "usage" => {} }),
       sse("type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" }),
       sse("type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => text }),
       sse("type" => "content_block_stop", "index" => 0),
       sse("type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => {}),
       sse("type" => "message_stop")]
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

    it "gives a tool that writes the placeholders as the model wrote them" do
      run_round("write_file_to_shared_folder", { "filepath" => "<<PERSON_1>>.txt", "content" => "About <<PERSON_1>>" })
      expect(tool_app.given).to eq([["<<PERSON_1>>.txt", "About <<PERSON_1>>", "write"]])
    end

    it "sends the request to the model it falls back to made from the conversation as it was" do
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property).and_call_original
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_property)
        .with(model, "unavailable_fallback").and_return("spec-fallback")
      chain = double("http")
      %i[timeout headers via].each { |m| allow(chain).to receive(m).and_return(chain) }
      allow(chain).to receive(:post) do |_uri, json:|
        sent << JSON.parse(JSON.generate(json))
        if json["model"] == model
          double("res", status: HTTP::Response::Status.new(404), code: 404, headers: {},
                        body: JSON.generate("error" => { "type" => "not_found_error", "message" => "gone" }))
        else
          lines = answering("Hi")
          body = Object.new.tap { |b| b.define_singleton_method(:each) { |&blk| lines.each { |l| blk.call(l.dup) } } }
          double("res", status: HTTP::Response::Status.new(200), body: body, code: 200, headers: {})
        end
      end
      allow(HTTP).to receive(:headers).and_return(chain)
      allow(HTTP).to receive(:timeout).and_return(chain)
      chat.api_request("user", session) { |_| }
      expect(sent.map { |b| b["model"] }.uniq).to eq([model, "spec-fallback"])
      expect(sent.map { |b| b["messages"] }.uniq.size).to eq(1)
      expect(JSON.generate(sent)).to include("<<PERSON_1>>")
      expect(JSON.generate(sent)).not_to include("‹‹")
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
