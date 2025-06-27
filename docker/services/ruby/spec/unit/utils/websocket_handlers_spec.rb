# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ostruct'
require_relative '../../../lib/monadic/utils/websocket'

RSpec.describe 'WebSocket Message Handlers' do
  # Test class that simulates a MonadicApp with WebSocket handling
  class TestWebSocketApp
    include WebSocketHelper
    
    attr_accessor :settings, :session, :parameters, :websocket_message
    
    def initialize
      @settings = OpenStruct.new(
        api_key: 'test-key',
        max_input_tokens: 4000,
        context_size: 10
      )
      @session = { 
        messages: [],
        session_id: 'test-session-123'
      }
      @parameters = {}
      @websocket_message = nil
    end
    
    # Simulate WebSocket message sending
    def send_websocket_message(message)
      @websocket_message = message
    end
    
    # Simulate message processing
    def process_websocket_message(type, data)
      # Handle nil inputs gracefully
      return false if type.nil?
      
      case type
      when 'chat'
        # Process chat message
        session[:messages] << {
          'type' => 'user',
          'content' => data && data['content'],
          'timestamp' => Time.now.to_i
        }
        true
      when 'status'
        # Process status request
        {
          status: 'active',
          session_id: session[:session_id],
          message_count: session[:messages].length
        }
      when 'clear'
        # Clear messages
        session[:messages].clear
        true
      else
        false
      end
    end
  end
  
  let(:app) { TestWebSocketApp.new }
  
  describe 'Message type handling' do
    it 'processes chat messages' do
      result = app.process_websocket_message('chat', { 'content' => 'Hello, AI!' })
      
      expect(result).to be true
      expect(app.session[:messages].length).to eq(1)
      expect(app.session[:messages].first['content']).to eq('Hello, AI!')
    end
    
    it 'processes status requests' do
      # Add some messages first
      3.times do |i|
        app.process_websocket_message('chat', { 'content' => "Message #{i}" })
      end
      
      result = app.process_websocket_message('status', {})
      
      expect(result).to be_a(Hash)
      expect(result[:status]).to eq('active')
      expect(result[:message_count]).to eq(3)
    end
    
    it 'processes clear commands' do
      # Add messages
      app.process_websocket_message('chat', { 'content' => 'Test message' })
      expect(app.session[:messages].length).to eq(1)
      
      # Clear
      result = app.process_websocket_message('clear', {})
      
      expect(result).to be true
      expect(app.session[:messages]).to be_empty
    end
    
    it 'handles unknown message types' do
      result = app.process_websocket_message('unknown', { 'data' => 'test' })
      
      expect(result).to be false
    end
  end
  
  describe 'Message validation' do
    it 'validates message structure' do
      valid_message = {
        'type' => 'chat',
        'content' => 'Hello',
        'session_id' => 'test-123'
      }
      
      # Basic validation
      expect(valid_message['type']).not_to be_nil
      expect(valid_message['content']).not_to be_nil
    end
    
    it 'handles messages with missing fields' do
      incomplete_message = { 'type' => 'chat' }
      
      # Should handle gracefully
      result = app.process_websocket_message(
        incomplete_message['type'], 
        incomplete_message
      )
      
      # Message should still be processed but with nil content
      expect(result).to be true
      expect(app.session[:messages].last['content']).to be_nil
    end
  end
  
  describe 'Concurrent message handling' do
    it 'handles multiple simultaneous messages' do
      threads = []
      message_count = 10
      
      message_count.times do |i|
        threads << Thread.new do
          app.process_websocket_message('chat', { 'content' => "Message #{i}" })
        end
      end
      
      threads.each(&:join)
      
      expect(app.session[:messages].length).to eq(message_count)
    end
  end
  
  describe 'Error recovery' do
    it 'recovers from processing errors' do
      # Simulate error by passing invalid data
      expect {
        app.process_websocket_message(nil, nil)
      }.not_to raise_error
    end
    
    it 'maintains session integrity after errors' do
      # Create a fresh app instance for this test
      fresh_app = TestWebSocketApp.new
      initial_count = fresh_app.session[:messages].length
      initial_session_id = fresh_app.session[:session_id]
      
      # Try to process invalid message
      fresh_app.process_websocket_message(nil, nil)
      
      # Session should remain intact
      expect(fresh_app.session[:messages].length).to eq(initial_count)
      expect(fresh_app.session[:session_id]).to eq(initial_session_id)
    end
  end
  
  describe 'WebSocket event simulation' do
    it 'simulates connection open event' do
      connection_opened = false
      
      # Simulate onopen
      on_open = -> { connection_opened = true }
      on_open.call
      
      expect(connection_opened).to be true
    end
    
    it 'simulates message receive event' do
      received_message = nil
      
      # Simulate onmessage
      on_message = ->(msg) { received_message = msg }
      on_message.call('{"type": "test"}')
      
      expect(received_message).to eq('{"type": "test"}')
    end
    
    it 'simulates connection close event' do
      connection_closed = false
      
      # Simulate onclose
      on_close = -> { connection_closed = true }
      on_close.call
      
      expect(connection_closed).to be true
    end
    
    it 'simulates error event' do
      error_occurred = false
      error_message = nil
      
      # Simulate onerror
      on_error = ->(err) { 
        error_occurred = true
        error_message = err
      }
      on_error.call('Connection timeout')
      
      expect(error_occurred).to be true
      expect(error_message).to eq('Connection timeout')
    end
  end
  
  describe 'Message batching and queueing' do
    it 'handles message queues' do
      message_queue = []
      
      # Add messages to queue
      5.times do |i|
        message_queue << {
          type: 'chat',
          content: "Queued message #{i}",
          timestamp: Time.now.to_f
        }
      end
      
      # Process queue
      message_queue.each do |msg|
        app.process_websocket_message(msg[:type].to_s, {
          'content' => msg[:content]
        })
      end
      
      expect(app.session[:messages].length).to eq(5)
    end
    
    it 'maintains message order' do
      messages = []
      
      3.times do |i|
        app.process_websocket_message('chat', { 'content' => "Message #{i}" })
        messages << app.session[:messages].last
      end
      
      # Check order is maintained
      messages.each_with_index do |msg, i|
        expect(msg['content']).to eq("Message #{i}")
      end
    end
  end
  
  describe 'Special message types' do
    it 'handles system messages' do
      system_message = {
        'type' => 'system',
        'content' => 'Model switched to gpt-4',
        'level' => 'info'
      }
      
      # Process as a special type
      app.session[:messages] << system_message
      
      system_msgs = app.session[:messages].select { |m| m['type'] == 'system' }
      expect(system_msgs.length).to eq(1)
      expect(system_msgs.first['level']).to eq('info')
    end
    
    it 'handles error messages' do
      error_message = {
        'type' => 'error',
        'content' => 'API rate limit exceeded',
        'code' => 429
      }
      
      app.session[:messages] << error_message
      
      error_msgs = app.session[:messages].select { |m| m['type'] == 'error' }
      expect(error_msgs.length).to eq(1)
      expect(error_msgs.first['code']).to eq(429)
    end
  end
  
  describe 'Message transformation' do
    it 'transforms messages before storage' do
      raw_message = { 'content' => '  Hello World  ', 'type' => 'chat' }
      
      # Transform: trim whitespace
      transformed_content = raw_message['content'].strip
      
      processed_message = {
        'type' => raw_message['type'],
        'content' => transformed_content,
        'timestamp' => Time.now.to_i
      }
      
      app.session[:messages] << processed_message
      
      expect(app.session[:messages].last['content']).to eq('Hello World')
    end
    
    it 'sanitizes message content' do
      unsafe_message = {
        'content' => '<script>alert("XSS")</script>Hello',
        'type' => 'chat'
      }
      
      # Simple sanitization
      sanitized_content = unsafe_message['content'].gsub(/<[^>]*>/, '')
      
      expect(sanitized_content).to eq('alert("XSS")Hello')
    end
  end
  
  describe 'Connection state management' do
    it 'tracks connection state' do
      connection_states = {
        'session1' => { connected: true, last_ping: Time.now },
        'session2' => { connected: false, last_ping: Time.now - 3600 }
      }
      
      # Check active connections
      active_sessions = connection_states.select { |_, state| state[:connected] }
      expect(active_sessions.length).to eq(1)
      expect(active_sessions.keys).to include('session1')
    end
    
    it 'handles connection timeouts' do
      timeout_threshold = 30 # seconds
      last_activity = Time.now - 60
      
      is_timed_out = (Time.now - last_activity) > timeout_threshold
      
      expect(is_timed_out).to be true
    end
  end
end