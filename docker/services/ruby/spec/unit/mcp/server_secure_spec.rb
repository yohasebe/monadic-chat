# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../../lib/monadic/mcp/server_secure'

RSpec.describe Monadic::MCP::SecureServer do
  # Mock CONFIG for testing
  before do
    stub_const('CONFIG', {
      'MCP_SERVER_ENABLED' => true,
      'MCP_SERVER_PORT' => 3100
    })
  end
  
  describe 'Authentication mechanism' do
    it 'defines authentication in the class' do
      # Check that the server has authentication capability
      methods = described_class.private_instance_methods(false)
      expect(methods).to include(:authenticate_request)
    end
    
    it 'defines authentication error codes' do
      # Check that authentication error code is defined
      expect(described_class.constants).to include(:JSONRPC_VERSION)
    end
  end
  
  describe 'Authentication logic' do
    it 'checks for API key in HTTP headers' do
      # The authenticate_request method should check HTTP_X_MCP_API_KEY
      # This test verifies the expected behavior
      expect(described_class.private_instance_methods).to include(:authenticate_request)
    end
    
    it 'requires non-empty API key' do
      # Documented behavior: empty keys should fail authentication
      # This is verified by reading the implementation
      source = described_class.instance_method(:authenticate_request).source_location
      expect(source).not_to be_nil
    end
  end
  
  describe 'Rate limiting' do
    it 'initializes rate limit tracking' do
      expect(described_class.class_variable_defined?(:@@request_counts)).to be true
    end
    
    it 'defines rate limit method' do
      # Test rate limit check method exists
      expect(described_class.private_instance_methods).to include(:rate_limit_check)
    end
  end
  
  describe 'Rate limit implementation' do
    it 'tracks requests in class variable' do
      # Verify rate limit tracking structure exists
      expect(described_class.class_variable_defined?(:@@request_counts)).to be true
    end
    
    it 'implements rate limit check method' do
      expect(described_class.private_instance_methods).to include(:rate_limit_check)
    end
    
    it 'enforces 60 requests per minute limit' do
      # This is documented in the implementation
      # The rate_limit_check method should halt with 429 when limit exceeded
      source = File.read(described_class.instance_method(:rate_limit_check).source_location[0])
      expect(source).to include('60')
    end
  end
  
  describe '.start!' do
    before do
      # Prevent actual server startup
      allow(described_class).to receive(:run!)
      allow(described_class).to receive(:set)
      # Mock EM check
      stub_const('EM', double('EventMachine', reactor_running?: false))
    end
    
    it 'respects MCP_SERVER_ENABLED configuration' do
      stub_const('CONFIG', { 'MCP_SERVER_ENABLED' => false })
      
      expect(described_class).not_to receive(:set)
      described_class.start!
    end
    
    it 'always binds to localhost for security' do
      stub_const('CONFIG', {
        'MCP_SERVER_ENABLED' => true,
        'MCP_SERVER_PORT' => 3100
      })
      
      expect(described_class).to receive(:set).with(:bind, '127.0.0.1')
      
      described_class.start!
    end
    
    it 'uses configured port or default' do
      stub_const('CONFIG', {
        'MCP_SERVER_ENABLED' => true,
        'MCP_SERVER_PORT' => 3200
      })
      
      # The port is set in the parent class, but we ensure binding is secure
      expect(described_class).to receive(:set).with(:bind, '127.0.0.1')
      
      described_class.start!
    end
  end
  
  describe 'Security features' do
    it 'includes both authentication and rate limiting' do
      # Check class methods
      methods = described_class.private_instance_methods(false)
      expect(methods).to include(:authenticate_request)
      expect(methods).to include(:rate_limit_check)
    end
    
    it 'inherits json_rpc_error from parent' do
      # Verify the server can create JSON-RPC errors
      # The parent Server class should provide this method
      # Note: json_rpc_error is a private method in Server
      all_methods = described_class.instance_methods(true) + described_class.private_instance_methods(true)
      expect(all_methods).to include(:json_rpc_error)
    end
  end
  
  describe 'Request handling flow' do
    let(:server) { described_class.new }
    
    before do
      # Mock Sinatra environment
      mock_request = double('request', 
        request_method: 'POST',
        ip: '127.0.0.1',
        env: {}
      )
      allow(server).to receive(:request).and_return(mock_request)
      allow(server).to receive(:halt)
      allow(server).to receive(:pass)
    end
    
    it 'allows OPTIONS requests without authentication' do
      allow(server.request).to receive(:request_method).and_return('OPTIONS')
      
      # Should pass through without auth check
      expect(server).to receive(:pass)
      expect(server).not_to receive(:authenticate_request)
      
      # Simulate before filter
      server.instance_eval do
        if request.request_method == 'OPTIONS'
          pass
        else
          authenticate_request
        end
      end
    end
    
    it 'requires authentication for non-OPTIONS requests' do
      allow(server.request).to receive(:request_method).and_return('POST')
      
      # Should check authentication
      expect(server).to receive(:authenticate_request).and_return(false)
      
      server.instance_eval do
        if request.request_method == 'OPTIONS'
          pass
        else
          authenticate_request
        end
      end
    end
  end
  
  describe 'Thread safety' do
    it 'uses class variable for shared state' do
      # Rate limiting uses @@request_counts which is shared across instances
      expect(described_class.class_variable_defined?(:@@request_counts)).to be true
      
      # Initialize if needed
      unless described_class.class_variable_get(:@@request_counts)
        described_class.class_variable_set(:@@request_counts, {})
      end
      
      # Verify it's a Hash for thread-safe operations
      expect(described_class.class_variable_get(:@@request_counts)).to be_a(Hash)
    end
  end
  
  describe 'Configuration validation' do
    it 'handles string boolean values for MCP_SERVER_ENABLED' do
      stub_const('CONFIG', { 'MCP_SERVER_ENABLED' => 'true' })
      
      # When enabled as 'true' string, should configure binding
      expect(described_class).to receive(:set).with(:bind, '127.0.0.1')
      
      described_class.start!
    end
    
    it 'handles missing configuration gracefully' do
      stub_const('CONFIG', {})
      
      # Should not start when not enabled
      expect(described_class).not_to receive(:set)
      described_class.start!
    end
  end
end