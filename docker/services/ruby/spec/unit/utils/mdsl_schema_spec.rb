# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/mdsl_schema'

RSpec.describe MDSLSchema do
  describe 'Property Type Definitions' do
    it 'defines all essential property types' do
      expect(described_class::PROPERTIES).to include(
        :description, :icon, :display_name, :system_prompt,
        :provider, :model, :temperature, :context_size,
        :monadic, :toggle, :image, :pdf, :images, :messages
      )
    end
    
    it 'correctly categorizes boolean properties' do
      boolean_props = %i[disabled monadic toggle easy_submit auto_speech 
                         initiate_from_assistant image pdf jupyter mathjax 
                         websearch stream vision reasoning ai_user]
      
      boolean_props.each do |prop|
        expect(described_class::PROPERTIES[prop][:type]).to eq(:boolean),
          "Expected #{prop} to be boolean type"
      end
    end
    
    it 'correctly categorizes array properties' do
      array_props = %i[images messages tools cells]
      
      array_props.each do |prop|
        expect(described_class::PROPERTIES[prop][:type]).to eq(:array),
          "Expected #{prop} to be array type"
      end
    end
    
    it 'correctly categorizes hash properties' do
      hash_props = %i[parameters response_format]
      
      hash_props.each do |prop|
        expect(described_class::PROPERTIES[prop][:type]).to eq(:hash),
          "Expected #{prop} to be hash type"
      end
    end
  end
  
  describe '.normalize' do
    context 'with canonical names' do
      it 'returns the same name' do
        expect(described_class.normalize('response_format')).to eq('response_format')
        expect(described_class.normalize('easy_submit')).to eq('easy_submit')
        expect(described_class.normalize('auto_speech')).to eq('auto_speech')
      end
    end
    
    context 'with camelCase aliases' do
      it 'converts to snake_case canonical form' do
        expect(described_class.normalize('responseFormat')).to eq('response_format')
        expect(described_class.normalize('easySubmit')).to eq('easy_submit')
        expect(described_class.normalize('autoSpeech')).to eq('auto_speech')
        expect(described_class.normalize('initiateFromAssistant')).to eq('initiate_from_assistant')
        expect(described_class.normalize('contextSize')).to eq('context_size')
      end
    end
    
    context 'with unknown properties' do
      it 'returns the original property name' do
        expect(described_class.normalize('unknownProperty')).to eq('unknownProperty')
        expect(described_class.normalize('custom_field')).to eq('custom_field')
      end
    end
  end
  
  describe '.alias?' do
    it 'identifies aliases correctly' do
      expect(described_class.alias?('responseFormat')).to be true
      expect(described_class.alias?('easySubmit')).to be true
      expect(described_class.alias?('response_format')).to be false
      expect(described_class.alias?('easy_submit')).to be false
      expect(described_class.alias?('unknown')).to be false
    end
  end
  
  describe '.aliases_for' do
    it 'returns all aliases for a property' do
      expect(described_class.aliases_for('response_format')).to include('response_format', 'responseFormat')
      expect(described_class.aliases_for('easy_submit')).to include('easy_submit', 'easySubmit')
    end
    
    it 'returns empty array for unknown properties' do
      expect(described_class.aliases_for('unknown')).to eq([])
    end
  end
  
  describe '.type_of' do
    it 'returns correct types for properties' do
      expect(described_class.type_of('temperature')).to eq(:float)
      expect(described_class.type_of('context_size')).to eq(:integer)
      expect(described_class.type_of('monadic')).to eq(:boolean)
      expect(described_class.type_of('images')).to eq(:array)
      expect(described_class.type_of('parameters')).to eq(:hash)
      expect(described_class.type_of('content')).to eq(:string_or_hash)
    end
    
    it 'works with aliases' do
      expect(described_class.type_of('responseFormat')).to eq(:hash)
      expect(described_class.type_of('easySubmit')).to eq(:boolean)
      expect(described_class.type_of('contextSize')).to eq(:integer)
    end
    
    it 'returns nil for unknown properties' do
      expect(described_class.type_of('unknown')).to be_nil
    end
  end
  
  describe '.boolean?' do
    it 'identifies boolean properties' do
      expect(described_class.boolean?('monadic')).to be true
      expect(described_class.boolean?('toggle')).to be true
      expect(described_class.boolean?('easy_submit')).to be true
      expect(described_class.boolean?('easySubmit')).to be true  # alias
    end
    
    it 'returns false for non-boolean properties' do
      expect(described_class.boolean?('temperature')).to be false
      expect(described_class.boolean?('images')).to be false
      expect(described_class.boolean?('unknown')).to be false
    end
  end
  
  describe '.protected?' do
    it 'identifies protected properties' do
      expect(described_class.protected?('images')).to be true
      expect(described_class.protected?('messages')).to be true
      expect(described_class.protected?('parameters')).to be true
      expect(described_class.protected?('content')).to be true
      expect(described_class.protected?('response_format')).to be true
      expect(described_class.protected?('responseFormat')).to be true  # alias
    end
    
    it 'returns false for non-protected properties' do
      expect(described_class.protected?('monadic')).to be false
      expect(described_class.protected?('temperature')).to be false
      expect(described_class.protected?('model')).to be false
    end
  end
  
  describe '.validate' do
    context 'boolean validation' do
      it 'validates boolean values' do
        expect(described_class.validate('monadic', true)).to be true
        expect(described_class.validate('monadic', false)).to be true
        expect(described_class.validate('monadic', 'true')).to be false
        expect(described_class.validate('monadic', 1)).to be false
      end
    end
    
    context 'string validation' do
      it 'validates string values' do
        expect(described_class.validate('model', 'gpt-4')).to be true
        expect(described_class.validate('model', 123)).to be false
        expect(described_class.validate('model', nil)).to be false
      end
    end
    
    context 'integer validation' do
      it 'validates integer values' do
        expect(described_class.validate('context_size', 100)).to be true
        expect(described_class.validate('context_size', '100')).to be false
        expect(described_class.validate('context_size', 100.5)).to be false
      end
    end
    
    context 'float validation' do
      it 'validates float values' do
        expect(described_class.validate('temperature', 0.7)).to be true
        expect(described_class.validate('temperature', 1)).to be true  # integer is ok for float
        expect(described_class.validate('temperature', '0.7')).to be false
      end
    end
    
    context 'array validation' do
      it 'validates array values' do
        expect(described_class.validate('images', [])).to be true
        expect(described_class.validate('images', ['img1.png'])).to be true
        expect(described_class.validate('images', 'not_array')).to be false
        expect(described_class.validate('images', nil)).to be false
      end
    end
    
    context 'hash validation' do
      it 'validates hash values' do
        expect(described_class.validate('parameters', {})).to be true
        expect(described_class.validate('parameters', { key: 'value' })).to be true
        expect(described_class.validate('parameters', [])).to be false
        expect(described_class.validate('parameters', 'string')).to be false
      end
    end
    
    context 'string_or_hash validation' do
      it 'validates string or hash values' do
        expect(described_class.validate('content', 'text')).to be true
        expect(described_class.validate('content', { text: 'hello' })).to be true
        expect(described_class.validate('content', [])).to be false
        expect(described_class.validate('content', 123)).to be false
      end
    end
    
    context 'any type validation' do
      it 'accepts any value' do
        expect(described_class.validate('data', 'string')).to be true
        expect(described_class.validate('data', 123)).to be true
        expect(described_class.validate('data', [])).to be true
        expect(described_class.validate('data', {})).to be true
        expect(described_class.validate('data', nil)).to be true
      end
    end
    
    context 'with aliases' do
      it 'validates using normalized property names' do
        expect(described_class.validate('easySubmit', true)).to be true
        expect(described_class.validate('responseFormat', { type: 'json' })).to be true
        expect(described_class.validate('contextSize', 100)).to be true
      end
    end
  end
  
  describe '.coerce' do
    context 'boolean coercion' do
      it 'coerces values to boolean' do
        expect(described_class.coerce('monadic', 'true')).to be true
        expect(described_class.coerce('monadic', 'false')).to be false
        expect(described_class.coerce('monadic', 1)).to be true
        expect(described_class.coerce('monadic', 0)).to be false
        expect(described_class.coerce('monadic', nil)).to be false
      end
    end
    
    context 'integer coercion' do
      it 'coerces values to integer' do
        expect(described_class.coerce('context_size', '100')).to eq(100)
        expect(described_class.coerce('context_size', 100.7)).to eq(100.7)  # Returns original if not string
        expect(described_class.coerce('context_size', 'invalid')).to eq('invalid')
      end
    end
    
    context 'float coercion' do
      it 'coerces values to float' do
        expect(described_class.coerce('temperature', '0.7')).to eq(0.7)
        expect(described_class.coerce('temperature', 1)).to eq(1.0)
        expect(described_class.coerce('temperature', 'invalid')).to eq('invalid')
      end
    end
    
    context 'non-coercible types' do
      it 'returns original value' do
        expect(described_class.coerce('images', 'string')).to eq('string')
        expect(described_class.coerce('parameters', 123)).to eq(123)
      end
    end
  end
  
  describe '.normalize_hash' do
    it 'normalizes all keys in a hash' do
      input = {
        'responseFormat' => { type: 'json' },
        'easySubmit' => true,
        'contextSize' => 100,
        'images' => ['img1.png'],
        'unknown_key' => 'value'
      }
      
      expected = {
        'response_format' => { type: 'json' },
        'easy_submit' => true,
        'context_size' => 100,
        'images' => ['img1.png'],
        'unknown_key' => 'value'
      }
      
      expect(described_class.normalize_hash(input)).to eq(expected)
    end
    
    it 'handles non-hash inputs' do
      expect(described_class.normalize_hash(nil)).to be_nil
      expect(described_class.normalize_hash('string')).to eq('string')
      expect(described_class.normalize_hash([])).to eq([])
    end
    
    it 'preserves symbol keys' do
      input = { responseFormat: 'json', easySubmit: true }
      result = described_class.normalize_hash(input)
      
      expect(result).to eq({
        'response_format' => 'json',
        'easy_submit' => true
      })
    end
  end
  
  describe '.boolean_properties' do
    it 'returns all boolean properties including aliases' do
      props = described_class.boolean_properties
      
      # Check canonical names are included
      expect(props).to include('monadic', 'toggle', 'easy_submit', 'auto_speech')
      
      # Check aliases are included
      expect(props).to include('easySubmit', 'autoSpeech')
      
      # Ensure no duplicates
      expect(props.uniq).to eq(props)
    end
  end
  
  describe '.protected_properties' do
    it 'returns all protected properties including aliases' do
      props = described_class.protected_properties
      
      # Check canonical names are included
      expect(props).to include('images', 'messages', 'parameters', 'response_format')
      
      # Check aliases are included  
      expect(props).to include('responseFormat')
      
      # Ensure no duplicates
      expect(props.uniq).to eq(props)
    end
  end
end