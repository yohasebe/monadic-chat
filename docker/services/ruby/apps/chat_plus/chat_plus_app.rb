class ChatPlus < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-comments'></i>"

  description = <<~TEXT
    This is a chat application that presents the reasoning behind the AI's responses. The AI also
    keeps track of topics, people, and notes mentioned in the conversation. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=chat-plus" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a friendly and professional consultant with real-time, up-to-date information about almost anything. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Try to use the same language as the user does. but if you are not 100% sure what language it is, keep using English. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

    While keeping the conversation going, you take notes on various aspects of the conversation, such as the topics discussed, the people mentioned, and other important information provided by the user. You should update these notes as the conversation progresses.

    Your response should be contained in a JSON object with the following structure:
    - "message": Your response to the user
    - "context": An object containing the following properties:
      - "reasoning": The reasoning and thought process behind your response
      - "topics": A list of topics ever discussed in the whole conversation
      - "people": A list of people and their relationships ever mentioned in the whole conversation
      - "notes": A list of the user's preferences and other important information including important dates, locations, and events ever mentioned in the whole conversation and should be remembered throughout the conversation

    You should update the "summary", "topics", "people", and "preferences" properties of the "context" object as the conversation progresses. Every time you respond, you consider these items carried over from the previous conversation.

      Remember that the list items in the context object should be "accumulated" do not remove any items from the list unless the user explicitly asks you to do so.
  TEXT

  @settings = {
    model: "gpt-4o-2024-11-20",
    temperature: 0.5,
    top_p: 0.0,
    max_tokens: 4000,
    context_size: 100,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Chat Plus",
    icon: icon,
    description: description,
    initiate_from_assistant: false,
    image: true,
    pdf: false,
    monadic: true,
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "chat_monadic_response",
        schema: {
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "The response message to the user."
            },
            context: {
              type: "object",
              properties: {
                summary: {
                  type: "string",
                  description: "A summary of the conversation so far."
                },
                topics: {
                  type: "array",
                  items: {
                    type: "string",
                    description: "A list of topics discussed in the conversation."
                  }
                },
                people: {
                  type: "array",
                  items: {
                    type: "string",
                    description: "A list of people and their relationships mentioned in the conversation."
                  }
                },
                notes: {
                  type: "array",
                  items: {
                    type: "string",
                    description: "A list of user preferences and other important information."
                  }
                }
              },
              required: ["summary", "topics", "people", "notes"],
              additionalProperties: false
            }
          },
          required: ["message", "context"],
          additionalProperties: false
        },
        strict: true
      }
    }
  }
end
