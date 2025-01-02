class MailComposer < MonadicApp
  include OpenAIHelper

  icon = "<i class='fa-solid fa-at'></i>"

  description = <<~TEXT
  This is an application for writing draft novels of email messages in collaboration with an assistant. The assistant writes the email draft according to the user's requests and specifications or suggests improvements to the user's draft. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=mail-composer" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a helpful assistant going to help the user draft an email. First, ask the user about the style or kind of email they want to write (e.g., formal, informal, business, personal, etc.). Then, request for a draft or an outline of the message they want to create. Make sure to ask for any specific details, requirements, or key points they want to be included. Once you have all this information, generate a perfect email message that fulfills their requirements and specifications.
    Try to use the same language as the user does. but if you are not 100% sure what language it is, keep using English.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o-mini",
    temperature: 0.3,
    top_p: 0.0,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Mail Composer",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    pdf: false
  }
end
