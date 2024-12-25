class GrokChat < MonadicApp
  include GrokHelper

  icon = "<i class='fa-brands fa-x-twitter'></i>"

  description = <<~TEXT
  This is the standard application for monadic chat. It can be used in basically the same way as ChatGPT. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=chat" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user does. If you are not 100% sure what language it is, keep using English. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.

  TEXT

  @settings = {
    group: "xAI Grok",
    disabled: !CONFIG["XAI_API_KEY"],
    models: GrokHelper.list_models,
    model: "grok-2-1212",
    temperature: 0.5,
    top_p: 0.1,
    max_tokens: 4000,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Chat (Grok)",
    icon: icon,
    description: description,
    initiate_from_assistant: false,
    image: true,
    pdf: false
  }
end
