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

# What every provider's reader of a streamed reply does, whatever the chunks
# the reply arrives in: the text comes whole, every call of a round is run,
# and an error inside the stream ends the reply as that error with no tool run.
module StreamContract
  TEXT = ["日本語の", "テキストと", " English words"].freeze
  CALLS = [["first_tool", { "n" => 1 }], ["second_tool", { "n" => 2 }]].freeze
  ERROR = "the service is overloaded"

  # OpenAI Chat Completions, DeepSeek, Mistral.
  module ChatCompletions
    module_function

    def text(pieces)
      pieces.map { |p| { "id" => "r", "choices" => [{ "index" => 0, "delta" => { "content" => p } }] } } +
        [{ "id" => "r", "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }] }]
    end

    def calls(calls)
      calls.each_with_index.flat_map do |(name, args), i|
        json = JSON.generate(args)
        [{ "id" => "r", "choices" => [{ "index" => 0, "delta" => { "tool_calls" => [
          { "index" => i, "id" => "call_#{i}", "type" => "function", "function" => { "name" => name, "arguments" => "" } }
        ] } }] },
         { "id" => "r", "choices" => [{ "index" => 0, "delta" => { "tool_calls" => [
           { "index" => i, "function" => { "arguments" => json[0, 3] } }
         ] } }] },
         { "id" => "r", "choices" => [{ "index" => 0, "delta" => { "tool_calls" => [
           { "index" => i, "function" => { "arguments" => json[3..] } }
         ] } }] }]
      end + [{ "id" => "r", "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "tool_calls" }] }]
    end

    def error(message) = { "error" => { "message" => message } }
  end

  module Gemini
    module_function

    def part_record(parts, finish = nil)
      { "candidates" => [{ "content" => { "role" => "model", "parts" => parts }, "finishReason" => finish }.compact] }
    end

    def text(pieces)
      pieces.each_with_index.map { |p, i| part_record([{ "text" => p }], i == pieces.size - 1 ? "STOP" : nil) }
    end

    def calls(calls)
      [part_record(calls.map { |name, args| { "functionCall" => { "name" => name, "args" => args } } })]
    end

    def error(message) = { "error" => { "code" => 503, "message" => message } }
  end

  module Cohere
    module_function

    def text(pieces)
      [{ "type" => "message-start", "delta" => { "message" => { "role" => "assistant" } } }] +
        pieces.map { |p| { "type" => "content-delta", "index" => 0, "delta" => { "message" => { "content" => { "text" => p } } } } } +
        [{ "type" => "message-end", "delta" => { "finish_reason" => "COMPLETE" } }]
    end

    def calls(calls)
      [{ "type" => "message-start", "delta" => { "message" => { "role" => "assistant" } } }] +
        calls.each_with_index.flat_map do |(name, args), i|
          json = JSON.generate(args)
          [{ "type" => "tool-call-start", "index" => i, "delta" => { "message" => { "tool_calls" => {
            "id" => "call_#{i}", "type" => "function", "function" => { "name" => name, "arguments" => "" }
          } } } },
           { "type" => "tool-call-delta", "index" => i, "delta" => { "message" => { "tool_calls" => { "function" => { "arguments" => json[0, 3] } } } } },
           { "type" => "tool-call-delta", "index" => i, "delta" => { "message" => { "tool_calls" => { "function" => { "arguments" => json[3..] } } } } },
           { "type" => "tool-call-end", "index" => i }]
        end + [{ "type" => "message-end", "delta" => { "finish_reason" => "TOOL_CALL" } }]
    end

    def error(message) = { "type" => "message-end", "delta" => { "finish_reason" => "ERROR", "error" => message } }
  end

  module Claude
    module_function

    def start = { "type" => "message_start", "message" => { "id" => "m", "usage" => { "input_tokens" => 1 } } }

    def text(pieces)
      [start, { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" } }] +
        pieces.map { |p| { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => p } } } +
        [{ "type" => "content_block_stop", "index" => 0 },
         { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 1 } },
         { "type" => "message_stop" }]
    end

    def calls(calls)
      [start] + calls.each_with_index.flat_map do |(name, args), i|
        json = JSON.generate(args)
        [{ "type" => "content_block_start", "index" => i,
           "content_block" => { "type" => "tool_use", "id" => "toolu_#{i}", "name" => name, "input" => {} } },
         { "type" => "content_block_delta", "index" => i, "delta" => { "type" => "input_json_delta", "partial_json" => json[0, 3] } },
         { "type" => "content_block_delta", "index" => i, "delta" => { "type" => "input_json_delta", "partial_json" => json[3..] } },
         { "type" => "content_block_stop", "index" => i }]
      end + [{ "type" => "message_delta", "delta" => { "stop_reason" => "tool_use" }, "usage" => { "output_tokens" => 1 } },
             { "type" => "message_stop" }]
    end

    def error(message) = { "type" => "error", "error" => { "type" => "overloaded_error", "message" => message } }
  end

  # OpenAI Responses API and xAI Grok.
  module Responses
    module_function

    def text(pieces)
      [{ "type" => "response.created", "response" => { "id" => "r", "metadata" => {} } }] +
        pieces.map { |p| { "type" => "response.output_text.delta", "item_id" => "m", "delta" => p } } +
        [{ "type" => "response.output_text.done", "item_id" => "m", "text" => pieces.join },
         { "type" => "response.completed", "response" => { "id" => "r", "status" => "completed" } }]
    end

    def calls(calls)
      items = calls.each_with_index.map do |(name, args), i|
        { "type" => "function_call", "id" => "fc_#{i}", "call_id" => "call_#{i}", "name" => name, "arguments" => JSON.generate(args) }
      end
      [{ "type" => "response.created", "response" => { "id" => "r", "metadata" => {} } }] +
        items.flat_map do |item|
          json = item["arguments"]
          [{ "type" => "response.output_item.added", "item" => item.merge("arguments" => "") },
           { "type" => "response.function_call_arguments.delta", "item_id" => item["id"], "delta" => json[0, 3] },
           { "type" => "response.function_call_arguments.delta", "item_id" => item["id"], "delta" => json[3..] },
           { "type" => "response.function_call_arguments.done", "item_id" => item["id"], "arguments" => json },
           { "type" => "response.output_item.done", "item" => item }]
        end + [{ "type" => "response.completed", "response" => { "id" => "r", "status" => "completed", "output" => items } }]
    end

    def error(message) = { "type" => "error", "message" => message }
  end

  module Ollama
    module_function

    def text(pieces)
      pieces.map { |p| { "message" => { "role" => "assistant", "content" => p }, "done" => false } } +
        [{ "message" => { "role" => "assistant", "content" => "" }, "done" => true }]
    end

    def calls(calls)
      [{ "message" => { "role" => "assistant", "content" => "",
                        "tool_calls" => calls.map { |name, args| { "function" => { "name" => name, "arguments" => args } } } },
         "done" => false },
       { "message" => { "role" => "assistant", "content" => "" }, "done" => true }]
    end

    def error(message) = { "error" => message }
  end
end

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
    allow(helper).to receive(:invoke_mistral_tool_function) do |_app, _session, _call, name|
      ran << name
      [{ "role" => "tool", "tool_call_id" => "x", "name" => name, "content" => "done" }, false, nil]
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
    stub_const("APPS", { "SpecApp" => double("app", settings: {}) })
    session = { parameters: { "app_name" => "SpecApp", "model" => "mistral-medium-latest", "message" => "Go",
                              "context_size" => "5", "max_tokens" => "1000", "temperature" => "0.5" },
                messages: [{ "role" => "system", "text" => "S", "active" => true }] }
    shown = +""
    error = nil
    helper.api_request("user", session) do |e|
      next unless e.is_a?(Hash)

      shown << e["content"].to_s if e["type"] == "fragment" && ran.empty?
      error = e["content"] if e["type"] == "error"
    end
    [shown, ran, error]
  end

  def read_with(helper_module, chunks)
    helper = Class.new(MonadicApp) { include helper_module }.new
    ran = nil
    allow(helper).to receive(:process_functions) do |*args|
      ran = args[2]
      [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "" } }] }]
    end
    session = { parameters: { "app_name" => "SpecApp", "model" => "m" }, messages: [], call_depth_per_turn: 0 }
    shown = +""
    error = nil
    sink = proc do |e|
      next unless e.is_a?(Hash)

      shown << e["content"].to_s if e["type"] == "fragment"
      error = e["content"] if e["type"] == "error"
    end
    yield(helper, session, chunks, sink)
    [shown, call_names(ran), error]
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
end
