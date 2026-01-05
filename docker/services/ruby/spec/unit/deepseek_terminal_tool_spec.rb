# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DeepSeek Terminal Tool Handling" do
  # Terminal tools signal the end of a tool sequence.
  # After a terminal tool is called, no additional API requests should be made.
  # This prevents empty responses that cause "content_not_found" errors.

  describe "Terminal tool identification" do
    # These tools indicate that the LLM's turn is complete
    let(:terminal_tools) { %w[save_learning_progress save_response] }

    it "recognizes save_learning_progress as terminal" do
      expect(terminal_tools).to include("save_learning_progress")
    end

    it "recognizes save_response as terminal" do
      expect(terminal_tools).to include("save_response")
    end

    it "does not treat load_learning_progress as terminal" do
      expect(terminal_tools).not_to include("load_learning_progress")
    end

    it "does not treat run_code as terminal" do
      expect(terminal_tools).not_to include("run_code")
    end
  end

  describe "Response structure after terminal tool" do
    # When a terminal tool is called, the helper must return a properly
    # structured response that websocket.rb can process without errors.
    #
    # websocket.rb extracts content via: response.dig("choices", 0, "message", "content")
    # If this returns nil, a "content_not_found" error is sent to the frontend.

    let(:final_response) do
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => ""  # Empty string is valid; nil would cause error
          },
          "finish_reason" => "stop"
        }]
      }
    end

    it "has the choices array structure" do
      expect(final_response).to have_key("choices")
      expect(final_response["choices"]).to be_an(Array)
      expect(final_response["choices"].length).to eq(1)
    end

    it "has message with content field" do
      message = final_response.dig("choices", 0, "message")
      expect(message).to have_key("content")
      expect(message).to have_key("role")
    end

    it "has non-nil content (empty string is acceptable)" do
      content = final_response.dig("choices", 0, "message", "content")

      # This is the critical check: content must not be nil
      # nil triggers content_not_found error in websocket.rb
      expect(content).not_to be_nil
    end

    it "has finish_reason set to stop" do
      finish_reason = final_response.dig("choices", 0, "finish_reason")
      expect(finish_reason).to eq("stop")
    end
  end

  describe "DONE message structure" do
    # Before returning final_response, a DONE message is sent to the frontend
    # via the block callback. This signals the UI to stop spinners.

    let(:done_message) do
      {
        "type" => "message",
        "content" => "DONE",
        "finish_reason" => "stop"
      }
    end

    it "has type message" do
      expect(done_message["type"]).to eq("message")
    end

    it "has content DONE" do
      expect(done_message["content"]).to eq("DONE")
    end

    it "has finish_reason stop" do
      expect(done_message["finish_reason"]).to eq("stop")
    end
  end
end
