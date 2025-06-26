# frozen_string_literal: true

require_relative '../spec_helper'

# Define test module to include helpers
module TestMonadicAppBehavior
  # Basic app functionality needed for tests
  def settings
    @settings ||= {}
  end
end

# Define helper modules for testing
module PythonContainerHelper
  def run_code(code:, command: "python")
    send_code(code: code, command: command)
  end
  
  def run_script(script:, command: "python")
    send_command(command: "#{command} #{script}", container: "python")
  end
  
  def send_code(code:, command:, extension: "py", success: nil)
    require 'tempfile'
    temp_file = Tempfile.new(["code", ".#{extension}"])
    temp_file.write(code)
    temp_file.close
    
    container_name = "monadic-chat-python-container"
    container_path = "/tmp/#{File.basename(temp_file.path)}"
    
    # Get initial file list
    initial_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    
    # Copy and execute
    system("docker cp #{temp_file.path} #{container_name}:#{container_path}")
    output = `docker exec -w /monadic/data #{container_name} #{command} #{container_path} 2>&1`
    
    # Check for new files
    final_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    new_files = final_files - initial_files
    
    # Cleanup
    temp_file.unlink
    system("docker exec #{container_name} rm -f #{container_path}")
    
    success_msg = success || "The code has been executed successfully"
    if new_files.any?
      "#{success_msg}; File(s) generated: #{new_files.join(', ')}; Output: #{output}"
    else
      "#{success_msg}; Output: #{output}"
    end
  end
  
  def send_command(command:, container:, success_with_output: nil)
    container_name = "monadic-chat-#{container}-container"
    output = `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
    
    message = success_with_output || "Command has been executed with the following output:\n"
    "#{message}#{output}"
  end
end

module BashCommandHelper
  def run_bash_command(command:)
    send_command(command: command, container: "ruby")
  end
  
  def send_command(command:, container:, success_with_output: nil)
    # Check if Ruby container is running
    container_name = "monadic-chat-#{container}-container"
    container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{container_name}$'")
    
    if container_running
      # Use Docker container
      output = `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
    else
      # Use local execution
      data_dir = File.join(Dir.home, "monadic", "data")
      Dir.chdir(data_dir) do
        output = `#{command} 2>&1`
      end
    end
    
    message = success_with_output || "Command has been executed with the following output:\n"
    "#{message}#{output}"
  end
end

module ReadWriteHelper
  def fetch_text_from_file(file:)
    data_dir = File.join(Dir.home, "monadic", "data")
    file_path = File.join(data_dir, file)
    
    if File.exist?(file_path)
      File.read(file_path)
    else
      # Try to read from container
      send_command(command: "cat #{file}", container: "ruby")
    end
  rescue => e
    "Error: #{e.message}"
  end
  
  def send_command(command:, container:, success_with_output: nil)
    # Check if container is running
    container_name = "monadic-chat-#{container}-container"
    container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{container_name}$'")
    
    if container_running
      # Use Docker container
      output = `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
    else
      # Use local execution
      data_dir = File.join(Dir.home, "monadic", "data")
      Dir.chdir(data_dir) do
        output = `#{command} 2>&1`
      end
    end
    
    message = success_with_output || ""
    "#{message}#{output}"
  end
end

RSpec.describe "Container Helpers Integration", type: :integration do
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
  end

  describe "PythonContainerHelper" do
    let(:test_class) do
      Class.new do
        include TestMonadicAppBehavior
        include PythonContainerHelper
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:helper) { test_class.new }

    describe "#run_code" do
      it "executes simple Python code" do
        result = helper.run_code(
          code: "print('Hello World')\nprint(42)",
          command: "python"
        )
        
        expect(result).to include("Hello World")
        expect(result).to include("42")
        expect(result).to include("The code has been executed successfully")
      end

      it "handles Python imports" do
        code = <<~PYTHON
          import sys
          import os
          print(f"Python version: {sys.version.split()[0]}")
          print(f"Working directory: {os.getcwd()}")
        PYTHON
        
        result = helper.run_code(code: code, command: "python")
        
        expect(result).to include("Python version: 3.")
        expect(result).to include("Working directory: /monadic/data")
      end

      it "detects generated files" do
        code = <<~PYTHON
          with open("test_output.txt", "w") as f:
              f.write("Test content")
          print("File written")
        PYTHON
        
        result = helper.run_code(code: code, command: "python")
        
        expect(result).to include("File written")
        expect(result).to include("File(s) generated: test_output.txt")
        
        # Cleanup
        file_path = File.join(Dir.home, "monadic", "data", "test_output.txt")
        File.delete(file_path) if File.exist?(file_path)
      end

      it "handles errors gracefully" do
        error_code = <<~PYTHON
          print("Before error")
          undefined_variable
          print("After error")
        PYTHON
        
        result = helper.run_code(code: error_code, command: "python")
        
        expect(result).to include("Before error")
        expect(result).to include("NameError")
        expect(result).not_to include("After error")
      end

      it "supports data science libraries" do
        numpy_code = <<~PYTHON
          import numpy as np
          arr = np.array([1, 2, 3, 4, 5])
          print(f"Mean: {arr.mean()}")
          print(f"Std: {arr.std():.2f}")
        PYTHON
        
        result = helper.run_code(code: numpy_code, command: "python")
        
        expect(result).to include("Mean: 3.0")
        expect(result).to include("Std: 1.41")
      end
    end

    describe "#run_script" do
      it "executes Python scripts from files" do
        # Create a test script
        script_path = File.join(Dir.home, "monadic", "data", "test_script.py")
        script_content = <<~PYTHON
          def greet(name):
              return f"Hello, {name}!"
          
          if __name__ == "__main__":
              print(greet("Monadic Chat"))
              print("Script executed successfully")
        PYTHON
        
        File.write(script_path, script_content)
        
        result = helper.run_script(
          script: "test_script.py",
          command: "python"
        )
        
        expect(result).to include("Hello, Monadic Chat!")
        expect(result).to include("Script executed successfully")
        
        # Cleanup
        File.delete(script_path) if File.exist?(script_path)
      end
    end
  end

  describe "BashCommandHelper" do
    let(:test_class) do
      Class.new do
        include TestMonadicAppBehavior
        include BashCommandHelper
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:helper) { test_class.new }

    describe "#run_bash_command" do
      it "executes basic bash commands" do
        result = helper.run_bash_command(command: "echo 'Test output'")
        expect(result).to include("Test output")
      end

      it "executes commands in the correct working directory" do
        result = helper.run_bash_command(command: "pwd")
        expect(result).to include("/monadic/data")
      end

      it "can list files in the data directory" do
        # Create a test file
        test_file = File.join(Dir.home, "monadic", "data", "test_file.txt")
        File.write(test_file, "test")
        
        result = helper.run_bash_command(command: "ls -la test_file.txt")
        expect(result).to include("test_file.txt")
        
        # Cleanup
        File.delete(test_file) if File.exist?(test_file)
      end

      it "handles piped commands" do
        result = helper.run_bash_command(command: "echo 'line1\nline2\nline3' | wc -l")
        expect(result.strip).to match(/3/)
      end

      it "handles command failures" do
        result = helper.run_bash_command(command: "ls /nonexistent/directory")
        expect(result).to include("No such file or directory")
      end
    end
  end

  describe "ReadWriteHelper" do
    let(:test_class) do
      Class.new do
        include TestMonadicAppBehavior
        include ReadWriteHelper
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:helper) { test_class.new }

    describe "file operations" do
      it "fetches text from files" do
        # Create test file
        test_content = "This is test content\nWith multiple lines"
        test_file = File.join(Dir.home, "monadic", "data", "read_test.txt")
        File.write(test_file, test_content)
        
        result = helper.fetch_text_from_file(file: "read_test.txt")
        expect(result).to include(test_content)
        
        # Cleanup
        File.delete(test_file) if File.exist?(test_file)
      end

      it "handles markdown files" do
        md_content = "# Test Markdown\n\n- Item 1\n- Item 2\n\n**Bold text**"
        md_file = File.join(Dir.home, "monadic", "data", "test.md")
        File.write(md_file, md_content)
        
        result = helper.fetch_text_from_file(file: "test.md")
        expect(result).to include("# Test Markdown")
        expect(result).to include("**Bold text**")
        
        # Cleanup
        File.delete(md_file) if File.exist?(md_file)
      end

      it "handles missing files gracefully" do
        result = helper.fetch_text_from_file(file: "nonexistent_file.txt")
        expect(result).to match(/Error|No such file or directory/)
      end
    end
  end

  describe "Cross-Helper Integration" do
    let(:test_class) do
      Class.new do
        include TestMonadicAppBehavior
        include PythonContainerHelper
        include BashCommandHelper
        include ReadWriteHelper
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:app) { test_class.new }

    it "combines Python code execution with file operations" do
      # Python creates a file
      python_code = <<~PYTHON
        import json
        data = {"status": "success", "items": [1, 2, 3]}
        with open("output.json", "w") as f:
            json.dump(data, f)
        print("JSON file created")
      PYTHON
      
      result = app.run_code(code: python_code, command: "python")
      expect(result).to include("JSON file created")
      
      # Read the file back
      content = app.fetch_text_from_file(file: "output.json")
      expect(content).to include('"status": "success"')
      
      # Use bash to verify
      bash_result = app.run_bash_command(command: "cat output.json | jq '.status'")
      expect(bash_result).to include("success")
      
      # Cleanup
      File.delete(File.join(Dir.home, "monadic", "data", "output.json")) rescue nil
    end

    it "processes data through multiple steps" do
      # Step 1: Create data with Python (to ensure it's in the shared directory)
      create_data_code = <<~PYTHON
        with open("numbers.txt", "w") as f:
            for i in range(1, 11):
                f.write(f"{i}\\n")
        print("Numbers file created")
      PYTHON
      
      result = app.run_code(code: create_data_code, command: "python")
      expect(result).to include("Numbers file created")
      
      # Step 2: Process with Python
      python_code = <<~PYTHON
        with open("numbers.txt", "r") as f:
            numbers = [int(line.strip()) for line in f]
        
        sum_nums = sum(numbers)
        avg_nums = sum_nums / len(numbers)
        
        with open("stats.txt", "w") as f:
            f.write(f"Sum: {sum_nums}\\n")
            f.write(f"Average: {avg_nums}\\n")
            f.write(f"Count: {len(numbers)}\\n")
        
        print(f"Processed {len(numbers)} numbers")
      PYTHON
      
      result = app.run_code(code: python_code, command: "python")
      expect(result).to include("Processed 10 numbers")
      
      # Step 3: Read results
      stats = app.fetch_text_from_file(file: "stats.txt")
      expect(stats).to include("Sum: 55")
      expect(stats).to include("Average: 5.5")
      
      # Cleanup
      data_dir = File.join(Dir.home, "monadic", "data")
      ["numbers.txt", "stats.txt"].each do |file|
        File.delete(File.join(data_dir, file)) rescue nil
      end
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end
end