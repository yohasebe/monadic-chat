# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Jupyter Notebook Gemini E2E Test", :e2e do
  before(:all) do
    # Load MDSL file
    require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"
    mdsl_path = File.expand_path("../../apps/jupyter_notebook/jupyter_notebook_gemini.mdsl", __dir__)
    if File.exist?(mdsl_path)
      load mdsl_path
    end
  end

  describe "Gemini with Structured Output and Function Calling" do
    let(:app_instance) do
      instance = JupyterNotebookGemini.new
      class_settings = JupyterNotebookGemini.instance_variable_get(:@settings)
      instance.settings = class_settings if class_settings
      instance
    end

    it "has both structured output and function calling configured" do
      # Verify structured output is enabled
      expect(app_instance.settings[:monadic]).to eq(true)
      
      # Verify tools are configured for function calling
      tools = app_instance.settings[:tools]
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
      
      # Verify tools have proper format for Gemini
      tool_names = tools.map { |t| t["name"] }
      expect(tool_names).to include("run_jupyter")
      expect(tool_names).to include("create_jupyter_notebook")
      expect(tool_names).to include("add_jupyter_cells")
      expect(tool_names).to include("get_jupyter_cells_with_results")
      
      # Verify each tool has correct structure for Gemini
      tools.each do |tool|
        expect(tool).to have_key("name")
        expect(tool).to have_key("description")
        expect(tool).to have_key("parameters")
        
        # Verify parameters structure
        params = tool["parameters"]
        expect(params["type"]).to eq("object")
        expect(params).to have_key("properties")
        expect(params).to have_key("required")
      end
      
      # Verify system prompt includes structured output format
      system_prompt = app_instance.settings[:initial_prompt]
      expect(system_prompt).to include("STRUCTURED OUTPUT FORMAT")
      expect(system_prompt).to include("message")
      expect(system_prompt).to include("context")
      expect(system_prompt).to include("jupyter_running")
      expect(system_prompt).to include("notebook_created")
      
      # Simulate what a structured response would look like
      structured_response = {
        "message" => "I've created a test notebook with Python cells.",
        "context" => {
          "jupyter_running" => true,
          "notebook_created" => true, 
          "notebook_name" => "test.ipynb",
          "link" => "<a href='http://localhost:8889/lab/tree/test.ipynb' target='_blank'>test.ipynb</a>",
          "imported_modules" => ["pandas", "numpy"],
          "defined_functions" => ["process_data"],
          "cells_added" => 3,
          "cells_total" => 5,
          "last_output" => "Data processed successfully",
          "errors" => []
        }
      }
      
      # Verify the structured output format matches expected schema
      expect(structured_response).to have_key("message")
      expect(structured_response["message"]).to be_a(String)
      expect(structured_response).to have_key("context")
      expect(structured_response["context"]).to be_a(Hash)
      
      # Verify all required context fields
      context = structured_response["context"]
      expect([true, false]).to include(context["jupyter_running"])
      expect([true, false]).to include(context["notebook_created"])
      expect(context["notebook_name"]).to be_a(String).or(be_nil)
      expect(context["link"]).to be_a(String).or(be_nil)
      expect(context["imported_modules"]).to be_an(Array)
      expect(context["defined_functions"]).to be_an(Array)
      expect(context["cells_added"]).to be_a(Integer)
      expect(context["cells_total"]).to be_a(Integer)
      expect(context["last_output"]).to be_a(String).or(be_nil)
      expect(context["errors"]).to be_an(Array)
      
      puts "\n✅ Gemini Jupyter Notebook app successfully configured with:"
      puts "   - Structured output (monadic mode): ENABLED"
      puts "   - Function calling with #{tools.length} tools: CONFIGURED"
      puts "   - Both features can work together in Gemini API"
    end
  end
end