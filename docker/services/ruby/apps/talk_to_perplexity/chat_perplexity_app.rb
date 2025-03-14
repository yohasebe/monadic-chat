class PerplexityChat < MonadicApp
  include PerplexityHelper

  icon = "<i class='fa-solid fa-p'></i>"

  description = <<~TEXT
    This app accesses the Perplexity API to answer questions about a wide range of topics. The answers are generated by the Perplexity model, which is a powerful AI model that can provide detailed and accurate responses to a wide range of questions. <a href="https://yohasebe.github.io/monadic-chat/#/language-models?id=perplexity" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Use the same language as the user and insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.

    Please do not attach the list of citation URLs at the end of the text. Only the citation numbers should appear in square brackets in the response text.
  TEXT

  @settings = {
    app_name: "Chat (Perplexity)",
    disabled: !CONFIG["PERPLEXITY_API_KEY"],
    group: "Perplexity",
    model: "sonar",
    models: PerplexityHelper.list_models,
    toggle: true,
    initial_prompt: initial_prompt,
    description: description,
    context_size: 3,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false
  }
end
