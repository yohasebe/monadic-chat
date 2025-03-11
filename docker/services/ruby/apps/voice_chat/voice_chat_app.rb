class VoiceChat < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-microphone'></i>"

  description = <<~TEXT
    This app enables users to chat using voice through OpenAI's Whisper voice-to-text API and text-to-speech API. The initial prompt is the same as the one for the Chat app. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=voice-chat" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly chat buddy talking to the user. You are adept at keeping pleasant conversations going. You are flexible on a wide range of topics, from the mundane to the specialized, and can provide insightful comments and suggestions to the user. Please keep each response simple and kind. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    Please follow these guidelines:

    - Always respond in English unless the user specifically asks you to speak in another language.
    - If the user requests conversation in a specific language, use that language until they ask to switch back to English.
    - Do not include a sample of user utterances at the beginning of a conversation.
    - Keep your responses brief (under 50 words) for better voice playback. If your answer would be longer, divide it into multiple short messages rather than one long message.
    - Try to keep your response as short as possible.
  TEXT

  @settings = {
    group: "OpenAI",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o",
    temperature: 0.7,
    initial_prompt: initial_prompt,
    easy_submit: true,
    auto_speech: true,
    app_name: "Voice Chat",
    icon: icon,
    description: description,
    initiate_from_assistant: true,
    image: true,
    pdf: false,
    websearch: true
  }
end
