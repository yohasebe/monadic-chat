# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/monadic/adapters/read_write_helper'

RSpec.describe "Code Interpreter Real Integration", type: :integration do
  before(:all) do
    skip "Real integration tests temporarily disabled - require full app environment with send_command method"
  end

  describe "File Reading Integration" do
    let(:test_content) { "# Test Python Script\nprint('Integration test working')\nresult = 2 + 2\nprint(f'Result: {result}')" }
    let(:test_filename) { "integration_test_#{Time.now.to_i}.py" }

    before(:each) do
      create_test_file(test_filename, test_content)
    end

    after(:each) do
      cleanup_test_files
    end

    context "when using real helper methods" do
      it "reads Python files correctly" do
        if defined?(MonadicHelper)
          helper_instance = create_helper_instance
          
          if helper_instance.respond_to?(:fetch_text_from_file)
            result = helper_instance.fetch_text_from_file(file: test_filename)
            
            expect(result).to include("Test Python Script")
            expect(result).to include("Integration test working")
            expect(result).not_to include("Error:")
          else
            skip "fetch_text_from_file method not available"
          end
        else
          skip "MonadicHelper not loaded"
        end
      end

      it "handles non-existent files gracefully" do
        if defined?(MonadicHelper)
          helper_instance = create_helper_instance
          
          if helper_instance.respond_to?(:fetch_text_from_file)
            result = helper_instance.fetch_text_from_file(file: "nonexistent_#{Time.now.to_i}.txt")
            
            # Should return an error message, not crash
            expect(result).to be_a(String)
            expect(result.downcase).to include("error").or include("not found").or include("no such file")
          else
            skip "fetch_text_from_file method not available"
          end
        else
          skip "MonadicHelper not loaded"
        end
      end
    end
  end

  describe "Code Execution Integration" do
    context "when testing real code execution" do
      it "executes simple Python code successfully" do
        python_code = <<~PYTHON
          print("Hello from real execution test")
          import math
          result = math.sqrt(16)
          print(f"Square root of 16: {result}")
        PYTHON

        if defined?(MonadicHelper)
          helper_instance = create_helper_instance
          
          if helper_instance.respond_to?(:run_code)
            result = helper_instance.run_code(
              command: "python",
              code: python_code,
              extension: "py"
            )
            
            if result.is_a?(Hash)
              output = result[:output] || result["output"] || result.to_s
              expect(output).to include("Hello from real execution test")
              expect(output).to include("Square root of 16: 4")
            else
              expect(result.to_s).to include("Hello from real execution test")
            end
          else
            skip "run_code method not available"
          end
        else
          skip "MonadicHelper not loaded"
        end
      end

      it "handles Python syntax errors appropriately" do
        invalid_python = <<~PYTHON
          print("This will fail"
          # Missing closing quote and parenthesis
        PYTHON

        if defined?(MonadicHelper)
          helper_instance = create_helper_instance
          
          if helper_instance.respond_to?(:run_code)
            result = helper_instance.run_code(
              command: "python",
              code: invalid_python,
              extension: "py"
            )
            
            # Should not crash, but return error information
            expect(result).not_to be_nil
            
            if result.is_a?(Hash)
              error_info = result[:error] || result["error"] || result[:output] || result["output"]
              expect(error_info.to_s.downcase).to include("error").or include("syntax")
            else
              expect(result.to_s.downcase).to include("error").or include("syntax")
            end
          else
            skip "run_code method not available"
          end
        else
          skip "MonadicHelper not loaded"
        end
      end
    end
  end

  describe "Environment Check Integration" do
    it "can check environment information" do
      if defined?(MonadicHelper)
        helper_instance = create_helper_instance
        
        if helper_instance.respond_to?(:check_environment)
          result = helper_instance.check_environment
          
          expect(result).to be_a(String)
          expect(result.length).to be > 0
          # Should contain some information about the environment
          expect(result.downcase).to include("python").or include("docker").or include("container")
        else
          skip "check_environment method not available"
        end
      else
        skip "MonadicHelper not loaded"
      end
    end
  end

  private

  def can_test_real_functionality?
    # Check if we have the basic helper functionality available
    defined?(MonadicHelper) && File.exist?(File.join(Dir.home, "monadic"))
  end

  def create_helper_instance
    # Create a minimal class that includes MonadicHelper for testing
    Class.new do
      include MonadicHelper if defined?(MonadicHelper)
      
      def initialize
        # Minimal initialization
      end
    end.new
  end

  def create_test_file(filename, content)
    data_dir = File.join(Dir.home, "monadic", "data")
    FileUtils.mkdir_p(data_dir) unless Dir.exist?(data_dir)
    File.write(File.join(data_dir, filename), content)
  end

  def cleanup_test_files
    data_dir = File.join(Dir.home, "monadic", "data")
    return unless Dir.exist?(data_dir)
    
    Dir.glob(File.join(data_dir, "integration_test_*")).each do |file|
      File.delete(file) if File.exist?(file)
    end
  end
end