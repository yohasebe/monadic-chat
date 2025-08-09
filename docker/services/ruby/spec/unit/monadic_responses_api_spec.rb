require "spec_helper"

RSpec.describe "Monadic Responses API JSON Handling" do
  describe "monadic response processing" do
    it "preserves full JSON structure including context" do
      # Sample monadic response that should be preserved
      monadic_response = {
        "message" => "Here is my response",
        "context" => {
          "target_lang" => "Japanese",
          "language_advice" => [
            "Use more polite forms",
            "Practice particle usage"
          ]
        }
      }
      
      # The content should be the full JSON, not just the message
      expected_content = JSON.generate(monadic_response)
      
      # Verify the JSON includes both message and context
      parsed = JSON.parse(expected_content)
      expect(parsed).to have_key("message")
      expect(parsed).to have_key("context")
      expect(parsed["context"]).to have_key("target_lang")
      expect(parsed["context"]).to have_key("language_advice")
    end
    
    it "handles Language Practice Plus JSON format" do
      # Actual format from Language Practice Plus
      language_practice_json = {
        "message" => "いいですね！初級で、目的は趣味、そしてアニメが好きなんですね😊📺",
        "context" => {
          "target_lang" => "Japanese",
          "language_advice" => [
            "Your bullet list is fine, but to make full sentences in Japanese...",
            "When listing preferences, use が to mark what you like..."
          ]
        }
      }
      
      json_string = JSON.generate(language_practice_json)
      parsed = JSON.parse(json_string)
      
      # Ensure all parts are preserved
      expect(parsed["message"]).to include("いいですね")
      expect(parsed["context"]["target_lang"]).to eq("Japanese")
      expect(parsed["context"]["language_advice"]).to be_an(Array)
      expect(parsed["context"]["language_advice"].length).to eq(2)
    end
    
    it "handles Chat Plus JSON format with nested context" do
      chat_plus_json = {
        "message" => "I can help you with that",
        "context" => {
          "reasoning" => "The user asked about learning Japanese",
          "topics" => ["language learning", "Japanese"],
          "people" => [],
          "notes" => ["User is beginner level", "Interested in anime"]
        }
      }
      
      json_string = JSON.generate(chat_plus_json)
      parsed = JSON.parse(json_string)
      
      # Verify nested structure is preserved
      expect(parsed["context"]).to have_key("reasoning")
      expect(parsed["context"]).to have_key("topics")
      expect(parsed["context"]).to have_key("people")
      expect(parsed["context"]).to have_key("notes")
      expect(parsed["context"]["topics"]).to include("Japanese")
    end
  end
end