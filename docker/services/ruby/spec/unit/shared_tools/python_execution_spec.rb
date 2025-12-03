# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/python_execution"

# Mock MonadicHelper for testing purposes
module MonadicHelper
  # Simulate run_code behavior for python_execution_spec
  def run_code(code:, command:, extension:, session: nil)
    if code.include?("matplotlib") && code.include?("savefig")
      # Simulate image generation
      return { success: true, filename: "plot_#{Time.now.to_i}.png" }.to_json
    elsif code.include?("fig.write_html")
      # Simulate HTML file generation
      return { success: true, filename: "report_#{Time.now.to_i}.html" }.to_json
    elsif code.include?("print")
      # Simulate text output
      return { success: true, message: "Hello from Python!" }.to_json
    end
    # Default fallback
    { success: true, message: "Executed code." }.to_json
  end
end

RSpec.describe "MonadicSharedTools::PythonExecution" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::PythonExecution

      # Override super from MonadicHelper for testing
      def super(args)
        # MonadicHelper methods are called directly in `python_execution.rb`
        # So we can just call our mock `run_code` here
        if args.key?(:code) && args.key?(:command) && args.key?(:extension)
          MonadicHelper.new.run_code(**args)
        else
          # Fallback for other super calls if any
          "Mock super response"
        end
      end
    end
  end

  let(:app) { test_class.new }
  let(:session) { { parameters: {} } }

  describe "#run_code" do
    context "when Python code generates an image" do
      let(:code_with_image) { "import matplotlib.pyplot as plt; plt.plot([1,2,3]); plt.savefig('my_plot.png')" }
      
      it "saves the generated filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_image, command: "python", extension: "py", session: session)
        parsed_result = JSON.parse(result_json)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to eq(parsed_result["filename"])
      end
    end

    context "when Python code generates an HTML file" do
      let(:code_with_html) { "with open('report.html', 'w') as f: f.write('<h1>Report</h1>')" }
      
      it "saves the generated filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_html, command: "python", extension: "py", session: session)
        parsed_result = JSON.parse(result_json)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to eq(parsed_result["filename"])
      end
    end

    context "when Python code produces text output" do
      let(:code_with_text) { "print('hello world')" }
      
      it "does not save a filename to session[:code_interpreter_last_output_file]" do
        result_json = app.run_code(code: code_with_text, command: "python", extension: "py", session: session)
        parsed_result = JSON.parse(result_json)
        expect(parsed_result["success"]).to be true
        expect(session[:code_interpreter_last_output_file]).to be_nil
      end
    end

    context "when code is empty" do
      it "returns an error" do
        result = app.run_code(code: "", command: "python", extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Code cannot be empty" })
      end
    end

    context "when command is missing" do
      it "returns an error" do
        result = app.run_code(code: "print('hello')", command: nil, extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Missing required parameters: code, command, and extension are all required" })
      end
    end
  end
end