# frozen_string_literal: true

require 'spec_helper'
require 'http'
require 'net/http'
require_relative '../../../lib/monadic/utils/network_error_handler'

RSpec.describe NetworkErrorHandler do
  # Test class that includes the module
  class TestNetworkHandler
    include NetworkErrorHandler
  end
  
  let(:handler) { TestNetworkHandler.new }
  
  describe '#with_network_retry' do
    context 'with successful request' do
      it 'returns the result on first attempt' do
        result = handler.with_network_retry do
          "success"
        end
        
        expect(result).to eq("success")
      end
      
      it 'does not retry on success' do
        attempt_count = 0
        
        result = handler.with_network_retry do
          attempt_count += 1
          "success"
        end
        
        expect(attempt_count).to eq(1)
        expect(result).to eq("success")
      end
    end
    
    context 'with retryable errors' do
      it 'retries on HTTP::TimeoutError' do
        attempts = 0
        
        result = handler.with_network_retry(max_retries: 2) do
          attempts += 1
          if attempts < 3
            raise HTTP::TimeoutError, "Request timed out"
          end
          "success after retries"
        end
        
        expect(attempts).to eq(3)
        expect(result).to eq("success after retries")
      end
      
      it 'retries on HTTP::ConnectionError' do
        attempts = 0
        
        result = handler.with_network_retry(max_retries: 1) do
          attempts += 1
          if attempts == 1
            raise HTTP::ConnectionError, "Connection failed"
          end
          "connected"
        end
        
        expect(attempts).to eq(2)
        expect(result).to eq("connected")
      end
      
      it 'retries on network timeout errors' do
        attempts = 0
        
        result = handler.with_network_retry(max_retries: 2) do
          attempts += 1
          case attempts
          when 1
            raise Net::OpenTimeout, "Connection timeout"
          when 2
            raise Net::ReadTimeout, "Read timeout"
          else
            "success"
          end
        end
        
        expect(attempts).to eq(3)
        expect(result).to eq("success")
      end
      
      it 'retries on connection refused' do
        attempts = 0
        
        result = handler.with_network_retry(max_retries: 1) do
          attempts += 1
          if attempts == 1
            raise Errno::ECONNREFUSED, "Connection refused"
          end
          "connected"
        end
        
        expect(attempts).to eq(2)
        expect(result).to eq("connected")
      end
      
      it 'retries on SSL errors' do
        attempts = 0
        
        result = handler.with_network_retry(max_retries: 1) do
          attempts += 1
          if attempts == 1
            raise OpenSSL::SSL::SSLError, "SSL handshake failed"
          end
          "secure connection"
        end
        
        expect(attempts).to eq(2)
        expect(result).to eq("secure connection")
      end
      
      it 'respects max_retries limit' do
        attempts = 0
        
        expect {
          handler.with_network_retry(max_retries: 2) do
            attempts += 1
            raise HTTP::TimeoutError, "Always fails"
          end
        }.to raise_error(RuntimeError)
        
        expect(attempts).to eq(3) # Initial attempt + 2 retries
      end
      
      it 'applies exponential backoff with sleep' do
        allow(handler).to receive(:sleep)
        attempts = 0
        
        begin
          handler.with_network_retry(max_retries: 3) do
            attempts += 1
            raise HTTP::TimeoutError, "Always fails"
          end
        rescue
          # Expected to fail
        end
        
        # Verify sleep was called with increasing delays
        expect(handler).to have_received(:sleep).exactly(3).times
      end
    end
    
    context 'with non-retryable errors' do
      it 'does not retry on JSON parse errors' do
        attempts = 0
        
        expect {
          handler.with_network_retry do
            attempts += 1
            raise JSON::ParserError, "Invalid JSON"
          end
        }.to raise_error(JSON::ParserError)
        
        expect(attempts).to eq(1)
      end
      
      it 'does not retry on standard errors' do
        attempts = 0
        
        expect {
          handler.with_network_retry do
            attempts += 1
            raise StandardError, "Generic error"
          end
        }.to raise_error(StandardError)
        
        expect(attempts).to eq(1)
      end
      
      it 'does not retry on argument errors' do
        attempts = 0
        
        expect {
          handler.with_network_retry do
            attempts += 1
            raise ArgumentError, "Invalid argument"
          end
        }.to raise_error(ArgumentError)
        
        expect(attempts).to eq(1)
      end
    end
    
    context 'with provider-specific behavior' do
      it 'formats timeout errors with provider name' do
        error_message = nil
        
        begin
          handler.with_network_retry(provider: 'openai', max_retries: 0) do
            raise HTTP::TimeoutError, "Timeout"
          end
        rescue => e
          error_message = e.message
        end
        
        expect(error_message).to include("openai")
        expect(error_message).to include("timed out")
      end
      
      it 'formats connection errors with provider name' do
        error_message = nil
        
        begin
          handler.with_network_retry(provider: 'claude', max_retries: 0) do
            raise HTTP::ConnectionError, "Connection failed"
          end
        rescue => e
          error_message = e.message
        end
        
        expect(error_message).to include("claude")
        expect(error_message).to include("Unable to connect")
      end
      
      it 'formats SSL errors with provider name' do
        error_message = nil
        
        begin
          handler.with_network_retry(provider: 'gemini', max_retries: 0) do
            raise OpenSSL::SSL::SSLError, "SSL error"
          end
        rescue => e
          error_message = e.message
        end
        
        expect(error_message).to include("gemini")
        expect(error_message).to include("SSL connection error")
      end
    end
  end
  
  describe '#timeout_config_for' do
    it 'returns default timeouts when no provider specified' do
      config = handler.timeout_config_for(nil)
      
      expect(config).to eq({
        open: 10,
        read: 120,
        write: 120
      })
    end
    
    it 'returns default timeouts for unknown provider' do
      config = handler.timeout_config_for('unknown')
      
      expect(config).to eq({
        open: 10,
        read: 120,
        write: 120
      })
    end
    
    it 'returns claude-specific timeouts' do
      config = handler.timeout_config_for('claude')
      
      expect(config).to eq({
        open: 10,
        read: 300,
        write: 300
      })
    end
    
    it 'returns perplexity-specific timeouts' do
      config = handler.timeout_config_for('perplexity')
      
      expect(config).to eq({
        open: 5,
        read: 600,
        write: 600
      })
    end
    
    it 'handles symbol provider names' do
      config = handler.timeout_config_for(:claude)
      
      expect(config[:read]).to eq(300)
    end
    
    it 'merges provider overrides with defaults' do
      config = handler.timeout_config_for(:perplexity)
      
      # Open timeout is overridden
      expect(config[:open]).to eq(5)
      # Read/write are overridden
      expect(config[:read]).to eq(600)
      expect(config[:write]).to eq(600)
    end
  end
  
  describe '#calculate_retry_delay (private)' do
    it 'implements exponential backoff' do
      # Access private method for testing
      delays = (1..5).map { |i| handler.send(:calculate_retry_delay, i) }
      
      # Each delay should be larger than the previous (ignoring jitter)
      delays.each_cons(2) do |prev, curr|
        expect(curr).to be > prev
      end
    end
    
    it 'caps delay at 30 seconds' do
      # Very high attempt number
      delay = handler.send(:calculate_retry_delay, 10)
      
      expect(delay).to be <= 30
    end
    
    it 'adds jitter to prevent thundering herd' do
      # Get multiple delays for the same attempt
      delays = 10.times.map { handler.send(:calculate_retry_delay, 3) }
      
      # They should not all be identical due to jitter
      expect(delays.uniq.size).to be > 1
    end
    
    it 'starts with base delay for first retry' do
      delay = handler.send(:calculate_retry_delay, 1)
      
      # Should be close to base delay (1 second) plus some jitter
      expect(delay).to be_between(1.0, 1.3)
    end
  end
  
  describe '#format_network_error (private)' do
    it 'formats timeout errors' do
      error = HTTP::TimeoutError.new("Timeout")
      message = handler.send(:format_network_error, error, 'openai')
      
      expect(message).to eq("Request to openai timed out. Please try again.")
    end
    
    it 'formats connection errors' do
      error = HTTP::ConnectionError.new("Connection failed")
      message = handler.send(:format_network_error, error, 'claude')
      
      expect(message).to eq("Unable to connect to claude. Please check your internet connection.")
    end
    
    it 'formats SSL errors' do
      error = OpenSSL::SSL::SSLError.new("SSL failed")
      message = handler.send(:format_network_error, error, 'gemini')
      
      expect(message).to eq("SSL connection error with gemini. Please try again.")
    end
    
    it 'formats generic errors' do
      error = RuntimeError.new("Something went wrong")
      message = handler.send(:format_network_error, error, nil)
      
      expect(message).to eq("Network error occurred: Something went wrong")
    end
    
    it 'uses API as default provider name' do
      error = HTTP::TimeoutError.new("Timeout")
      message = handler.send(:format_network_error, error, nil)
      
      expect(message).to eq("Request to API timed out. Please try again.")
    end
  end
  
  describe 'error categorization' do
    it 'correctly identifies retryable errors' do
      retryable = [
        HTTP::TimeoutError.new("timeout"),
        HTTP::ConnectionError.new("connection"),
        Net::OpenTimeout.new("open timeout"),
        Net::ReadTimeout.new("read timeout"),
        Errno::ECONNREFUSED.new("refused"),
        Errno::ETIMEDOUT.new("timed out"),
        Errno::ENETUNREACH.new("unreachable"),
        OpenSSL::SSL::SSLError.new("ssl")
      ]
      
      retryable.each do |error|
        expect(NetworkErrorHandler::RETRYABLE_ERRORS).to include(error.class)
      end
    end
  end
  
  describe 'logging behavior' do
    before do
      # Mock DebugHelper module
      module DebugHelper
        def self.debug(message, category: :app, level: :debug)
          # No-op for testing
        end
      end
      
      allow(DebugHelper).to receive(:debug).and_call_original
    end
    
    it 'logs retry attempts' do
      allow(handler).to receive(:sleep) # Speed up test
      
      begin
        handler.with_network_retry(max_retries: 1) do
          raise HTTP::TimeoutError, "Timeout"
        end
      rescue
        # Expected to fail
      end
      
      # Should log the retry attempt
      expect(DebugHelper).to have_received(:debug).at_least(:once)
    end
    
    it 'logs when retries are exhausted' do
      allow(handler).to receive(:sleep)
      
      begin
        handler.with_network_retry(max_retries: 0) do
          raise HTTP::TimeoutError, "Always fails"
        end
      rescue
        # Expected
      end
      
      # Should log exhaustion
      expect(DebugHelper).to have_received(:debug).with(
        anything,
        category: "api",
        level: :error
      )
    end
    
    it 'logs JSON errors as non-retryable' do
      begin
        handler.with_network_retry do
          raise JSON::ParserError, "Bad JSON"
        end
      rescue JSON::ParserError
        # Expected
      end
      
      expect(DebugHelper).to have_received(:debug).with(
        /JSON parse error.*not retryable/,
        category: "api",
        level: :error
      )
    end
  end
end