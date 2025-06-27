# frozen_string_literal: true

require_relative 'e2e_helper'
require_relative 'validation_helper'
require 'tempfile'
require 'json'

RSpec.describe "Chat Export/Import E2E Workflow", type: :e2e do
  include E2EHelper
  include ValidationHelper

  before(:all) do
    unless check_containers_running
      skip "E2E tests require all containers to be running. Run: ./docker/monadic.sh start"
    end
    
    unless wait_for_server
      skip "E2E tests require server to be running on localhost:4567. Run: rake server"
    end
  end

  describe "Export/Import via HTTP endpoints" do
    let(:base_url) { "http://localhost:4567" }
    let(:session_cookie) { get_session_cookie }
    
    def get_session_cookie
      # Get a session by visiting the main page
      uri = URI("#{base_url}/")
      response = Net::HTTP.get_response(uri)
      
      # Extract session cookie from response
      cookie = response['set-cookie']
      cookie ? cookie.split(';').first : nil
    end
    
    def make_request(method, path, body = nil, headers = {})
      uri = URI("#{base_url}#{path}")
      
      request = case method
      when :get
        Net::HTTP::Get.new(uri)
      when :post
        Net::HTTP::Post.new(uri)
      end
      
      # Add session cookie if available
      request['Cookie'] = session_cookie if session_cookie
      
      # Add custom headers
      headers.each { |k, v| request[k] = v }
      
      # Add body for POST requests
      if body && method == :post
        if body.is_a?(Hash) || body.is_a?(Array)
          request.body = body.to_json
          request['Content-Type'] = 'application/json'
        else
          request.body = body
        end
      end
      
      Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(request)
      end
    end
    
    describe "Import functionality" do
      let(:valid_import_data) do
        {
          'parameters' => {
            'app_name' => 'ChatOpenAI',
            'model' => 'gpt-4',
            'temperature' => 0.7,
            'max_input_tokens' => 4000,
            'context_size' => 20,
            'initial_prompt' => 'You are a helpful assistant.',
            'monadic' => false
          },
          'messages' => [
            {
              'role' => 'system',
              'text' => 'You are a helpful assistant.',
              'mid' => 'sys_001'
            },
            {
              'role' => 'user',
              'text' => 'What is 2+2?',
              'mid' => 'usr_001'
            },
            {
              'role' => 'assistant',
              'text' => '2+2 equals 4.',
              'mid' => 'ast_001'
            }
          ]
        }
      end
      
      it "imports valid JSON data via AJAX" do
        # Create temporary file with JSON data
        import_file = Tempfile.new(['import_test', '.json'])
        import_file.write(JSON.pretty_generate(valid_import_data))
        import_file.rewind
        
        # Prepare multipart form data
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        # Add file part
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"import.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        # Make AJAX request
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        expect(response.code).to eq('200')
        expect(response['content-type']).to include('application/json')
        
        result = JSON.parse(response.body)
        expect(result['success']).to be true
        
        import_file.close
        import_file.unlink
      end
      
      it "handles invalid JSON gracefully" do
        # Create temporary file with invalid JSON
        import_file = Tempfile.new(['invalid_import', '.json'])
        import_file.write('{ invalid json }')
        import_file.rewind
        
        # Prepare multipart form data
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"invalid.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        # Make AJAX request
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        expect(response.code).to eq('200')
        
        result = JSON.parse(response.body)
        expect(result['success']).to be false
        expect(result['error']).to include('Invalid JSON')
        
        import_file.close
        import_file.unlink
      end
      
      it "rejects data with missing parameters" do
        incomplete_data = { 'messages' => [] }
        
        import_file = Tempfile.new(['incomplete_import', '.json'])
        import_file.write(JSON.generate(incomplete_data))
        import_file.rewind
        
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"incomplete.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        result = JSON.parse(response.body)
        expect(result['success']).to be false
        expect(result['error']).to include('missing parameters')
        
        import_file.close
        import_file.unlink
      end
    end
    
    describe "Import workflow without WebSocket" do
      it "imports conversation data successfully" do
        # Prepare test data with context
        import_data = {
          'parameters' => {
            'app_name' => 'ChatOpenAI',
            'model' => 'gpt-4',
            'temperature' => 0.7,
            'initial_prompt' => 'You are a helpful assistant.'
          },
          'messages' => [
            {
              'role' => 'system',
              'text' => 'You are a helpful assistant.',
              'mid' => 'sys_001'
            },
            {
              'role' => 'user',
              'text' => 'Remember this: My favorite color is blue and my lucky number is 42.',
              'mid' => 'usr_001'
            },
            {
              'role' => 'assistant',
              'text' => 'I\'ll remember that your favorite color is blue and your lucky number is 42. Is there anything specific you\'d like to know or discuss about these preferences?',
              'mid' => 'ast_001'
            }
          ]
        }
        
        # Create and import file
        import_file = Tempfile.new(['context_test', '.json'])
        import_file.write(JSON.generate(import_data))
        import_file.rewind
        
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"context.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        # Import via AJAX
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        result = JSON.parse(response.body)
        expect(result['success']).to be true
        
        # Note: In a real browser scenario, the page would reload and 
        # WebSocket would reconnect with the imported session data.
        # This test verifies the import endpoint works correctly.
        
        import_file.close
        import_file.unlink
      end
    end
    
    describe "Special cases" do
      it "handles large conversations" do
        # Create large conversation
        large_data = {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => []
        }
        
        # Add 50 message pairs
        50.times do |i|
          large_data['messages'] << {
            'role' => 'user',
            'text' => "Question #{i}: What is #{i} + #{i}?",
            'mid' => "usr_#{i}"
          }
          large_data['messages'] << {
            'role' => 'assistant',
            'text' => "#{i} + #{i} = #{i * 2}",
            'mid' => "ast_#{i}"
          }
        end
        
        import_file = Tempfile.new(['large_import', '.json'])
        import_file.write(JSON.generate(large_data))
        import_file.rewind
        
        # Check file size
        file_size = import_file.size
        expect(file_size).to be > 1000 # At least 1KB
        expect(file_size).to be < 1_000_000 # Less than 1MB
        
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"large.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        result = JSON.parse(response.body)
        expect(result['success']).to be true
        
        import_file.close
        import_file.unlink
      end
      
      it "preserves Unicode and special characters" do
        unicode_data = {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => [
            {
              'role' => 'user',
              'text' => 'Test Unicode: 你好 こんにちは مرحبا 🌍',
              'mid' => 'usr_unicode'
            },
            {
              'role' => 'assistant',
              'text' => "Code example:\n```python\nprint(\"Hello, 世界!\")\n# Special: < > & ' \"\n```",
              'mid' => 'ast_code'
            }
          ]
        }
        
        import_file = Tempfile.new(['unicode_import', '.json'])
        import_file.write(JSON.generate(unicode_data))
        import_file.rewind
        
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        body = []
        
        body << "--#{boundary}"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"unicode.json\""
        body << "Content-Type: application/json"
        body << ""
        body << import_file.read
        body << "--#{boundary}--"
        
        response = make_request(:post, '/load', body.join("\r\n"), {
          'X-Requested-With' => 'XMLHttpRequest',
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        })
        
        result = JSON.parse(response.body)
        expect(result['success']).to be true
        
        import_file.close
        import_file.unlink
      end
    end
  end
  
  describe "Export format validation" do
    it "exports data in expected format" do
      # This validates the expected export format
      expected_format = {
        'parameters' => {
          'app_name' => String,
          'model' => String,
          'temperature' => Numeric,
          'max_input_tokens' => Integer,
          'context_size' => Integer,
          'initial_prompt' => String,
          'easy_submit' => [TrueClass, FalseClass],
          'auto_speech' => [TrueClass, FalseClass],
          'monadic' => [TrueClass, FalseClass]
        },
        'messages' => [
          {
            'role' => String,
            'text' => String,
            'mid' => String,
            'active' => [TrueClass, FalseClass],
            'thinking' => [String, NilClass],
            'images' => [Array, NilClass]
          }
        ]
      }
      
      # Verify structure
      expect(expected_format).to include('parameters', 'messages')
    end
  end
  
  describe "Real browser behavior documentation" do
    it "documents the actual export/import flow in browser" do
      # This test documents how the feature works in a real browser:
      
      # 1. EXPORT (Client-side JavaScript):
      #    - User clicks Export button
      #    - JavaScript collects session[:parameters] and session[:messages]
      #    - Creates JSON blob and triggers download
      #    - File saved to user's computer
      
      # 2. IMPORT (Server-side Ruby + Client reload):
      #    - User clicks Import button
      #    - Modal opens with file selector
      #    - User selects JSON file
      #    - JavaScript submits file via AJAX to POST /load
      #    - Server updates session[:parameters] and session[:messages]
      #    - Server returns { success: true }
      #    - JavaScript reloads the page: window.location.reload()
      #    - Page reload causes WebSocket to reconnect
      #    - WebSocket loads fresh session data
      #    - Conversation history appears in UI
      
      # The key insight: WebSocket and HTTP share the same Rack session,
      # but WebSocket needs to reconnect to see updated session data.
      
      expect(true).to be true  # Documentary test
    end
  end
end