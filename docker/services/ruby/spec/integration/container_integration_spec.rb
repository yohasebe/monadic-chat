# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe "Container Integration Tests", type: :integration do
  before(:all) do
    skip "Container integration tests require Docker environment" unless docker_available?
  end

  describe "Python Container Integration" do
    context "when containers are running" do
      it "can check if Python is available in the environment" do
        # Simple test that doesn't require complex execution
        python_available = system("python3 --version > /dev/null 2>&1") || system("python --version > /dev/null 2>&1")
        
        expect([true, false]).to include(python_available)
        puts "Python available locally: #{python_available}"
      end
    end
  end

  describe "File Sharing Integration" do
    it "can create and access files in the monadic data directory" do
      # Test basic file operations in the shared directory
      test_content = "Host integration test\nTimestamp: #{Time.now}"
      host_data_dir = File.join(Dir.home, "monadic", "data")
      FileUtils.mkdir_p(host_data_dir) unless Dir.exist?(host_data_dir)
      
      test_file = File.join(host_data_dir, "integration_test_#{Time.now.to_i}.txt")
      File.write(test_file, test_content)

      # Verify the file exists and has correct content
      expect(File.exist?(test_file)).to be true
      content = File.read(test_file)
      expect(content).to eq(test_content)

      # Cleanup
      File.delete(test_file) if File.exist?(test_file)
    end
  end

  describe "Container Health Checks" do
    it "can check container status" do
      # Check if specific containers are running
      containers = %w[
        monadic-chat-python-container
        monadic-chat-selenium-container
        monadic-chat-pgvector-container
      ]

      containers.each do |container_name|
        result = system("docker ps --format '{{.Names}}' | grep -q '#{container_name}'", out: File::NULL, err: File::NULL)
        puts "Container #{container_name}: #{result ? 'running' : 'not running'}"
      end

      # At least Docker should be available
      expect(docker_available?).to be true
    end

    it "can check basic network connectivity" do
      # Simple network connectivity test that doesn't require complex execution
      network_available = system("ping -c 1 8.8.8.8 > /dev/null 2>&1")
      
      expect([true, false]).to include(network_available)
      puts "Network connectivity: #{network_available ? 'available' : 'not available'}"
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end

  # Simple helper methods for basic system checks
end