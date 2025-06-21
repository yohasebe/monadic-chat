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
        
        # For now, no API key validation implemented
        # This would need to be configured differently
        return true
      end

      # Override to allow configurable bind address
      def self.start!
        return unless CONFIG["MCP_SERVER_ENABLED"] == true || CONFIG["MCP_SERVER_ENABLED"] == "true"
        
        port = (CONFIG["MCP_SERVER_PORT"] || 3100).to_i
        bind_address = '127.0.0.1'  # Always bind to localhost for security
        
        # Start server with localhost binding
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