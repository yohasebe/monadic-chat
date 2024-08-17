# frozen_string_literal: true

require_relative "./claude_helper"

class ChatWithClaude < MonadicApp
  include ClaudeHelper

  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    "This app accesses the Anthropic API to answer questions about a wide range of topics."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.
    TEXT
    text.strip
  end

  def settings
    {
      "disabled": !CONFIG["ANTHROPIC_API_KEY"],
      "app_name": "▹ Anthropic Claude (Chat)",
      "context_size": 100,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "toggle": true,
      "image": true,
      "models": [
        "claude-3-5-sonnet-20240620",
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307"
      ]
    }
  end
end
