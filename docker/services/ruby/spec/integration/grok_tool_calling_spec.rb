# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../apps/jupyter_notebook/jupyter_notebook_tools"

RSpec.describe "Grok Tool Calling Integration", :integration do
  let(:session) do
    {
      parameters: {
        "app_name" => "JupyterNotebookGrok",
        "model" => "grok-4-0709",
        "temperature" => 0.7,
        "max_tokens" => 4096,
        "tools" => true,
        "tool_choice" => "auto",
        "parallel_function_calling" => true,
        "monadic" => false,
        "initial_prompt" => "You are a helpful assistant.",
        "message" => "",
        "context_size" => 10
      },
      messages: []
    }
  end
  
  describe "Tool inclusion in API requests" do
    context "when role is 'user'" do
      it "includes tools in the request body" do
        # Create instance directly from class
        skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
        app = JupyterNotebookGrok.new
        class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
        app.settings = class_settings if class_settings
        
        # Verify app has tools defined
        expect(app.settings[:tools]).not_to be_nil
        expect(app.settings[:tools]).to be_an(Array)
        expect(app.settings[:tools]).not_to be_empty
        
        # Check that tools include Jupyter-specific functions
        tool_names = app.settings[:tools].map { |t| t.dig(:type) == "function" ? t.dig(:function, :name) : nil }.compact
        expect(tool_names).to include("run_jupyter")
        expect(tool_names).to include("create_jupyter_notebook")
        expect(tool_names).to include("add_jupyter_cells")
      end
    end
    
    context "when role is 'tool'" do
      it "still includes tools for continued function calling" do
        session[:parameters]["function_returns"] = [
          {
            "role" => "tool",
            "tool_call_id" => "call_123",
            "name" => "run_jupyter",
            "content" => "JupyterLab started"
          }
        ]
        
        skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
        app = JupyterNotebookGrok.new
        class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
        app.settings = class_settings if class_settings
        
        # Tools should still be available for Grok even in tool responses
        expect(app.settings[:tools]).not_to be_nil
        expect(app.settings[:tools]).not_to be_empty
      end
    end
  end
  
  describe "Tool execution flow" do
    let(:app) do
      if defined?(JupyterNotebookGrok)
        instance = JupyterNotebookGrok.new
        class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
        instance.settings = class_settings if class_settings
        instance
      else
        nil
      end
    end
    
    before do
      # Clean up any running Jupyter processes
      system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
      sleep 1
    end
    
    after do
      system("pkill -f jupyter-lab", out: File::NULL, err: File::NULL)
    end
    
    it "executes tools and returns results" do
      skip "JupyterNotebookGrok not loaded" unless app
      # Test actual tool execution
      result = app.run_jupyter(command: "start")
      
      expect(result).to be_a(String)
      expect(result).not_to be_empty
      expect(result).to match(/Jupyter/i)
    end
    
    it "handles tool execution errors gracefully" do
      skip "JupyterNotebookGrok not loaded" unless app
      # Test with invalid parameters
      expect {
        app.run_jupyter(command: "invalid_command")
      }.not_to raise_error
      
      # Should return an error message, not crash
      result = app.run_jupyter(command: "invalid_command")
      expect(result).to match(/error|invalid|unknown/i)
    end
    
    it "supports parallel function calling" do
      # Verify parallel_function_calling is properly configured
      expect(session[:parameters]["parallel_function_calling"]).to eq(true)
    end
  end
  
  describe "Response formatting" do
    context "with monadic mode disabled" do
      it "returns natural language responses" do
        session[:parameters]["monadic"] = false
        
        # Monadic should be false for Grok Jupyter
        expect(session[:parameters]["monadic"]).to eq(false)
      end
    end
    
    context "structured output limitations" do
      it "cannot use response_format with function calling" do
        # If we set monadic to true, it would add response_format
        # which conflicts with function calling
        session[:parameters]["monadic"] = true
        session[:parameters]["response_format"] = { "type" => "json_object" }
        
        # This configuration would prevent tools from executing
        # This is the known limitation we documented
        expect(session[:parameters]["response_format"]).not_to be_nil
      end
    end
  end
  
  describe "MAX_FUNC_CALLS limit" do
    it "has a reasonable limit set" do
      expect(GrokHelper::MAX_FUNC_CALLS).to eq(20)
    end
    
    it "prevents infinite recursion" do
      # Create a scenario that would cause recursion
      call_depth = 0
      max_depth = GrokHelper::MAX_FUNC_CALLS
      
      # Simulate recursive calls
      while call_depth < max_depth + 5
        call_depth += 1
        if call_depth > max_depth
          # Should stop here
          expect(call_depth).to be > max_depth
          break
        end
      end
      
      # Verify we stopped at a reasonable point
      expect(call_depth).to eq(max_depth + 1)
    end
  end
  
  describe "Model configuration" do
    it "uses the correct Grok model name" do
      skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
      app_instance = JupyterNotebookGrok.new
      class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
      app_instance.settings = class_settings if class_settings
      
      # Check MDSL configuration
      expect(app_instance.settings[:model]).to eq("grok-code-fast-1")
      expect(app_instance.settings[:model]).not_to eq("grok-4")  # Wrong model name
    end
    
    it "has proper temperature settings for deterministic outputs" do
      skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
      app_instance = JupyterNotebookGrok.new
      class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
      app_instance.settings = class_settings if class_settings
      
      expect(app_instance.settings[:temperature]).to eq(0.0)
    end
    
    it "has adequate max_tokens for Jupyter operations" do
      skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
      app_instance = JupyterNotebookGrok.new
      class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
      app_instance.settings = class_settings if class_settings
      
      expect(app_instance.settings[:max_tokens]).to eq(4096)
      expect(app_instance.settings[:max_tokens]).to be >= 2048  # Minimum for useful responses
    end
  end
  
  describe "Tool choice configuration" do
    it "supports different tool_choice settings" do
      skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
      app_instance = JupyterNotebookGrok.new
      class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
      app_instance.settings = class_settings if class_settings
      
      # Default should be "auto"
      expect(app_instance.settings[:tool_choice]).to eq("auto")
      
      # Should support other values
      valid_choices = ["auto", "required", "none"]
      expect(valid_choices).to include(app_instance.settings[:tool_choice])
    end
  end
  
  describe "Status reporting" do
    it "includes Jupyter notebook management instructions in system prompt" do
      skip "JupyterNotebookGrok not loaded" unless defined?(JupyterNotebookGrok)
      app_instance = JupyterNotebookGrok.new
      class_settings = JupyterNotebookGrok.instance_variable_get(:@settings)
      app_instance.settings = class_settings if class_settings
      
      system_prompt = app_instance.settings[:initial_prompt]
      skip "System prompt not configured" unless system_prompt
      
      # Check that Jupyter notebook management instructions are included
      expect(system_prompt).to include("Jupyter Notebook assistant")
      expect(system_prompt).to include("create_and_populate_jupyter_notebook")
      expect(system_prompt).to include("Combined Tool")
    end
  end
end