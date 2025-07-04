# frozen_string_literal: true

require 'thread'

module Monadic
  module MCP
    # Thread-safe LRU-based rate limiter to prevent memory leaks
    class RateLimiter
      # Maximum number of IP addresses to track
      MAX_TRACKED_IPS = 10_000
      
      # Rate limit configuration
      REQUESTS_PER_MINUTE = 60
      WINDOW_SIZE = 60 # seconds
      
      def initialize(max_ips: MAX_TRACKED_IPS, requests_per_minute: REQUESTS_PER_MINUTE)
        @max_ips = max_ips
        @requests_per_minute = requests_per_minute
        @window_size = WINDOW_SIZE
        
        # Thread-safe data structures
        @mutex = Mutex.new
        @ip_data = {}
        @access_order = [] # For LRU tracking
      end
      
      # Check if request should be allowed
      # Returns true if allowed, false if rate limited
      def allow?(client_ip)
        @mutex.synchronize do
          current_time = Time.now.to_i
          
          # Clean expired entries first
          clean_expired_entries(current_time)
          
          # Check if IP exists
          if @ip_data[client_ip]
            # Update access order for LRU
            update_lru_order(client_ip)
            
            # Check rate limit
            if @ip_data[client_ip][:count] >= @requests_per_minute
              return false
            end
            
            # Increment counter
            @ip_data[client_ip][:count] += 1
          else
            # New IP - enforce LRU if at capacity
            if @ip_data.size >= @max_ips
              evict_least_recently_used
            end
            
            # Add new IP
            @ip_data[client_ip] = {
              count: 1,
              window_start: current_time
            }
            @access_order.push(client_ip)
          end
          
          true
        end
      end
      
      # Get current request count for an IP
      def request_count(client_ip)
        @mutex.synchronize do
          @ip_data[client_ip]&.[](:count) || 0
        end
      end
      
      # Get number of tracked IPs
      def tracked_ips_count
        @mutex.synchronize do
          @ip_data.size
        end
      end
      
      # Manual cleanup (for testing or maintenance)
      def cleanup!
        @mutex.synchronize do
          clean_expired_entries(Time.now.to_i)
        end
      end
      
      private
      
      # Remove entries outside the time window
      def clean_expired_entries(current_time)
        expired_ips = @ip_data.select do |_, data|
          data[:window_start] < current_time - @window_size
        end.keys
        
        expired_ips.each do |ip|
          @ip_data.delete(ip)
          @access_order.delete(ip)
        end
      end
      
      # Update LRU order when IP is accessed
      def update_lru_order(client_ip)
        @access_order.delete(client_ip)
        @access_order.push(client_ip)
      end
      
      # Remove least recently used IP
      def evict_least_recently_used
        return if @access_order.empty?
        
        # Remove the least recently used IP
        lru_ip = @access_order.shift
        @ip_data.delete(lru_ip)
        
        # Log eviction if debugging enabled
        if CONFIG["EXTRA_LOGGING"]
          puts "[RateLimiter] Evicted LRU IP: #{lru_ip} (capacity: #{@max_ips})"
        end
      end
    end
  end
end