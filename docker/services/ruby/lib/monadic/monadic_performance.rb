# frozen_string_literal: true

require 'json'
require 'digest'

# Performance optimization for monadic operations
module MonadicPerformance
  # Simple in-memory cache for monadic responses
  class ResponseCache
    MAX_CACHE_SIZE = 100
    CACHE_TTL = 300 # 5 minutes

    def initialize
      @cache = {}
      @access_times = {}
    end

    def get(key)
      clean_expired_entries
      
      if @cache.key?(key) && !expired?(key)
        @access_times[key] = Time.now
        @cache[key]
      end
    end

    def set(key, value)
      clean_if_needed
      
      @cache[key] = value
      @access_times[key] = Time.now
    end

    def clear
      @cache.clear
      @access_times.clear
    end

    private

    def expired?(key)
      Time.now - @access_times[key] > CACHE_TTL
    end

    def clean_expired_entries
      expired_keys = @access_times.select { |_, time| Time.now - time > CACHE_TTL }.keys
      expired_keys.each do |key|
        @cache.delete(key)
        @access_times.delete(key)
      end
    end

    def clean_if_needed
      if @cache.size >= MAX_CACHE_SIZE
        # Remove least recently accessed entries
        sorted_keys = @access_times.sort_by { |_, time| time }.map(&:first)
        keys_to_remove = sorted_keys[0...(MAX_CACHE_SIZE / 2)]
        
        keys_to_remove.each do |key|
          @cache.delete(key)
          @access_times.delete(key)
        end
      end
    end
  end

  # Lazy JSON parser for streaming responses
  class LazyJsonParser
    def initialize
      @buffer = ""
      @parsed_chunks = []
    end

    def add_chunk(chunk)
      @buffer += chunk
      parse_available
    end

    def get_partial_result
      merge_chunks(@parsed_chunks)
    end

    def get_final_result
      # Try to parse any remaining buffer
      if @buffer.strip.length > 0
        begin
          final_chunk = JSON.parse(@buffer)
          @parsed_chunks << final_chunk
        rescue JSON::ParserError
          # Buffer might be incomplete
        end
      end
      
      merge_chunks(@parsed_chunks)
    end

    private

    def parse_available
      # Try to find complete JSON objects in buffer
      start_pos = 0
      brace_count = 0
      in_string = false
      escape_next = false
      
      @buffer.each_char.with_index do |char, idx|
        if escape_next
          escape_next = false
          next
        end
        
        case char
        when '\\'
          escape_next = true if in_string
        when '"'
          in_string = !in_string unless escape_next
        when '{'
          brace_count += 1 unless in_string
        when '}'
          unless in_string
            brace_count -= 1
            if brace_count == 0 && start_pos < idx
              # Found complete JSON object
              json_str = @buffer[start_pos..idx]
              begin
                @parsed_chunks << JSON.parse(json_str)
                start_pos = idx + 1
              rescue JSON::ParserError
                # Invalid JSON, skip
              end
            end
          end
        end
      end
      
      # Keep only unparsed portion in buffer
      @buffer = @buffer[start_pos..-1] if start_pos > 0
    end

    def merge_chunks(chunks)
      return {} if chunks.empty?
      
      # Merge all chunks intelligently
      result = {
        "message" => "",
        "context" => {}
      }
      
      chunks.each do |chunk|
        if chunk.is_a?(Hash)
          # Concatenate messages
          if chunk["message"]
            result["message"] += chunk["message"]
          end
          
          # Merge contexts
          if chunk["context"]
            result["context"] = deep_merge(result["context"], chunk["context"])
          end
        end
      end
      
      result
    end

    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |_, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        elsif old_val.is_a?(Array) && new_val.is_a?(Array)
          (old_val + new_val).uniq
        else
          new_val
        end
      end
    end
  end

  # Performance monitoring
  class PerformanceMonitor
    def initialize
      @metrics = {}
    end

    def measure(operation_name)
      start_time = Time.now
      result = yield
      duration = Time.now - start_time
      
      record_metric(operation_name, duration)
      
      result
    end

    def record_metric(operation_name, duration)
      @metrics[operation_name] ||= {
        count: 0,
        total_time: 0.0,
        min_time: Float::INFINITY,
        max_time: 0.0
      }
      
      metric = @metrics[operation_name]
      metric[:count] += 1
      metric[:total_time] += duration
      metric[:min_time] = [metric[:min_time], duration].min
      metric[:max_time] = [metric[:max_time], duration].max
    end

    def get_stats(operation_name)
      metric = @metrics[operation_name]
      return nil unless metric
      
      {
        count: metric[:count],
        average_time: metric[:total_time] / metric[:count],
        min_time: metric[:min_time],
        max_time: metric[:max_time],
        total_time: metric[:total_time]
      }
    end

    def report
      @metrics.map do |name, metric|
        {
          operation: name,
          count: metric[:count],
          average_ms: ((metric[:total_time] / metric[:count]) * 1000).round(2),
          min_ms: (metric[:min_time] * 1000).round(2),
          max_ms: (metric[:max_time] * 1000).round(2)
        }
      end
    end
  end

  # Module methods
  module_function

  def response_cache
    @response_cache ||= ResponseCache.new
  end

  def performance_monitor
    @performance_monitor ||= PerformanceMonitor.new
  end

  # Cache key generation for monadic responses
  def generate_cache_key(provider, model, messages, options = {})
    data = {
      provider: provider,
      model: model,
      messages: messages.map { |m| m.slice("role", "content") },
      options: options.slice("temperature", "max_tokens", "response_format")
    }
    
    Digest::SHA256.hexdigest(JSON.generate(data))
  end

  # Optimized JSON parsing with caching
  def parse_json_with_cache(content, cache_key = nil)
    if cache_key
      cached = response_cache.get(cache_key)
      return cached if cached
    end
    
    result = performance_monitor.measure("json_parse") do
      safe_parse_monadic_response(content)
    end
    
    response_cache.set(cache_key, result) if cache_key
    result
  end

  # Optimized monadic transformation
  def optimize_monadic_transform(content, app)
    performance_monitor.measure("monadic_transform") do
      # Skip transformation if already valid monadic format
      if content.is_a?(Hash) && content["message"] && content["context"]
        return content
      end
      
      # Apply transformation
      if defined?(APPS) && APPS[app]&.respond_to?(:monadic_map)
        APPS[app].monadic_map(content)
      else
        content
      end
    end
  end

  # Batch validation for multiple responses
  def validate_batch(responses, schema_type = :basic)
    performance_monitor.measure("batch_validation") do
      responses.map do |response|
        validate_monadic_response!(response, schema_type)
      end
    end
  end

  # Get performance report
  def get_performance_report
    {
      cache_stats: {
        size: response_cache.instance_variable_get(:@cache).size,
        hit_rate: calculate_cache_hit_rate
      },
      operation_stats: performance_monitor.report
    }
  end

  private

  def self.calculate_cache_hit_rate
    # This would need to track hits/misses in the cache
    # For now, return a placeholder
    "Not implemented"
  end
end