# frozen_string_literal: true

require "json"

# Streams in each provider's format, for the specs that read replies the
# way the providers send them.
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
