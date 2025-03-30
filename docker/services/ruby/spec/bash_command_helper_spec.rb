# frozen_string_literal: true

require_relative 'spec_helper'
require 'ostruct'
require 'open3'

# Include the module to test directly
# We're using a separate test class to avoid conflicts with other tests
require_relative 'monadic_app_command_mock'

RSpec.describe MonadicAppTest::MonadicHelper do
  # Set up test class that includes the module
  class TestCommandHelper
    include MonadicAppTest::MonadicHelper
    
    # Dummy send_command method to use in tests
    def send_command(command:, container:, success:, success_with_output:)
      # In a real implementation, this would execute the command
      # For testing, we'll just return the arguments
      {
        command: command,
        container: container,
        success: success,
        success_with_output: success_with_output
      }
    end
  end
  
  let(:helper) { TestCommandHelper.new }
  
  describe "#lib_installer" do
    context "with pip packager" do
      it "formats pip install command correctly" do
        result = helper.lib_installer(command: "numpy", packager: "pip")
        
        expect(result[:command]).to eq("pip install numpy")
        expect(result[:container]).to eq("python")
        expect(result[:success]).to include("installed successfully")
      end
    end
    
    context "with apt packager" do
      it "formats apt-get install command correctly" do
        result = helper.lib_installer(command: "python3-dev", packager: "apt")
        
        expect(result[:command]).to eq("apt-get install -y python3-dev")
        expect(result[:container]).to eq("python")
        expect(result[:success]).to include("installed successfully")
      end
    end
    
    context "with invalid packager" do
      it "returns invalid packager message" do
        result = helper.lib_installer(command: "some-package", packager: "invalid")
        
        expect(result[:command]).to eq("echo 'Invalid packager'")
        expect(result[:container]).to eq("python")
      end
    end
  end
  
  describe "#run_bash_command" do
    it "passes command to send_command with correct parameters" do
      result = helper.run_bash_command(command: "ls -la")
      
      expect(result[:command]).to eq("ls -la")
      expect(result[:container]).to eq("python")
      expect(result[:success]).to include("command has been executed")
      expect(result[:success_with_output]).to include("with the following output")
    end
    
    it "handles complex commands with quotes" do
      complex_command = 'echo "Hello, world!" | grep Hello'
      result = helper.run_bash_command(command: complex_command)
      
      expect(result[:command]).to eq(complex_command)
      expect(result[:container]).to eq("python")
    end
  end
end