#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'time'

# MCP HTTP Proxy for Claude Desktop
# This script acts as a bridge between Claude Desktop (stdio) and Monadic Chat MCP server (HTTP)

class MCPProxy
  def initialize
    @base_url = ENV['MCP_SERVER_URL'] || 'http://localhost:3100/mcp'
    @debug = ENV['MCP_DEBUG'] == 'true'
    
    log("MCP Proxy started, connecting to: #{@base_url}")
  end

  def run
    loop do
      begin
        # Read JSON-RPC request from stdin
        line = STDIN.gets
        break unless line
        
        # Skip empty lines
        next if line.strip.empty?
        
        request = JSON.parse(line.strip)
        log("Received request: #{request}")
        
        # Forward to HTTP server
        response = forward_to_http(request)
        log("Got response: #{response}")
        
        # Only write response if it's not empty (notifications don't require responses)
        unless response.nil? || response.empty? || response == ""
          STDOUT.puts(response.to_json)
          STDOUT.flush
        end
        
      rescue JSON::ParserError => e
        error_response = {
          jsonrpc: "2.0",
          id: nil,
          error: {
            code: -32700,
            message: "Parse error",
            data: e.message
          }
        }
        STDOUT.puts(error_response.to_json)
        STDOUT.flush
      rescue => e
        log("Error: #{e.class} - #{e.message}")
        log(e.backtrace.join("\n")) if @debug
        
        error_response = {
          jsonrpc: "2.0",
          id: nil,
          error: {
            code: -32603,
            message: "Internal error",
            data: e.message
          }
        }
        STDOUT.puts(error_response.to_json)
        STDOUT.flush
      end
    end
  end

  private

  def forward_to_http(request)
    uri = URI(@base_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 30
    
    http_request = Net::HTTP::Post.new(uri)
    http_request['Content-Type'] = 'application/json'
    http_request['Accept'] = 'application/json'
    http_request.body = request.to_json
    
    response = http.request(http_request)
    
    if response.code == '200'
      # Handle empty responses (e.g., from notifications)
      if response.body.nil? || response.body.strip.empty?
        return nil
      end
      
      begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        log("Failed to parse response: #{response.body}")
        {
          jsonrpc: "2.0",
          id: request['id'],
          error: {
            code: -32700,
            message: "Parse error",
            data: e.message
          }
        }
      end
    else
      {
        jsonrpc: "2.0",
        id: request['id'],
        error: {
          code: -32603,
          message: "HTTP error: #{response.code}",
          data: response.body
        }
      }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    {
      jsonrpc: "2.0",
      id: request['id'],
      error: {
        code: -32603,
        message: "Connection timeout",
        data: "MCP server at #{@base_url} is not responding"
      }
    }
  rescue => e
    {
      jsonrpc: "2.0",
      id: request['id'],
      error: {
        code: -32603,
        message: "Connection error",
        data: e.message
      }
    }
  end

  def log(message)
    return unless @debug
    
    File.open('/tmp/mcp_proxy.log', 'a') do |f|
      f.puts("[#{Time.now.iso8601}] #{message}")
    end
  end
end

# Run the proxy
if __FILE__ == $0
  proxy = MCPProxy.new
  proxy.run
end