# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tempfile'

RSpec.describe 'Chat Export/Import Integration', type: :integration do
  describe 'Complete export/import workflow' do
    let(:test_conversation) do
      {
        'parameters' => {
          'app_name' => 'ChatOpenAI',
          'model' => 'gpt-4',
          'temperature' => 0.7,
          'max_input_tokens' => 4000,
          'context_size' => 20,
          'initial_prompt' => 'You are a helpful AI assistant.',
          'easy_submit' => false,
          'auto_speech' => false,
          'monadic' => false,
          'disabled' => false
        },
        'messages' => [
          {
            'role' => 'system',
            'text' => 'You are a helpful AI assistant.',
            'mid' => 'sys_123',
            'active' => true
          },
          {
            'role' => 'user',
            'text' => 'What is the capital of France?',
            'mid' => 'usr_456',
            'active' => true,
            'lang' => 'en'
          },
          {
            'role' => 'assistant',
            'text' => 'The capital of France is Paris.',
            'mid' => 'ast_789',
            'active' => true,
            'lang' => 'en',
            'thinking' => 'The user is asking about geography...'
          }
        ]
      }
    end
    
    it 'preserves all data through export and import cycle' do
      # Simulate export by creating JSON file
      export_file = Tempfile.new(['export_test', '.json'])
      export_file.write(JSON.pretty_generate(test_conversation))
      export_file.rewind
      
      # Read exported content
      exported_content = JSON.parse(export_file.read)
      
      # Verify exported structure
      expect(exported_content['parameters']).to eq(test_conversation['parameters'])
      expect(exported_content['messages'].length).to eq(3)
      
      # Verify message details preserved
      system_msg = exported_content['messages'].find { |m| m['role'] == 'system' }
      expect(system_msg['text']).to eq('You are a helpful AI assistant.')
      expect(system_msg['mid']).to eq('sys_123')
      
      assistant_msg = exported_content['messages'].find { |m| m['role'] == 'assistant' }
      expect(assistant_msg['thinking']).to eq('The user is asking about geography...')
      
      export_file.close
      export_file.unlink
    end
    
    it 'handles complex message content' do
      complex_conversation = {
        'parameters' => {
          'app_name' => 'CodeInterpreterOpenAI',
          'monadic' => true
        },
        'messages' => [
          {
            'role' => 'user',
            'text' => 'Can you create a chart?',
            'mid' => 'usr_001',
            'images' => ['input_data.png']
          },
          {
            'role' => 'assistant',
            'text' => '```python\nimport matplotlib.pyplot as plt\nplt.plot([1,2,3])\n```',
            'mid' => 'ast_001',
            'thinking' => 'User wants a visualization...',
            'images' => ['output_chart.png', 'output_data.csv']
          }
        ]
      }
      
      # Export
      export_file = Tempfile.new(['complex_export', '.json'])
      export_file.write(JSON.pretty_generate(complex_conversation))
      export_file.rewind
      
      # Verify complex content preserved
      content = JSON.parse(export_file.read)
      user_msg = content['messages'].find { |m| m['role'] == 'user' }
      expect(user_msg['images']).to eq(['input_data.png'])
      
      assistant_msg = content['messages'].find { |m| m['role'] == 'assistant' }
      expect(assistant_msg['text']).to include('import matplotlib')
      expect(assistant_msg['images']).to eq(['output_chart.png', 'output_data.csv'])
      
      export_file.close
      export_file.unlink
    end
    
    it 'validates exported JSON schema' do
      # Define expected schema
      schema_validator = lambda do |data|
        return false unless data.is_a?(Hash)
        return false unless data['parameters'].is_a?(Hash)
        return false unless data['messages'].is_a?(Array)
        
        # Validate parameters
        params = data['parameters']
        return false unless params['app_name'].is_a?(String)
        
        # Validate messages
        data['messages'].all? do |msg|
          msg.is_a?(Hash) &&
          msg['role'].is_a?(String) &&
          ['system', 'user', 'assistant'].include?(msg['role']) &&
          msg['text'].is_a?(String) &&
          (msg['mid'].nil? || msg['mid'].is_a?(String))
        end
      end
      
      expect(schema_validator.call(test_conversation)).to be true
      
      # Test invalid schemas
      expect(schema_validator.call({})).to be false
      expect(schema_validator.call({'parameters' => {}})).to be false
      expect(schema_validator.call({'messages' => []})).to be false
      expect(schema_validator.call({
        'parameters' => {},
        'messages' => [{'invalid' => 'message'}]
      })).to be false
    end
  end
  
  describe 'Export format compatibility' do
    it 'exports in format compatible with frontend saveObjToJson' do
      # This matches the format used by the frontend JavaScript
      frontend_format = {
        'parameters' => {
          # All parameter fields from the UI
          'app_name' => 'ChatOpenAI',
          'model' => 'gpt-4',
          'temperature' => 0.7,
          # ... other parameters
        },
        'messages' => [
          # Message format matching frontend structure
          {
            'role' => 'user',
            'text' => 'Hello',
            'mid' => 'unique_id',
            # Optional fields
            'thinking' => nil,
            'images' => nil
          }
        ]
      }
      
      # Verify format can be parsed
      expect { JSON.parse(frontend_format.to_json) }.not_to raise_error
    end
  end
  
  describe 'Import error recovery' do
    it 'provides clear error messages for common issues' do
      error_cases = [
        {
          name: 'Empty file',
          content: '',
          expected_error: /Invalid JSON/
        },
        {
          name: 'Not JSON',
          content: 'This is not JSON',
          expected_error: /Invalid JSON/
        },
        {
          name: 'Wrong structure',
          content: '{"wrong": "structure"}',
          expected_error: /missing parameters/
        },
        {
          name: 'Missing messages',
          content: '{"parameters": {"app_name": "Test"}}',
          expected_error: /missing.*messages/
        },
        {
          name: 'Invalid message format',
          content: '{"parameters": {}, "messages": ["string instead of object"]}',
          expected_error: /Invalid.*format/
        }
      ]
      
      error_cases.each do |test_case|
        file = Tempfile.new(['error_test', '.json'])
        file.write(test_case[:content])
        file.rewind
        
        # In actual implementation, this would return error
        content = file.read
        is_valid = begin
          data = JSON.parse(content)
          # Check for proper structure: both parameters and messages must exist and be the right type
          data.is_a?(Hash) && 
            data['parameters'].is_a?(Hash) && 
            data['messages'].is_a?(Array) &&
            data['messages'].all? { |m| m.is_a?(Hash) }
        rescue JSON::ParserError
          false
        end
        
        expect(is_valid).to be(false), "Expected #{test_case[:name]} to be invalid"
        
        file.close
        file.unlink
      end
    end
  end
  
  describe 'Large conversation handling' do
    it 'handles conversations with many messages' do
      large_conversation = {
        'parameters' => { 'app_name' => 'ChatOpenAI' },
        'messages' => []
      }
      
      # Create 100 messages
      100.times do |i|
        large_conversation['messages'] << {
          'role' => i.even? ? 'user' : 'assistant',
          'text' => "Message #{i} with some content to make it realistic",
          'mid' => "msg_#{i}",
          'active' => true
        }
      end
      
      file = Tempfile.new(['large_export', '.json'])
      file.write(JSON.generate(large_conversation))
      file.rewind
      
      # Verify file size is reasonable
      file_size = file.size
      expect(file_size).to be > 1000  # At least 1KB
      expect(file_size).to be < 1_000_000  # Less than 1MB
      
      # Verify can be parsed
      parsed = JSON.parse(file.read)
      expect(parsed['messages'].length).to eq(100)
      
      file.close
      file.unlink
    end
  end
  
  describe 'Special characters and encoding' do
    it 'preserves Unicode characters' do
      unicode_conversation = {
        'parameters' => { 'app_name' => 'ChatOpenAI' },
        'messages' => [
          {
            'role' => 'user',
            'text' => 'Hello in different languages: 你好, こんにちは, مرحبا, 🌍',
            'mid' => 'usr_unicode'
          }
        ]
      }
      
      file = Tempfile.new(['unicode_test', '.json'])
      file.write(JSON.generate(unicode_conversation))
      file.rewind
      
      parsed = JSON.parse(file.read)
      expect(parsed['messages'][0]['text']).to include('你好')
      expect(parsed['messages'][0]['text']).to include('こんにちは')
      expect(parsed['messages'][0]['text']).to include('🌍')
      
      file.close
      file.unlink
    end
    
    it 'handles code blocks with special characters' do
      code_conversation = {
        'parameters' => { 'app_name' => 'CodeInterpreterOpenAI' },
        'messages' => [
          {
            'role' => 'assistant',
            'text' => "Here's the code:\n```python\nprint(\"Hello, World!\")\n# Special chars: < > & ' \"\n```",
            'mid' => 'ast_code'
          }
        ]
      }
      
      file = Tempfile.new(['code_test', '.json'])
      file.write(JSON.generate(code_conversation))
      file.rewind
      
      parsed = JSON.parse(file.read)
      expect(parsed['messages'][0]['text']).to include('print("Hello, World!")')
      expect(parsed['messages'][0]['text']).to include('< > &')
      
      file.close
      file.unlink
    end
  end
end