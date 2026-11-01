# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/adapters/vendors/grok_helper"
require_relative "../../../../lib/monadic/adapters/vendors/deepseek_helper"
require_relative "../../../../lib/monadic/adapters/vendors/cohere_helper"

# A streamed answer arrives in chunks that can end anywhere: in the middle of
# an event, or right after a "}" inside one. However the stream is cut, every
# piece of the answer is passed on.
RSpec.describe "Streamed answers cut into chunks" do
  let(:words) { %w[The bridge carries cyclists every week] }
  let(:pieces) { words.each_with_index.map { |w, i| i.zero? ? w : " #{w}" } }

  def sse(events)
    events.map { |e| "data: #{JSON.generate(e)}\n\n" }.join
  end

  def chat_completions_stream(model)
    deltas = pieces.map do |p|
      { "id" => "c1", "object" => "chat.completion.chunk", "model" => model,
        "choices" => [{ "index" => 0, "delta" => { "content" => p }, "finish_reason" => nil }] }
    end
    # The first chunk names the role with empty content, as the providers send it.
    first = { "id" => "c1", "object" => "chat.completion.chunk", "model" => model,
              "choices" => [{ "index" => 0, "delta" => { "role" => "assistant", "content" => "" }, "finish_reason" => nil }] }
    last = { "id" => "c1", "object" => "chat.completion.chunk", "model" => model,
             "choices" => [{ "index" => 0, "delta" => {}, "finish_reason" => "stop" }] }
    sse([first] + deltas + [last]) + "data: [DONE]\n\n"
  end

  STREAMS = {
    "OpenAI Chat Completions" => [OpenAIHelper, "gpt-4.1", :chat_completions_stream],
    "Grok" => [GrokHelper, "grok-4", :responses_stream],
    "DeepSeek" => [DeepSeekHelper, "deepseek-flash", :chat_completions_stream],
    "Claude" => [ClaudeHelper, "claude-sonnet-5-5", :claude_stream],
    "Cohere" => [CohereHelper, "command-a", :cohere_stream]
  }.freeze

  def responses_stream(model)
    events = [{ "type" => "response.created", "response" => { "id" => "r1", "model" => model, "metadata" => {} } }]
    pieces.each { |p| events << { "type" => "response.output_text.delta", "item_id" => "m1", "delta" => p } }
    events << { "type" => "response.output_text.done", "item_id" => "m1", "text" => pieces.join }
    events << { "type" => "response.completed", "response" => { "id" => "r1", "model" => model, "status" => "completed",
                                                                "usage" => { "input_tokens" => 1, "output_tokens" => 6 } } }
    events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
  end

  def claude_stream(model)
    events = [{ "type" => "message_start", "message" => { "id" => "m1", "model" => model, "usage" => { "input_tokens" => 1 } } },
              { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" } }]
    pieces.each { |p| events << { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "text_delta", "text" => p } } }
    events << { "type" => "content_block_stop", "index" => 0 }
    events << { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 6 } }
    events << { "type" => "message_stop" }
    events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
  end

  def cohere_stream(_model)
    events = [{ "type" => "message-start", "id" => "m1", "delta" => { "message" => { "role" => "assistant" } } },
              { "type" => "content-start", "index" => 0, "delta" => { "message" => { "content" => { "type" => "text", "text" => "" } } } }]
    pieces.each do |p|
      events << { "type" => "content-delta", "index" => 0, "delta" => { "message" => { "content" => { "text" => p } } } }
    end
    events << { "type" => "content-end", "index" => 0 }
    events << { "type" => "message-end", "delta" => { "finish_reason" => "COMPLETE" } }
    events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
  end

  attr_accessor :builder_reader

  def run(helper_module, model, stream, chunk_size)
    helper = Class.new(MonadicApp) { include helper_module }.new
    chunks = stream.b.bytes.each_slice(chunk_size).map { |s| s.pack("C*").force_encoding("UTF-8") }
    res = Object.new
    res.define_singleton_method(:each) { |&b| chunks.each(&b) }
    text = +""
    # As api_request leaves the session at the start of a user turn.
    session = { parameters: { "app_name" => "TestApp", "model" => model }, messages: [], call_depth_per_turn: 0 }
    reader = builder_reader
    result = helper.public_send(reader, app: "TestApp", session: session, query: { "model" => model }, res: res,
                                        call_depth: 0) do |fragment|
      text << fragment["content"].to_s if fragment.is_a?(Hash) && fragment["type"] == "fragment"
    end
    # A reader that holds the text back until the end returns it instead.
    text.empty? ? Array(result).first&.dig("choices", 0, "message", "content").to_s : text
  end

  STREAMS.each do |name, (helper_module, model, builder)|
    describe name do
      [1, 5, 64, 1_000_000].each do |size|
        it "passes on every piece with chunks of #{size} bytes" do
          stream = send(builder, model)
          self.builder_reader = builder == :responses_stream ? :process_responses_api_data : :process_json_data
          expect(run(helper_module, model, stream, size)).to eq(pieces.join)
        end
      end
    end
  end
end
