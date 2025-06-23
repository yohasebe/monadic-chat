# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "Environment Variable Behavior" do
  # Mock class to test environment-aware behavior
  class TestApp
    def debug_operation
      output = []
      
      if ENV['APP_DEBUG']
        output << "[DEBUG] Starting operation"
      end
      
      output << "Operation completed"
      
      if ENV['DEVELOPMENT_MODE']
        output << "[INFO] Development mode active"
      end
      
      output.join("\n")
    end
    
    def complex_operation
      output = []
      
      begin
        if ENV['DEVELOPMENT_MODE']
          output << "[INFO] Starting complex operation..."
          output << "[DEBUG] Current state: initialized"
        end
        
        # Simulate operation
        result = "Success"
        
        if ENV['APP_DEBUG']
          output << "[DEBUG] Operation result: #{result}"
        end
        
        output << result
      rescue StandardError => e
        output << "[ERROR] Complex operation failed: #{e.message}"
        raise
      end
      
      output.join("\n")
    end
    
    def error_operation
      raise StandardError, "Test error"
    rescue StandardError => e
      "[ERROR] Operation failed: #{e.message}"
    end
  end
  
  let(:app) { TestApp.new }
  
  describe "Debug Environment Variables" do
    after(:each) do
      # Clean up environment variables after each test
      ENV.delete('APP_DEBUG')
      ENV.delete('DEVELOPMENT_MODE')
      ENV.delete('DRAWIO_DEBUG')
      ENV.delete('TOOL_DEBUG')
    end
    
    context "with APP_DEBUG enabled" do
      before { ENV['APP_DEBUG'] = '1' }
      
      it "includes debug output when enabled" do
        result = app.debug_operation
        expect(result).to include("[DEBUG] Starting operation")
        expect(result).to include("Operation completed")
      end
    end
    
    context "without APP_DEBUG" do
      it "excludes debug output when disabled" do
        result = app.debug_operation
        expect(result).not_to include("[DEBUG]")
        expect(result).to include("Operation completed")
      end
    end
    
    context "with DEVELOPMENT_MODE enabled" do
      before { ENV['DEVELOPMENT_MODE'] = '1' }
      
      it "includes development info when enabled" do
        result = app.debug_operation
        expect(result).to include("[INFO] Development mode active")
      end
      
      it "includes detailed logging in complex operations" do
        result = app.complex_operation
        expect(result).to include("[INFO] Starting complex operation")
        expect(result).to include("[DEBUG] Current state")
      end
    end
    
    context "with multiple debug flags" do
      before do
        ENV['APP_DEBUG'] = '1'
        ENV['DEVELOPMENT_MODE'] = '1'
      end
      
      it "includes all relevant debug output" do
        result = app.complex_operation
        expect(result).to include("[INFO] Starting complex operation")
        expect(result).to include("[DEBUG] Operation result")
        expect(result).to include("Success")
      end
    end
  end
  
  describe "Error Handling" do
    it "always logs errors regardless of environment" do
      result = app.error_operation
      expect(result).to include("[ERROR]")
      expect(result).to include("Test error")
    end
  end
  
  describe "Environment Variable Standards" do
    it "recognizes standard debug environment variables" do
      standard_vars = %w[APP_DEBUG DRAWIO_DEBUG TOOL_DEBUG DEVELOPMENT_MODE]
      
      standard_vars.each do |var|
        expect(ENV).to respond_to(:[])
        expect(ENV).to respond_to(:[]=)
        expect(ENV).to respond_to(:delete)
        
        # Test setting and unsetting
        ENV[var] = '1'
        expect(ENV[var]).to eq('1')
        
        ENV.delete(var)
        expect(ENV[var]).to be_nil
      end
    end
  end
  
  describe "DrawIO-specific Debug Behavior" do
    it "validates DrawIO debug pattern" do
      # Load the actual DrawIO file to check pattern
      drawio_file = File.join(
        File.dirname(__FILE__), 
        "..", "apps", "drawio_grapher", "drawio_grapher_tools.rb"
      )
      
      if File.exist?(drawio_file)
        content = File.read(drawio_file)
        
        # Check that debug output is conditional
        expect(content).to match(/if\s+ENV\['DRAWIO_DEBUG'\]/)
        
        # Check that debug messages follow the pattern
        debug_lines = content.scan(/puts.*\[DEBUG\].*DrawIOGrapher/)
        expect(debug_lines).not_to be_empty
      end
    end
  end
end