# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../../../lib/monadic/workspace"
require_relative "../../../../lib/monadic/workbench/look"

# A file a look gives as it is goes to OpenAI as a file part of its own
# data (never uploaded), after the tool results it answers, named by its
# kind; the log shows none of its data.
RSpec.describe "A file a look gives as it is, for OpenAI" do
  FILE_LOOK = "look_#{'d' * 16}".freeze
  DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  let(:helper) { Class.new(MonadicApp) { include OpenAIHelper }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:request_id) { Monadic::Workspace::Ids.generate(:request) }
  let(:session) { { chat_id: chat, parameters: {}, messages: [] } }
  let(:bytes) { "PK\x03\x04 a report".b }
  let(:ledger) do
    Monadic::Workbench::Look::Ledger.for(chat, Monadic::Workspace::Chats.epoch(chat), request_id, session: session)
  end

  around do |example|
    Monadic::Workbench::Look::Ledger.reset!
    context = Monadic::Workspace::RequestContext.new(chat_id: chat, request_id: request_id)
    Monadic::Workspace::RequestContext.with(context) { example.run }
  end

  before do
    id = ledger.add(id: FILE_LOOK, item_id: "i_1", kind: "text", name: "private-report.docx", path: "private-report.docx",
                    version: "a" * 64, scope: "whole", file: Monadic::Workbench::Look::FileValue.document(bytes, DOCX),
                    parts: { "file" => true }, result: %({"status":"looked","observation_id":"#{FILE_LOOK}"}),
                    caption: "The document below is #{FILE_LOOK}")
    ledger.bind(id, "call_1")
  end

  # The request OpenAI is sent with the tool's results, built by the helper.
  def built
    body = {}
    context = [{ "role" => "system", "text" => "S" }, { "role" => "user", "text" => "Read it" }]
    obj = { "model" => "gpt-6.1-sol", "function_returns" => [{ "role" => "tool", "tool_call_id" => "call_1", "content" => "looked" }] }
    helper.send(:build_openai_messages, body, context, {}, obj, "tool", false, [], true, false, nil, nil, nil, nil)
    body
  end

  def file_part(body)
    body["messages"].flat_map { |m| Array(m[:content] || m["content"]) }.find { |c| c.is_a?(Hash) && c["type"] == "file" }
  end

  it "follows the results as a file part of its data, named by its kind, and is held for the check before the post" do
    expect(file_part(built)).to eq("type" => "file", "file" => { "filename" => "document.docx",
                                                                 "file_data" => "data:#{DOCX};base64,#{Base64.strict_encode64(bytes)}" })
    expect(ledger.held).to eq([FILE_LOOK])
  end

  it "becomes an input file of the Responses API" do
    body = built
    body["messages"] = body["messages"].map { |m| m.transform_keys(&:to_s) }
    input = helper.send(:convert_to_responses_api_body, body, {}, "gpt-6.1-sol", session, nil, "gpt-6.1-sol")
    part = input["input"].flat_map { |m| Array(m["content"]) }.find { |c| c["type"] == "input_file" }
    expect(part).to include("filename" => "document.docx", "file_data" => start_with("data:#{DOCX};base64,"))
  end

  it "shows none of its data in the log" do
    logged = JSON.generate(helper.workbench_loggable(built))
    expect(logged).not_to include(Base64.strict_encode64(bytes))
    expect(logged).not_to include("private-report")
  end
end
