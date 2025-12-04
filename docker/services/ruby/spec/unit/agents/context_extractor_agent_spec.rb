# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/agents/context_extractor_agent"

RSpec.describe ContextExtractorAgent do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include ContextExtractorAgent

      # Mock CONFIG for testing
      def config
        { "EXTRA_LOGGING" => false }
      end
    end
  end

  let(:agent) { test_class.new }

  describe "DEFAULT_SCHEMA" do
    it "defines three default fields" do
      expect(ContextExtractorAgent::DEFAULT_SCHEMA[:fields].length).to eq(3)
    end

    it "includes topics, people, and notes fields" do
      field_names = ContextExtractorAgent::DEFAULT_SCHEMA[:fields].map { |f| f[:name] }
      expect(field_names).to contain_exactly("topics", "people", "notes")
    end

    it "provides icon, label, and description for each field" do
      ContextExtractorAgent::DEFAULT_SCHEMA[:fields].each do |field|
        expect(field).to have_key(:name)
        expect(field).to have_key(:icon)
        expect(field).to have_key(:label)
        expect(field).to have_key(:description)
      end
    end
  end

  describe "#build_extraction_prompt" do
    context "with default schema" do
      it "builds a prompt containing all field descriptions" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA)

        expect(prompt).to include("topics:")
        expect(prompt).to include("people:")
        expect(prompt).to include("notes:")
      end

      it "includes JSON structure example" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA)

        expect(prompt).to include('"topics":[')
        expect(prompt).to include('"people":[')
        expect(prompt).to include('"notes":[')
      end

      it "includes normalization instructions" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA)

        expect(prompt).to include("deduplicate")
        expect(prompt).to include("canonical form")
      end
    end

    context "with custom schema" do
      let(:custom_schema) do
        {
          fields: [
            { name: "vocabulary", icon: "fa-book", label: "Vocabulary", description: "New words learned" },
            { name: "grammar", icon: "fa-list", label: "Grammar", description: "Grammar points covered" }
          ]
        }
      end

      it "builds a prompt with custom field names" do
        prompt = agent.build_extraction_prompt(custom_schema)

        # Custom fields should be in the field descriptions
        expect(prompt).to include("vocabulary:")
        expect(prompt).to include("grammar:")
        # JSON example should contain custom fields, not default fields
        expect(prompt).to include('"vocabulary":[')
        expect(prompt).to include('"grammar":[')
        expect(prompt).not_to include('"topics":[')
      end
    end

    context "with language parameter" do
      it "includes Japanese language instruction" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA, "ja")

        expect(prompt).to include("Japanese")
      end

      it "includes Spanish language instruction" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA, "es")

        expect(prompt).to include("Spanish")
      end

      it "handles auto language without detected language" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA, "auto")

        # When language is "auto" but no detected_language is provided, fallback to generic instruction
        expect(prompt).to include("same language as the conversation")
      end

      it "handles auto language with detected language" do
        prompt = agent.build_extraction_prompt(ContextExtractorAgent::DEFAULT_SCHEMA, "auto", "ja")

        # When language is "auto" and detected_language is provided, use that language
        expect(prompt).to include("Japanese")
        expect(prompt).to include("Do not mix languages")
      end
    end
  end

  describe "#detect_conversation_language" do
    it "detects Japanese" do
      text = "これは日本語のテストです。こんにちは！"
      expect(agent.detect_conversation_language(text)).to eq("ja")
    end

    it "detects English" do
      text = "This is a test in English. Hello world!"
      expect(agent.detect_conversation_language(text)).to eq("en")
    end

    it "detects French" do
      text = "Bonjour, comment allez-vous? C'est un test en français."
      expect(agent.detect_conversation_language(text)).to eq("fr")
    end

    it "detects German" do
      text = "Guten Tag, wie geht es Ihnen? Das ist ein Test auf Deutsch."
      expect(agent.detect_conversation_language(text)).to eq("de")
    end

    it "detects Spanish" do
      text = "Hola, ¿cómo estás? Esta es una prueba en español."
      expect(agent.detect_conversation_language(text)).to eq("es")
    end

    it "detects Korean" do
      text = "이것은 한국어 테스트입니다. 안녕하세요!"
      expect(agent.detect_conversation_language(text)).to eq("ko")
    end

    it "returns English for empty text" do
      expect(agent.detect_conversation_language("")).to eq("en")
      expect(agent.detect_conversation_language(nil)).to eq("en")
    end
  end

  describe "#normalize_provider" do
    it "normalizes anthropic/claude variants to anthropic" do
      expect(agent.send(:normalize_provider, "claude")).to eq("anthropic")
      expect(agent.send(:normalize_provider, "anthropic")).to eq("anthropic")
      expect(agent.send(:normalize_provider, "Claude")).to eq("anthropic")
      expect(agent.send(:normalize_provider, "ANTHROPIC")).to eq("anthropic")
    end

    it "normalizes google/gemini variants to gemini" do
      expect(agent.send(:normalize_provider, "google")).to eq("gemini")
      expect(agent.send(:normalize_provider, "gemini")).to eq("gemini")
      expect(agent.send(:normalize_provider, "Google")).to eq("gemini")
      expect(agent.send(:normalize_provider, "GEMINI")).to eq("gemini")
    end

    it "normalizes grok/xai variants to xai" do
      expect(agent.send(:normalize_provider, "grok")).to eq("xai")
      expect(agent.send(:normalize_provider, "xai")).to eq("xai")
      expect(agent.send(:normalize_provider, "Grok")).to eq("xai")
      expect(agent.send(:normalize_provider, "XAI")).to eq("xai")
    end

    it "handles openai provider" do
      expect(agent.send(:normalize_provider, "openai")).to eq("openai")
      expect(agent.send(:normalize_provider, "OpenAI")).to eq("openai")
    end

    it "handles nil or empty provider by returning openai" do
      expect(agent.send(:normalize_provider, nil)).to eq("openai")
      expect(agent.send(:normalize_provider, "")).to eq("openai")
    end
  end

  describe "#parse_context_json" do
    context "with clean JSON" do
      it "parses valid JSON correctly" do
        json = '{"topics":["AI","Ruby"],"people":["John"],"notes":[]}'
        result = agent.send(:parse_context_json, json)

        expect(result["topics"]).to eq(["AI", "Ruby"])
        expect(result["people"]).to eq(["John"])
        expect(result["notes"]).to eq([])
      end
    end

    context "with markdown code blocks" do
      it "extracts JSON from markdown code blocks" do
        json = <<~MARKDOWN
          ```json
          {"topics":["Machine Learning"],"people":[],"notes":["Important"]}
          ```
        MARKDOWN

        result = agent.send(:parse_context_json, json)

        expect(result["topics"]).to eq(["Machine Learning"])
        expect(result["notes"]).to eq(["Important"])
      end

      it "handles code blocks without json specifier" do
        json = <<~MARKDOWN
          ```
          {"topics":["Python"],"people":[],"notes":[]}
          ```
        MARKDOWN

        result = agent.send(:parse_context_json, json)

        expect(result["topics"]).to eq(["Python"])
      end
    end

    context "with custom schema" do
      let(:custom_schema) do
        {
          fields: [
            { name: "vocabulary", icon: "fa-book", label: "Vocabulary", description: "New words" },
            { name: "grammar", icon: "fa-list", label: "Grammar", description: "Grammar points" }
          ]
        }
      end

      it "parses JSON according to custom schema fields" do
        json = '{"vocabulary":["hello","world"],"grammar":["past tense"]}'
        result = agent.send(:parse_context_json, json, custom_schema)

        expect(result["vocabulary"]).to eq(["hello", "world"])
        expect(result["grammar"]).to eq(["past tense"])
      end
    end

    context "with invalid JSON" do
      it "returns nil for invalid JSON" do
        result = agent.send(:parse_context_json, "not valid json")

        expect(result).to be_nil
      end
    end
  end

  describe "#similar_items?" do
    context "with exact matches" do
      it "returns true for identical strings" do
        expect(agent.send(:similar_items?, "John", "John")).to be true
      end
    end

    context "with substring matches" do
      it "returns true when one contains the other" do
        expect(agent.send(:similar_items?, "Machine Learning", "Machine")).to be true
        expect(agent.send(:similar_items?, "AI", "Artificial Intelligence and AI")).to be true
      end
    end

    context "with Japanese honorific variations" do
      it "returns true for name with/without -san suffix" do
        expect(agent.send(:similar_items?, "田中", "田中さん")).to be true
        expect(agent.send(:similar_items?, "田中さん", "田中")).to be true
      end

      it "returns true for name with/without -kun suffix" do
        expect(agent.send(:similar_items?, "太郎", "太郎くん")).to be true
      end

      it "returns true for name with/without -sama suffix" do
        expect(agent.send(:similar_items?, "山田", "山田様")).to be true
      end

      it "returns true for name with/without -chan suffix" do
        expect(agent.send(:similar_items?, "花子", "花子ちゃん")).to be true
      end
    end

    context "with different items" do
      it "returns false for unrelated strings" do
        expect(agent.send(:similar_items?, "John", "Mary")).to be false
        expect(agent.send(:similar_items?, "Python", "Ruby")).to be false
      end
    end

    context "with edge cases" do
      it "returns false for empty strings" do
        expect(agent.send(:similar_items?, "", "something")).to be false
        expect(agent.send(:similar_items?, "something", "")).to be false
      end
    end
  end

  describe "#merge_with_session_context" do
    let(:session) { { monadic_state: { conversation_context: nil } } }

    context "with empty existing context" do
      it "adds new items with turn information" do
        new_context = { "topics" => ["AI"], "people" => ["John"], "notes" => [] }

        result = agent.send(:merge_with_session_context, session, new_context)

        expect(result["topics"].first).to eq({ "text" => "AI", "turn" => 1 })
        expect(result["people"].first).to eq({ "text" => "John", "turn" => 1 })
        expect(result["_turn_count"]).to eq(1)
      end
    end

    context "with existing context" do
      before do
        session[:monadic_state][:conversation_context] = {
          "_turn_count" => 1,
          "topics" => [{ "text" => "AI", "turn" => 1 }],
          "people" => [],
          "notes" => []
        }
      end

      it "increments turn count" do
        new_context = { "topics" => ["Ruby"], "people" => [], "notes" => [] }

        result = agent.send(:merge_with_session_context, session, new_context)

        expect(result["_turn_count"]).to eq(2)
      end

      it "adds new items without duplicating existing ones" do
        new_context = { "topics" => ["Ruby"], "people" => [], "notes" => [] }

        result = agent.send(:merge_with_session_context, session, new_context)

        topic_texts = result["topics"].map { |t| t["text"] }
        expect(topic_texts).to contain_exactly("AI", "Ruby")
      end

      it "deduplicates similar items" do
        new_context = { "topics" => ["AI technology"], "people" => [], "notes" => [] }

        result = agent.send(:merge_with_session_context, session, new_context)

        # "AI technology" contains "AI", so should replace shorter version
        topic_texts = result["topics"].map { |t| t["text"] }
        expect(topic_texts).to include("AI technology")
      end
    end

    context "with custom schema" do
      let(:custom_schema) do
        {
          fields: [
            { name: "vocabulary", icon: "fa-book", label: "Vocabulary", description: "New words" }
          ]
        }
      end

      it "handles custom schema fields" do
        session[:monadic_state][:conversation_context] = nil
        new_context = { "vocabulary" => ["hello"] }

        result = agent.send(:merge_with_session_context, session, new_context, custom_schema)

        expect(result["vocabulary"].first).to eq({ "text" => "hello", "turn" => 1 })
      end
    end
  end

  describe "API_ENDPOINTS" do
    it "defines endpoints for all major providers" do
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("openai")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("anthropic")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("gemini")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("xai")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("mistral")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("cohere")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("deepseek")
      expect(ContextExtractorAgent::API_ENDPOINTS).to have_key("ollama")
    end

    it "uses local URL for ollama" do
      expect(ContextExtractorAgent::API_ENDPOINTS["ollama"]).to include("ollama:11434")
    end
  end

  describe "#remove_turn_from_context" do
    let(:context) do
      {
        "_turn_count" => 3,
        "topics" => [
          { "text" => "AI", "turn" => 1 },
          { "text" => "Ruby", "turn" => 2 },
          { "text" => "Python", "turn" => 3 }
        ],
        "people" => [
          { "text" => "John", "turn" => 1 },
          { "text" => "Mary", "turn" => 2 }
        ],
        "notes" => []
      }
    end

    it "removes items from the specified turn" do
      result = agent.send(:remove_turn_from_context, context, 2)

      topic_texts = result["topics"].map { |t| t["text"] }
      expect(topic_texts).to contain_exactly("AI", "Python")

      people_texts = result["people"].map { |p| p["text"] }
      expect(people_texts).to contain_exactly("John")
    end

    it "preserves turn count" do
      result = agent.send(:remove_turn_from_context, context, 2)
      expect(result["_turn_count"]).to eq(3)
    end

    it "returns original context if turn_to_remove is nil" do
      result = agent.send(:remove_turn_from_context, context, nil)
      expect(result).to eq(context)
    end
  end

  describe "#remap_turns_after_deletion" do
    let(:context) do
      {
        "_turn_count" => 3,
        "topics" => [
          { "text" => "AI", "turn" => 1 },
          { "text" => "Python", "turn" => 3 }
        ],
        "people" => [],
        "notes" => []
      }
    end

    it "decrements turn numbers greater than deleted turn" do
      result = agent.send(:remap_turns_after_deletion, context, 2)

      # Turn 3 should become Turn 2
      python_item = result["topics"].find { |t| t["text"] == "Python" }
      expect(python_item["turn"]).to eq(2)

      # Turn 1 should stay as Turn 1
      ai_item = result["topics"].find { |t| t["text"] == "AI" }
      expect(ai_item["turn"]).to eq(1)
    end

    it "decrements turn count" do
      result = agent.send(:remap_turns_after_deletion, context, 2)
      expect(result["_turn_count"]).to eq(2)
    end

    it "does not go below zero for turn count" do
      context["_turn_count"] = 0
      result = agent.send(:remap_turns_after_deletion, context, 1)
      expect(result["_turn_count"]).to eq(0)
    end
  end
end
