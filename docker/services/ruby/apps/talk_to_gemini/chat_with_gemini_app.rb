# frozen_string_literal: true

class ChatWithGemini < MonadicApp
  include GeminiHelper

  icon = "<i class='fab fa-google'></i>"

  description = <<~TEXT
    This app accesses the Google Gemini API to answer questions about a wide range of topics.
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear, ask the user to rephrase it.

    Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response. Use Japanese, for example, if the user's input is in Japanese.

    Your response must be formatted as a valid Markdown document.

    If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.
  TEXT

  @settings = {
    group: "Google",
    disabled: !CONFIG["GEMINI_API_KEY"],
    app_name: "Google Gemini (Chat)",
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image: true,
    models: GeminiHelper.list_models,
    model: "gemini-1.5-flash"
  }
end
