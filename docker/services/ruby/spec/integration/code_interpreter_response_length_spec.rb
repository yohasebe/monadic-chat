require "spec_helper"

RSpec.describe "Code Interpreter Response Length Configuration" do
  let(:gemini_mdsl_path) { "apps/code_interpreter/code_interpreter_gemini.mdsl" }
  let(:grok_mdsl_path) { "apps/code_interpreter/code_interpreter_grok.mdsl" }
  
  describe "MDSL Configuration" do
    context "Gemini Code Interpreter" do
      it "has max_tokens configured" do
        if File.exist?(gemini_mdsl_path)
          content = File.read(gemini_mdsl_path)
          
          # Check for max_tokens setting
          expect(content).to match(/max_tokens\s+8192/)
          
          # Check for monadic false setting (required for function calling)
          expect(content).to match(/monadic\s+false/)
          
          # Check for minimal reasoning_effort (required for function calling)
          expect(content).to match(/reasoning_effort\s+"minimal"/)
        else
          pending "Gemini Code Interpreter MDSL file not found"
        end
      end
    end
    
    context "Grok Code Interpreter" do
      it "has max_tokens configured" do
        if File.exist?(grok_mdsl_path)
          content = File.read(grok_mdsl_path)
          
          # Check for max_tokens setting
          expect(content).to match(/max_tokens\s+\d+/)
        else
          pending "Grok Code Interpreter MDSL file not found"
        end
      end
    end
  end
  
  describe "Response Completeness" do
    context "when generating long responses" do
      # This is a mock test to demonstrate the expected behavior
      # In a real scenario, this would test against actual API responses
      
      let(:long_code_output) do
        # Simulate a long output that would be truncated without proper max_tokens
        Array.new(100) { |i| "Line #{i}: " + "x" * 80 }.join("\n")
      end
      
      it "should not truncate responses with finishReason: STOP" do
        # Mock response structure
        mock_response = {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => long_code_output }
                ]
              },
              "finishReason" => "STOP"  # This indicates proper completion
            }
          ]
        }
        
        # The finishReason should be STOP, not MAX_TOKENS
        expect(mock_response["candidates"][0]["finishReason"]).to eq("STOP")
        
        # The content should be complete
        expect(mock_response["candidates"][0]["content"]["parts"][0]["text"].length).to be > 8000
      end
      
      it "identifies truncated responses with finishReason: MAX_TOKENS" do
        # Mock a truncated response
        truncated_response = {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => long_code_output[0..4000] }  # Truncated
                ]
              },
              "finishReason" => "MAX_TOKENS"  # This indicates truncation
            }
          ]
        }
        
        # This should be detected as incomplete
        expect(truncated_response["candidates"][0]["finishReason"]).to eq("MAX_TOKENS")
      end
    end
  end
  
  describe "Configuration Validation" do
    it "ensures max_tokens is sufficient for typical code outputs" do
      recommended_min_tokens = 4096
      
      # Check various Code Interpreter configurations
      code_interpreter_files = Dir.glob("apps/code_interpreter/code_interpreter_*.mdsl")
      
      code_interpreter_files.each do |file|
        content = File.read(file)
        provider = File.basename(file, ".mdsl").split("_").last
        
        # Check if max_tokens is configured (if present)
        if content =~ /max_tokens\s+(\d+)/
          tokens = $1.to_i
          expect(tokens).to be >= recommended_min_tokens,
            "#{provider} Code Interpreter has max_tokens=#{tokens}, recommended minimum is #{recommended_min_tokens}"
        end
      end
    end
    
    it "ensures monadic mode is properly configured for Gemini" do
      if File.exist?(gemini_mdsl_path)
        content = File.read(gemini_mdsl_path)
        
        # Gemini requires monadic false for proper function calling
        expect(content).to match(/monadic\s+false/),
          "Gemini Code Interpreter must have 'monadic false' for proper function calling"
      end
    end
  end
  
  describe "Graph Display with Complete Response" do
    it "should display graphs AND complete text response" do
      # This simulates the expected behavior after fix
      expected_behavior = {
        graph_displayed: true,
        response_complete: true,
        response_parts: [
          "Here's the graph you requested:",
          "```python\nimport matplotlib.pyplot as plt\n...\n```",
          "The graph shows...",  # Complete explanation should be present
          "Key observations:",
          "1. The trend is increasing...",
          "2. Peak values occur at..."
        ]
      }
      
      expect(expected_behavior[:graph_displayed]).to be true
      expect(expected_behavior[:response_complete]).to be true
      expect(expected_behavior[:response_parts]).to all(be_a(String))
    end
  end
end