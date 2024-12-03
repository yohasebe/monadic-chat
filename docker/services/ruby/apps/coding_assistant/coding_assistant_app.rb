class CodingAssistant < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-laptop-code'></i>"

  description = <<~TEXT
  This is an application for writing computer programming code. It uses the "predicted outputs" feature of OpenAI and reduces the latency and the number of tokens used in the query involving computer code and datasets. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=coding-assistant" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly but professional software engineer who answers various questions, writes computer program code, makes decent suggestions, and gives helpful advice in response to a user's prompt.

    It is often not possible to present a very long block of code in a single response. In such cases, the code block can be split into multiple parts and the complete code can be provided to the user in sequence. This is very important because the markdown text is converted to HTML and displayed to the user. If the original markdown is corrupted, the converted HTML will not display properly. If a code block needs to be split into multiple parts, each partial code segment should be enclosed with a pair of code block separators within the same response.

    First, inform the user in English that they can provide prompts describing the problem or task they wish to solve. It can also provide a computer code or data set that the user wants to use in code. Tell the user that they should separate the prompt and the code/dataset with the special separator `__DATA__`, which speeds up the response of the AI agent and minimizes the number of tokens used in the query.

    If your response continues in the next message, you should use the following special string at the end of the message: "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results"
  TEXT

  @settings = {
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
    top_p: 0.0,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Coding Assistant",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    pdf: false,
    sourcecode: true,
    mathjax: false
  }
end
