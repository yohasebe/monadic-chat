# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require_relative "../../../lib/monadic/version"
require_relative "../../../lib/monadic/utils/model_spec"
require_relative "../../../lib/monadic/utils/container_dependencies"
require_relative "../../../lib/monadic/mcp/server"

# The MCP server as the HTTP server runs it (rack_app: guard + JSON-RPC app).
# A web page open on the same computer must not be able to call its tools.
RSpec.describe "MCP server and web pages" do
  include Rack::Test::Methods

  def app
    Monadic::MCP::Server.rack_app
  end

  let(:list_tools) { { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json }

  before do
    allow(Monadic::Utils::ContainerDependencies).to receive(:container_running?).and_return(false)
    header "Host", "127.0.0.1:3100"
  end

  it "serves an MCP client: JSON, no Origin" do
    post "/mcp", list_tools, "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body).dig("result", "tools")).not_to be_empty
  end

  it "refuses a body a page can send without asking first, before reading it" do
    expect_any_instance_of(Monadic::MCP::Server).not_to receive(:handle_single_request)
    ["text/plain", "application/x-www-form-urlencoded", "multipart/form-data; boundary=x", nil].each do |type|
      env = type ? { "CONTENT_TYPE" => type } : {}
      post "/mcp", list_tools, env
      expect(last_response.status).to eq(415), type.inspect
    end
  end

  it "refuses any request from a web page, with or without CORS" do
    expect_any_instance_of(Monadic::MCP::Server).not_to receive(:handle_single_request)
    %w[http://evil.example http://localhost:4567 null].each do |origin|
      header "Origin", origin
      post "/mcp", list_tools, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(403), "POST #{origin}"
      options "/mcp", nil, "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST"
      expect(last_response.status).to eq(403), "OPTIONS #{origin}"
    end
  end

  it "grants no page the right to read its answers" do
    post "/mcp", list_tools, "CONTENT_TYPE" => "application/json"
    expect(last_response.headers.keys.map(&:downcase).grep(/access-control/)).to be_empty
    get "/health"
    expect(last_response.headers.keys.map(&:downcase).grep(/access-control/)).to be_empty
  end

  it "refuses a request naming another host (DNS rebinding)" do
    header "Host", "evil.example:3100"
    post "/mcp", list_tools, "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(403)
  end
end
