# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"

# An app is one object shared by every chat that uses it: what a reply
# keeps belongs to its chat.
RSpec.describe "A reply's state with an app shared by chats" do
  let(:app) { Class.new(MonadicApp) { include ClaudeHelper }.new }

  def sse(events)
    events.map { |e| "event: #{e['type']}\ndata: #{JSON.generate(e)}\n\n" }.join
  end

  def reply(thinking: nil)
    events = [{ "type" => "message_start", "message" => { "id" => "m", "usage" => { "input_tokens" => 1 } } }]
    if thinking
      events += [{ "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "thinking", "thinking" => "" } },
                 { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "thinking_delta", "thinking" => thinking } },
                 { "type" => "content_block_delta", "index" => 0, "delta" => { "type" => "signature_delta", "signature" => "sig" } },
                 { "type" => "content_block_stop", "index" => 0 }]
    end
    events += [{ "type" => "content_block_start", "index" => 1, "content_block" => { "type" => "text", "text" => "" } },
               { "type" => "content_block_delta", "index" => 1, "delta" => { "type" => "text_delta", "text" => "Done." } },
               { "type" => "content_block_stop", "index" => 1 },
               { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 1 } },
               { "type" => "message_stop" }]
    [sse(events)]
  end

  def answer(session, stream)
    app.process_json_data(app: "SpecApp", session: session, query: {}, res: stream, call_depth: 0) { |_| }
  end

  it "keeps one chat's reasoning out of another chat's reply" do
    chat_a = { parameters: { "app_name" => "SpecApp", "model" => "m" }, messages: [], call_depth_per_turn: 0 }
    chat_b = { parameters: { "app_name" => "SpecApp", "model" => "m" }, messages: [], call_depth_per_turn: 0 }
    answer(chat_a, reply(thinking: "Chat A's private reasoning"))
    result = answer(chat_b, reply)
    expect(JSON.generate(result)).not_to include("Chat A's private reasoning")
  end
end
