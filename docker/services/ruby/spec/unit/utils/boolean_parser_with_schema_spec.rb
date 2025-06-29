# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/boolean_parser'
require_relative '../../../lib/monadic/utils/mdsl_schema'

RSpec.describe 'BooleanParser with MDSLSchema Integration' do
  describe '.parse_hash with MDSLSchema' do
    context 'with camelCase aliases' do
      it 'normalizes keys and parses boolean values' do
        input = {
          'responseFormat' => { type: 'json_object' },
          'easySubmit' => 'true',
          'autoSpeech' => 'false',
          'initiateFromAssistant' => '1',
          'contextSize' => 100
        }
        
        result = BooleanParser.parse_hash(input)
        
        # Keys should be normalized
        expect(result).to have_key('response_format')
        expect(result).to have_key('easy_submit')
        expect(result).to have_key('auto_speech')
        expect(result).to have_key('initiate_from_assistant')
        expect(result).to have_key('context_size')
        
        # Boolean values should be parsed
        expect(result['easy_submit']).to be true
        expect(result['auto_speech']).to be false
        expect(result['initiate_from_assistant']).to be true
        
        # Non-boolean values should remain unchanged
        expect(result['response_format']).to eq({ type: 'json_object' })
        expect(result['context_size']).to eq(100)
      end
    end
    
    context 'with protected properties' do
      it 'does not convert protected array properties' do
        input = {
          'images' => ['img1.png', 'img2.png'],
          'messages' => [{ 'role' => 'user', 'text' => 'Hello' }],
          'cells' => [],
          'tools' => [{ 'name' => 'test_tool' }]
        }
        
        result = BooleanParser.parse_hash(input)
        
        # Protected properties should remain unchanged
        expect(result['images']).to be_an(Array)
        expect(result['images']).to eq(['img1.png', 'img2.png'])
        expect(result['messages']).to be_an(Array)
        expect(result['cells']).to be_an(Array)
        expect(result['tools']).to be_an(Array)
      end
      
      it 'does not convert protected hash properties' do
        input = {
          'parameters' => { 'key' => 'value' },
          'response_format' => { 'type' => 'json' },
          'responseFormat' => { 'type' => 'xml' }  # alias
        }
        
        result = BooleanParser.parse_hash(input)
        
        # Protected properties should remain unchanged
        expect(result['parameters']).to be_a(Hash)
        expect(result['parameters']).to eq({ 'key' => 'value' })
        expect(result['response_format']).to be_a(Hash)
      end
    end
    
    context 'with mixed property types' do
      it 'correctly processes each property according to its type' do
        input = {
          # Boolean properties (various formats)
          'monadic' => 'true',
          'image' => '1',
          'pdf' => '0',
          'websearch' => 'yes',
          'stream' => 'no',
          
          # String properties
          'model' => 'gpt-4',
          'provider' => 'openai',
          
          # Numeric properties
          'temperature' => 0.7,
          'context_size' => 100,
          
          # Array properties
          'images' => ['test.png'],
          
          # Hash properties
          'parameters' => { 'test' => true }
        }
        
        result = BooleanParser.parse_hash(input)
        
        # Boolean conversions
        expect(result['monadic']).to be true
        expect(result['image']).to be true
        expect(result['pdf']).to be false
        expect(result['websearch']).to be true
        expect(result['stream']).to be false
        
        # Non-boolean properties unchanged
        expect(result['model']).to eq('gpt-4')
        expect(result['temperature']).to eq(0.7)
        expect(result['images']).to eq(['test.png'])
        expect(result['parameters']).to eq({ 'test' => true })
      end
    end
    
    context 'edge cases' do
      it 'handles nil values in boolean fields' do
        input = {
          'monadic' => nil,
        }
        
        result = BooleanParser.parse_hash(input)
        
        expect(result['monadic']).to be false
      end
      
      it 'handles empty strings in boolean fields' do
        input = {
          'easy_submit' => '',
          'auto_speech' => '   '  # whitespace
        }
        
        result = BooleanParser.parse_hash(input)
        
        expect(result['easy_submit']).to be false
        expect(result['auto_speech']).to be false
      end
      
      it 'preserves original structure for unknown properties' do
        input = {
          'unknown_field' => 'true',
          'custom_data' => { 'nested' => 'value' },
          'random_array' => [1, 2, 3]
        }
        
        result = BooleanParser.parse_hash(input)
        
        expect(result['unknown_field']).to eq('true')  # Not converted
        expect(result['custom_data']).to eq({ 'nested' => 'value' })
        expect(result['random_array']).to eq([1, 2, 3])
      end
    end
    
    context 'symbol keys' do
      it 'handles symbol keys correctly' do
        input = {
          monadic: 'true',
          toggle: 'false',
          images: ['test.png'],
          temperature: 0.7
        }
        
        result = BooleanParser.parse_hash(input)
        
        # BooleanParser normalizes to string keys when using MDSLSchema
        expect(result['monadic']).to be true
        expect(result['images']).to eq(['test.png'])
        expect(result['temperature']).to eq(0.7)
      end
      
      it 'handles mixed string and symbol keys' do
        input = {
          'monadic' => 'true',
          'images' => ['test.png'],
          :temperature => 0.7
        }
        
        result = BooleanParser.parse_hash(input)
        
        # All keys are normalized to strings when using MDSLSchema
        expect(result['monadic']).to be true
        expect(result['images']).to eq(['test.png'])
        expect(result['temperature']).to eq(0.7)
      end
    end
    
    context 'without MDSLSchema (fallback mode)' do
      before do
        # Temporarily hide MDSLSchema to test fallback
        allow(BooleanParser).to receive(:require_relative).with('mdsl_schema').and_raise(LoadError)
      end
      
      it 'falls back to pattern matching' do
        input = {
          'easy_submit' => 'true',
          'auto_speech' => 'false',
          'images' => ['test.png'],
          'custom_field' => 'true'
        }
        
        result = BooleanParser.parse_hash(input)
        
        # Known patterns should still work
        expect(result['easy_submit']).to be true
        expect(result['auto_speech']).to be false
        
        # Protected fields should still be protected
        expect(result['images']).to eq(['test.png'])
        
        # Unknown fields not converted
        expect(result['custom_field']).to eq('true')
      end
    end
    
    context 'performance considerations' do
      it 'efficiently handles large hashes' do
        # Create a large hash with mixed properties
        large_input = {}
        
        # Add many boolean properties
        100.times do |i|
          large_input["boolean_#{i}"] = i.even? ? 'true' : 'false'
        end
        
        # Add protected properties
        large_input['images'] = Array.new(50) { |i| "image_#{i}.png" }
        large_input['messages'] = Array.new(50) { |i| { 'id' => i } }
        
        # Add other properties
        large_input['model'] = 'gpt-4'
        large_input['temperature'] = 0.7
        
        # Should complete quickly
        start_time = Time.now
        result = BooleanParser.parse_hash(large_input)
        elapsed = Time.now - start_time
        
        expect(elapsed).to be < 0.1  # Should complete in under 100ms
        
        # Verify some conversions
        # Pattern matching doesn't match 'boolean_0' pattern, so they remain strings
        expect(result['boolean_0']).to eq('true')
        expect(result['boolean_1']).to eq('false')
        expect(result['images']).to be_an(Array)
        expect(result['images'].size).to eq(50)
      end
    end
  end
  
  describe 'Real-world scenarios' do
    it 'handles WebSocket message format' do
      # Simulating a message from JavaScript WebSocket
      ws_message = {
        'app_name' => 'ChatOpenAI',
        'monadic' => 'true',
        'easy_submit' => '1',
        'auto_speech' => '0',
        'initiate_from_assistant' => 'yes',
        'images' => [
          { 'data' => 'base64...', 'type' => 'image/png' }
        ],
        'message' => 'User input text',
        'temperature' => '0.7',  # Note: should remain string
        'context_size' => '100'  # Note: should remain string
      }
      
      result = BooleanParser.parse_hash(ws_message)
      
      # Boolean conversions
      expect(result['monadic']).to be true
      expect(result['easy_submit']).to be true
      expect(result['auto_speech']).to be false
      expect(result['initiate_from_assistant']).to be true
      
      # Protected and non-boolean fields
      expect(result['images']).to be_an(Array)
      expect(result['message']).to eq('User input text')
      expect(result['temperature']).to eq('0.7')  # Not converted
      expect(result['context_size']).to eq('100')  # Not converted
    end
    
    it 'handles MDSL configuration format' do
      # Simulating parsed MDSL configuration
      mdsl_config = {
        'responseFormat' => { type: 'json_object' },
        'easySubmit' => true,  # Already boolean
        'autoSpeech' => 'false',  # String to convert
        'contextSize' => 100,
        'temperature' => 0.0,
        'images' => nil,  # Could be nil initially
        'parameters' => {}
      }
      
      result = BooleanParser.parse_hash(mdsl_config)
      
      # Normalization and conversions
      expect(result['response_format']).to eq({ type: 'json_object' })
      expect(result['easy_submit']).to be true
      expect(result['auto_speech']).to be false
      expect(result['context_size']).to eq(100)
      expect(result['temperature']).to eq(0.0)
    end
  end
end