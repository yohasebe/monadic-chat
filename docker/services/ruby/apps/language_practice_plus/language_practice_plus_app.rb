class LanguagePracticePlus < MonadicApp
  def icon
    "<i class='fas fa-person-chalkboard'></i>"
  end

  def description
    "This is a language learning application where conversations start with the assistant's speech. The assistant's speech is played back in a synthesized voice. To speak, press the Enter key to start speech input and press Enter again to stop speech input. The assistant's response will include linguistic advice and the usual content. The language advice is presented only as text and not as text-to-speech."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly and experienced language teacher. You are adept at making conversations fun and informative, even when speaking with users who are not very proficient in the language. If the "target language" is unknown, please ask the user.

      Each time the user speaks, you respond to them, say something relevant to the ongoing topic, or ask a question, using emojis that express the topic or tone of the conversation.

      While you are responding to the user, you provide language advice. You correct grammar, check the user's tone of voice, and suggest better ways to say things if necessary. You can offer useful expressions relevant to the ongoing conversation if there are no grammar or vocabulary mistakes.

      The following JSON structure is used to respond to the user's message. The "message" contains your response to the user's message. The "context" contains two propertes: "target_lang" is the target language to practice, and "language_advice" is an array of pieces of your language advice to the user.

      - message: your response to the user's message
      - context:
        - target_lang: the target language to practice
        - language_advice: pieces of your language advice to the user
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-mini",
      "temperature": 0.4,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": true,
      "auto_speech": true,
      "app_name": "Language Practice +",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "image": true,
      "pdf": false,
      "monadic": true,
      "response_format": {
        type: "json_schema",
        json_schema: {
          name: "language_practice_plus_response",
          schema: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Your response to the user's message."
              },
              context: {
                type: "object",
                properties: {

                  language_advice: {
                    type: "array",
                    items: {
                      type: "string"
                    },
                    description: "An array of pieces of your language advice to the user."
                  }
                },
                required: ["language_advice"],
                additionalProperties: false
              }
            },
            required: ["message", "context"]
          },
          strict: true
        }
      }
    }
  end
end
