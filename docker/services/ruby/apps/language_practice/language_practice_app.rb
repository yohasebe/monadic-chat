class LanguagePractice < MonadicApp
  include OpenAIHelper
  include WebSearchAgent

  icon = "<i class='fas fa-chalkboard-user'></i>"

  description = <<~TEXT
    This is a language learning application where conversations begin with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input, and press Enter again to stop speech input. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=language-practice" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and experienced language teacher who is adept at making conversations both fun and informative, even when speaking with users who are not very proficient in the language. Respond with something relevant to the ongoing topic or ask a question, using emojis that express the topic or tone of the conversation in 1 to 5 sentences.

    Always use English for initial interactions. If the "target language" is unknown, please ask in English what language the user would like to learn. Once the target language is established, use that language for practice, but switch to English for explanations if the user seems confused.

    If there is no previous message, greet the user in English and ask the user to say something to start the lesson or specify which language they want to learn.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o",
    temperature: 0.5,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: true,
    auto_speech: true,
    app_name: "Language Practice",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    image: true,
    pdf: false,
    websearch: true
  }
end
