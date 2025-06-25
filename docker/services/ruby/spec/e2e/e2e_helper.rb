# frozen_string_literal: true

require_relative '../spec_helper'
require 'net/http'
require 'uri'
require 'json'
require 'websocket-client-simple'
require 'timeout'
require 'dotenv'

# Load custom retry helper if enabled
if ENV['USE_CUSTOM_RETRY'] == 'true'
  require_relative 'e2e_retry_helper'
end

# Load configuration from ~/monadic/config/env for E2E tests
config_path = File.expand_path("~/monadic/config/env")
if File.exist?(config_path)
  Dotenv.load(config_path)
  # Override the empty CONFIG from spec_helper
  Object.send(:remove_const, :CONFIG) if defined?(CONFIG)
  CONFIG = ENV.to_hash
end

# Set PostgreSQL environment variables for E2E tests
ENV['POSTGRES_HOST'] ||= 'localhost'
ENV['POSTGRES_PORT'] ||= '5433'
ENV['POSTGRES_USER'] ||= 'postgres'
ENV['POSTGRES_PASSWORD'] ||= 'postgres'

# E2E Test Helper Module
module E2EHelper
  # Wait for server to be ready
  def wait_for_server(host: 'localhost', port: 4567, timeout: 30)
    Timeout.timeout(timeout) do
      loop do
        begin
          Net::HTTP.get(URI("http://#{host}:#{port}/health"))
          return true
        rescue Errno::ECONNREFUSED, Net::OpenTimeout
          sleep 1
        end
      end
    end
  rescue Timeout::Error
    false
  end

  # Create WebSocket connection
  def create_websocket_connection(host: 'localhost', port: 4567)
    begin
      # WebSocket endpoint is at root path, not /ws
      ws = WebSocket::Client::Simple.connect("ws://#{host}:#{port}/")
      
      # Store messages received
      messages = []
      connected = false
      
      ws.on :open do
        connected = true
      end
      
      ws.on :message do |msg|
        begin
          parsed = JSON.parse(msg.data)
          messages << parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError
          # Ignore non-JSON messages
        end
      end
      
      ws.on :error do |e|
        # WebSocket error - ignore stream closed errors
      end
      
      ws.on :close do |e|
        # Handle close event silently
      end
      
      # Wait for connection with timeout
      timeout = 5
      start_time = Time.now
      while !connected && Time.now - start_time < timeout
        sleep 0.1
      end
      
      unless connected
        raise "Failed to establish WebSocket connection to ws://#{host}:#{port}/"
      end
      
      { client: ws, messages: messages }
    rescue => e
      # Error creating WebSocket connection
      raise
    end
  end

  # Send a chat message via WebSocket
  def send_chat_message(ws_connection, message_text, app: "ChatOpenAI", model: "gpt-4o", max_tokens: nil, skip_activation: false)
    # Determine if this provider needs special handling for initiate_from_assistant: false
    needs_initial_message = false
    if !skip_activation && (app.include?("Gemini") || app.include?("DeepSeek") || app.include?("Mistral"))
      needs_initial_message = true
    end
    
    # For Gemini, ensure we have a clean state
    if app.include?("Gemini") && !ws_connection[:gemini_ready]
      # Force re-initialization for Gemini
      ws_connection[:messages].clear
      ws_connection[:gemini_ready] = true
    end
    # First, send LOAD message to initialize session
    load_message = {
      "message" => "LOAD"
    }
    ws_connection[:client].send(JSON.generate(load_message))
    sleep 1  # Wait for initialization
    
    # Get app tools and initial_prompt if available
    tools = nil
    initial_prompt = "You are a helpful assistant."
    
    ws_connection[:messages].each do |msg|
      if msg["type"] == "apps" && msg["content"][app]
        app_settings = msg["content"][app]
        
        # Parse tools if they're a JSON string
        if app_settings["tools"]
          if app_settings["tools"].is_a?(String)
            tools = JSON.parse(app_settings["tools"]) rescue nil
          else
            tools = app_settings["tools"]
          end
        end
        
        initial_prompt = app_settings["initial_prompt"] if app_settings["initial_prompt"]
        break
      end
    end
    
    # Send SYSTEM_PROMPT message if we have an initial prompt
    if initial_prompt && initial_prompt != "You are a helpful assistant."
      system_prompt_msg = {
        "message" => "SYSTEM_PROMPT",
        "content" => initial_prompt,
        "mathjax" => false,
        "monadic" => false
      }
      ws_connection[:client].send(JSON.generate(system_prompt_msg))
      sleep 0.5
    end
    
    # Then send the actual message
    # Based on the websocket.rb code, when msg == "fragment" is not a special case,
    # so the actual parameters are sent directly
    message_data = {
      "app_name" => app,
      "model" => model,
      "message" => message_text,
      "temperature" => 0.0,
      "context_size" => 10,
      "initial_prompt" => initial_prompt,  # Use the app's initial prompt
      "monadic" => false,
      "agent_name" => "",
      "websearch" => false,
      "auto_speech" => false,
      "tools" => tools  # Include tools for the app
    }
    
    # For apps with initiate_from_assistant, ensure message is not empty
    # to avoid "No response received from model" errors
    if message_text.to_s.strip.empty? && tools && tools.any? { |t| t["name"] == "check_environment" }
      # Add a minimal message to trigger proper response
      message_data["message"] = "Ready to help with code execution."
    end
    
    # Add max_tokens if provided (for Claude)
    message_data["max_tokens"] = max_tokens if max_tokens
    
    # For providers with initiate_from_assistant: false, send an activation message first
    if needs_initial_message
      # Check if we've sent initial message for this specific WebSocket connection
      ws_connection[:initial_message_sent] ||= {}
      
      if !ws_connection[:initial_message_sent][app]
        # Send a simple activation message first
        activation_msg = message_data.dup
        # For Gemini and DeepSeek, use a more explicit activation message
        if app.include?("Gemini")
          activation_msg["message"] = "I'm ready to execute Python code. Please give me a task to perform using the run_code function."
        elsif app.include?("DeepSeek")
          activation_msg["message"] = "Ready to execute code. What task would you like me to perform?"
        else
          activation_msg["message"] = "Hello, let's start working with code."
        end
        ws_connection[:client].send(JSON.generate(activation_msg))
        
        # Wait for activation response and consume it properly
        start_time = Time.now
        loop do
          if ws_connection[:messages].any? { |msg| msg["type"] == "message" && msg["content"] == "DONE" }
            break
          end
          if Time.now - start_time > 5
            # Activation timeout after 5 seconds
            break
          end
          sleep 0.1
        end
        
        # Extract activation response for debugging
        activation_response = extract_ai_response(ws_connection[:messages])
        # Activation response received
        
        # Clear messages to prepare for actual test
        ws_connection[:messages].clear
        
        # Mark that we've sent the initial message for this app/connection
        ws_connection[:initial_message_sent][app] = true
        
        # For Gemini, add a small delay after activation
        if app.include?("Gemini")
          sleep 0.5
        end
      end
    end
    
    ws_connection[:client].send(JSON.generate(message_data))
  end

  # Wait for AI response completion
  def wait_for_response(ws_connection, timeout: 60)
    start_time = Time.now
    
    loop do
      # Check for completion message
      if ws_connection[:messages].any? { |msg| msg["type"] == "message" && msg["content"] == "DONE" }
        response = extract_ai_response(ws_connection[:messages])
        
        # If no response extracted but we have a successful completion, 
        # it might be a responses API format issue. Try to find any text content.
        if response.empty?
          ws_connection[:messages].each do |msg|
            if msg["type"] == "message" && msg["content"].is_a?(String) && 
               msg["content"] != "DONE" && !msg["content"].start_with?("ERROR") &&
               !msg["content"].start_with?("Content not found")
              response = msg["content"]
              break
            end
          end
        end
        
        return response
      end
      
      # Check for function call depth exceeded
      if ws_connection[:messages].any? { |msg| 
          msg["type"] == "fragment" && 
          msg["content"]&.include?("Maximum function call depth exceeded")
        }
        # Extract any response we have so far, including the error message
        response = extract_ai_response(ws_connection[:messages])
        return response unless response.empty?
        
        # If no proper response, return the error message itself
        return "Maximum function call depth exceeded. The AI tried to call too many functions."
      end
      
      # Check for error
      if ws_connection[:messages].any? { |msg| msg["type"] == "error" }
        error_msg = ws_connection[:messages].find { |msg| msg["type"] == "error" }
        
        # Log detailed error information
        puts "ERROR: #{error_msg['content']}"
        puts "All messages received: #{ws_connection[:messages].map { |m| "#{m['type']}: #{m['content'].to_s[0..100]}..." }.join("\n")}"
        
        raise "AI response error: #{error_msg['content']}"
      end
      
      if Time.now - start_time > timeout
        puts "TIMEOUT: Messages received so far:"
        ws_connection[:messages].each do |msg|
          puts "  #{msg['type']}: #{msg['content'].to_s[0..100]}..."
        end
        raise "Timeout waiting for AI response"
      end
      
      sleep 0.1
    end
  end

  # Extract AI response from messages
  def extract_ai_response(messages)
    response_parts = []
    
    messages.each do |msg|
      if msg["type"] == "fragment"
        response_parts << msg["content"]
      elsif msg["type"] == "message" && msg["content"] && msg["content"] != "DONE"
        # Some providers may send complete messages instead of fragments
        response_parts << msg["content"]
      end
    end
    
    # If no response found, check for assistant messages in a different format
    if response_parts.empty?
      messages.each do |msg|
        if msg["content"].is_a?(Hash) && msg["content"]["role"] == "assistant" && msg["content"]["text"]
          response_parts << msg["content"]["text"]
        end
      end
    end
    
    result = response_parts.join("")
    
    # Log for debugging if still empty
    if result.empty?
      puts "DEBUG: No response extracted. Message types found: #{messages.map { |m| m["type"] }.uniq.join(", ")}"
      puts "DEBUG: First few messages: #{messages.take(5).inspect}"
    end
    
    result
  end

  # Simulate file upload
  def upload_file(host: 'localhost', port: 4567, file_path:, app_name:)
    uri = URI("http://#{host}:#{port}/upload")
    
    File.open(file_path) do |file|
      req = Net::HTTP::Post::Multipart.new(uri.path, 
        "file" => UploadIO.new(file, "application/octet-stream", File.basename(file_path)),
        "app_name" => app_name
      )
      
      res = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end
      
      JSON.parse(res.body)
    end
  end

  # Check if Docker containers are running
  def check_containers_running
    # For E2E tests, we don't need Ruby container since we run server locally
    # Only check Python container for Code Interpreter tests
    # pgvector is only needed for PDF Navigator and Monadic Help
    required_containers = %w[
      monadic-chat-python-container
    ]
    
    required_containers.all? do |container|
      system("docker ps | grep -q #{container}")
    end
  end

  # Create test file
  def create_test_file(filename, content)
    path = File.join(Dir.home, "monadic", "data", filename)
    File.write(path, content)
    path
  end

  # Clean up test files
  def cleanup_test_files(*filenames)
    filenames.each do |filename|
      path = File.join(Dir.home, "monadic", "data", filename)
      File.delete(path) if File.exist?(path)
    end
  end
end

# Multipart upload helper (simplified version)
module UploadIO
  def self.new(file, content_type, filename)
    {
      file: file,
      content_type: content_type,
      filename: filename
    }
  end
end