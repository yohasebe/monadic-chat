# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require_relative "../../../lib/monadic/version"
require_relative "../../../lib/monadic/utils/model_spec"
require_relative "../../../lib/monadic/utils/container_dependencies"
require_relative "../../../lib/monadic/mcp/server"

# End-to-end JSON-RPC checks for the MCP server's Conduit dispatch
# (handle_tools_list / handle_tool_call rewired to the monadic_* surface).
RSpec.describe Monadic::MCP::Server do
  include Rack::Test::Methods

  def app
    Monadic::MCP::Server
  end

  def rpc(method, params = {}, id = 1)
    post "/mcp", { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         "CONTENT_TYPE" => "application/json", "HTTP_HOST" => "localhost"
    JSON.parse(last_response.body)
  end

  before do
    allow(Monadic::Utils::ContainerDependencies)
      .to receive(:container_running?).and_return(false)
  end

  describe "tools/list" do
    it "returns the Conduit capability surface, not app__tool entries" do
      body = rpc("tools/list")
      names = body.dig("result", "tools").map { |t| t["name"] }
      expect(names).to contain_exactly(
        "monadic_status", "monadic_list_models", "monadic_query",
        "monadic_parallel_query", "monadic_second_opinion",
        "monadic_search_kb", "monadic_list_kb", "monadic_import_kb",
        "monadic_analyze_image", "monadic_transcribe_audio",
        "monadic_speak", "monadic_generate_code", "monadic_generate_image",
        "monadic_generate_video", "monadic_generate_music",
        "monadic_submit", "monadic_poll", "monadic_cancel", "monadic_jobs"
      )
    end
  end

  describe ".mcp_bind_host" do
    it "binds all interfaces inside the container so Docker port publish works" do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(true)
      expect(described_class.mcp_bind_host).to eq("0.0.0.0")
    end

    it "binds loopback on the host (dev mode)" do
      allow(Monadic::Utils::Environment).to receive(:in_container?).and_return(false)
      expect(described_class.mcp_bind_host).to eq("127.0.0.1")
    end
  end

  describe "tools/call monadic_status" do
    it "returns both text content and structuredContent" do
      body = rpc("tools/call", { "name" => "monadic_status", "arguments" => {} })
      result = body["result"]
      expect(result["content"].first["type"]).to eq("text")
      expect(result["structuredContent"]).to include("backend")
      # text payload is the structured object serialized as JSON
      parsed = JSON.parse(result["content"].first["text"])
      expect(parsed["backend"]["name"]).to eq("monadic-chat")
    end
  end

  describe "tools/call monadic_list_models" do
    it "honors the provider filter through the full RPC path" do
      body = rpc("tools/call",
                 { "name" => "monadic_list_models", "arguments" => { "provider" => "anthropic" } })
      providers = body.dig("result", "structuredContent", "providers").map { |p| p["provider"] }
      expect(providers).to eq(["anthropic"])
    end
  end

  describe "error handling" do
    it "rejects an unknown tool with INVALID_PARAMS" do
      body = rpc("tools/call", { "name" => "Chat__legacy_tool", "arguments" => {} })
      expect(body.dig("error", "code")).to eq(Monadic::MCP::Server::INVALID_PARAMS)
      expect(body.dig("error", "message")).to match(/Unknown tool/)
    end

    it "returns METHOD_NOT_FOUND for an unsupported method" do
      body = rpc("nonexistent/method")
      expect(body.dig("error", "code")).to eq(Monadic::MCP::Server::METHOD_NOT_FOUND)
    end
  end

  describe "initialize" do
    it "advertises tools capability and server info" do
      body = rpc("initialize", { "clientInfo" => { "name" => "test" } })
      expect(body.dig("result", "capabilities")).to include("tools")
      expect(body.dig("result", "serverInfo", "name")).to eq("monadic-chat")
    end
  end
end
