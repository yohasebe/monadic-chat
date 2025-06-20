#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone test for MCP server
require 'bundler/setup'

# Mock CONFIG if not available
unless defined?(CONFIG)
  CONFIG = {
    "MCP_SERVER_ENABLED" => true,
    "MCP_SERVER_PORT" => 3100,
    "MCP_ENABLED_APPS" => "help",
    "EXTRA_LOGGING" => "true"
  }
end

# Set up paths
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Test loading the server
begin
  puts "Loading MCP server..."
  require_relative '../lib/monadic/mcp/server'
  puts "MCP server loaded successfully"
  
  # Try to start the server
  puts "Starting MCP server on port #{CONFIG["MCP_SERVER_PORT"]}..."
  Monadic::MCP::Server.set :port, CONFIG["MCP_SERVER_PORT"]
  Monadic::MCP::Server.set :bind, '127.0.0.1'
  Monadic::MCP::Server.run!
  
rescue LoadError => e
  puts "LoadError: #{e.message}"
  puts e.backtrace.join("\n")
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
end