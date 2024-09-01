# frozen_string_literal: true

class ChatWithMistral < MonadicApp
  include MistralHelper

  icon = "<i class='fa-solid fa-m'></i>"

  description = <<~TEXT
    This app accesses the Mistral AI API to answer questions about a wide range of topics.
  TEXT

  initial_prompt = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it.
  TEXT

  prompt_suffix = <<~TEXT
    "Use the same language as the user and insert an ascii emoji that you deem appropriate for the user's input at the beginning of your response. When you use emoji, it should be something like 😀 instead of `:smiley:`. Avoid repeating words or phrases in your responses."
  TEXT

  @settings = {
    disabled: !CONFIG["MISTRAL_API_KEY"],
    temperature: 0.7,  # Adjusted temperature
    top_p: 1.0,        # Adjusted top_p
    context_size: 20,
    initial_prompt: initial_prompt,
    prompt_suffix: prompt_suffix,
    image_generation: false,
    sourcecode: true,
    easy_submit: false,
    auto_speech: false,
    mathjax: false,
    app_name: "▹ Mistral AI (Chat)",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: false,
    image: false,
    toggle: false,
    models: MistralHelper.list_models,
    model: "mistral-large-latest"
  }
end
