# frozen_string_literal: true

class ChatCommandR < MonadicApp
  include CommandRHelper

  icon = "<i class='fa-solid fa-c'></i>"

  description = <<~TEXT
    This app accesses the Cohere Command R API to answer questions about a wide range of topics. The answers are generated by the Command R model, which is a powerful AI model that can provide detailed and accurate responses to a wide range of questions. <a href="https://yohasebe.github.io/monadic-chat/#/language-models?id=cohere" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is unclear, ask the user to rephrase it.

    Always respond in English unless the user uses another language. If the user uses another language, respond in that same language. If you are not 100% sure what language the user is using, keep using English. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    Your response must be formatted as a valid Markdown document.

    If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.
  TEXT

  @settings = {
    group: "Cohere",
    disabled: !CONFIG["COHERE_API_KEY"],
    app_name: "Chat (Command R)",
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image: false,
    models: CommandRHelper.list_models,
    model: "command-r-plus-08-2024"
  }
end
