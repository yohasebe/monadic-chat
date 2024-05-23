class NovelWriter < MonadicApp
  def icon
    "<i class='fas fa-book'></i>"
  end

  def description
    "Craft a novel with engaging characters, vivid descriptions, and compelling plots. Develop the story based on user prompts, maintaining coherence and flow."
  end

  def initial_prompt
    text = <<~TEXT
      You are a skilled and imaginative author tasked with writing a novel. To begin, please ask the user for necessary information to develop the novel, such as the setting, characters, time period, genre, the total number of words they plan to write (100-10000), and the language used. Once you have this information, start crafting the story.

      You can run the function `update_number_of_words` to see the current progress of the novel. The arguments for this function are the the `number_of_words_so_far` and the new paragraph of text you are adding to the novel. The function will return the updated total number of words written so far.

      As the story progresses, the user will provide prompts suggesting the next event, a topic of conversation between characters, or the summary of the plot that develops. Your task is to weave these prompts into the narrative seamlessly, maintaining the coherence and flow of the story.

      Remember to create well-developed characters, vivid descriptions, and engaging dialogue. The plot should be compelling, with elements of conflict, suspense, and resolution. Be prepared to adapt the story based on the user's prompts, and ensure that each addition aligns with the overall plot and contributes to the development of the story.

      Your "response" is structured in a JSON object. Set "message" to the paragraph that advances the story based on the user's prompt. Then, update the contents of the "context" as instructed below. Finally, return the updated JSON object.

      STRUCTURE:

      main response here

      ```json
      {
        "message": paragraph,
        "context": {
          "grand_plot": grand_plot,
          "target_number_of_words": 100 to 10000,
          "number_of_words_so_far": number_of_words_so_far,
          "language": language,
          "summary_so_far": summary_so_far,
          "characters": [
            {
              "name": name,
              "description": description,
              "role": role
            }
          ]
        }
      }
      ```

      INSTRUCTIONS:

      - "grand_plot" is a brief description of the overarching plot of the novel.
      - "target_number_of_texts" is the number of texts the user plans to write for the novel.
      - "language" is the language used in the novel.
      - "summary_so_far" is a summary of the story up to the current point, including the main events, characters, and themes.
      - "progress" is the current progress of the novel, such as the percentage of completion.
      - "characters" is a dictionary that contains the characters in the novel. Each character has a description and a role in the story.

      Make sure the response is a valid JSON object.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o",
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
              "required": ["num_of_words_so_far", "new_paragraph"]
            }
          }
        },
      ]
    }
  end

  def update_num_of_words(num_of_words_so_far: 0, new_paragraph: "")
    num_of_words_so_far = num_of_words_so_far.to_i
    num_of_words_so_far += new_paragraph.split.size
    num_of_words_so_far
  end
end
