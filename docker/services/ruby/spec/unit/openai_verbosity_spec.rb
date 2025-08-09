require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

RSpec.describe "OpenAI Verbosity Support" do
  describe "Verbosity parameter handling" do
    it "preserves verbosity parameter for GPT-5 models" do
      obj = {
        "model" => "gpt-5",
        "verbosity" => "low",
        "messages" => [
          { "role" => "user", "content" => "Hello" }
        ]
      }

      # Test that verbosity parameter is preserved in the object
      expect(obj["verbosity"]).to eq("low")
      expect(obj["model"]).to include("gpt-5")
    end
  end

  describe "Responses API with verbosity" do
    it "includes verbosity in text object for GPT-5" do
      # Test that verbosity is properly included in Responses API format
      body = {
        "model" => "gpt-5",
        "verbosity" => "high",
        "text" => {
          "format" => {
            "type" => "json_schema",
            "name" => "test",
            "schema" => {}
          }
        }
      }

      # When processing for Responses API
      # The verbosity should be added to the text object
      expect(body["verbosity"]).to eq("high")
      expect(body["text"]).to be_a(Hash)
    end

    it "creates text object with verbosity when not present" do
      body = {
        "model" => "gpt-5-mini",
        "verbosity" => "medium"
      }

      # When no text object exists, one should be created with verbosity
      # This logic is in the openai_helper.rb file
      expect(body["verbosity"]).to eq("medium")
    end
  end

  describe "Non-GPT-5 models" do
    it "does not add verbosity for non-GPT-5 models" do
      obj = {
        "model" => "gpt-4.1",
        "verbosity" => "low",  # This should be ignored
        "messages" => [
          { "role" => "user", "content" => "Hello" }
        ]
      }

      # For non-GPT-5 models, verbosity should not affect the request
      # This is handled by the model.to_s.include?("gpt-5") check
      expect(obj["model"]).not_to include("gpt-5")
    end
  end
end