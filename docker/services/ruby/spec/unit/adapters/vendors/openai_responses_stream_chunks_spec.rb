# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"

# A Responses API stream arrives in chunks that can end anywhere, also in the
# middle of an event or right after a "}" inside one. However it is cut, the
# whole answer and the usage of the completed event come through.
RSpec.describe "OpenAI Responses stream split into chunks" do
  let(:helper) { Class.new(MonadicApp) { include OpenAIHelper }.new }
  let(:words) { %w[The bridge carries cyclists every week .] }
  let(:usage) { { "input_tokens" => 1200, "output_tokens" => 34, "total_tokens" => 1234 } }

  # Large events carry nested objects ("}" inside the line), as real ones do.
  let(:stream) do
    big = { "instructions" => "x" * 3000, "metadata" => { "a" => {} }, "tools" => [{ "name" => "t", "parameters" => {} }] }
    events = [{ "type" => "response.created", "response" => big.merge("model" => "gpt-6.1-sol") }]
    words.each_with_index do |w, i|
      events << { "type" => "response.output_text.delta", "item_id" => "m1", "delta" => (i.zero? ? w : " #{w}") }
    end
    events << { "type" => "response.output_text.done", "item_id" => "m1", "text" => words.join(" ") }
    events << { "type" => "response.completed", "response" => big.merge("usage" => usage, "status" => "completed") }
    events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
  end

  def run_with(chunk_size)
    chunks = stream.b.bytes.each_slice(chunk_size).map { |slice| slice.pack("C*").force_encoding("UTF-8") }
    res = Object.new
    res.define_singleton_method(:each) { |&b| chunks.each(&b) }
    session = { parameters: { "app_name" => "TestApp" }, messages: [] }
    helper.process_responses_api_data(app: "TestApp", session: session, query: { "model" => "gpt-6.1-sol" },
                                      res: res, call_depth: 0) { |_fragment| nil }
  end

  [1, 7, 256, 4096, 1_000_000].each do |size|
    it "keeps every word and the usage with chunks of #{size} bytes" do
      result = run_with(size).first
      expect(result.dig("choices", 0, "message", "content")).to eq(words.join(" "))
      expect(result["usage"]).to include("input_tokens" => 1200, "output_tokens" => 34)
    end
  end
end
