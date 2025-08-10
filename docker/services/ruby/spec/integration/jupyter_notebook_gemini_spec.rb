# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Jupyter Notebook Gemini Integration", :integration do
  before(:all) do
    # Load MDSL file
    require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"
    mdsl_path = File.expand_path("../../apps/jupyter_notebook/jupyter_notebook_gemini.mdsl", __dir__)
    if File.exist?(mdsl_path)
      load mdsl_path
    end
  end

  describe "JupyterNotebookGemini" do
    it "is defined as a class" do
      expect(defined?(JupyterNotebookGemini)).to eq("constant")
      expect(JupyterNotebookGemini).to be < MonadicApp
    end

    it "includes GeminiHelper module" do
      expect(JupyterNotebookGemini.included_modules).to include(GeminiHelper)
    end

    describe "Settings and Configuration" do
      let(:app_instance) do
        instance = JupyterNotebookGemini.new
        class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      end

      it "has correct model configuration" do
        model = app_instance.settings[:model]
        # Now uses 2.5 flash as primary with 2.0 as fallback
        if model.is_a?(Array)
          expect(model.first).to eq("gemini-2.5-flash")
          expect(model).to include("gemini-2.0-flash")
        else
          expect(model).to eq("gemini-2.5-flash")
        end
      end

      it "has deterministic temperature setting" do
        expect(app_instance.settings[:temperature]).to eq(0.0)
      end

      it "has adequate max_tokens setting" do
        expect(app_instance.settings[:max_tokens]).to eq(8192)
      end

      it "has reasoning_effort configured for Gemini 2.5" do
        # Gemini 2.5 requires reasoning_effort: minimal for proper function calling
        expect(app_instance.settings[:reasoning_effort]).to eq("minimal")
      end

      it "has monadic mode DISABLED for function calling compatibility" do
        # Monadic mode disabled for better function calling (like Grok)
        expect(app_instance.settings[:monadic]).to eq(false)
      end

      it "has initiate_from_assistant enabled for better UX" do
        expect(app_instance.settings[:initiate_from_assistant]).to eq(true)
      end

      it "has Jupyter-specific tools defined" do
        tools = app_instance.settings[:tools]
        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty

        tool_names = tools.map { |t| t["name"] }
        expect(tool_names).to include("run_jupyter")
        expect(tool_names).to include("create_jupyter_notebook")
        expect(tool_names).to include("add_jupyter_cells")
        expect(tool_names).to include("get_jupyter_cells_with_results")
      end

      it "has proper tool format for Gemini" do
        tools = app_instance.settings[:tools]
        
        # Check that each tool has the correct structure
        tools.each do |tool|
          expect(tool).to have_key("name")
          expect(tool).to have_key("description")
          expect(tool).to have_key("parameters")
          
          # Check parameters structure
          params = tool["parameters"]
          expect(params).to have_key("type")
          expect(params["type"]).to eq("object")
          expect(params).to have_key("properties")
          expect(params).to have_key("required")
        end
      end
    end

    describe "Tool Methods" do
      let(:app_instance) do
        instance = JupyterNotebookGemini.new
        class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      end

      it "responds to Jupyter tool methods" do
        expect(app_instance).to respond_to(:run_jupyter)
        expect(app_instance).to respond_to(:create_jupyter_notebook)
        expect(app_instance).to respond_to(:add_jupyter_cells)
        expect(app_instance).to respond_to(:get_jupyter_cells_with_results)
        expect(app_instance).to respond_to(:list_jupyter_notebooks)
      end

      it "responds to file operation methods" do
        expect(app_instance).to respond_to(:fetch_text_from_file)
        expect(app_instance).to respond_to(:fetch_text_from_pdf)
        expect(app_instance).to respond_to(:fetch_text_from_office)
        expect(app_instance).to respond_to(:write_to_file)
      end

      it "responds to code execution methods" do
        expect(app_instance).to respond_to(:run_code)
        expect(app_instance).to respond_to(:check_environment)
      end
    end

    describe "Basic Jupyter Operations" do
      let(:app_instance) do
        instance = JupyterNotebookGemini.new
        class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      end

      before do
        # Clean up any existing Jupyter processes
        system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
        sleep 1
      end

      after do
        # Clean up
        system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
      end

      it "can start JupyterLab server" do
        result = app_instance.run_jupyter(command: "start")
        
        expect(result).to be_a(String)
        expect(result).to match(/Jupyter.*running|started/i)
      end

      it "can create a new notebook" do
        # Start Jupyter first
        app_instance.run_jupyter(command: "start")
        sleep 2
        
        # Create notebook
        result = app_instance.create_jupyter_notebook(filename: "test_gemini_notebook")
        
        expect(result).to be_a(String)
        expect(result).to match(/created|test_gemini_notebook/i)
        
        # Clean up
        file_path = File.join(Dir.home, "monadic", "data", "test_gemini_notebook.ipynb")
        File.delete(file_path) if File.exist?(file_path)
      end

      it "can add cells to a notebook" do
        # Start Jupyter first
        app_instance.run_jupyter(command: "start")
        sleep 2
        
        # Create notebook
        app_instance.create_jupyter_notebook(filename: "test_cells_gemini")
        
        # Add cells
        cells = [
          { "cell_type" => "markdown", "source" => "# Test Notebook" },
          { "cell_type" => "code", "source" => "import numpy as np\nprint('Hello from Gemini')" }
        ]
        
        result = app_instance.add_jupyter_cells(filename: "test_cells_gemini.ipynb", cells: cells)
        
        expect(result).to be_a(String)
        expect(result).to match(/added|cells/i)
        
        # Clean up
        file_path = File.join(Dir.home, "monadic", "data", "test_cells_gemini.ipynb")
        File.delete(file_path) if File.exist?(file_path)
      end
    end

    describe "Thinking Model Compatibility" do
      let(:app_instance) do
        instance = JupyterNotebookGemini.new
        class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      end

      it "is configured for optimal function calling" do
        # Monadic mode disabled for better function calling (like Grok)
        expect(app_instance.settings[:monadic]).to eq(false)
        
        # Tools available
        expect(app_instance.settings[:tools]).not_to be_empty
        
        # Reasoning effort minimal for Gemini 2.5 function calling
        expect(app_instance.settings[:reasoning_effort]).to eq("minimal")
        
        # Assistant initiation enabled with proper tool mode management
        expect(app_instance.settings[:initiate_from_assistant]).to eq(true)
        
        puts "\n✅ Gemini Jupyter Notebook optimized for function calling:"
        puts "   - Model: gemini-2.5-flash with 2.0 fallback"
        puts "   - Reasoning effort: minimal (required for 2.5 function calling)"
        puts "   - Monadic mode: DISABLED (like Grok for better function calling)"
        puts "   - Function calling: ENABLED with #{app_instance.settings[:tools].length} tools"
        puts "   - Assistant initiation: ENABLED"
        puts "   - Natural language responses with embedded links"
      end

      it "includes natural language response instructions" do
        system_prompt = app_instance.settings[:initial_prompt]
        
        # Should have natural language response format
        expect(system_prompt).to include("Provide clear, natural language responses")
        expect(system_prompt).to include("http://localhost:8889/lab/tree/")
        
        # Should not have JSON context instructions
        expect(system_prompt).not_to include("context.link")
      end
    end
  end
end