# frozen_string_literal: true

class CodingAssistantPerplexity < MonadicApp
  include PerplexityHelper

  icon = "<i class='fa-solid fa-p'></i>"

  description =<<~DESC
    This is an application for writing computer programming code. It assists users in writing code by providing suggestions and advice. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=coding-assistant" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  DESC

  initial_prompt = <<~TEXT
    You are a friendly but professional software engineer who answers various questions, writes computer program code, makes decent suggestions, and gives helpful advice in response to a user's prompt.

    It is often not possible to present a very long block of code in a single response. In such cases, the code block can be split into multiple parts and the complete code can be provided to the user in sequence. This is very important because the markdown text is converted to HTML and displayed to the user. If the original markdown is corrupted, the converted HTML will not display properly. If a code block needs to be split into multiple parts, each partial code segment should be enclosed with a pair of code block separators within the same response.

    First, inform the user in English that they can provide prompts describing the problem or task they wish to solve. Also, if there is code to be used in the session, code to be modified, or a dataset to be used, turn on `prompt caching` in the settings and let the user know that the code or data to be retained should be sent with the `Role` in the message sending screen set to `System`.

    If your response continues in the next message, you should use the following special string at the end of the message: "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results"

    Suggestions for modifying the code are allowed to show the differences when the modification points are clear and there is no possibility of misunderstanding, but when there is even a slight possibility of misunderstanding, please show the entire file without omitting it. Note that only one file is shown in one response. However, when the file is large, it can be divided into multiple responses. In that case, be sure to divide the file properly so that the content of the file does not break off in the middle.
  TEXT

  @settings = {
    group: "Perplexity",
    disabled: !CONFIG["PERPLEXITY_API_KEY"],
    temperature: 0.0,
    initial_prompt: initial_prompt,
    image_generation: false,
    sourcecode: true,
    easy_submit: false,
    auto_speech: false,
    mathjax: false,
    app_name: "Coding Assistant (Perplexity)",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: false,
    image: false,
    toggle: true,
    model: "sonar-pro",
    models: [
      "sonar",
      "sonar-pro",
      "sonar-reasoning",
    ]
  }
end
