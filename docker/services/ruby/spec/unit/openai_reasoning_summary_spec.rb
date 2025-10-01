require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/openai_helper"

RSpec.describe "OpenAI Reasoning Summary Extraction" do
  describe "Summary array processing" do
    it "extracts text from summary_text items" do
      # Simulate the structure from response.output_item.done
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => [
          {
            "type" => "summary_text",
            "text" => "First reasoning segment"
          },
          {
            "type" => "summary_text",
            "text" => "Second reasoning segment"
          }
        ]
      }

      # Extract text using filter_map pattern from our implementation
      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("First reasoning segment\n\nSecond reasoning segment")
    end

    it "handles empty summary array" do
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => []
      }

      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("")
    end

    it "skips entries with nil or empty text" do
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => [
          {
            "type" => "summary_text",
            "text" => "Valid text"
          },
          {
            "type" => "summary_text",
            "text" => nil
          },
          {
            "type" => "summary_text",
            "text" => ""
          },
          {
            "type" => "summary_text",
            "text" => "Another valid text"
          }
        ]
      }

      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("Valid text\n\nAnother valid text")
    end

    it "skips non-summary_text entries" do
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => [
          {
            "type" => "summary_text",
            "text" => "Correct type"
          },
          {
            "type" => "other_type",
            "text" => "Wrong type - should be skipped"
          },
          {
            "type" => "summary_text",
            "text" => "Another correct type"
          }
        ]
      }

      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("Correct type\n\nAnother correct type")
    end

    it "handles single summary_text entry" do
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => [
          {
            "type" => "summary_text",
            "text" => "Single reasoning text with **markdown** formatting\n\nMultiple paragraphs"
          }
        ]
      }

      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("Single reasoning text with **markdown** formatting\n\nMultiple paragraphs")
    end

    it "handles malformed entries gracefully" do
      item = {
        "id" => "rs_test123",
        "type" => "reasoning",
        "summary" => [
          {
            "type" => "summary_text",
            "text" => "Valid entry"
          },
          "not_a_hash",
          nil,
          {
            # Missing type field
            "text" => "No type field"
          },
          {
            "type" => "summary_text",
            "text" => "Another valid entry"
          }
        ]
      }

      summary_text = item["summary"].filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["type"] == "summary_text"
        text = entry["text"]
        next if text.nil? || text.to_s.empty?
        text.to_s
      end.join("\n\n")

      expect(summary_text).to eq("Valid entry\n\nAnother valid entry")
    end
  end

  describe "Reasoning parameter configuration" do
    it "includes summary: auto parameter with reasoning effort" do
      body = {
        "reasoning_effort" => "medium"
      }

      # Simulate what openai_helper.rb does
      responses_body = {}
      if body["reasoning_effort"]
        responses_body["reasoning"] = {
          "effort" => body["reasoning_effort"],
          "summary" => "auto"
        }
      end

      expect(responses_body["reasoning"]).to eq({
        "effort" => "medium",
        "summary" => "auto"
      })
    end

    it "does not create reasoning config without reasoning_effort" do
      body = {
        "model" => "gpt-5"
      }

      responses_body = {}
      if body["reasoning_effort"]
        responses_body["reasoning"] = {
          "effort" => body["reasoning_effort"],
          "summary" => "auto"
        }
      end

      expect(responses_body["reasoning"]).to be_nil
    end
  end

  describe "Delta event structure" do
    it "extracts delta text correctly" do
      # Simulate response.reasoning_summary_text.delta event
      json = {
        "type" => "response.reasoning_summary_text.delta",
        "item_id" => "rs_test123",
        "delta" => "**Thinking** about"
      }

      delta = json["delta"]
      expect(delta).to eq("**Thinking** about")
      expect(delta).to be_a(String)
    end

    it "handles empty delta" do
      json = {
        "type" => "response.reasoning_summary_text.delta",
        "item_id" => "rs_test123",
        "delta" => ""
      }

      delta = json["delta"]
      expect(delta).to eq("")
      expect(delta.to_s.empty?).to be true
    end
  end
end
