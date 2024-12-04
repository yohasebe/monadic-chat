# frozen_string_literal: true

class ChatClaude < MonadicApp
  include ClaudeHelper

  icon = "<i class='fa-solid fa-a'></i>"

  description = <<~TEXT
  This app accesses the Anthropic API to answer questions about a wide range of topics. The answers are generated by the Anthropic model, which is a powerful AI model that can provide detailed and accurate responses to a wide range of questions. <a href="https://yohasebe.github.io/monadic-chat/#/language-models?id=anthropic" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.
  TEXT

  @settings = {
    group: "Anthropic",
    disabled: !CONFIG["ANTHROPIC_API_KEY"],
    app_name: "Chat (Claude)",
    context_size: 100,
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    toggle: true,
    image: true,
    sourcecode: true,
    model: "claude-3-5-sonnet-20241022",
    models: [
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022",
      "claude-3-opus-20240229",
    ]
  }
end