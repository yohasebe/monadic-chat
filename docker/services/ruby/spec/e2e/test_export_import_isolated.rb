# frozen_string_literal: true

# Isolated test to debug the export/import cycle issue

require_relative 'e2e_helper'
require 'tempfile'
require 'json'

include E2EHelper

puts "Testing Export/Import Cycle..."

begin
  # Check if server is running
  unless wait_for_server
    puts "Server not running. Please start with: rake server"
    exit 1
  end

  # Step 1: Get session cookie from HTTP
  puts "\n1. Getting session cookie..."
  uri = URI("http://localhost:4567/")
  response = Net::HTTP.get_response(uri)
  cookie = response['set-cookie']
  session_id = cookie ? cookie.split('=')[1].split(';').first : nil
  puts "   Session ID: #{session_id}"

  # Step 2: Create WebSocket connection
  puts "\n2. Creating WebSocket connection..."
  ws_connection = create_websocket_connection
  puts "   WebSocket connected"

  # Step 3: Send initial message
  puts "\n3. Sending initial message..."
  send_chat_message(ws_connection, "Hello! My favorite color is blue and my lucky number is 42.")
  response1 = wait_for_response(ws_connection)
  puts "   Response: #{response1[0..100]}..."

  # Step 4: Create export data
  puts "\n4. Creating export data..."
  export_data = {
    'parameters' => {
      'app_name' => 'ChatOpenAI',
      'model' => 'gpt-4',
      'temperature' => 0.7
    },
    'messages' => [
      {
        'role' => 'user',
        'text' => 'Hello! My favorite color is blue and my lucky number is 42.',
        'mid' => 'usr_001'
      },
      {
        'role' => 'assistant',
        'text' => response1,
        'mid' => 'ast_001'
      }
    ]
  }

  # Step 5: Close WebSocket
  puts "\n5. Closing WebSocket..."
  ws_connection[:client].close
  sleep 1

  # Step 6: Import via HTTP with same session
  puts "\n6. Importing conversation..."
  import_file = Tempfile.new(['export_test', '.json'])
  import_file.write(JSON.generate(export_data))
  import_file.rewind

  boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
  body = []
  
  body << "--#{boundary}"
  body << "Content-Disposition: form-data; name=\"file\"; filename=\"export.json\""
  body << "Content-Type: application/json"
  body << ""
  body << import_file.read
  body << "--#{boundary}--"

  uri = URI("http://localhost:4567/load")
  request = Net::HTTP::Post.new(uri)
  request['Cookie'] = cookie if cookie
  request['X-Requested-With'] = 'XMLHttpRequest'
  request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
  request.body = body.join("\r\n")

  response = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(request)
  end

  puts "   Import response: #{response.code}"
  result = JSON.parse(response.body)
  puts "   Import success: #{result['success']}"

  # Step 7: Create new WebSocket with same session
  puts "\n7. Creating new WebSocket connection..."
  # Try to pass session cookie to WebSocket (may not work with standard WebSocket)
  ws_connection2 = create_websocket_connection
  puts "   New WebSocket connected"

  # Step 8: Wait a bit for session to sync
  puts "\n8. Waiting for session sync..."
  sleep 2

  # Step 9: Send question about context
  puts "\n9. Testing context preservation..."
  send_chat_message(ws_connection2, "What was my favorite color and lucky number?")
  response2 = wait_for_response(ws_connection2)
  puts "   Response: #{response2}"

  # Check if context was preserved
  if response2.downcase.include?('blue') && response2.include?('42')
    puts "\n✅ SUCCESS: Context was preserved!"
  else
    puts "\n❌ FAILED: Context was not preserved"
    puts "   Expected mentions of 'blue' and '42'"
  end

  # Cleanup
  ws_connection2[:client].close if ws_connection2[:client]
  import_file.close
  import_file.unlink

rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5)
end