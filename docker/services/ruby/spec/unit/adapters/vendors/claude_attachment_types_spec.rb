# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/adapters/vendors/claude_helper"

# What Claude is sent of a message's attachments: images as images, a PDF as
# a document, and a message with another file refused before it is sent.
RSpec.describe "Claude attachments" do
  let(:helper) { Class.new(MonadicApp) { include ClaudeHelper }.new }
  let(:context) { [{ "role" => "user", "text" => "Look" }] }
  let(:session) { { messages: [], parameters: {} } }

  def build(files)
    body = {}
    shown = []
    result = helper.send(:build_claude_messages, body, context, { "images" => files }, "claude-sonnet-5-5", "user", session) do |res|
      shown << res
    end
    [body, result, shown]
  end

  def file(type, name)
    { "title" => name, "type" => type, "data" => "data:#{type};base64,AAAA" }
  end

  it "sends an image as an image and a PDF as a document" do
    body, result, shown = build([file("image/png", "a.png"), file("application/pdf", "b.pdf")])
    expect(result).not_to be_a(Array)
    expect(shown).to be_empty
    expect(body["messages"].last["content"].map { |c| c["type"] }).to eq(%w[document text image])
  end

  it "refuses a message with a file that is neither, without sending its name" do
    docx = file("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "private-notes.docx")
    body, result, shown = build([file("image/png", "a.png"), docx])
    expect(result.first["type"]).to eq("error")
    expect(shown.first["content"]).to include("images (JPEG, PNG, GIF, WebP) and PDFs only")
    expect(shown.first["content"]).not_to include("private-notes")
    expect(body).not_to have_key("messages")
  end
end
