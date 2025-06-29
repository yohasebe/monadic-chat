# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/monadic_performance'

RSpec.describe MonadicPerformance do
  describe MonadicPerformance::ResponseCache do
    let(:cache) { MonadicPerformance::ResponseCache.new }

    describe '#get and #set' do
      it 'stores and retrieves values' do
        cache.set('key1', 'value1')
        expect(cache.get('key1')).to eq('value1')
      end

      it 'returns nil for non-existent keys' do
        expect(cache.get('nonexistent')).to be_nil
      end

      it 'returns nil for expired entries' do
        cache.set('key1', 'value1')
        # Simulate expiration by manipulating access time
        access_times = cache.instance_variable_get(:@access_times)
        access_times['key1'] = Time.now - 400 # Beyond TTL
        expect(cache.get('key1')).to be_nil
      end
    end

    describe '#clear' do
      it 'removes all entries' do
        cache.set('key1', 'value1')
        cache.set('key2', 'value2')
        cache.clear
        expect(cache.get('key1')).to be_nil
        expect(cache.get('key2')).to be_nil
      end
    end

    describe 'size management' do
      it 'removes least recently used entries when at capacity' do
        # Fill cache to capacity
        (1..MonadicPerformance::ResponseCache::MAX_CACHE_SIZE).each do |i|
          cache.set("key#{i}", "value#{i}")
          sleep 0.001 # Ensure different access times
        end

        # Add one more to trigger cleanup
        cache.set('new_key', 'new_value')

        # First half should be removed
        expect(cache.get('key1')).to be_nil
        expect(cache.get('new_key')).to eq('new_value')
      end
    end
  end

  describe MonadicPerformance::LazyJsonParser do
    let(:parser) { MonadicPerformance::LazyJsonParser.new }

    describe '#add_chunk and #get_partial_result' do
      it 'parses complete JSON objects from chunks' do
        parser.add_chunk('{"message": "Hello')
        parser.add_chunk('", "context": {}}')
        
        result = parser.get_final_result
        expect(result).to eq({
          "message" => "Hello",
          "context" => {}
        })
      end

      it 'handles multiple JSON objects in stream' do
        parser.add_chunk('{"message": "First"')
        parser.add_chunk(', "context": {}}')
        parser.add_chunk('{"message": "Second", "context": {}}')
        
        result = parser.get_final_result
        expect(result["message"]).to include("First")
      end

      it 'merges context from multiple chunks' do
        parser.add_chunk('{"message": "Test", "context": {"a": 1}}')
        parser.add_chunk('{"message": " continued", "context": {"b": 2}}')
        
        result = parser.get_final_result
        expect(result["message"]).to eq("Test continued")
        expect(result["context"]).to eq({ "a" => 1, "b" => 2 })
      end
    end

    describe '#get_final_result' do
      it 'returns empty hash for no chunks' do
        expect(parser.get_final_result).to eq({})
      end

      it 'handles incomplete JSON gracefully' do
        parser.add_chunk('{"message": "Incomplete')
        result = parser.get_final_result
        expect(result).to eq({})
      end
    end
  end

  describe MonadicPerformance::PerformanceMonitor do
    let(:monitor) { MonadicPerformance::PerformanceMonitor.new }

    describe '#measure' do
      it 'measures operation duration' do
        result = monitor.measure('test_op') do
          sleep 0.01
          'result'
        end
        
        expect(result).to eq('result')
        stats = monitor.get_stats('test_op')
        expect(stats[:count]).to eq(1)
        expect(stats[:total_time]).to be >= 0.01
      end

      it 'accumulates multiple measurements' do
        3.times do
          monitor.measure('test_op') { sleep 0.001 }
        end
        
        stats = monitor.get_stats('test_op')
        expect(stats[:count]).to eq(3)
        expect(stats[:average_time]).to be_between(0.001, 0.01)
      end
    end

    describe '#report' do
      it 'generates performance report' do
        monitor.measure('op1') { sleep 0.001 }
        monitor.measure('op2') { sleep 0.002 }
        
        report = monitor.report
        expect(report).to be_an(Array)
        expect(report.length).to eq(2)
        
        op1_report = report.find { |r| r[:operation] == 'op1' }
        expect(op1_report[:count]).to eq(1)
        expect(op1_report[:average_ms]).to be >= 1.0
      end
    end
  end

  describe 'Module methods' do
    describe '.generate_cache_key' do
      it 'generates consistent hash for same inputs' do
        key1 = MonadicPerformance.generate_cache_key('openai', 'gpt-4', [{ "role" => "user", "content" => "Hi" }])
        key2 = MonadicPerformance.generate_cache_key('openai', 'gpt-4', [{ "role" => "user", "content" => "Hi" }])
        
        expect(key1).to eq(key2)
      end

      it 'generates different hash for different inputs' do
        key1 = MonadicPerformance.generate_cache_key('openai', 'gpt-4', [{ "role" => "user", "content" => "Hi" }])
        key2 = MonadicPerformance.generate_cache_key('claude', 'gpt-4', [{ "role" => "user", "content" => "Hi" }])
        
        expect(key1).not_to eq(key2)
      end
    end

    describe '.parse_json_with_cache' do
      before do
        MonadicPerformance.response_cache.clear
      end

      it 'caches parsed JSON' do
        json = '{"message": "test", "context": {}}'
        key = 'test_key'
        
        # First call should parse
        result1 = MonadicPerformance.parse_json_with_cache(json, key)
        
        # Second call should use cache
        expect(MonadicPerformance).not_to receive(:safe_parse_monadic_response)
        result2 = MonadicPerformance.parse_json_with_cache(json, key)
        
        expect(result1).to eq(result2)
      end
    end

    describe '.optimize_monadic_transform' do
      it 'skips transformation for already valid format' do
        valid_content = { "message" => "test", "context" => {} }
        result = MonadicPerformance.optimize_monadic_transform(valid_content, 'test_app')
        expect(result).to eq(valid_content)
      end
    end

    describe '.validate_batch' do
      it 'validates multiple responses' do
        responses = [
          '{"message": "test1", "context": {}}',
          '{"message": "test2", "context": {}}',
          'invalid json'
        ]
        
        results = MonadicPerformance.validate_batch(responses)
        expect(results.length).to eq(3)
        expect(results[0]["message"]).to eq("test1")
        expect(results[1]["message"]).to eq("test2")
        expect(results[2]["context"]["error_type"]).to eq("parse_error")
      end
    end
  end
end