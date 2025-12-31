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
        # gemini-3-flash-preview is default
        if model.is_a?(Array)
          expect(model.first).to eq("gemini-3-flash-preview")
        else
          expect(model).to eq("gemini-3-flash-preview")
        end
      end

      it "has deterministic temperature setting" do
        expect(app_instance.settings[:temperature]).to eq(0.0)
      end

      it "has adequate max_tokens setting" do
        expect(app_instance.settings[:max_tokens]).to eq(8192)
      end

      it "has monadic mode ENABLED for session state tracking" do
        expect(app_instance.settings[:monadic]).to eq(true)
      end

      it "has initiate_from_assistant enabled for better UX" do
        expect(app_instance.settings[:initiate_from_assistant]).to eq(true)
      end

      it "has Jupyter tools defined via shared tools import" do
        tools = app_instance.settings[:tools]
        # Gemini format: {"function_declarations" => [...]}
        expect(tools).to be_a(Hash)
        expect(tools).to have_key("function_declarations")

        function_declarations = tools["function_declarations"]
        expect(function_declarations).to be_an(Array)

        tool_names = function_declarations.map { |t| t["name"] }

        # Should have Jupyter tools (from jupyter_operations shared tools)
        expect(tool_names).to include("run_jupyter")
        expect(tool_names).to include("create_jupyter_notebook")
        expect(tool_names).to include("add_jupyter_cells")
        expect(tool_names).to include("get_jupyter_cells_with_results")

        # Should have file reading tools
        expect(tool_names).to include("fetch_text_from_file")
        expect(tool_names).to include("fetch_text_from_pdf")
        expect(tool_names).to include("fetch_text_from_office")

        # Should have monadic state tool
        expect(tool_names).to include("monadic_load_state")
      end

      it "has proper tool format for Gemini" do
        tools = app_instance.settings[:tools]

        # Gemini format: {"function_declarations" => [...]}
        expect(tools).to be_a(Hash)
        expect(tools).to have_key("function_declarations")

        function_declarations = tools["function_declarations"]
        # Check that each tool has the correct structure
        function_declarations.each do |tool|
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

      it "responds to Jupyter tool methods (via MonadicHelper)" do
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

    describe "System Prompt" do
      let(:app_instance) do
        instance = JupyterNotebookGemini.new
        class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      end

      it "includes state management instructions" do
        system_prompt = app_instance.settings[:initial_prompt]

        expect(system_prompt).to include("STATE MANAGEMENT")
        expect(system_prompt).to include("monadic_load_state")
      end

      it "includes response format with notebook link" do
        system_prompt = app_instance.settings[:initial_prompt]

        # Should have link format examples
        expect(system_prompt).to match(/http:\/\/127\.0\.0\.1:8889\/lab\/tree\//)
      end

      it "includes execution rules" do
        system_prompt = app_instance.settings[:initial_prompt]

        expect(system_prompt).to include("CRITICAL EXECUTION RULE")
        expect(system_prompt).to include("run_jupyter")
        expect(system_prompt).to include("add_jupyter_cells")
      end
    end
  end
end
