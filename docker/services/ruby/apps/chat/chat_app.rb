class Chat < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-comments'></i>"

  description = <<~TEXT
    This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT.
  TEXT

  initial_prompt = <<~TEXT
      You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.
  TEXT

  @settings = {
    model: "gpt-4o-mini",
    temperature: 0.5,
    top_p: 0.0,
    max_tokens: 4000,
    context_size: 20,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Chat",
    icon: icon,
    description: description,
    initiate_from_assistant: false,
    image: true,
    pdf: false
  }
end
