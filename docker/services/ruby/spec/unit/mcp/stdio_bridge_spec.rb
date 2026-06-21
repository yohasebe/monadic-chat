# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require_relative "../../../scripts/mcp_stdio_bridge"

RSpec.describe MonadicConduitStdioBridge do
  let(:output) { StringIO.new }

  def bridge(forwarder)
    described_class.new(output: output, forwarder: forwarder)
  end

  def lines
    output.string.each_line.map(&:strip).reject(&:empty?)
  end

  it "forwards a request and writes the server response as one line" do
    seen = nil
    b = bridge(->(line) { seen = line; '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}' })
    b.process('{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')

    expect(seen).to include('"tools/list"')
    expect(lines.size).to eq(1)
    expect(JSON.parse(lines.first)).to include("result" => { "ok" => true })
  end

  it "does NOT reply to a notification (no id), but still forwards it" do
    forwarded = false
    b = bridge(->(_line) { forwarded = true; '{"jsonrpc":"2.0","id":null,"error":{"code":-32600}}' })
    b.process('{"jsonrpc":"2.0","method":"notifications/initialized"}')

    expect(forwarded).to be true
    expect(lines).to be_empty
  end

  it "emits a JSON-RPC parse error for invalid JSON input" do
    b = bridge(->(_line) { raise "should not be called" })
    b.process('{ this is not json')

    err = JSON.parse(lines.first)
    expect(err["error"]["code"]).to eq(-32_700)
    expect(err["id"]).to be_nil
  end

  it "reports an unreachable server as a transport error carrying the request id" do
    b = bridge(->(_line) { raise Errno::ECONNREFUSED, "connection refused" })
    b.process('{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{}}')

    err = JSON.parse(lines.first)
    expect(err["id"]).to eq(7)
    expect(err["error"]["code"]).to eq(-32_603)
    expect(err["error"]["message"]).to match(/unreachable/)
  end

  it "stays silent when forwarding a notification fails" do
    b = bridge(->(_line) { raise Errno::ECONNREFUSED, "down" })
    b.process('{"jsonrpc":"2.0","method":"notifications/cancelled"}')
    expect(lines).to be_empty
  end

  it "treats a batch (array) as a request and writes the response" do
    b = bridge(->(_line) { '[{"jsonrpc":"2.0","id":1,"result":{}}]' })
    b.process('[{"jsonrpc":"2.0","id":1,"method":"tools/list"}]')
    expect(lines.size).to eq(1)
  end

  it "runs over stdin lines, skipping blanks" do
    calls = 0
    input = StringIO.new("\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"x\"}\n\n")
    described_class.new(input: input, output: output,
                        forwarder: ->(_l) { calls += 1; '{"jsonrpc":"2.0","id":1,"result":1}' }).run
    expect(calls).to eq(1)
    expect(lines.size).to eq(1)
  end
end
