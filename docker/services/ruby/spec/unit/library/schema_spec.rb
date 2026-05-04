# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require_relative "../../../lib/monadic/library/schema"

RSpec.describe Monadic::Library::Schema do
  # Reusable factory to keep each test focused on the property being checked.
  def base_conversation(overrides = {})
    {
      "format_version" => "1.0",
      "conversation_id" => SecureRandom.uuid,
      "conversation_metadata" => {
        "source" => "monadic-chat",
        "language" => "en",
        "license" => "private"
      },
      "participants" => [
        { "id" => "user-1", "role" => "human" },
        { "id" => "asst-1", "role" => "assistant" }
      ],
      "messages" => [
        { "id" => "msg-0001", "speaker" => { "id" => "user-1" }, "text" => "Hello" },
        { "id" => "msg-0002", "speaker" => { "id" => "asst-1" }, "text" => "Hi there." }
      ]
    }.merge(overrides)
  end

  describe ".valid?" do
    context "with a minimal Monadic Chat conversation" do
      it "accepts the canonical shape" do
        expect(described_class.valid?(base_conversation)).to be true
      end
    end

    context "with a TED Talk monologue (timing-based, single narrator)" do
      it "accepts a transcript-style conversation" do
        data = base_conversation(
          "conversation_metadata" => {
            "source" => "ted-talk",
            "external_id" => "02551",
            "title" => "Nature is everywhere",
            "language" => "en",
            "license" => "CC-BY-NC-ND-4.0",
            "duration_seconds" => 1080
          },
          "participants" => [
            { "id" => "speaker-1", "role" => "narrator", "label" => "Emma Marris",
              "description" => "TED_speaker" }
          ],
          "messages" => [
            {
              "id" => "msg-0001",
              "speaker" => { "id" => "speaker-1" },
              "text" => "We are stealing nature from our children.",
              "timing" => { "offset_seconds" => 12.56, "duration_seconds" => 3.28 }
            }
          ]
        )

        expect(described_class.valid?(data)).to be true
      end
    end

    context "with a CHILDES-style multi-party conversation (rich participant metadata)" do
      it "accepts open-vocabulary description and free-form metadata" do
        data = base_conversation(
          "conversation_metadata" => {
            "source" => "imported-childes",
            "language" => "en",
            "license" => "CC-BY-NC-SA-3.0"
          },
          "participants" => [
            {
              "id" => "chi", "role" => "human", "label" => "Sarah",
              "description" => "target_child",
              "metadata" => { "age" => "2;3.04", "sex" => "female", "native_language" => "en" }
            },
            {
              "id" => "mot", "role" => "human", "label" => "Mary",
              "description" => "mother",
              "metadata" => { "sex" => "female" }
            },
            {
              "id" => "inv", "role" => "human", "label" => "John",
              "description" => "investigator"
            }
          ],
          "messages" => [
            { "id" => "m1", "speaker" => { "id" => "mot" }, "text" => "what is that?" },
            { "id" => "m2", "speaker" => { "id" => "chi" }, "text" => "doggy!" },
            { "id" => "m3", "speaker" => { "id" => "inv" }, "text" => "good naming." }
          ]
        )

        expect(described_class.valid?(data)).to be true
      end
    end

    context "with full message metadata (edits, monadic_state, tools)" do
      it "accepts all documented metadata fields" do
        data = base_conversation(
          "messages" => [
            {
              "id" => "msg-0001",
              "speaker" => { "id" => "user-1" },
              "text" => "What is 2+2?",
              "timestamp" => "2026-04-30T10:00:00Z"
            },
            {
              "id" => "msg-0002",
              "speaker" => { "id" => "asst-1" },
              "text" => "2 + 2 equals 4.",
              "timestamp" => "2026-04-30T10:00:05Z",
              "metadata" => {
                "provider" => "openai",
                "model" => "gpt-5.4",
                "edited" => true,
                "edit_history" => [
                  {
                    "at" => "2026-04-30T10:00:03Z",
                    "text" => "It is 4.",
                    "reason" => "regeneration"
                  }
                ],
                "tools" => [{ "name" => "calculator", "args" => { "expr" => "2+2" } }],
                "monadic_state" => {
                  "version" => "1",
                  "conversation_context" => {
                    "topics" => ["arithmetic"],
                    "people" => [],
                    "notes" => []
                  },
                  "app_specific" => {
                    "solved_problems" => ["2+2"]
                  }
                }
              }
            }
          ]
        )

        expect(described_class.valid?(data)).to be true
      end
    end

    context "with annotations" do
      it "accepts an empty annotations array" do
        data = base_conversation("annotations" => [])
        expect(described_class.valid?(data)).to be true
      end

      it "accepts a populated annotation with a message anchor" do
        data = base_conversation(
          "annotations" => [
            {
              "tier" => "rhetorical_move",
              "unit_type" => "message",
              "anchor" => { "message_id" => "msg-0001" },
              "label" => "argumentative_pivot",
              "annotator" => { "id" => "alice", "type" => "human" },
              "at" => "2026-04-30T11:00:00Z"
            }
          ]
        )
        expect(described_class.valid?(data)).to be true
      end

      it "accepts an annotation with a range anchor (turn / span)" do
        data = base_conversation(
          "annotations" => [
            {
              "tier" => "coreference",
              "unit_type" => "span",
              "anchor" => {
                "start_message_id" => "msg-0001",
                "end_message_id" => "msg-0002",
                "start_offset" => 0,
                "end_offset" => 3
              },
              "label" => "she_refers_to_emma"
            }
          ]
        )
        expect(described_class.valid?(data)).to be true
      end
    end
  end

  describe "rejects invalid input" do
    it "rejects unknown top-level fields" do
      data = base_conversation("totally_unknown_field" => 42)
      expect(described_class.valid?(data)).to be false
    end

    it "rejects a missing required field (license)" do
      data = base_conversation
      data["conversation_metadata"].delete("license")
      expect(described_class.valid?(data)).to be false
    end

    it "rejects a wrong format_version (only '1.0' is accepted in v1 schema)" do
      data = base_conversation("format_version" => "2.0")
      expect(described_class.valid?(data)).to be false
    end

    it "rejects a participant role outside the broad enum" do
      data = base_conversation(
        "participants" => [{ "id" => "x", "role" => "ghost" }],
        "messages" => []
      )
      expect(described_class.valid?(data)).to be false
    end

    it "rejects an edit_history reason outside the controlled vocabulary" do
      data = base_conversation(
        "messages" => [
          {
            "id" => "msg-0001",
            "speaker" => { "id" => "user-1" },
            "text" => "Hello",
            "metadata" => {
              "edited" => true,
              "edit_history" => [
                { "at" => "2026-04-30T10:00:00Z", "text" => "Hi", "reason" => "magic" }
              ]
            }
          }
        ]
      )
      expect(described_class.valid?(data)).to be false
    end

    it "rejects a monadic_state version other than '1'" do
      data = base_conversation(
        "messages" => [
          {
            "id" => "msg-0001",
            "speaker" => { "id" => "user-1" },
            "text" => "Hi",
            "metadata" => { "monadic_state" => { "version" => "2" } }
          }
        ]
      )
      expect(described_class.valid?(data)).to be false
    end
  end

  describe ".validate" do
    it "returns an empty array for a valid conversation" do
      expect(described_class.validate(base_conversation)).to eq([])
    end

    it "returns a non-empty error list when invalid" do
      data = base_conversation
      data["conversation_metadata"].delete("license")
      errors = described_class.validate(data)
      expect(errors).not_to be_empty
      expect(errors.first).to include("type", "data", "data_pointer")
    end
  end

  describe "constants" do
    it "exposes the format version that matches the schema's const" do
      schema_json = JSON.parse(File.read(described_class::SCHEMA_PATH))
      expect(schema_json.dig("properties", "format_version", "const"))
        .to eq(Monadic::Library::FORMAT_VERSION)
    end
  end
end
