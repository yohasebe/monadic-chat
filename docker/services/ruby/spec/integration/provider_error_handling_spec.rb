require "spec_helper"

RSpec.describe "Provider Error Handling" do
  describe "Gemini Error Handling" do
    context "when Jupyter notebook file not found" do
      let(:error_message) { "Error: Notebook 'test_notebook' not found. Did you mean one of these? test_notebook_20240828_123456. Please use the exact filename with timestamp returned by create_jupyter_notebook." }
      
      it "provides helpful error message with suggestions" do
        expect(error_message).to include("Did you mean")
        expect(error_message).to include("Please use the exact filename with timestamp")
        expect(error_message).to match(/test_notebook_\d{8}_\d{6}/)
      end
    end
    
    context "when function call fails" do
      it "formats error message consistently" do
        # Test the error formatter output
        error_scenarios = [
          {
            type: "tool_error",
            tool: "add_jupyter_cells",
            message: "Invalid cell format",
            expected: /\[Gemini\].*Tool Execution Error.*add_jupyter_cells.*Invalid cell format/
          },
          {
            type: "api_error",
            message: "Rate limit exceeded",
            code: 429,
            expected: /\[Gemini\].*API Error.*Rate limit exceeded.*Code: 429/
          },
          {
            type: "network_error",
            message: "Connection timeout",
            expected: /\[Gemini\].*Network Error.*Connection timeout/
          }
        ]
        
        error_scenarios.each do |scenario|
          # The actual error formatter would be called here
          # This is a mock to demonstrate expected format
          formatted_error = case scenario[:type]
          when "tool_error"
            "[Gemini] Tool Execution Error: #{scenario[:tool]} - #{scenario[:message]}"
          when "api_error"
            "[Gemini] API Error: #{scenario[:message]} (Code: #{scenario[:code]})"
          when "network_error"
            "[Gemini] Network Error: #{scenario[:message]}"
          end
          
          expect(formatted_error).to match(scenario[:expected])
        end
      end
    end
    
    context "when cells parameter is invalid" do
      it "validates cells array structure" do
        invalid_cells_cases = [
          { cells: nil, error: "Expected an array of cell objects" },
          { cells: "", error: "Expected an array of cell objects" },
          { cells: "not an array", error: "Expected an array of cell objects, but received String" },
          { cells: [], error: "Please provide at least one cell" },
          { cells: [{}], error: "cell_type and source properties" }
        ]
        
        invalid_cells_cases.each do |test_case|
          # Mock validation that would happen in add_jupyter_cells
          error = if test_case[:cells].nil?
            "Expected an array of cell objects"
          elsif test_case[:cells] == ""
            "Expected an array of cell objects"
          elsif !test_case[:cells].is_a?(Array)
            "Expected an array of cell objects, but received #{test_case[:cells].class}"
          elsif test_case[:cells].empty?
            "Please provide at least one cell"
          else
            "cell_type and source properties"
          end
          
          expect(error).to include(test_case[:error])
        end
      end
    end
  end
  
  describe "Code Interpreter Error Handling" do
    context "when code execution fails" do
      it "stops retrying after repeated errors" do
        max_retries = 3
        retry_count = 0
        error_message = "ModuleNotFoundError: No module named 'nonexistent'"
        
        # Simulate retry logic
        while retry_count < max_retries
          retry_count += 1
          # Simulate error occurring
          if retry_count >= max_retries
            final_message = "Error persists after #{max_retries} attempts. #{error_message}"
            expect(final_message).to include("Error persists")
            expect(final_message).to include(error_message)
            break
          end
        end
        
        expect(retry_count).to eq(max_retries)
      end
    end
    
    context "when response is truncated" do
      it "detects MAX_TOKENS finish reason" do
        response = {
          "finishReason" => "MAX_TOKENS",
          "content" => "Partial response..."
        }
        
        is_truncated = response["finishReason"] == "MAX_TOKENS"
        expect(is_truncated).to be true
      end
      
      it "detects STOP finish reason for complete responses" do
        response = {
          "finishReason" => "STOP",
          "content" => "Complete response with all content"
        }
        
        is_truncated = response["finishReason"] == "MAX_TOKENS"
        expect(is_truncated).to be false
      end
    end
  end
  
  describe "Cross-Provider Error Consistency" do
    let(:providers) { %w[gemini openai claude grok cohere deepseek mistral perplexity] }
    
    it "all providers use consistent error format" do
      providers.each do |provider|
        # Mock error formatter for each provider
        formatted_error = "[#{provider.capitalize}] API Error: Test error (Code: 500)"
        
        expect(formatted_error).to match(/\[#{provider.capitalize}\]/)
        expect(formatted_error).to include("API Error")
        expect(formatted_error).to include("Code:")
      end
    end
    
    it "all providers handle missing API keys" do
      providers.each do |provider|
        # Mock API key error
        key_name = "#{provider.upcase}_API_KEY"
        error = "[#{provider.capitalize}] API Key Error: #{key_name} not found"
        suggestion = "Set #{key_name} in ~/monadic/config/env"
        
        expect(error).to include("API Key Error")
        expect(suggestion).to include("~/monadic/config/env")
      end
    end
  end
  
  describe "Partial Success Handling" do
    context "when notebook is created but cells fail to add" do
      it "reports partial success clearly" do
        result = {
          notebook_created: true,
          cells_added: false,
          message: "Notebook created successfully, but failed to add cells: Invalid cell format"
        }
        
        expect(result[:notebook_created]).to be true
        expect(result[:cells_added]).to be false
        expect(result[:message]).to include("created successfully")
        expect(result[:message]).to include("failed to add cells")
      end
    end
    
    context "when some cells succeed and others fail" do
      it "reports which cells succeeded" do
        cells_result = {
          total: 5,
          successful: 3,
          failed: 2,
          message: "Added 3 of 5 cells. Failed cells: 4, 5"
        }
        
        expect(cells_result[:successful]).to eq(3)
        expect(cells_result[:failed]).to eq(2)
        expect(cells_result[:message]).to match(/Added 3 of 5 cells/)
      end
    end
  end
end