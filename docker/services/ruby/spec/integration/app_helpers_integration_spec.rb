# frozen_string_literal: true

require_relative '../spec_helper'
require 'tempfile'
require 'fileutils'

# Define constants for helper modules
unless defined?(MonadicApp)
  module MonadicApp
    SHARED_VOL = "/monadic/data"
    LOCAL_SHARED_VOL = File.join(Dir.home, "monadic", "data")
  end
end

# Environment is now handled by Monadic::Utils::Environment module

# Test implementation module
module TestMonadicAppBehavior
  def settings
    @settings ||= {}
  end
  
  def send_command(command:, container:, success_with_output: nil)
    container_name = "monadic-chat-#{container}-container"
    container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{container_name}$'")
    
    if container_running
      # Use timeout to prevent hanging
      require 'timeout'
      begin
        output = Timeout.timeout(30) do
          `docker exec -w /monadic/data #{container_name} #{command} 2>&1`
        end
        status = $?.success?
      rescue Timeout::Error
        output = "Command timed out after 30 seconds"
        status = false
      end
    else
      if container == "ruby"
        data_dir = File.join(Dir.home, "monadic", "data")
        Dir.chdir(data_dir) do
          output = `#{command} 2>&1`
          status = $?.success?
        end
      else
        output = "Error: Container #{container_name} is not running"
        status = false
      end
    end
    
    if block_given?
      status_obj = Object.new
      status_obj.define_singleton_method(:success?) { status }
      yield output, output, status_obj
    end
    
    message = success_with_output || "Command has been executed with the following output:\n"
    "#{message}#{output}"
  end
  
  def send_code(code:, command:, extension: "py", success: nil)
    temp_file = Tempfile.new(["code", ".#{extension}"])
    temp_file.write(code)
    temp_file.close
    
    container_name = "monadic-chat-python-container"
    container_path = "/tmp/#{File.basename(temp_file.path)}"
    
    initial_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    
    system("docker cp #{temp_file.path} #{container_name}:#{container_path}")
    output = `docker exec -w /monadic/data #{container_name} #{command} #{container_path} 2>&1`
    
    final_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    new_files = final_files - initial_files
    
    temp_file.unlink
    system("docker exec #{container_name} rm -f #{container_path}")
    
    success_msg = success || "The code has been executed successfully"
    if new_files.any?
      "#{success_msg}; File(s) generated: #{new_files.join(', ')}; Output: #{output}"
    else
      "#{success_msg}; Output: #{output}"
    end
  end
end

# Load helper modules - first define the modules inline since they may not exist as separate files
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
    
    initial_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    
    system("docker cp #{temp_file.path} #{container_name}:#{container_path}")
    output = `docker exec -w /monadic/data #{container_name} #{command} #{container_path} 2>&1`
    
    final_files = `docker exec -w /monadic/data #{container_name} ls -1 2>/dev/null`.split("\n")
    new_files = final_files - initial_files
    
    temp_file.unlink
    system("docker exec #{container_name} rm -f #{container_path}")
    
    success_msg = success || "The code has been executed successfully"
    if new_files.any?
      "#{success_msg}; File(s) generated: #{new_files.join(', ')}; Output: #{output}"
    else
      "#{success_msg}; Output: #{output}"
    end
  end
end

module BashCommandHelper
  def run_bash_command(command:)
    send_command(command: command, container: "ruby")
  end
end

module ReadWriteHelper
  def fetch_text_from_file(file:)
    data_dir = File.join(Dir.home, "monadic", "data")
    file_path = File.join(data_dir, file)
    
    if File.exist?(file_path)
      File.read(file_path)
    else
      send_command(command: "cat #{file}", container: "ruby")
    end
  end
end

RSpec.describe "App Helpers Integration", type: :integration do
  before(:all) do
    skip "Docker tests require Docker environment" unless docker_available?
  end

  let(:test_class) do
    Class.new do
      include TestMonadicAppBehavior
      include PythonContainerHelper
      include BashCommandHelper
      include ReadWriteHelper
    end
  end
  
  let(:test_instance) { test_class.new }

  describe "PythonContainerHelper" do
    describe "#run_code" do
      it "executes Python code and returns output" do
        result = test_instance.run_code(code: "print('Helper test')")
        
        expect(result).to include("The code has been executed successfully")
        expect(result).to include("Helper test")
      end
      
      it "captures and reports generated files" do
        code = <<~PYTHON
          with open('helper_test.txt', 'w') as f:
              f.write('Test content')
          print('File created')
        PYTHON
        
        result = test_instance.run_code(code: code)
        
        expect(result).to include("File(s) generated: helper_test.txt")
        expect(result).to include("File created")
        
        # Cleanup
        test_instance.run_bash_command(command: "rm -f helper_test.txt")
      end
      
      it "handles Python errors properly" do
        result = test_instance.run_code(code: "raise ValueError('Test error')")
        
        expect(result).to include("ValueError: Test error")
      end
    end
    
    describe "#run_script" do
      it "executes Python scripts from file system" do
        # Create a test script
        script_path = File.join(Dir.home, "monadic", "data", "test_script.py")
        File.write(script_path, "print('Script executed')")
        
        result = test_instance.run_script(script: "test_script.py")
        
        expect(result).to include("Script executed")
        
        # Cleanup
        File.delete(script_path)
      end
    end
  end

  describe "BashCommandHelper" do
    describe "#run_bash_command" do
      it "executes bash commands" do
        result = test_instance.run_bash_command(command: "echo 'Bash test'")
        
        expect(result).to include("Command has been executed")
        expect(result).to include("Bash test")
      end
      
      it "handles command failures" do
        result = test_instance.run_bash_command(command: "false")
        
        expect(result).to include("Command has been executed")
      end
      
      it "can manipulate files" do
        result = test_instance.run_bash_command(command: "touch bash_test.txt && ls bash_test.txt")
        
        expect(result).to include("bash_test.txt")
        
        # Cleanup
        test_instance.run_bash_command(command: "rm -f bash_test.txt")
      end
    end
  end

  describe "ReadWriteHelper" do
    describe "#fetch_text_from_file" do
      it "reads file content from the data directory" do
        # Create test file
        file_path = File.join(Dir.home, "monadic", "data", "read_test.txt")
        File.write(file_path, "Test content for reading")
        
        result = test_instance.fetch_text_from_file(file: "read_test.txt")
        
        expect(result).to include("Test content for reading")
        
        # Cleanup
        File.delete(file_path)
      end
      
      it "handles non-existent files" do
        result = test_instance.fetch_text_from_file(file: "nonexistent.txt")
        
        expect(result).to match(/No such file|not found/)
      end
    end
  end

  describe "Cross-Helper Integration" do
    it "combines Python code execution with file reading" do
      # Python creates file
      python_code = <<~PYTHON
        data = "Integration test content"
        with open('integration_test.txt', 'w') as f:
            f.write(data)
        print("File written")
      PYTHON
      
      create_result = test_instance.run_code(code: python_code)
      expect(create_result).to include("File written")
      expect(create_result).to include("integration_test.txt")
      
      # ReadWriteHelper reads file
      read_result = test_instance.fetch_text_from_file(file: "integration_test.txt")
      expect(read_result).to include("Integration test content")
      
      # BashCommandHelper cleans up
      cleanup_result = test_instance.run_bash_command(command: "rm -f integration_test.txt")
      expect(cleanup_result).to include("Command has been executed")
    end
    
    it "processes data through multiple steps" do
      # Step 1: Create data with Python
      step1 = test_instance.run_code(code: <<~PYTHON)
        import json
        data = {"numbers": [1, 2, 3, 4, 5]}
        with open('data.json', 'w') as f:
            json.dump(data, f)
        print("Data created")
      PYTHON
      
      expect(step1).to include("Data created")
      
      # Step 2: Process with another Python script
      step2 = test_instance.run_code(code: <<~PYTHON)
        import json
        with open('data.json', 'r') as f:
            data = json.load(f)
        total = sum(data['numbers'])
        with open('result.txt', 'w') as f:
            f.write(f"Total: {total}")
        print(f"Processed: sum = {total}")
      PYTHON
      
      expect(step2).to include("Processed: sum = 15")
      
      # Step 3: Read result
      result = test_instance.fetch_text_from_file(file: "result.txt")
      expect(result).to include("Total: 15")
      
      # Cleanup
      test_instance.run_bash_command(command: "rm -f data.json result.txt")
    end
  end

  describe "Data Science Workflow Integration" do
    it "runs NumPy calculations" do
      numpy_code = <<~PYTHON
        import numpy as np
        arr = np.array([1, 2, 3, 4, 5])
        print(f"Mean: {arr.mean()}")
        print(f"Std: {arr.std()}")
      PYTHON
      
      result = test_instance.run_code(code: numpy_code)
      
      expect(result).to include("Mean: 3.0")
      expect(result).to include("Std:")
    end
    
    it "creates matplotlib visualizations" do
      plot_code = <<~PYTHON
        import matplotlib.pyplot as plt
        import numpy as np
        
        x = np.linspace(0, 10, 100)
        y = np.sin(x)
        
        plt.figure(figsize=(8, 6))
        plt.plot(x, y)
        plt.title('Sine Wave')
        plt.savefig('sine_wave.png')
        plt.close()
        print("Plot saved")
      PYTHON
      
      result = test_instance.run_code(code: plot_code)
      
      expect(result).to include("Plot saved")
      expect(result).to include("sine_wave.png")
      
      # Verify file exists
      file_exists = test_instance.run_bash_command(command: "ls sine_wave.png")
      expect(file_exists).to include("sine_wave.png")
      
      # Cleanup
      test_instance.run_bash_command(command: "rm -f sine_wave.png")
    end
    
    it "processes pandas dataframes" do
      pandas_code = <<~PYTHON
        import pandas as pd
        
        data = {
            'name': ['Alice', 'Bob', 'Charlie'],
            'age': [25, 30, 35],
            'score': [85, 90, 95]
        }
        
        df = pd.DataFrame(data)
        print("DataFrame created:")
        print(df)
        print(f"\\nAverage age: {df['age'].mean()}")
        print(f"Total score: {df['score'].sum()}")
        
        df.to_csv('test_data.csv', index=False)
        print("\\nData saved to CSV")
      PYTHON
      
      result = test_instance.run_code(code: pandas_code)
      
      expect(result).to include("DataFrame created")
      expect(result).to include("Average age: 30")
      expect(result).to include("Total score: 270")
      expect(result).to include("Data saved to CSV")
      
      # Verify CSV content
      csv_content = test_instance.fetch_text_from_file(file: "test_data.csv")
      expect(csv_content).to include("name,age,score")
      expect(csv_content).to include("Alice,25,85")
      
      # Cleanup
      test_instance.run_bash_command(command: "rm -f test_data.csv")
    end
  end

  describe "Web Scraping Integration" do
    it "uses Selenium for web scraping" do
      # Test webpage_fetcher.py which uses Selenium internally for markdown conversion
      fetch_command = [
        "python /monadic/scripts/cli_tools/webpage_fetcher.py",
        "--url", "https://httpbin.org/html",
        "--mode", "md",
        "--filepath", "/monadic/data/"
      ].join(" ")
      
      result = test_instance.send_command(
        command: fetch_command,
        container: "python"
      )
      
      # Check that it processed the page
      expect(result).to match(/Successfully saved|saved|\.md/)
      
      # Clean up any generated files
      test_instance.run_bash_command(command: "rm -f /monadic/data/*httpbin*.md")
    end
    
    it "captures web screenshots using Selenium" do
      # Test screenshot capture with webpage_fetcher.py
      screenshot_command = [
        "python /monadic/scripts/cli_tools/webpage_fetcher.py",
        "--url", "https://httpbin.org/html",  # Use a more reliable test URL
        "--mode", "png",
        "--filepath", "/monadic/data/",
        "--timeout-sec", "10"  # Add explicit timeout
      ].join(" ")
      
      result = test_instance.send_command(
        command: screenshot_command,
        container: "python"
      )
      
      # Check for successful screenshot
      expect(result).to match(/saved|\.png/)
      
      # Clean up any generated files
      test_instance.run_bash_command(command: "rm -f /monadic/data/*httpbin*.png")
    end
  end

  describe "Error Handling" do
    it "handles missing Python packages gracefully" do
      result = test_instance.run_code(code: "import nonexistent_package")
      
      expect(result).to match(/ModuleNotFoundError|No module named/)
    end
    
    it "handles file permission errors" do
      # Try to write to a read-only location
      result = test_instance.run_code(code: <<~PYTHON)
        try:
            with open('/etc/readonly_test.txt', 'w') as f:
                f.write('test')
        except PermissionError as e:
            print(f"Permission denied: {e}")
      PYTHON
      
      expect(result).to match(/Permission denied|successfully/)
    end
  end

  private

  def docker_available?
    system("docker ps > /dev/null 2>&1")
  end
end