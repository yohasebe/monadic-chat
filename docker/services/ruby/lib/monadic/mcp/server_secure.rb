# frozen_string_literal: true

# Example of secure MCP server implementation with authentication
# This is a concept for future implementation

require 'jwt'
require 'bcrypt'

module Monadic
  module MCP
    class SecureServer < Server
      # Add authentication middleware
      before do
        # Skip auth for OPTIONS requests
        pass if request.request_method == 'OPTIONS'
        
        # Check authentication token
        unless authenticate_request
          halt 401, json_rpc_error(nil, "Unauthorized", -32001)
        end
      end

      private

      def authenticate_request
        # Check for API key in header
        api_key = request.env['HTTP_X_MCP_API_KEY']
        return false unless api_key
        
        # Validate API key against configured keys
        valid_keys = CONFIG["MCP_API_KEYS"]&.split(",")&.map(&:strip) || []
        return false if valid_keys.empty?
        
        # Use BCrypt for secure comparison
        valid_keys.any? do |valid_key|
          BCrypt::Password.new(valid_key) == api_key rescue false
        end
      end

      # Override to allow configurable bind address
      def self.start!
        return unless CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true"
        
        port = (CONFIG["MCP_SERVER_PORT"] || 3100).to_i
        bind_address = CONFIG["MCP_BIND_ADDRESS"] || '127.0.0.1'
        
        # Warn if binding to non-localhost without auth
        if bind_address != '127.0.0.1' && bind_address != 'localhost'
          unless CONFIG["MCP_API_KEYS"]
            puts "WARNING: MCP server binding to #{bind_address} without authentication!"
            puts "Please set MCP_API_KEYS in your configuration for security."
          end
        end
        
        # Start server with configurable bind address
        set :bind, bind_address
        super
      end

      # Add rate limiting
      @@request_counts = {}
      
      def rate_limit_check
        client_ip = request.ip
        current_time = Time.now.to_i
        
        # Clean old entries
        @@request_counts.delete_if { |_, data| data[:time] < current_time - 60 }
        
        # Check rate limit (60 requests per minute)
        if @@request_counts[client_ip]
          if @@request_counts[client_ip][:count] > 60
            halt 429, json_rpc_error(nil, "Rate limit exceeded", -32002)
          end
          @@request_counts[client_ip][:count] += 1
        else
          @@request_counts[client_ip] = { count: 1, time: current_time }
        end
      end
    end
  end
end