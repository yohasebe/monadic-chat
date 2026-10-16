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

  def post_raw(body)
    post "/mcp", body, "CONTENT_TYPE" => "application/json", "HTTP_HOST" => "localhost"
    last_response
  end

  describe "JSON-RPC framing" do
    it "answers a notification with 202 and no body" do
      res = post_raw({ jsonrpc: "2.0", method: "notifications/initialized" }.to_json)
      expect(res.status).to eq(202)
      expect(res.body).to be_empty
    end

    it "answers ping with an empty result" do
      expect(rpc("ping")).to eq("jsonrpc" => "2.0", "id" => 1, "result" => {})
    end

    it "answers a batch with an array of reply objects, leaving notifications out" do
      batch = [{ jsonrpc: "2.0", id: 1, method: "ping" },
               { jsonrpc: "2.0", method: "notifications/initialized" },
               { jsonrpc: "2.0", id: 2, method: "ping" }]
      replies = JSON.parse(post_raw(batch.to_json).body)
      expect(replies).to eq([{ "jsonrpc" => "2.0", "id" => 1, "result" => {} },
                             { "jsonrpc" => "2.0", "id" => 2, "result" => {} }])
    end

    it "answers a batch of notifications only with 202" do
      expect(post_raw([{ jsonrpc: "2.0", method: "notifications/initialized" }].to_json).status).to eq(202)
    end

    it "marks only the bad element of a batch as an Invalid Request" do
      replies = JSON.parse(post_raw([1, { jsonrpc: "2.0", id: 7, method: "ping" }].to_json).body)
      expect(replies[0].dig("error", "code")).to eq(-32_600)
      expect(replies[1]).to eq("jsonrpc" => "2.0", "id" => 7, "result" => {})
    end

    it "answers an empty batch with one Invalid Request" do
      expect(JSON.parse(post_raw("[]").body).dig("error", "code")).to eq(-32_600)
    end

    it "answers params or arguments that are not objects with Invalid params" do
      post_raw({ jsonrpc: "2.0", id: 1, method: "tools/list", params: [] }.to_json)
      expect(JSON.parse(last_response.body).dig("error", "code")).to eq(-32_602)
      [[], false, nil].each do |value|
        expect(rpc("tools/call", { "name" => "monadic_status", "arguments" => value }).dig("error", "code")).to eq(-32_602)
      end
    end

    it "runs a tool when arguments are left out" do
      allow(Monadic::MCP::Conduit).to receive(:call).and_return({ success: true })
      expect(rpc("tools/call", { "name" => "monadic_status" })["result"]).to include("structuredContent")
    end

    it "takes a JSON-RPC response from the client with 202 and no body" do
      res = post_raw({ jsonrpc: "2.0", id: 5, result: {} }.to_json)
      expect(res.status).to eq(202)
      expect(res.body).to be_empty
    end

    it "refuses GET with 405" do
      get "/mcp", {}, "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(405)
    end
  end

  describe "tools/list" do
    it "returns the Conduit capability surface, not app__tool entries" do
      body = rpc("tools/list")
      names = body.dig("result", "tools").map { |t| t["name"] }
      expect(names).to contain_exactly(
        "monadic_status", "monadic_list_models", "monadic_query",
        "monadic_parallel_query", "monadic_second_opinion", "monadic_confidence",
        "monadic_search_kb", "monadic_list_kb", "monadic_import_kb",
        "monadic_analyze_image", "monadic_transcribe_audio",
        "monadic_analyze_audio", "monadic_analyze_video",
        "monadic_speak", "monadic_generate_code", "monadic_generate_image",
        "monadic_generate_video", "monadic_generate_music", "monadic_agent",
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

    it "maps a tool's ArgumentError (bad params) to INVALID_PARAMS, not INTERNAL_ERROR" do
      # monadic_query without a provider raises ArgumentError inside the handler.
      body = rpc("tools/call", { "name" => "monadic_query", "arguments" => { "message" => "hi" } })
      expect(body.dig("error", "code")).to eq(Monadic::MCP::Server::INVALID_PARAMS)
      expect(body.dig("error", "data")).to match(/provider is required/)
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
