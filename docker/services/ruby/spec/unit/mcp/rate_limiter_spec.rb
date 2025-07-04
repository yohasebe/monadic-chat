# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/mcp/rate_limiter'

RSpec.describe Monadic::MCP::RateLimiter do
  let(:rate_limiter) { described_class.new(max_ips: 3, requests_per_minute: 5) }
  
  describe '#allow?' do
    it 'allows requests within rate limit' do
      5.times do
        expect(rate_limiter.allow?('192.168.1.1')).to be true
      end
    end
    
    it 'blocks requests exceeding rate limit' do
      5.times { rate_limiter.allow?('192.168.1.1') }
      expect(rate_limiter.allow?('192.168.1.1')).to be false
    end
    
    it 'tracks multiple IPs independently' do
      3.times { rate_limiter.allow?('192.168.1.1') }
      3.times { rate_limiter.allow?('192.168.1.2') }
      
      expect(rate_limiter.allow?('192.168.1.1')).to be true
      expect(rate_limiter.allow?('192.168.1.2')).to be true
    end
  end
  
  describe 'LRU eviction' do
    it 'evicts least recently used IP when capacity is reached' do
      # Fill up with 3 IPs
      rate_limiter.allow?('192.168.1.1')
      rate_limiter.allow?('192.168.1.2')
      rate_limiter.allow?('192.168.1.3')
      
      expect(rate_limiter.tracked_ips_count).to eq(3)
      
      # Access a new IP, should evict 192.168.1.1
      rate_limiter.allow?('192.168.1.4')
      
      expect(rate_limiter.tracked_ips_count).to eq(3)
      
      # 192.168.1.1 should be evicted and have 0 count
      expect(rate_limiter.request_count('192.168.1.1')).to eq(0)
      expect(rate_limiter.request_count('192.168.1.4')).to eq(1)
    end
    
    it 'updates LRU order when existing IP is accessed' do
      # Set up 3 IPs
      rate_limiter.allow?('192.168.1.1')
      rate_limiter.allow?('192.168.1.2')
      rate_limiter.allow?('192.168.1.3')
      
      # Access the first IP again to move it to end
      rate_limiter.allow?('192.168.1.1')
      
      # Add new IP - should evict 192.168.1.2 (now least recently used)
      rate_limiter.allow?('192.168.1.4')
      
      expect(rate_limiter.request_count('192.168.1.1')).to eq(2) # Still tracked
      expect(rate_limiter.request_count('192.168.1.2')).to eq(0) # Evicted
      expect(rate_limiter.request_count('192.168.1.3')).to eq(1) # Still tracked
      expect(rate_limiter.request_count('192.168.1.4')).to eq(1) # New
    end
  end
  
  describe '#cleanup!' do
    it 'removes expired entries' do
      rate_limiter.allow?('192.168.1.1')
      
      # Manually set window_start to past
      rate_limiter.instance_eval do
        @mutex.synchronize do
          @ip_data['192.168.1.1'][:window_start] = Time.now.to_i - 120
        end
      end
      
      rate_limiter.cleanup!
      expect(rate_limiter.tracked_ips_count).to eq(0)
    end
  end
  
  describe 'thread safety' do
    it 'handles concurrent access safely' do
      threads = []
      errors = []
      
      10.times do |i|
        threads << Thread.new do
          begin
            100.times do
              rate_limiter.allow?("192.168.1.#{i}")
            end
          rescue => e
            errors << e
          end
        end
      end
      
      threads.each(&:join)
      expect(errors).to be_empty
    end
  end
end