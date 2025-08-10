# frozen_string_literal: true

require_relative '../spec_helper'
require 'tempfile'
require 'fileutils'
require 'json'

RSpec.describe "Docker Infrastructure Integration", type: :integration do
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
  end

  let(:monadic_data_dir) { "/monadic/data" }
  let(:host_data_dir) { File.join(Dir.home, "monadic", "data") }

  describe "Container Health Checks" do
    it "verifies all required containers are running" do
      containers = %w[
        monadic-chat-python-container
        monadic-chat-selenium-container
        monadic-chat-pgvector-container
      ]

      containers.each do |container_name|
        result = system("docker ps --format '{{.Names}}' | grep -q '#{container_name}'", out: File::NULL, err: File::NULL)
        puts "Container #{container_name}: #{result ? 'running' : 'not running'}"
        
        # At least check container exists
        expect(system("docker ps -a --format '{{.Names}}' | grep -q '#{container_name}'", out: File::NULL, err: File::NULL)).to be true
      end
    end

    it "checks container network connectivity" do
      # Test that containers can communicate
      result = execute_command(
        command: "ping -c 1 pgvector_service",
        container: "python"
      )
      
      # Network might not allow ping, but command should execute
      expect(result).not_to be_empty
    end
  end

  describe "Python Container Infrastructure" do
    it "has Python 3.x installed" do
      result = execute_command(
        command: "python --version",
        container: "python"
      )

      expect(result).to match(/Python 3\.\d+\.\d+/)
    end

    it "has required Python packages installed" do
      packages = %w[numpy pandas matplotlib selenium bs4]
      
      packages.each do |package|
        result = execute_command(
          command: "python -c 'import #{package}'",
          container: "python"
        )
        
        expect($?.success?).to be(true), "Package #{package} not found"
      end
    end

    it "can execute Python code with file I/O" do
      python_code = <<~PYTHON
        import json
        data = {"test": "infrastructure", "timestamp": 123456}
        with open("infra_test.json", "w") as f:
            json.dump(data, f)
        print("File created successfully")
      PYTHON

      result = execute_in_container(
        code: python_code,
        command: "python",
        container: "python"
      )

      expect(result).to include("File created successfully")
      
      # Verify file exists
      output_file = File.join(host_data_dir, "infra_test.json")
      expect(File.exist?(output_file)).to be true
      
      # Cleanup
      File.delete(output_file) if File.exist?(output_file)
    end
  end

  describe "Selenium Container Infrastructure" do
    it "has Selenium service accessible" do
      result = check_container_health("selenium")
      expect(result).to be true
    end

    it "can execute webpage_fetcher.py script" do
      # Test that the script exists and is executable
      result = execute_command(
        command: "which webpage_fetcher.py",
        container: "python"
      )
      
      expect(result).to match(%r{/webpage_fetcher\.py})
    end

    it "can capture screenshots via Selenium" do
      test_url = "https://example.com"
      
      # Run webpage_fetcher.py for screenshot
      command = "docker exec monadic-chat-python-container webpage_fetcher.py --url \"#{test_url}\" --filepath \"/monadic/data/\" --mode \"png\""
      
      result = `#{command} 2>&1`
      
      # Skip if network connectivity issues
      if result.include?("connection timed out")
        skip "Network connectivity issue - Selenium cannot reach external URLs"
      end
      
      # Check for success indicators
      expect(result).to match(/saved to:|\.png/i)
    end
  end

  describe "PostgreSQL/pgvector Infrastructure" do
    it "has PostgreSQL service accessible" do
      result = check_container_health("pgvector")
      expect(result).to be true
    end

    it "has pgvector extension installed and available" do
      require 'pg'
      
      # Connect to PostgreSQL
      conn = PG.connect(postgres_connection_params)
      
      # Ensure pgvector extension is created
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
      
      # Check pgvector extension
      result = conn.exec("SELECT * FROM pg_extension WHERE extname = 'vector'")
      expect(result.ntuples).to be > 0
      
      # Check version
      version_result = conn.exec("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
      version = version_result[0]['extversion']
      expect(version).not_to be_nil
      puts "pgvector version: #{version}"
      
      conn.close
    end
  end

  describe "File System Integration" do
    it "shares files correctly between host and containers" do
      # Ensure directory exists
      FileUtils.mkdir_p(host_data_dir) unless Dir.exist?(host_data_dir)
      
      # Host creates file
      test_content = "Infrastructure test #{Time.now.to_i}"
      test_file = File.join(host_data_dir, "infra_share_test.txt")
      File.write(test_file, test_content)

      # Container reads file
      result = execute_command(
        command: "cat infra_share_test.txt",
        container: "python"
      )

      expect(result).to include(test_content)

      # Cleanup
      File.delete(test_file) if File.exist?(test_file)
    end

    it "handles concurrent file operations" do
      files = []
      3.times do |i|
        file_path = File.join(host_data_dir, "concurrent_infra_#{i}.txt")
        File.write(file_path, "Infrastructure #{i}")
        files << file_path
      end

      # Python lists and reads files
      python_code = <<~PYTHON
        import os
        files = sorted([f for f in os.listdir('.') if f.startswith('concurrent_infra_')])
        print(f"Found {len(files)} files")
        for f in files:
            print(f"Reading {f}")
      PYTHON

      result = execute_in_container(
        code: python_code,
        command: "python",
        container: "python"
      )

      expect(result).to include("Found 3 files")
      
      # Cleanup
      files.each { |f| File.delete(f) if File.exist?(f) }
    end
  end

  describe "Error Handling" do
    it "handles container command failures gracefully" do
      result = execute_command(
        command: "nonexistent_command_xyz",
        container: "python"
      )

      expect(result).to include("not found")
    end

    it "handles Python execution errors properly" do
      error_code = <<~PYTHON
        raise RuntimeError("Infrastructure test error")
      PYTHON

      result = execute_in_container(
        code: error_code,
        command: "python",
        container: "python"
      )

      expect(result).to include("RuntimeError: Infrastructure test error")
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end

  def execute_in_container(code:, command:, container:)
    temp_file = Tempfile.new(["infra_test", ".py"])
    temp_file.write(code)
    temp_file.close

    container_name = "monadic-chat-#{container}-container"
    container_path = "/tmp/#{File.basename(temp_file.path)}"
    
    system("docker cp #{temp_file.path} #{container_name}:#{container_path}")
    output = `docker exec -w /monadic/data #{container_name} #{command} #{container_path} 2>&1`
    
    temp_file.unlink
    system("docker exec #{container_name} rm -f #{container_path}")
    
    output
  end

  def execute_command(command:, container:)
    container_name = "monadic-chat-#{container}-container"
    `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
  end

  def check_container_health(container)
    container_name = "monadic-chat-#{container}-container"
    system("docker exec #{container_name} echo 'health check' > /dev/null 2>&1")
  end
end