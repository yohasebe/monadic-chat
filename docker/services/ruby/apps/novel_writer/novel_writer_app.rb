class NovelWriter < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-book'></i>"

  description = <<~TEXT
    Craft a novel with engaging characters, vivid descriptions, and compelling plots. Develop the story based on user prompts, maintaining coherence and flow.
  TEXT

  prompt_suffix = <<~TEXT
    Remember you are supposed to write a novel, not a summary, synopsis, or outline. It is not a good idea to let the plot move too fast. Stick to the good old rule of "show, don't tell."
  TEXT

  initial_prompt = <<~TEXT
    You are a skilled and imaginative author tasked with writing a novel. To begin, please ask the user for the necessary information to develop the novel, such as the setting, characters, time period, genre, the total number of words or characters they plan to write, and the language used. Once you have this information, start crafting the story.

    You can run the function `count_number_of_words` or `count_number_of_chars` For novels written in a language where whitespace is not used to separate words, use the `count_number_of_chars` function. Otherwise, use the `count_number_of_words` function. The argument for these functions is the text you want to count. You can use these functions to keep track of the number of words or characters written in the novel.

    As the story progresses, the user will provide prompts suggesting the next event, a topic of conversation between characters, or a summary of the plot that develops upon your inquiry. You are expected
    to weave these prompts seamlessly into the narrative, maintaining the coherence and flow of the story.

    Make sure to include the ideas and suggestions provided by the user in the story so that your paragraphs will be coherent and engaging by themselves.

    Remember to create well-developed characters, vivid descriptions, and engaging dialogue. The plot should be compelling, with elements of conflict, suspense, and resolution. Be prepared to adapt the story based on the user's prompts, and ensure that each addition aligns with the overall plot and contributes to the development of the story.

    Your response is structured in a JSON object. Set "message" to the paragraph that advances the story based on the user's prompt. The contents of the "context" are instructed below.

    INSTRUCTIONS:
    - "grand_plot" is a brief description of the overarching plot of the novel.
    - "total_text_amount" is the number of words or characters the user plans to write for the novel.
    - "text_amount_so_far" holds the current number of words or characters written in the novel.
    - "language" is the language used in the novel.
    - "summary_so_far" is a summary of the story up to the current point, including the main events, characters, and themes.
    - "progress" is the current progress of the novel, such as the percentage of completion.
    - "characters" is a dictionary that contains the characters that appear in the novel. Each character has a name and its specification and the role are provided in the dictionary.
    - "inquiry" is a prompt for the user to provide the next event, a topic of conversation between characters, or a summary of the plot that develops.
  TEXT

  @settings = {
    model: "gpt-4o-2024-11-20",
    temperature: 0.5,
    top_p: 0.0,
    initial_prompt: initial_prompt,
    prompt_suffix: prompt_suffix,
    easy_submit: false,
    auto_speech: false,
    app_name: "Novel Writer",
    description: description,
    icon: icon,
    initiate_from_assistant: true,
    pdf: false,
    image: true,
    monadic: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "count_num_of_words",
          description: "Count the number of words in a given text.",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "The text to count the number of words."
              }
            },
            required: ["count_num_of_words"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "count_num_of_chars",
          description: "Count the number of characters in a given text.",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "The text to count the number of characters."
              }
            },
            required: ["count_num_of_chars"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "novel_writer_response",
        schema: {
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "The text that advances the story based on the user's prompt."
            },
            context: {
              type: "object",
              properties: {
                grand_plot: {
                  type: "string",
                  description: "A brief description of the overarching plot of the novel."
                },
                total_text_amount: {
                  type: "object",
                  properties: {
                    item: {
                      anyOf: [
                        {
                          name: "total_number_of_words",
                          type: "integer"
                        },
                        {
                          name: "total_number_of_chars",
                          type: "integer"
                        }
                      ]
                    }
                  },
                  required: ["item"],
                  additionalProperties: false
                },
                text_amount_so_far: {
                  type: "object",
                  properties: {
                    item: {
                      anyOf: [
                        {
                          name: "number_of_words_so_far",
                          type: "integer"
                        },
                        {
                          name: "number_of_chars_so_far",
                          type: "integer"
                        }
                      ]
                    }
                  },
                  required: ["item"],
                  additionalProperties: false
                },
                language: {
                  type: "string",
                  description: "The language used in the novel."
                },
                summary_so_far: {
                  type: "string",
                  description: "A summary of the story up to the current point, including the main events, characters, and themes."
                },
                characters: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      name: {
                        type: "string",
                        description: "The name of the character."
                      },
                      specification: {
                        type: "string",
                        description: "The characteristics of the character."
                      },
                      role: {
                        type: "string",
                        description: "The role of the character in the novel."
                      }
                    },
                    required: ["name", "specification", "role"],
                    additionalProperties: false
                  }
                },
                inquiry: {
                  type: "object",
                  properties: {
                    prompt: {
                      type: "string",
                      description: "The prompt for the user to provide the next event, a topic of conversation between characters, or a summary of the plot that develops."
                    }
                  },
                  required: ["prompt"],
                  additionalProperties: false
                }
              },
              required: ["grand_plot",
                         "total_text_amount",
                         "text_amount_so_far",
                         "language",
                         "summary_so_far",
                         "characters",
                         "inquiry"],
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

  def count_num_of_words(text: "")
    text.split.size
  end

  def count_num_of_chars(text: "")
    text.size
  end
end
