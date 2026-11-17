# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"

# A streamed reply is read the same whatever the chunks it arrives in.
RSpec.describe "Gemini stream reading" do
  let(:host) { Class.new { include GeminiHelper }.new }
  let(:session) { { parameters: { "app_name" => "SpecApp" }, messages: [] } }

  def event(object)
    "data: #{JSON.generate(object)}\n\n"
  end

  def text(value, finish = nil)
    event({ "candidates" => [{ "content" => { "role" => "model", "parts" => [{ "text" => value }] },
                               "finishReason" => finish }.compact] })
  end

  def read(chunks)
    events = []
    reply = host.process_json_data(app: "SpecApp", session: session, query: {}, res: chunks, call_depth: 0) { |e| events << e }
    [reply, events]
  end

  def fragments(events)
    events.select { |e| e["type"] == "fragment" }.map { |e| e["content"] }.join
  end

  it "keeps every record whatever the chunks" do
    stream = (text("日本語の") + text("テキスト", "STOP")).b
    (0..stream.bytesize).each do |i|
      _reply, events = read([stream.byteslice(0, i), stream.byteslice(i, stream.bytesize - i)])
      expect(fragments(events)).to eq("日本語のテキスト")
    end
  end

  it "ends the reply as an error when the stream reports one, and runs no tool before it" do
    call = event({ "candidates" => [{ "content" => { "role" => "model", "parts" => [
      { "functionCall" => { "name" => "some_tool", "args" => {} } }
    ] } }] })
    expect(host).not_to receive(:process_functions)
    reply, events = read([text("Partial"), call, event({ "error" => { "code" => 503, "message" => "overloaded" } })])
    expect(reply.first["type"]).to eq("error")
    expect(reply.first["content"]).to include("overloaded")
    expect(events.last["type"]).to eq("error")
  end
end
