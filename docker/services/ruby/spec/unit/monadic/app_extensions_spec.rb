# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/app_extensions'

# Mock MonadicApp for testing
class TestMonadicApp
  include MonadicChat::AppExtensions
  
  attr_accessor :context
  
  def initialize
    @context = {}
  end
  
  def settings
    { mathjax: false }
  end
end

RSpec.describe MonadicChat::AppExtensions do
  let(:app) { TestMonadicApp.new }
  
  describe '#monadic_unit' do
    it 'returns a JSON string with message and context' do
      result = app.monadic_unit('Hello, world!')
      
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed['message']).to eq('Hello, world!')
      expect(parsed['context']).to eq({})
    end
    
    it 'includes current context' do
      app.context = { 'user' => 'test' }
      result = app.monadic_unit('Test message')
      
      parsed = JSON.parse(result)
      expect(parsed['context']).to eq({ 'user' => 'test' })
    end
  end
  
  describe '#monadic_unwrap' do
    it 'parses JSON string and returns Hash' do
      json_str = '{"message": "Test", "context": {"count": 42}}'
      result = app.monadic_unwrap(json_str)
      
      expect(result).to be_a(Hash)
      expect(result['message']).to eq('Test')
      expect(result['context']).to eq({ 'count' => 42 })
    end
    
    it 'returns Hash as-is' do
      hash = { 'message' => 'Direct', 'context' => {} }
      result = app.monadic_unwrap(hash)
      
      expect(result).to eq(hash)
    end
    
    it 'handles invalid JSON gracefully' do
      result = app.monadic_unwrap('invalid json')
      
      expect(result).to be_a(Hash)
      expect(result['message']).to eq('invalid json')
      expect(result['context']).to eq({})
    end
  end
  
  describe '#monadic_map' do
    it 'transforms context and returns JSON string' do
      json_str = '{"message": "Test", "context": {"count": 1}}'
      
      result = app.monadic_map(json_str) do |ctx|
        ctx.merge('count' => ctx['count'] + 1)
      end
      
      expect(result).to be_a(String)
      parsed = JSON.parse(result)
      expect(parsed['message']).to eq('Test')
      expect(parsed['context']['count']).to eq(2)
    end
    
    it 'updates instance context' do
      json_str = '{"message": "Test", "context": {"updated": true}}'
      
      app.monadic_map(json_str) { |ctx| ctx }
      
      expect(app.context).to eq({ 'updated' => true })
    end
  end
  
  describe '#monadic_html' do
    it 'returns HTML string' do
      json_str = '{"message": "Test", "context": {"key": "value"}}'
      
      result = app.monadic_html(json_str)
      
      expect(result).to be_a(String)
      expect(result).to include('Test')
      expect(result).to include('Context')
      expect(result).to include('toggle')
      expect(result).to include('Key:')
      expect(result).to include('value')
    end
  end
end