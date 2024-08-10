class NovelWriter < MonadicApp
  def icon
    "<i class='fas fa-book'></i>"
  end

  def description
    "Craft a novel with engaging characters, vivid descriptions, and compelling plots. Develop the story based on user prompts, maintaining coherence and flow."
  end

  def initial_prompt
    text = <<~TEXT
      You are a skilled and imaginative author tasked with writing a novel. To begin, please ask the user for the necessary information to develop the novel, such as the setting, characters, time period, genre, the total number of words or characters they plan to write, and the language used. Once you have this information, start crafting the story.

      You can run the function `update_number_of_words` or `update_number_of_chars` to see the current progress of the novel. For novels written in a language where whitespace is not used to separate words, use the `update_number_of_chars` function. Otherwise, use the `update_number_of_words` function. The arguments for these functions are the number of words or characters and the new paragraph of text you are adding to the novel. The function will return the updated total number of words or characters written so far.

      As the story progresses, the user will provide prompts suggesting the next event, a topic of conversation between characters, or a summary of the plot that develops. Your task is to weave these prompts seamlessly into the narrative, maintaining the coherence and flow of the story.

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
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-2024-08-06",
      "temperature": 0.5,
      "top_p": 0.0,
      "context_size": 40,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Novel Writer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "pdf": false,
      "image": true,
      "monadic": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "update_num_of_words",
            "description": "Update the total number of words written so far in the novel.",
            "parameters": {
              "type": "object",
              "properties": {
                "num_of_words_so_far": {
                  "type": "integer",
                  "description": "The total number of words written so far in the novel."
                },
                "new_paragraph": {
                  "type": "string",
                  "description": "The new paragraph of text to be added to the novel."
                }
              },
              "required": ["num_of_words_so_far", "new_paragraph"],
              "additionalProperties": false
            }
          },
          "strict": true
        },
        {
          "type": "function",
          "function":
          {
            "name": "update_num_of_chars",
            "description": "Update the total number of chars written so far in the novel.",
            "parameters": {
              "type": "object",
              "properties": {
                "num_of_chars_so_far": {
                  "type": "integer",
                  "description": "The total number of chars written so far in the novel."
                },
                "new_paragraph": {
                  "type": "string",
                  "description": "The new paragraph of text to be added to the novel."
                }
              },
              "required": ["num_of_chars_so_far", "new_paragraph"],
              "additionalProperties": false
            }
          },
          "strict": true
        }
      ],
      "response_format": {
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
                            type: "object",
                            properties: {
                              "name": "total_number_of_words",
                              "type": "integer"
                            },
                            required: ["total_number_of_words"],
                            additionalProperties: false
                          },
                          {
                            type: "object",
                            properties: {
                              "name": "total_number_of_chars",
                              "type": "integer"
                            },
                            required: ["total_number_of_chars"],
                            additionalProperties: false
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
                            type: "object",
                            properties: {
                              "name": "number_of_words_so_far",
                              "type": "integer"
                            },
                            required: ["number_of_words_so_far"],
                            additionalProperties: false
                          },
                          {
                            type: "object",
                            properties: {
                              "name": "number_of_chars_so_far",
                              "type": "integer"
                            },
                            required: ["number_of_chars_so_far"],
                            additionalProperties: false
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
                  }
                },
                required: ["grand_plot", "total_text_amount", "text_amount_so_far", "language", "summary_so_far", "characters"],
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

  def update_num_of_words(num_of_words_so_far: 0, new_paragraph: "")
    num_of_words_so_far = num_of_words_so_far.to_i
    num_of_words_so_far += new_paragraph.split.size
    num_of_words_so_far
  end

  def update_num_of_chars(num_of_chars_so_far: 0, new_paragraph: "")
    num_of_chars_so_far = num_of_chars_so_far.to_i
    num_of_chars_so_far += new_paragraph.split(//).size
    num_of_chars_so_far
  end
end
