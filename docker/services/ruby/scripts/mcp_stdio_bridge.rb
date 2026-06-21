#!/usr/bin/env ruby
# frozen_string_literal: true

# Monadic Conduit — stdio <-> HTTP bridge.
#
# Many MCP clients speak only the stdio transport: they launch a subprocess and
# exchange newline-delimited JSON-RPC over stdin/stdout. Monadic Conduit's MCP
# server is HTTP (http://127.0.0.1:3100/mcp). This bridge lets a stdio client
# use Conduit: it reads one JSON-RPC message per line from stdin, forwards it to
# the HTTP endpoint, and writes the response back as one line on stdout.
#
# It is intentionally self-contained (Ruby stdlib only) so it can be copied
# anywhere and run by the host's ruby, with no bundler or Monadic load path.
#
# Register it with an MCP client, e.g.:
#   <client> mcp add monadic-conduit -- ruby /path/to/mcp_stdio_bridge.rb
#
# Requires the Monadic app to be running with MCP enabled
# (MCP_SERVER_ENABLED=true). Honors MCP_SERVER_HOST / MCP_SERVER_PORT.

require 'json'
require 'net/http'
require 'uri'

class MonadicConduitStdioBridge
  PARSE_ERROR = -32_700
  INTERNAL_ERROR = -32_603

  def initialize(host: ENV['MCP_SERVER_HOST'] || '127.0.0.1',
                 port: (ENV['MCP_SERVER_PORT'] || 3100).to_i,
                 input: $stdin, output: $stdout, forwarder: nil)
    @uri = URI("http://#{host}:#{port}/mcp")
    @input = input
    @output = output
    @forwarder = forwarder || method(:post_http)
  end

  # Read newline-delimited JSON-RPC messages until stdin closes.
  def run
    @input.each_line do |line|
      line = line.strip
      next if line.empty?

      process(line)
    end
  end

  # Process a single stdio line: forward it and emit 0 or 1 response lines.
  # A JSON-RPC notification (an object with no `id`) gets no reply.
  def process(line)
    request = parse(line)
    return emit(parse_error) if request.nil?

    notification = request.is_a?(Hash) && !request.key?('id')

    begin
      response = @forwarder.call(line)
    rescue StandardError => e
      return if notification

      return emit(transport_error(request, e))
    end

    return if notification

    emit(response) if response && !response.to_s.empty?
  end

  private

  def parse(line)
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  def post_http(body)
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.open_timeout = 5
    http.read_timeout = 600   # long media/code jobs run async; queries are short
    req = Net::HTTP::Post.new(@uri.path, 'Content-Type' => 'application/json', 'Accept' => 'application/json')
    req.body = body
    http.request(req).body
  end

  def emit(line)
    @output.puts(line)
    @output.flush
  end

  def parse_error
    { jsonrpc: '2.0', id: nil, error: { code: PARSE_ERROR, message: 'Parse error' } }.to_json
  end

  def transport_error(request, error)
    id = request.is_a?(Hash) ? request['id'] : nil
    {
      jsonrpc: '2.0',
      id: id,
      error: {
        code: INTERNAL_ERROR,
        message: 'Monadic Conduit MCP server unreachable',
        data: "#{error.class}: #{error.message} (is Monadic running with MCP_SERVER_ENABLED=true at #{@uri}?)"
      }
    }.to_json
  end
end

MonadicConduitStdioBridge.new.run if $PROGRAM_NAME == __FILE__
