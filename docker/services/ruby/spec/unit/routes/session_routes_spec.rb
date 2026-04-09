# frozen_string_literal: true

require "spec_helper"
require "json"
require "securerandom"

RSpec.describe "Session Routes Logic" do
  describe "Monadic state export serialization" do
    it "converts symbol keys to string keys for JSON" do
      monadic_state = {
        "ChatOpenAI" => {
          topics: { data: ["topic1", "topic2"], version: 3, updated_at: "2026-03-01" },
          notes: { data: ["note1"], version: 1, updated_at: "2026-03-02" }
        }
      }

      serializable_state = monadic_state.each_with_object({}) do |(app_key, app_data), result|
        next if [:conversation_context, :context_schema, "conversation_context", "context_schema"].include?(app_key)

        if app_data.is_a?(Hash)
          result[app_key.to_s] = app_data.each_with_object({}) do |(state_key, state_entry), app_result|
            next unless state_entry.is_a?(Hash) && state_entry.key?(:data)
            app_result[state_key.to_s] = {
              "data" => state_entry[:data],
              "version" => state_entry[:version],
              "updated_at" => state_entry[:updated_at]
            }
          end
        end
      end

      expect(serializable_state).to have_key("ChatOpenAI")
      expect(serializable_state["ChatOpenAI"]).to have_key("topics")
      expect(serializable_state["ChatOpenAI"]["topics"]["data"]).to eq(["topic1", "topic2"])
      expect(serializable_state["ChatOpenAI"]["topics"]["version"]).to eq(3)
    end

    it "skips conversation_context and context_schema keys" do
      monadic_state = {
        conversation_context: { topics: ["a"] },
        context_schema: { field: "topics" },
        "ChatOpenAI" => {
          notes: { data: ["note"], version: 1, updated_at: "now" }
        }
      }

      serializable_state = monadic_state.each_with_object({}) do |(app_key, app_data), result|
        next if [:conversation_context, :context_schema, "conversation_context", "context_schema"].include?(app_key)
        if app_data.is_a?(Hash)
          result[app_key.to_s] = app_data.each_with_object({}) do |(state_key, state_entry), app_result|
            next unless state_entry.is_a?(Hash) && state_entry.key?(:data)
            app_result[state_key.to_s] = { "data" => state_entry[:data] }
          end
        end
      end

      expect(serializable_state).not_to have_key("conversation_context")
      expect(serializable_state).not_to have_key("context_schema")
      expect(serializable_state).to have_key("ChatOpenAI")
    end

    it "skips state entries without :data key" do
      monadic_state = {
        "App" => {
          valid: { data: [1], version: 1, updated_at: "now" },
          invalid: { some_other_key: "value" }
        }
      }

      serializable_state = monadic_state.each_with_object({}) do |(app_key, app_data), result|
        next if [:conversation_context, :context_schema].include?(app_key)
        if app_data.is_a?(Hash)
          result[app_key.to_s] = app_data.each_with_object({}) do |(state_key, state_entry), app_result|
            next unless state_entry.is_a?(Hash) && state_entry.key?(:data)
            app_result[state_key.to_s] = { "data" => state_entry[:data] }
          end
        end
      end

      expect(serializable_state["App"]).to have_key("valid")
      expect(serializable_state["App"]).not_to have_key("invalid")
    end

    it "includes session_context when present" do
      monadic_state = {
        conversation_context: { "topics" => ["AI"], "notes" => ["important"] }
      }

      conversation_context = monadic_state[:conversation_context] || monadic_state["conversation_context"]
      response_data = { success: true, monadic_state: {} }
      response_data[:session_context] = conversation_context if conversation_context

      expect(response_data[:session_context]).to eq({ "topics" => ["AI"], "notes" => ["important"] })
    end

    it "returns nil monadic_state when session has none" do
      response = { success: true, monadic_state: nil }
      expect(response[:monadic_state]).to be_nil
    end
  end

  describe "Import processing" do
    it "forces initiate_from_assistant and auto_speech to false" do
      json_data = {
        "parameters" => {
          "app_name" => "ChatOpenAI",
          "initiate_from_assistant" => true,
          "auto_speech" => true
        },
        "messages" => []
      }

      imported_params = json_data["parameters"].dup
      imported_params["initiate_from_assistant"] = false
      imported_params["auto_speech"] = false

      expect(imported_params["initiate_from_assistant"]).to be false
      expect(imported_params["auto_speech"]).to be false
    end

    it "extracts system message as initial_prompt" do
      json_data = {
        "parameters" => { "app_name" => "ChatOpenAI" },
        "messages" => [
          { "role" => "system", "text" => "You are a helpful assistant." },
          { "role" => "user", "text" => "Hello" }
        ]
      }

      params = json_data["parameters"].dup
      if json_data["messages"].first && json_data["messages"].first["role"] == "system"
        params["initial_prompt"] = json_data["messages"].first["text"]
      end

      expect(params["initial_prompt"]).to eq("You are a helpful assistant.")
    end

    it "does not set initial_prompt when first message is not system" do
      json_data = {
        "parameters" => { "app_name" => "ChatOpenAI" },
        "messages" => [
          { "role" => "user", "text" => "Hello" }
        ]
      }

      params = json_data["parameters"].dup
      if json_data["messages"].first && json_data["messages"].first["role"] == "system"
        params["initial_prompt"] = json_data["messages"].first["text"]
      end

      expect(params).not_to have_key("initial_prompt")
    end

    it "validates required fields" do
      missing_params = { "messages" => [] }
      missing_messages = { "parameters" => {} }
      valid = { "parameters" => {}, "messages" => [] }

      expect(missing_params["parameters"] && missing_params["messages"]).to be_falsy
      expect(missing_messages["parameters"] && missing_messages["messages"]).to be_falsy
      expect(valid["parameters"] && valid["messages"]).to be_truthy
    end

    it "preserves token counts on import" do
      msg = { "role" => "user", "text" => "Hello", "tokens" => 5 }

      message_obj = { "role" => msg["role"], "text" => msg["text"] }
      message_obj["tokens"] = msg["tokens"].to_i if msg.key?("tokens")

      expect(message_obj["tokens"]).to eq(5)
    end

    it "does not add tokens key when not present in source" do
      msg = { "role" => "user", "text" => "Hello" }

      message_obj = { "role" => msg["role"], "text" => msg["text"] }
      message_obj["tokens"] = msg["tokens"].to_i if msg.key?("tokens")

      expect(message_obj).not_to have_key("tokens")
    end

    it "generates mid when missing" do
      allow(SecureRandom).to receive(:hex).with(4).and_return("abcd1234")

      msg = { "role" => "user", "text" => "Hello" }
      mid = msg["mid"] || SecureRandom.hex(4)

      expect(mid).to eq("abcd1234")
    end

    it "preserves existing mid" do
      msg = { "role" => "user", "text" => "Hello", "mid" => "existing_id" }
      mid = msg["mid"] || SecureRandom.hex(4)

      expect(mid).to eq("existing_id")
    end

    it "restores monadic_state with proper key transformation" do
      import_state = {
        "ChatOpenAI" => {
          "topics" => {
            "data" => ["topic1"],
            "version" => "2",
            "updated_at" => "2026-03-01"
          }
        }
      }

      restored = import_state.transform_keys(&:to_s).each_with_object({}) do |(app_key, app_data), result|
        result[app_key] = app_data.transform_keys(&:to_s).each_with_object({}) do |(state_key, state_entry), app_result|
          app_result[state_key] = {
            data: state_entry["data"],
            version: state_entry["version"].to_i,
            updated_at: state_entry["updated_at"]
          }
        end
      end

      expect(restored["ChatOpenAI"]["topics"][:data]).to eq(["topic1"])
      expect(restored["ChatOpenAI"]["topics"][:version]).to eq(2)
    end

    it "preserves thinking and images fields" do
      msg = {
        "role" => "assistant",
        "text" => "Response",
        "thinking" => "Internal reasoning",
        "images" => ["img1.png"]
      }

      message_obj = { "role" => msg["role"], "text" => msg["text"] }
      message_obj["thinking"] = msg["thinking"] if msg["thinking"]
      message_obj["images"] = msg["images"] if msg["images"]

      expect(message_obj["thinking"]).to eq("Internal reasoning")
      expect(message_obj["images"]).to eq(["img1.png"])
    end

    it "skips messages without role or text" do
      messages = [
        { "text" => "No role" },
        { "role" => "user" },
        { "role" => "user", "text" => "Valid" }
      ]

      processed = messages.map do |msg|
        next unless msg["role"] && msg["text"]
        { "role" => msg["role"], "text" => msg["text"] }
      end.compact

      expect(processed.length).to eq(1)
      expect(processed.first["text"]).to eq("Valid")
    end

    it "deduplicates messages" do
      messages = [
        { "role" => "user", "text" => "Hello", "mid" => "a" },
        { "role" => "user", "text" => "Hello", "mid" => "a" },
        { "role" => "user", "text" => "World", "mid" => "b" }
      ]

      unique = messages.uniq
      expect(unique.length).to eq(2)
    end
  end
end
