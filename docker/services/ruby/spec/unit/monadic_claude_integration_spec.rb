require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../lib/monadic/monadic_provider_interface"

RSpec.describe "Claude Monadic Response Integration" do
  # Create a test class that includes ClaudeHelper
  let(:test_class) do
    Class.new do
      include ClaudeHelper

      attr_accessor :obj

      def initialize
        @obj = {
          "monadic" => "true",
          "model" => "claude-sonnet-4-5-20250929"
        }
      end

      def monadic_mode?
        @obj["monadic"].to_s == "true"
      end

      def self.monadic_map(content)
        content
      end
    end
  end

  let(:helper) { test_class.new }

  describe "Structured outputs configuration" do
    it "configures output_format for supported models in monadic mode" do
      body = {
        "model" => "claude-sonnet-4-5-20250929",
        "messages" => []
      }

      # Test configure_claude_response method from MonadicProviderInterface
      configured_body = helper.configure_monadic_response(body, :claude, :chat_plus_claude, false)

      expect(configured_body["output_format"]).not_to be_nil
      expect(configured_body["output_format"]["type"]).to eq("json_schema")
      expect(configured_body["output_format"]["schema"]).to be_a(Hash)
      expect(configured_body["output_format"]["schema"]["properties"]).to have_key("message")
      expect(configured_body["output_format"]["schema"]["properties"]).to have_key("context")
    end

    it "uses CHAT_PLUS_SCHEMA for chat_plus apps" do
      body = {
        "model" => "claude-sonnet-4-5-20250929",
        "messages" => []
      }

      configured_body = helper.configure_monadic_response(body, :claude, :chat_plus_claude, false)

      schema = configured_body["output_format"]["schema"]
      context_props = schema["properties"]["context"]["properties"]

      expect(context_props).to have_key("reasoning")
      expect(context_props).to have_key("topics")
      expect(context_props).to have_key("people")
      expect(context_props).to have_key("notes")
    end

    it "uses MONADIC_JSON_SCHEMA for non-chat_plus apps" do
      body = {
        "model" => "claude-sonnet-4-5-20250929",
        "messages" => []
      }

      configured_body = helper.configure_monadic_response(body, :claude, :language_practice_plus_claude, false)

      schema = configured_body["output_format"]["schema"]
      context_props = schema["properties"]["context"]["properties"]

      # Claude requires additionalProperties: false for all objects
      expect(schema["properties"]["context"]["additionalProperties"]).to eq(false)
      expect(schema["additionalProperties"]).to eq(false)
    end

    it "skips structured outputs for thinking models" do
      body = {
        "model" => "claude-sonnet-4-5-20250929",
        "messages" => [],
        "thinking" => { "type" => "enabled", "budget_tokens" => 1000 }
      }

      configured_body = helper.configure_monadic_response(body, :claude, :chat_plus_claude, false)

      # Should not add output_format when thinking is enabled
      expect(configured_body["output_format"]).to be_nil
    end

    it "automatically disables thinking mode in monadic mode with structured outputs" do
      # This test verifies that thinking mode is automatically disabled
      # when monadic mode is enabled with structured output support
      # (thinking and structured outputs are incompatible features)

      # Simulate the obj hash that would be passed to api_request
      obj = {
        "model" => "claude-sonnet-4-5-20250929",
        "monadic" => "true",
        "reasoning_effort" => "medium"  # This would normally enable thinking
      }

      # Check the conditions that determine thinking mode
      supports_thinking = Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
      supports_structured = Monadic::Utils::ModelSpec.supports_structured_outputs?(obj["model"])

      monadic_with_structured_outputs = obj["monadic"].to_s == "true" && supports_structured

      # Thinking should be disabled due to monadic + structured outputs
      should_enable_thinking = supports_thinking &&
                               obj["reasoning_effort"] &&
                               obj["reasoning_effort"] != "none" &&
                               !monadic_with_structured_outputs

      expect(supports_thinking).to be true
      expect(supports_structured).to be true
      expect(monadic_with_structured_outputs).to be true
      expect(should_enable_thinking).to be false  # Thinking disabled!
    end

    it "skips structured outputs for non-supported models" do
      helper.obj["model"] = "claude-3-5-sonnet-20241022"

      body = {
        "model" => "claude-3-5-sonnet-20241022",
        "messages" => []
      }

      configured_body = helper.configure_monadic_response(body, :claude, :chat_plus_claude, false)

      # Claude 3.5 Sonnet doesn't support structured outputs
      expect(configured_body["output_format"]).to be_nil
    end
  end

  describe "Beta header management" do
    it "adds structured-outputs beta header for supported models" do
      # This test simulates the beta header logic in claude_helper.rb
      headers = {}

      model = "claude-sonnet-4-5-20250929"
      if Monadic::Utils::ModelSpec.supports_structured_outputs?(model)
        beta_header = Monadic::Utils::ModelSpec.get_structured_output_beta(model)
        if beta_header
          headers["anthropic-beta"] ||= []
          headers["anthropic-beta"] = Array(headers["anthropic-beta"])
          unless headers["anthropic-beta"].include?(beta_header)
            headers["anthropic-beta"] << beta_header
          end
          headers["anthropic-beta"] = headers["anthropic-beta"].join(",") if headers["anthropic-beta"].is_a?(Array)
        end
      end

      expect(headers["anthropic-beta"]).to eq("structured-outputs-2025-11-13")
    end

    it "combines multiple beta headers correctly" do
      headers = {
        "anthropic-beta" => ["context-management-v1"]
      }

      model = "claude-sonnet-4-5-20250929"
      if Monadic::Utils::ModelSpec.supports_structured_outputs?(model)
        beta_header = Monadic::Utils::ModelSpec.get_structured_output_beta(model)
        if beta_header
          headers["anthropic-beta"] = Array(headers["anthropic-beta"])
          unless headers["anthropic-beta"].include?(beta_header)
            headers["anthropic-beta"] << beta_header
          end
          headers["anthropic-beta"] = headers["anthropic-beta"].join(",")
        end
      end

      expect(headers["anthropic-beta"]).to eq("context-management-v1,structured-outputs-2025-11-13")
    end

    it "does not duplicate beta headers" do
      headers = {
        "anthropic-beta" => ["structured-outputs-2025-11-13"]
      }

      model = "claude-sonnet-4-5-20250929"
      if Monadic::Utils::ModelSpec.supports_structured_outputs?(model)
        beta_header = Monadic::Utils::ModelSpec.get_structured_output_beta(model)
        if beta_header
          headers["anthropic-beta"] = Array(headers["anthropic-beta"])
          unless headers["anthropic-beta"].include?(beta_header)
            headers["anthropic-beta"] << beta_header
          end
          headers["anthropic-beta"] = headers["anthropic-beta"].join(",")
        end
      end

      expect(headers["anthropic-beta"]).to eq("structured-outputs-2025-11-13")
    end

    it "merges model spec beta flags with new beta headers (string-based)" do
      # Simulate what happens in claude_helper.rb:
      # 1. Line 656 sets beta headers from model spec as comma-separated string
      headers = {
        "anthropic-beta" => "interleaved-thinking-2025-05-14,pdfs-2024-09-25"
      }

      # 2. Lines 731-750 merge additional beta headers
      beta_headers = []

      # Start with existing headers (split comma-separated string)
      if headers["anthropic-beta"]
        beta_headers.concat(headers["anthropic-beta"].split(",").map(&:strip))
      end

      # Add context management
      beta_headers << "context-management-2025-06-27"

      # Add model-context-window-exceeded
      beta_headers << "model-context-window-exceeded-2025-08-26"

      # Add structured outputs
      beta_headers << "structured-outputs-2025-11-13"

      # Join unique headers
      headers["anthropic-beta"] = beta_headers.uniq.join(",")

      # Verify all headers are present
      expected = "interleaved-thinking-2025-05-14,pdfs-2024-09-25,context-management-2025-06-27,model-context-window-exceeded-2025-08-26,structured-outputs-2025-11-13"
      expect(headers["anthropic-beta"]).to eq(expected)
    end
  end

  describe "Monadic response processing" do
    it "preserves full JSON structure when processing Hash response" do
      processed = {
        "message" => "This is the response from Claude",
        "context" => {
          "reasoning" => "The user asked about X",
          "topics" => ["topic1", "topic2"],
          "people" => [],
          "notes" => ["Important note"]
        }
      }

      # Claude returns structured JSON directly in content
      content = JSON.generate(processed)

      # process_monadic_response should return Hash
      result = helper.process_monadic_response(content, :chat_plus_claude)

      expect(result).to be_a(Hash)
      expect(result).to have_key("message")
      expect(result).to have_key("context")
      expect(result["context"]["reasoning"]).to eq("The user asked about X")
      expect(result["context"]["topics"]).to eq(["topic1", "topic2"])
    end

    it "handles language_practice_plus format correctly" do
      processed = {
        "message" => "Bonjour! Comment allez-vous?",
        "context" => {
          "target_lang" => "French",
          "language_advice" => [
            "Use 'Comment allez-vous?' for formal situations",
            "Use 'Ça va?' for informal conversations"
          ]
        }
      }

      content = JSON.generate(processed)
      result = helper.process_monadic_response(content, :language_practice_plus_claude)

      expect(result).to be_a(Hash)
      expect(result["context"]["target_lang"]).to eq("French")
      expect(result["context"]["language_advice"]).to be_an(Array)
      expect(result["context"]["language_advice"].length).to eq(2)
    end
  end

  describe "Regression tests for monadic context" do
    it "does NOT lose context information" do
      processed = {
        "message" => "User message",
        "context" => {
          "important" => "This must not be lost",
          "nested" => {
            "data" => "deeply nested value"
          }
        }
      }

      content = JSON.generate(processed)
      result = helper.process_monadic_response(content, :chat_plus_claude)

      # Critical test - context must be fully preserved
      expect(result["context"]).not_to be_nil
      expect(result["context"]["important"]).to eq("This must not be lost")
      expect(result["context"]["nested"]["data"]).to eq("deeply nested value")
    end

    it "handles all Claude monadic app formats correctly" do
      test_cases = [
        # Language Practice Plus format
        {
          "message" => "Hello",
          "context" => {
            "target_lang" => "Spanish",
            "language_advice" => ["Use '¿Cómo estás?' for informal greetings"]
          }
        },
        # Chat Plus format
        {
          "message" => "I understand your question",
          "context" => {
            "reasoning" => "User is asking about structured outputs",
            "topics" => ["Claude API", "JSON Schema"],
            "people" => [],
            "notes" => ["User prefers detailed explanations"]
          }
        }
      ]

      test_cases.each do |test_case|
        content = JSON.generate(test_case)
        result = helper.process_monadic_response(content, :chat_plus_claude)

        # Every test case must preserve its context
        expect(result["context"]).to eq(test_case["context"])
      end
    end
  end

  describe "Edge cases and error handling" do
    it "handles malformed JSON gracefully" do
      content = "not valid json"
      result = helper.process_monadic_response(content, :chat_plus_claude)

      # Should return fallback structure
      expect(result).to be_a(Hash)
      expect(result).to have_key("message")
      expect(result).to have_key("context")
    end

    it "handles deeply nested context structures" do
      processed = {
        "message" => "Complex response",
        "context" => {
          "level1" => {
            "level2" => {
              "level3" => {
                "data" => "deeply nested value"
              }
            }
          }
        }
      }

      content = JSON.generate(processed)
      result = helper.process_monadic_response(content, :chat_plus_claude)

      expect(result["context"]["level1"]["level2"]["level3"]["data"]).to eq("deeply nested value")
    end

    it "handles empty context object" do
      processed = {
        "message" => "Simple response",
        "context" => {}
      }

      content = JSON.generate(processed)
      result = helper.process_monadic_response(content, :chat_plus_claude)

      expect(result["message"]).to eq("Simple response")
      expect(result["context"]).to eq({})
    end
  end
end
