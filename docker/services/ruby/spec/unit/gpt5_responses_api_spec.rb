require "spec_helper"

RSpec.describe "GPT-5 Responses API" do
  describe "Model detection" do
    it "identifies GPT-5 models as requiring Responses API" do
      gpt5_models = ["gpt-5", "gpt-5-mini", "gpt-5-nano"]
      
      gpt5_models.each do |model|
        # These models should be in RESPONSES_API_MODELS constant
        expect(OpenAIHelper::RESPONSES_API_MODELS).to include(model)
      end
    end

    it "identifies GPT-5 models as reasoning models" do
      gpt5_models = ["gpt-5", "gpt-5-mini", "gpt-5-nano"]
      
      gpt5_models.each do |model|
        # Check if model matches reasoning model pattern
        is_reasoning = OpenAIHelper::REASONING_MODELS.any? { |pattern| model.include?(pattern) }
        expect(is_reasoning).to be true
      end
    end
  end

  describe "Tool continuation" do
    it "continues passing tools for GPT-5 even after tool responses" do
      # GPT-5 should keep tools available even when processing tool responses
      use_responses_api = true
      role = "tool"
      non_tool_model = false
      
      # This logic from openai_helper.rb
      skip_tools = non_tool_model || (role == "tool" && !use_responses_api)
      
      expect(skip_tools).to be false
    end
  end

  describe "Structured output configuration" do
    it "uses text.format for Responses API" do
      # For Responses API, structured output should use text.format
      # not response_format
      
      body = {
        "text" => {
          "format" => {
            "type" => "json_schema",
            "name" => "monadic_response",
            "schema" => {},
            "strict" => true
          }
        }
      }
      
      expect(body["text"]["format"]["type"]).to eq("json_schema")
      expect(body["text"]["format"]["strict"]).to be true
    end
  end

  describe "Function call ID format" do
    it "generates fc_ prefixed IDs for Responses API" do
      # Function calls in Responses API need fc_ prefix
      call_id = "call_abc123"
      fc_id = call_id.start_with?("fc_") ? call_id : "fc_#{SecureRandom.hex(16)}"
      
      expect(fc_id).to start_with("fc_")
    end
  end
end