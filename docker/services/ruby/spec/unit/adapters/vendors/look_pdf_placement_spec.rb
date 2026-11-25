# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../../../lib/monadic/adapters/vendors/gemini_helper"
require_relative "../../../../lib/monadic/workspace"
require_relative "../../../../lib/monadic/workbench/look"

# A PDF a look gives as it is goes in the request after the results it
# answers: for Claude as a document block after the message's tool results,
# for Gemini as inline data in the user turn that follows the results.
RSpec.describe "A PDF a look gives as it is, in the request" do
  LOOK_ID = "look_#{'c' * 16}".freeze

  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, parameters: {}, messages: [] } }
  let(:pdf) { "%PDF-1.4\n%%EOF\n".b }
  let(:ledger) do
    Monadic::Workbench::Look::Ledger.for(chat, Monadic::Workspace::Chats.epoch(chat), request_id, session: session)
  end

  around do |example|
    Monadic::Workbench::Look::Ledger.reset!
    context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id)
    Monadic::Workspace::RequestContext.with(context) { example.run }
  end

  def file_look(call)
    id = ledger.add(id: LOOK_ID, item_id: "i_1", kind: "pdf", name: "paper.pdf", path: "paper.pdf", version: "a" * 64,
                    scope: "whole", file: Monadic::Workbench::Look::FileValue.pdf(pdf), pages: { first: 1, last: 2, total: 2 },
                    parts: { "file" => true }, result: %({"status":"looked","observation_id":"#{LOOK_ID}"}),
                    caption: "The PDF below is #{LOOK_ID}")
    ledger.bind(id, call)
    id
  end

  it "follows Claude's tool results as a document, and is held for the check before the post" do
    helper = Class.new(MonadicApp) { include ClaudeHelper }.new
    file_look("toolu_1")
    messages = [{ "role" => "user", "content" => [{ "type" => "tool_result", "tool_use_id" => "toolu_1", "content" => "ok" }] }]
    out = helper.send(:claude_messages_with_looks, messages, session)
    content = out.first["content"]
    expect(content.map { |b| b[:type] || b["type"] }).to eq(%w[tool_result text document])
    expect(content.last[:source]).to eq(type: "base64", media_type: "application/pdf", data: Base64.strict_encode64(pdf))
    expect(ledger.held).to eq([LOOK_ID])
  end

  it "goes as Gemini's inline data after the results" do
    helper = Class.new(MonadicApp) { include GeminiHelper }.new
    file_look("call_1")
    turn = helper.send(:gemini_look_turn, session, ["call_1"])
    expect(turn["role"]).to eq("user")
    expect(turn["parts"]).to eq([{ "text" => "The PDF below is #{LOOK_ID}" },
                                 { "inlineData" => { "mimeType" => "application/pdf", "data" => Base64.strict_encode64(pdf) } }])
    expect(helper.send(:gemini_look_turn, session, ["other"])).to be_nil
  end
end
