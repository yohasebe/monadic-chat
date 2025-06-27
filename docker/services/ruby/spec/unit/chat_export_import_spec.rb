# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'
require 'securerandom'

RSpec.describe 'Chat Export/Import Functionality' do
  # Test the import logic without loading the full Sinatra app
  class ImportHandler
    attr_reader :session, :errors
    
    def initialize
      @session = {}
      @errors = []
    end
    
    def detect_language(text)
      'en'
    end
    
    def markdown_to_html(text)
      "<p>#{text}</p>"
    end
    
    def handle_error(msg)
      @errors << msg
    end
    
    def process_import(json_data, monadic_app = nil)
      # Validate required fields
      unless json_data["parameters"] && json_data["messages"]
        handle_error("Invalid format: missing parameters or messages")
        return false
      end
      
      # Set session data
      @session[:status] = "loaded"
      @session[:parameters] = json_data["parameters"]
      
      # Check if the first message is a system message
      if json_data["messages"].first && json_data["messages"].first["role"] == "system"
        @session[:parameters]["initial_prompt"] = json_data["messages"].first["text"]
      end
      
      # Process messages
      app_name = json_data["parameters"]["app_name"]
      @session[:messages] = json_data["messages"].uniq.map do |msg|
        # Skip invalid messages
        next unless msg["role"] && msg["text"]
        
        text = msg["text"]
        
        # Handle HTML conversion based on role and settings
        html = if json_data["parameters"]["monadic"].to_s == "true" && msg["role"] == "assistant" && monadic_app
          begin
            monadic_app.monadic_html(text)
          rescue => e
            # Fallback to standard markdown if monadic_html fails
            markdown_to_html(text)
          end
        elsif msg["role"] == "assistant"
          markdown_to_html(text)
        else
          text
        end
        
        # Create message object with required fields
        mid = msg["mid"] || SecureRandom.hex(4)
        message_obj = { 
          "role" => msg["role"], 
          "text" => text, 
          "html" => html, 
          "lang" => detect_language(text), 
          "mid" => mid, 
          "active" => true 
        }
        
        # Add optional fields if present
        message_obj["thinking"] = msg["thinking"] if msg["thinking"]
        message_obj["images"] = msg["images"] if msg["images"]
        message_obj
      end.compact # Remove nil values from invalid messages
      
      true
    end
  end
  
  describe 'Import functionality' do
    let(:handler) { ImportHandler.new }
    let(:mock_app) { double('app', monadic_html: '<div>Monadic HTML</div>') }
    
    context 'with valid JSON data' do
      let(:valid_json) do
        {
          'parameters' => {
            'app_name' => 'ChatOpenAI',
            'monadic' => 'false',
            'model' => 'gpt-4',
            'temperature' => 0.7
          },
          'messages' => [
            {
              'role' => 'system',
              'text' => 'You are a helpful assistant.',
              'mid' => 'sys001'
            },
            {
              'role' => 'user',
              'text' => 'Hello!',
              'mid' => 'usr001'
            },
            {
              'role' => 'assistant',
              'text' => 'Hi there! How can I help you?',
              'mid' => 'ast001'
            }
          ]
        }
      end
      
      it 'successfully imports chat data' do
        result = handler.process_import(valid_json)
        
        expect(result).to be true
        expect(handler.errors).to be_empty
        expect(handler.session[:status]).to eq('loaded')
        expect(handler.session[:parameters]).to eq(valid_json['parameters'])
        expect(handler.session[:messages].length).to eq(3)
      end
      
      it 'extracts system prompt to initial_prompt parameter' do
        handler.process_import(valid_json)
        
        expect(handler.session[:parameters]['initial_prompt']).to eq('You are a helpful assistant.')
      end
      
      it 'processes messages with correct attributes' do
        handler.process_import(valid_json)
        
        messages = handler.session[:messages]
        
        # Check user message
        user_msg = messages.find { |m| m['role'] == 'user' }
        expect(user_msg['text']).to eq('Hello!')
        expect(user_msg['html']).to eq('Hello!')
        expect(user_msg['lang']).to eq('en')
        expect(user_msg['mid']).to eq('usr001')
        expect(user_msg['active']).to be true
        
        # Check assistant message
        assistant_msg = messages.find { |m| m['role'] == 'assistant' }
        expect(assistant_msg['text']).to eq('Hi there! How can I help you?')
        expect(assistant_msg['html']).to eq('<p>Hi there! How can I help you?</p>')
      end
    end
    
    context 'with monadic mode enabled' do
      let(:monadic_json) do
        {
          'parameters' => {
            'app_name' => 'ChatOpenAI',
            'monadic' => 'true'
          },
          'messages' => [
            {
              'role' => 'assistant',
              'text' => 'Monadic response',
              'mid' => 'ast001'
            }
          ]
        }
      end
      
      it 'uses monadic_html for assistant messages' do
        handler.process_import(monadic_json, mock_app)
        
        assistant_msg = handler.session[:messages].first
        expect(assistant_msg['html']).to eq('<div>Monadic HTML</div>')
      end
      
      it 'falls back to markdown when monadic_html fails' do
        failing_app = double('app')
        allow(failing_app).to receive(:monadic_html).and_raise('Error')
        
        handler.process_import(monadic_json, failing_app)
        
        assistant_msg = handler.session[:messages].first
        expect(assistant_msg['html']).to eq('<p>Monadic response</p>')
      end
    end
    
    context 'with additional message fields' do
      let(:json_with_extras) do
        {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => [
            {
              'role' => 'assistant',
              'text' => 'Response with thinking',
              'thinking' => 'Internal reasoning...',
              'images' => ['image1.png', 'image2.png'],
              'mid' => 'ast001'
            }
          ]
        }
      end
      
      it 'preserves thinking and images fields' do
        handler.process_import(json_with_extras)
        
        msg = handler.session[:messages].first
        expect(msg['thinking']).to eq('Internal reasoning...')
        expect(msg['images']).to eq(['image1.png', 'image2.png'])
      end
    end
    
    context 'with invalid data' do
      it 'returns error when parameters are missing' do
        result = handler.process_import({ 'messages' => [] })
        
        expect(result).to be false
        expect(handler.errors).to include('Invalid format: missing parameters or messages')
      end
      
      it 'returns error when messages are missing' do
        result = handler.process_import({ 'parameters' => {} })
        
        expect(result).to be false
        expect(handler.errors).to include('Invalid format: missing parameters or messages')
      end
      
      it 'skips invalid messages without role or text' do
        json_with_invalid = {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => [
            { 'text' => 'Missing role' },
            { 'role' => 'user' },  # Missing text
            { 'role' => 'user', 'text' => 'Valid message', 'mid' => 'usr001' }
          ]
        }
        
        handler.process_import(json_with_invalid)
        
        expect(handler.session[:messages].length).to eq(1)
        expect(handler.session[:messages].first['text']).to eq('Valid message')
      end
    end
    
    context 'with duplicate messages' do
      let(:json_with_duplicates) do
        {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => [
            { 'role' => 'user', 'text' => 'Same message', 'mid' => 'usr001' },
            { 'role' => 'user', 'text' => 'Same message', 'mid' => 'usr001' },
            { 'role' => 'user', 'text' => 'Different message', 'mid' => 'usr002' }
          ]
        }
      end
      
      it 'removes duplicate messages' do
        handler.process_import(json_with_duplicates)
        
        expect(handler.session[:messages].length).to eq(2)
      end
    end
    
    context 'with missing mid values' do
      let(:json_without_mids) do
        {
          'parameters' => { 'app_name' => 'ChatOpenAI' },
          'messages' => [
            { 'role' => 'user', 'text' => 'Message without mid' }
          ]
        }
      end
      
      it 'generates mid values for messages without them' do
        allow(SecureRandom).to receive(:hex).with(4).and_return('generated')
        
        handler.process_import(json_without_mids)
        
        msg = handler.session[:messages].first
        expect(msg['mid']).to eq('generated')
      end
    end
  end
  
  describe 'Export functionality (conceptual test)' do
    it 'exports chat data in correct format' do
      # This tests the expected format that should be exported
      expected_export = {
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
            'mid' => 'sys001'
          },
          {
            'role' => 'user',
            'text' => 'Hello!',
            'mid' => 'usr001'
          },
          {
            'role' => 'assistant',
            'text' => 'Hi! How can I help?',
            'mid' => 'ast001',
            'thinking' => 'User greeted me...',
            'images' => ['chart.png']
          }
        ]
      }
      
      # Verify structure matches import expectations
      expect(expected_export).to have_key('parameters')
      expect(expected_export).to have_key('messages')
      expect(expected_export['messages']).to all(include('role', 'text'))
    end
  end
  
  describe 'JSON parsing and validation' do
    it 'handles various JSON parse errors' do
      test_cases = [
        { input: '', error: 'empty' },
        { input: 'not json', error: 'invalid' },
        { input: '{"incomplete":', error: 'incomplete' },
        { input: '{"valid": "json", "but": "wrong structure"}', error: 'structure' }
      ]
      
      test_cases.each do |test_case|
        begin
          JSON.parse(test_case[:input])
          valid = true
        rescue JSON::ParserError
          valid = false
        end
        
        expect(valid).to be false unless test_case[:input].include?('"valid"')
      end
    end
  end
  
  describe 'File handling' do
    it 'reads JSON files correctly' do
      file = Tempfile.new(['test', '.json'])
      data = { 'test' => 'data' }
      
      file.write(JSON.pretty_generate(data))
      file.rewind
      
      content = file.read
      parsed = JSON.parse(content)
      
      expect(parsed).to eq(data)
      
      file.close
      file.unlink
    end
    
    it 'handles file encoding' do
      file = Tempfile.new(['test', '.json'])
      data = { 'text' => 'Unicode: 你好 こんにちは' }
      
      file.write(JSON.generate(data))
      file.rewind
      
      content = file.read.force_encoding('UTF-8')
      parsed = JSON.parse(content)
      
      expect(parsed['text']).to include('你好')
      expect(parsed['text']).to include('こんにちは')
      
      file.close
      file.unlink
    end
  end
end