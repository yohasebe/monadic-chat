#!/usr/bin/env ruby
# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'
require 'colorize'

def create_websocket_connection
  ws = WebSocket::Client::Simple.connect("ws://localhost:4567/")
  connection = { client: ws, messages: [], ready: false }

  ws.on :message do |msg|
    data = JSON.parse(msg.data) rescue msg.data
    connection[:messages] << data
    
    if data.is_a?(Hash)
      if data["type"] == "error"
        puts "ERROR: #{data["content"]}".red
      elsif data["type"] == "fragment"
        print data["content"].yellow
      elsif data["type"] == "message"
        puts "\n#{data["content"]}".green
      elsif data["type"] == "system"
        puts "SYSTEM: #{data["content"]}".blue
      end
    end
  end

  ws.on :open do
    connection[:ready] = true
  end

  ws.on :error do |e|
    puts "WebSocket error: #{e}".red unless e.message.include?('stream closed')
  end

  # Wait for connection
  start = Time.now
  while !connection[:ready] && Time.now - start < 5
    sleep 0.1
  end

  connection
end

def send_message(ws_connection, text, interaction_num)
  puts "\n" + "="*60
  puts "Interaction ##{interaction_num}: Sending: #{text}".cyan
  puts "="*60
  
  # Send LOAD message
  load_msg = { "message" => "LOAD" }
  ws_connection[:client].send(JSON.generate(load_msg))
  sleep 1
  
  # Send the actual message
  msg = {
    "message" => "ASSISTANT",
    "content" => text,
    "context" => [],
    "app" => "JupyterNotebookGrok",
    "model" => "grok-4-0709",
    "tools" => [],
    "max_tokens" => 4096,
    "temperature" => 0.0
  }
  
  ws_connection[:client].send(JSON.generate(msg))
  
  # Wait for response
  puts "\nWaiting for response...".gray
  start = Time.now
  timeout = 60
  
  while Time.now - start < timeout
    sleep 0.5
    # Check if we got a complete message
    if ws_connection[:messages].any? { |m| m["type"] == "message" && m["timestamp"] && Time.parse(m["timestamp"]) > start rescue false }
      break
    end
  end
  
  sleep 2 # Give it a bit more time for any trailing messages
end

# Main test
puts "Testing xAI Jupyter Notebook Multiple Interactions".magenta
puts "This test will demonstrate the issue where the first few interactions don't work properly\n"

ws = create_websocket_connection
puts "WebSocket connection established".green

# Test interactions
messages = [
  "Create a Jupyter notebook with a simple Python cell that prints 'Hello World'",
  "Add a cell to the notebook that prints 'Hello World'",
  "Please create a notebook and add a Python cell that prints 'Hello World'"
]

messages.each_with_index do |msg, i|
  send_message(ws, msg, i + 1)
  sleep 3 # Wait between interactions
end

puts "\n\nTest complete. Check ~/monadic/log/extra.log for detailed logs".magenta
ws[:client].close