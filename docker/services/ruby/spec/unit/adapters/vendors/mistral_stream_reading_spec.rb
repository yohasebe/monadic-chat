# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/mistral_helper"

# A streamed reply is read the same whatever the chunks it arrives in.
RSpec.describe "Mistral stream reading" do
  let(:helper) { Class.new { include MistralHelper }.new }
  let(:obj) { { "model" => "mistral-medium-latest" } }

  def event(json)
    "data: #{JSON.generate(json)}\n\n"
  end

  def delta(content)
    event({ "choices" => [{ "delta" => { "content" => content } }] })
  end

  def read(chunks)
    helper.send(:read_mistral_stream, chunks, obj, false) { |_res| }
  end

  it "keeps every character when a chunk ends inside one or just after a brace" do
    stream = (delta("日本語の") + delta("テキスト") + "data: [DONE]\n\n").b
    (0..stream.bytesize).each do |i|
      chunks = [stream.byteslice(0, i), stream.byteslice(i, stream.bytesize - i)]
      expect(read(chunks)[:content]).to eq("日本語のテキスト")
    end
  end

  it "keeps every call of a delta that holds several" do
    calls = [0, 1].map do |i|
      { "index" => i, "id" => "c#{i}", "function" => { "name" => "t#{i}", "arguments" => "{\"n\":#{i}}" } }
    end
    result = read([event({ "choices" => [{ "delta" => { "tool_calls" => calls } }] })])
    expect(result[:tool_calls].map { |c| [c["id"], c.dig("function", "arguments")] })
      .to eq([["c0", '{"n":0}'], ["c1", '{"n":1}']])
  end

  it "joins the arguments that come in later deltas to their call" do
    first = { "index" => 0, "id" => "c0", "function" => { "name" => "t", "arguments" => "{\"a\":" } }
    rest = { "index" => 0, "function" => { "arguments" => "1}" } }
    result = read([event({ "choices" => [{ "delta" => { "tool_calls" => [first] } }] }),
                   event({ "choices" => [{ "delta" => { "tool_calls" => [rest] } }] })])
    expect(result[:tool_calls].first.dig("function", "arguments")).to eq('{"a":1}')
  end

  it "reports an error the stream sends and stops reading" do
    result = read([delta("Partial"), event({ "error" => { "message" => "overloaded" } }), delta(" more")])
    expect(result[:error]).to eq("overloaded")
    expect(result[:content]).to eq("Partial")
  end

  it "stops at [DONE]" do
    expect(read([delta("A"), "data: [DONE]\n\n", delta("B")])[:content]).to eq("A")
  end
end
