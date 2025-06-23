# frozen_string_literal: true

require_relative '../spec_helper'
require 'tempfile'
require 'fileutils'
require 'json'

RSpec.describe "Docker Container Integration", type: :integration do
  # Skip if not in a Docker environment
  before(:all) do
    @skip_docker_tests = !docker_available?
    skip "Docker tests require Docker environment" if @skip_docker_tests
  end

  let(:monadic_data_dir) { "/monadic/data" }
  let(:host_data_dir) { File.join(Dir.home, "monadic", "data") }

  describe "Python Container Integration" do
    context "code execution" do
      it "executes Python code and returns output" do
        python_code = <<~PYTHON
          print("Hello from Python container!")
          print(f"2 + 2 = {2 + 2}")
        PYTHON

        result = execute_in_container(
          code: python_code,
          command: "python",
          container: "python"
        )

        expect(result).to include("Hello from Python container!")
        expect(result).to include("2 + 2 = 4")
      end

      it "handles Python errors gracefully" do
        error_code = <<~PYTHON
          import sys
          print("Before error")
          raise ValueError("Test error")
          print("This should not appear")
        PYTHON

        result = execute_in_container(
          code: error_code,
          command: "python",
          container: "python"
        )

        expect(result).to include("Before error")
        expect(result).to include("ValueError: Test error")
        expect(result).not_to include("This should not appear")
      end

      it "can import and use installed packages" do
        numpy_code = <<~PYTHON
          import numpy as np
          arr = np.array([1, 2, 3, 4, 5])
          print(f"Array mean: {arr.mean()}")
          print(f"Array sum: {arr.sum()}")
        PYTHON

        result = execute_in_container(
          code: numpy_code,
          command: "python",
          container: "python"
        )

        expect(result).to include("Array mean: 3.0")
        expect(result).to include("Array sum: 15")
      end

      it "generates files in the shared directory" do
        file_gen_code = <<~PYTHON
          import json
          data = {"status": "success", "value": 42}
          with open("test_output.json", "w") as f:
              json.dump(data, f)
          print("File created: test_output.json")
        PYTHON

        result = execute_in_container(
          code: file_gen_code,
          command: "python",
          container: "python"
        )

        expect(result).to include("File created: test_output.json")
        
        # Check if file exists in host directory
        output_file = File.join(host_data_dir, "test_output.json")
        expect(File.exist?(output_file)).to be true
        
        # Verify content
        content = JSON.parse(File.read(output_file))
        expect(content["status"]).to eq("success")
        expect(content["value"]).to eq(42)
        
        # Cleanup
        File.delete(output_file) if File.exist?(output_file)
      end
    end

    context "command execution" do
      it "executes shell commands in Python container" do
        result = execute_command(
          command: "python --version",
          container: "python"
        )

        expect(result).to match(/Python 3\.\d+\.\d+/)
      end

      it "can access files in the shared directory" do
        # Create a test file
        test_file = File.join(host_data_dir, "test_file.txt")
        File.write(test_file, "Test content from host")

        result = execute_command(
          command: "cat test_file.txt",
          container: "python"
        )

        expect(result).to include("Test content from host")

        # Cleanup
        File.delete(test_file) if File.exist?(test_file)
      end
    end
  end

  describe "Selenium Container Integration" do
    it "can connect to Selenium service" do
      # Simple check that Selenium container is accessible
      result = check_container_health("selenium")
      expect(result).to be true
    end

    it "can take screenshots via Selenium" do
      skip "Selenium screenshot test requires full integration setup"
      
      # This would require setting up Selenium WebDriver
      # Example structure:
      # driver = create_selenium_driver
      # driver.navigate.to "https://example.com"
      # screenshot = driver.screenshot_as(:png)
      # expect(screenshot).not_to be_nil
    end
  end

  describe "PostgreSQL/pgvector Integration" do
    it "can connect to PostgreSQL service" do
      result = check_container_health("pgvector")
      expect(result).to be true
    end

    it "has pgvector extension available" do
      skip "PostgreSQL test requires database connection setup"
      
      # This would require setting up database connection
      # Example structure:
      # conn = PG.connect(host: "pgvector", dbname: "monadic")
      # result = conn.exec("SELECT * FROM pg_extension WHERE extname = 'vector'")
      # expect(result.ntuples).to be > 0
    end
  end

  describe "Cross-Container File Sharing" do
    it "shares files between Ruby and Python containers" do
      # Ruby creates file
      test_content = "Shared file test #{Time.now.to_i}"
      shared_file = File.join(host_data_dir, "shared_test.txt")
      File.write(shared_file, test_content)

      # Python reads file
      python_code = <<~PYTHON
        with open("shared_test.txt", "r") as f:
            content = f.read()
        print(f"Python read: {content}")
      PYTHON

      result = execute_in_container(
        code: python_code,
        command: "python",
        container: "python"
      )

      expect(result).to include("Python read: #{test_content}")

      # Cleanup
      File.delete(shared_file) if File.exist?(shared_file)
    end

    it "handles concurrent file access" do
      # Create multiple files
      files = []
      5.times do |i|
        file_path = File.join(host_data_dir, "concurrent_#{i}.txt")
        File.write(file_path, "Content #{i}")
        files << file_path
      end

      # Python reads all files
      python_code = <<~PYTHON
        import os
        files = [f for f in os.listdir('.') if f.startswith('concurrent_')]
        print(f"Found {len(files)} files")
        for f in sorted(files):
            with open(f, 'r') as file:
                print(f"{f}: {file.read()}")
      PYTHON

      result = execute_in_container(
        code: python_code,
        command: "python",
        container: "python"
      )

      expect(result).to include("Found 5 files")
      5.times do |i|
        expect(result).to include("concurrent_#{i}.txt: Content #{i}")
      end

      # Cleanup
      files.each { |f| File.delete(f) if File.exist?(f) }
    end
  end

  describe "Error Handling and Recovery" do
    it "handles container command failures gracefully" do
      result = execute_command(
        command: "nonexistent_command",
        container: "python"
      )

      expect(result).to include("not found") # Command not found error
    end

    it "handles file permission issues" do
      skip "Permission test may require specific setup"
      
      # This would test handling of permission-denied scenarios
      # Example: trying to write to a read-only directory
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end

  def execute_in_container(code:, command:, container:)
    # Create temporary file with code
    temp_file = Tempfile.new(["test", ".py"])
    temp_file.write(code)
    temp_file.close

    # Copy to container and execute
    container_name = "monadic-chat-#{container}-container"
    container_path = "/tmp/#{File.basename(temp_file.path)}"
    
    # Copy file to container
    system("docker cp #{temp_file.path} #{container_name}:#{container_path}")
    
    # Execute in container with working directory set to /monadic/data
    output = `docker exec -w /monadic/data #{container_name} #{command} #{container_path} 2>&1`
    
    # Cleanup
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