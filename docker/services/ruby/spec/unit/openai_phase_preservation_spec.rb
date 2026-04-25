# frozen_string_literal: true

require_relative "../spec_helper"

# GPT-5.5 introduced a `phase` field on assistant output items that must be
# preserved when manually managing state via output items (not previous_response_id).
# See: https://developers.openai.com/api/docs/guides/latest-model#behavioral-changes
#
# Monadic Chat uses manual state management for multi-provider compatibility,
# so we capture full original items at output_item.done and replay them
# unchanged on the next turn (with the response-specific `id` removed).
RSpec.describe "OpenAI phase parameter preservation" do
  describe "state capture for function_call items" do
    it "stores the full raw_item including phase on output_item.added" do
      tools_state = {}
      item = {
        "id" => "fc_abc123",
        "type" => "function_call",
        "name" => "get_weather",
        "call_id" => "call_xyz",
        "arguments" => "{}",
        "phase" => "primary"
      }

      # Mirror of the capture logic in openai_helper.rb (response.output_item.added)
      item_id = item["id"]
      tools_state[item_id] ||= {}
      tools_state[item_id]["name"] = item["name"]
      tools_state[item_id]["call_id"] = item["call_id"]
      tools_state[item_id]["arguments"] ||= ""
      tools_state[item_id]["raw_item"] = item.dup

      expect(tools_state[item_id]["raw_item"]).to include("phase" => "primary")
      expect(tools_state[item_id]["raw_item"]).to include("name" => "get_weather")
    end

    it "updates raw_item on output_item.done with the completed version" do
      tools_state = { "fc_abc123" => { "raw_item" => { "id" => "fc_abc123", "type" => "function_call", "phase" => "primary", "arguments" => "" } } }
      done_item = {
        "id" => "fc_abc123",
        "type" => "function_call",
        "name" => "get_weather",
        "call_id" => "call_xyz",
        "arguments" => '{"location":"Tokyo"}',
        "phase" => "primary"
      }

      tools_state["fc_abc123"]["raw_item"] = done_item.dup

      expect(tools_state["fc_abc123"]["raw_item"]["arguments"]).to eq('{"location":"Tokyo"}')
      expect(tools_state["fc_abc123"]["raw_item"]["phase"]).to eq("primary")
    end
  end

  describe "state capture for message items" do
    it "appends full message item including phase to message_items_raw" do
      message_items_raw = []
      item = {
        "id" => "msg_xyz789",
        "type" => "message",
        "role" => "assistant",
        "content" => [{ "type" => "output_text", "text" => "hello" }],
        "phase" => "primary"
      }

      message_items_raw << item.dup

      expect(message_items_raw.size).to eq(1)
      expect(message_items_raw.first["phase"]).to eq("primary")
      expect(message_items_raw.first["type"]).to eq("message")
    end
  end

  describe "replay logic for function_call output items" do
    # Mirror of the replay branch in convert_to_responses_api_body (openai_helper.rb)
    def replay_function_call(tool_call)
      raw_item = tool_call["raw_item"] || tool_call[:raw_item]
      if raw_item.is_a?(Hash)
        normalized = raw_item.transform_keys { |k| k.to_s }
        normalized["type"] ||= "function_call"
        normalized.delete("id")
        normalized
      else
        call_id = tool_call["id"] || tool_call[:id]
        fc_id = call_id.start_with?("fc_") ? call_id : "fc_#{SecureRandom.hex(16)}"
        {
          "type" => "function_call",
          "id" => fc_id,
          "call_id" => call_id,
          "name" => tool_call.dig("function", "name"),
          "arguments" => tool_call.dig("function", "arguments")
        }
      end
    end

    it "preserves phase when raw_item is available" do
      tool_call = {
        "id" => "call_xyz",
        "function" => { "name" => "get_weather", "arguments" => '{"location":"Tokyo"}' },
        "raw_item" => {
          "id" => "fc_abc123",
          "type" => "function_call",
          "name" => "get_weather",
          "call_id" => "call_xyz",
          "arguments" => '{"location":"Tokyo"}',
          "phase" => "primary"
        }
      }

      result = replay_function_call(tool_call)

      expect(result["phase"]).to eq("primary")
      expect(result).not_to have_key("id")  # response-specific id is stripped
      expect(result["type"]).to eq("function_call")
      expect(result["call_id"]).to eq("call_xyz")
      expect(result["arguments"]).to eq('{"location":"Tokyo"}')
    end

    it "preserves any future unknown fields when raw_item is available" do
      tool_call = {
        "id" => "call_xyz",
        "function" => { "name" => "get_weather", "arguments" => "{}" },
        "raw_item" => {
          "type" => "function_call",
          "call_id" => "call_xyz",
          "name" => "get_weather",
          "arguments" => "{}",
          "phase" => "primary",
          "future_field" => "future_value"
        }
      }

      result = replay_function_call(tool_call)

      expect(result["future_field"]).to eq("future_value")
      expect(result["phase"]).to eq("primary")
    end

    it "falls back to constructed item when raw_item is absent" do
      tool_call = {
        "id" => "call_xyz",
        "function" => { "name" => "get_weather", "arguments" => "{}" }
      }

      result = replay_function_call(tool_call)

      expect(result["type"]).to eq("function_call")
      expect(result["call_id"]).to eq("call_xyz")
      expect(result["name"]).to eq("get_weather")
      expect(result["arguments"]).to eq("{}")
      expect(result).not_to have_key("phase")
    end
  end

  describe "replay logic for assistant message items" do
    def replay_message(msg, fallback_text)
      message_items_payload = msg["message_items"] || msg[:message_items]
      if message_items_payload && !message_items_payload.empty?
        Array(message_items_payload).map do |entry|
          next unless entry.is_a?(Hash)
          normalized = entry.transform_keys { |k| k.to_s }
          normalized.delete("id")
          normalized
        end.compact
      else
        [{
          "type" => "message",
          "role" => "assistant",
          "content" => [{ "type" => "output_text", "text" => fallback_text.to_s }]
        }]
      end
    end

    it "preserves phase when message_items is available" do
      msg = {
        "role" => "assistant",
        "message_items" => [
          {
            "id" => "msg_xyz789",
            "type" => "message",
            "role" => "assistant",
            "content" => [{ "type" => "output_text", "text" => "hello" }],
            "phase" => "primary"
          }
        ]
      }

      result = replay_message(msg, "fallback")

      expect(result.size).to eq(1)
      expect(result.first["phase"]).to eq("primary")
      expect(result.first).not_to have_key("id")
    end

    it "falls back to constructed item when message_items is absent" do
      msg = { "role" => "assistant", "content" => "hello" }

      result = replay_message(msg, "hello")

      expect(result.size).to eq(1)
      expect(result.first["type"]).to eq("message")
      expect(result.first["role"]).to eq("assistant")
      expect(result.first).not_to have_key("phase")
    end
  end
end
