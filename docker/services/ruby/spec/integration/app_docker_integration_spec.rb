# frozen_string_literal: true

require_relative '../spec_helper'

# Define MonadicApp constants globally for SeleniumHelper
unless defined?(MonadicApp)
  module MonadicApp
    SHARED_VOL = "/monadic/data"
    LOCAL_SHARED_VOL = File.join(Dir.home, "monadic", "data")
  end
end

# Define IN_CONTAINER constant for SeleniumHelper if not already defined
unless defined?(IN_CONTAINER)
  IN_CONTAINER = false
end

# Test implementation module that provides MonadicApp-like behavior
module TestMonadicAppBehavior
  def settings
    @settings ||= {}
  end
  
  # Basic implementation of send_command for testing
  def send_command(command:, container:, success_with_output: nil)
    container_name = "monadic-chat-#{container}-container"
    container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{container_name}$'")
    
    if container_running
      # Use Docker container
      output = `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
      status = $?.success?
    else
      # Use local execution for Ruby container
      if container == "ruby"
        data_dir = File.join(Dir.home, "monadic", "data")
        Dir.chdir(data_dir) do
          output = `#{command} 2>&1`
          status = $?.success?
        end
      else
        # For other containers, return error if not running
        output = "Error: Container #{container_name} is not running"
        status = false
      end
    end
    
    # If block is provided (for SeleniumHelper compatibility), yield to it
    if block_given?
      status_obj = Object.new
      status_obj.define_singleton_method(:success?) { status }
      yield output, output, status_obj
    end
    
    message = success_with_output || "Command has been executed with the following output:\n"
    "#{message}#{output}"
  end
  
  # Basic implementation of send_code for testing
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
  
  # Wrapper methods that use send_command/send_code
  def run_code(code:, command: "python")
    send_code(code: code, command: command)
  end
  
  def run_bash_command(command:)
    send_command(command: command, container: "ruby")
  end
  
  def fetch_text_from_file(file:)
    send_command(command: "cat #{file}", container: "ruby")
  rescue => e
    "Error: #{e.message}"
  end
end

# Define ReadWriteHelper for the File Processing Tools tests
module ReadWriteHelper
  def fetch_text_from_file(file:)
    data_dir = File.join(Dir.home, "monadic", "data")
    file_path = File.join(data_dir, file)
    
    if File.exist?(file_path)
      File.read(file_path)
    else
      # Try to read from container
      container_name = "monadic-chat-ruby-container"
      output = `docker exec -w /monadic/data #{container_name} cat #{file} 2>&1`
      output
    end
  rescue => e
    "Error: #{e.message}"
  end
end

RSpec.describe "App Docker Integration", type: :integration do
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
  end

  describe "Code Interpreter Apps" do
    let(:app_class) do
      # Create a test app class that includes actual implementation
      Class.new do
        include TestMonadicAppBehavior
        
        def initialize
          @settings = {
            "model" => "gpt-4",
            "temperature" => 0.7
          }
        end
        
        attr_reader :settings
      end
    end
    
    let(:app) { app_class.new }

    it "executes Python code through run_code method" do
      result = app.run_code(
        code: "print('Test from Code Interpreter')\nprint(2 ** 10)",
        command: "python"
      )

      expect(result).to include("Test from Code Interpreter")
      expect(result).to include("1024")
    end

    it "handles matplotlib visualization" do
      matplotlib_code = <<~PYTHON
        import matplotlib.pyplot as plt
        import numpy as np
        
        x = np.linspace(0, 2 * np.pi, 100)
        y = np.sin(x)
        
        plt.figure(figsize=(8, 6))
        plt.plot(x, y)
        plt.title('Sine Wave')
        plt.xlabel('x')
        plt.ylabel('sin(x)')
        plt.grid(True)
        plt.savefig('sine_wave.png')
        print("Plot saved as sine_wave.png")
      PYTHON

      result = app.run_code(code: matplotlib_code, command: "python")
      
      expect(result).to include("Plot saved as sine_wave.png")
      expect(result).to include("File(s) generated: sine_wave.png")
      
      # Check if file exists
      output_file = File.join(Dir.home, "monadic", "data", "sine_wave.png")
      expect(File.exist?(output_file)).to be true
      
      # Cleanup
      File.delete(output_file) if File.exist?(output_file)
    end

    it "handles pandas data processing" do
      pandas_code = <<~PYTHON
        import pandas as pd
        import json
        
        # Create sample data
        data = {
            'name': ['Alice', 'Bob', 'Charlie'],
            'age': [25, 30, 35],
            'city': ['New York', 'London', 'Tokyo']
        }
        
        df = pd.DataFrame(data)
        print("DataFrame created:")
        print(df)
        print(f"\\nAverage age: {df['age'].mean()}")
        
        # Save to CSV
        df.to_csv('sample_data.csv', index=False)
        print("\\nData saved to sample_data.csv")
      PYTHON

      result = app.run_code(code: pandas_code, command: "python")
      
      expect(result).to include("DataFrame created:")
      expect(result).to include("Alice")
      expect(result).to include("Average age: 30.0")
      expect(result).to include("Data saved to sample_data.csv")
      
      # Verify CSV file
      csv_file = File.join(Dir.home, "monadic", "data", "sample_data.csv")
      if File.exist?(csv_file)
        content = File.read(csv_file)
        expect(content).to include("name,age,city")
        expect(content).to include("Alice,25,New York")
        File.delete(csv_file)
      end
    end
  end

  describe "File Processing Tools" do
    let(:app_class) do
      Class.new do
        include TestMonadicAppBehavior
        include ReadWriteHelper
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:app) { app_class.new }

    it "fetches text from various file types" do
      # Create test files
      data_dir = File.join(Dir.home, "monadic", "data")
      
      # Plain text file
      text_file = File.join(data_dir, "test.txt")
      File.write(text_file, "This is a test text file.")
      
      result = app.fetch_text_from_file(file: "test.txt")
      expect(result).to include("This is a test text file.")
      
      # Cleanup
      File.delete(text_file) if File.exist?(text_file)
    end

    it "handles file not found errors" do
      result = app.fetch_text_from_file(file: "nonexistent.txt")
      expect(result).to match(/Error|No such file or directory/) # Should include error message
    end
  end

  describe "Web Scraping with Selenium" do
    let(:app_class) do
      Class.new do
        include TestMonadicAppBehavior
        include SeleniumHelper if defined?(SeleniumHelper)
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:app) { app_class.new }

    it "checks Selenium container availability" do
      # Test basic Selenium container connectivity
      selenium_running = system("docker ps | grep selenium > /dev/null 2>&1")
      expect(selenium_running).to be true
      
      # Test webpage_fetcher.py script availability in Python container
      test_command = "python -c \"import sys; print('Python available')\""
      python_result = `docker exec monadic-chat-python-container #{test_command} 2>&1`
      expect(python_result).to include("Python available")
      
      # Test that webpage_fetcher.py exists and can show help
      help_command = "webpage_fetcher.py --help"
      help_result = `docker exec monadic-chat-python-container #{help_command} 2>&1`
      expect(help_result).to include("usage:")
      
      # This verifies the Selenium infrastructure is available
      # Full functional testing would require more complex setup
    end
  end

  describe "Bash Command Execution" do
    let(:app_class) do
      Class.new do
        include TestMonadicAppBehavior
        include BashCommandHelper if defined?(BashCommandHelper)
        
        def initialize
          @settings = {}
        end
        
        attr_reader :settings
      end
    end
    
    let(:app) { app_class.new }

    it "executes bash commands in containers" do
      # Test basic command execution
      result = app.run_bash_command(command: "echo 'Hello from container'")
      expect(result).to include("Hello from container")
      
      # Test working directory
      result = app.run_bash_command(command: "pwd")
      expect(result).to include("/monadic/data")
    end

    it "handles command failures appropriately" do
      # The 'false' command returns exit code 1 but no output
      result = app.run_bash_command(command: "false || echo 'Command failed'")
      expect(result).to include("Command failed") # Should handle non-zero exit codes
    end
  end

  describe "Multi-Container Workflow" do
    it "completes a data processing workflow across containers" do
      app_class = Class.new do
        include TestMonadicAppBehavior
        def initialize
          @settings = {}
        end
        attr_reader :settings
      end
      
      app = app_class.new
      
      # Step 1: Generate data with Python
      python_code = <<~PYTHON
        import json
        import random
        
        data = [{"id": i, "value": random.randint(1, 100)} for i in range(10)]
        
        with open("data.json", "w") as f:
            json.dump(data, f)
        
        print(f"Generated {len(data)} data points")
      PYTHON
      
      result1 = app.run_code(code: python_code, command: "python")
      expect(result1).to include("Generated 10 data points")
      
      # Step 2: Process data with another Python script
      process_code = <<~PYTHON
        import json
        
        with open("data.json", "r") as f:
            data = json.load(f)
        
        total = sum(item["value"] for item in data)
        average = total / len(data)
        
        result = {
            "total": total,
            "average": average,
            "count": len(data)
        }
        
        with open("result.json", "w") as f:
            json.dump(result, f)
        
        print(f"Processed {len(data)} items")
        print(f"Total: {total}, Average: {average:.2f}")
      PYTHON
      
      result2 = app.run_code(code: process_code, command: "python")
      expect(result2).to include("Processed 10 items")
      expect(result2).to match(/Average: \d+\.\d+/)
      
      # Cleanup
      data_dir = File.join(Dir.home, "monadic", "data")
      ["data.json", "result.json"].each do |file|
        file_path = File.join(data_dir, file)
        File.delete(file_path) if File.exist?(file_path)
      end
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end
end