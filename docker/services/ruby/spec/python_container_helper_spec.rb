# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "../lib/monadic/adapters/python_container_helper"

RSpec.describe MonadicHelper do
  # Create a test class that includes the MonadicHelper module
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      # Mock send_command method
      def send_command(command:, container:)
        case container
        when "python"
          if command.include?("sysinfo")
            "Python container system info"
          elsif command.include?("Dockerfile")
            "FROM python:3.9\nRUN pip install requirements"
          elsif command.include?("pysetup.sh")
            "#!/bin/bash\npip install pandas numpy"
          else
            "Python container response"
          end
        when "ruby"
          if command.include?("rbsetup.sh")
            "#!/bin/bash\ngem install rspec"
          else
            "Ruby container response"
          end
        else
          "Unknown container response"
        end
      end
    end
  end
  
  let(:helper) { test_class.new }

  describe "#system_info" do
    it "calls send_command with sysinfo command in python container" do
      expect(helper).to receive(:send_command).with(
        command: match(/sysinfo/),
        container: "python"
      ).and_return("System info result")
      
      result = helper.system_info
      expect(result).to eq("System info result")
    end
    
    it "calls sysinfo.sh command directly" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to eq("sysinfo.sh")
        "System info result"
      end
      
      helper.system_info
    end
  end

  describe "#get_dockerfile" do
    it "calls send_command with dockerfile command in python container" do
      expect(helper).to receive(:send_command).with(
        command: match(/\/usr\/bin\/cat \/monadic\/Dockerfile/),
        container: "python"
      ).and_return("Dockerfile content")
      
      result = helper.get_dockerfile
      expect(result).to eq("Dockerfile content")
    end
    
    it "redirects stderr to /dev/null" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("2>/dev/null")
        "Dockerfile content"
      end
      
      helper.get_dockerfile
    end
  end

  describe "#get_rbsetup" do
    it "calls send_command with rbsetup command in ruby container" do
      expect(helper).to receive(:send_command).with(
        command: match(/\/usr\/bin\/cat \/monadic\/rbsetup\.sh/),
        container: "ruby"
      ).and_return("rbsetup.sh content")
      
      result = helper.get_rbsetup
      expect(result).to eq("rbsetup.sh content")
    end
    
    it "redirects stderr to /dev/null" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("2>/dev/null")
        "rbsetup.sh content"
      end
      
      helper.get_rbsetup
    end
  end

  describe "#get_pysetup" do
    it "calls send_command with pysetup command in python container" do
      expect(helper).to receive(:send_command).with(
        command: match(/\/usr\/bin\/cat \/monadic\/pysetup\.sh/),
        container: "python"
      ).and_return("pysetup.sh content")
      
      result = helper.get_pysetup
      expect(result).to eq("pysetup.sh content")
    end
    
    it "redirects stderr to /dev/null" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include("2>/dev/null")
        "pysetup.sh content"
      end
      
      helper.get_pysetup
    end
  end

  describe "#check_environment" do
    it "combines all environment information into formatted output" do
      result = helper.check_environment
      
      expect(result).to include("### Dockerfile")
      expect(result).to include("### rbsetup.sh")
      expect(result).to include("### pysetup.sh")
      expect(result).to include("FROM python:3.9")
      expect(result).to include("gem install rspec")
      expect(result).to include("pip install pandas numpy")
    end
    
    it "calls all three getter methods" do
      expect(helper).to receive(:get_dockerfile).and_return("Dockerfile content")
      expect(helper).to receive(:get_rbsetup).and_return("rbsetup content")
      expect(helper).to receive(:get_pysetup).and_return("pysetup content")
      
      result = helper.check_environment
      
      expect(result).to include("Dockerfile content")
      expect(result).to include("rbsetup content")
      expect(result).to include("pysetup content")
    end
    
    it "formats output with code blocks" do
      result = helper.check_environment
      
      # Count the number of ``` markers (should be 6: 3 opening + 3 closing)
      code_block_count = result.scan(/```/).length
      expect(code_block_count).to eq(6)
    end
    
    it "returns a properly formatted heredoc string" do
      result = helper.check_environment
      
      # Check that it starts with environment info header
      expect(result).to start_with("### Dockerfile")
      # Check that it ends properly
      expect(result).to end_with("```\n")
      # Check for proper section separation
      expect(result).to include("###")
    end
  end
end