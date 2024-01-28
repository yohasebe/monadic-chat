# frozen_string_literal: false

class LinguisticAnalysis < MonadicApp
  attr_accessor :context

  def icon
    "<i class='fas fa-tree'></i>"
  end

  def description
    ""
  end

  def initial_prompt
    text = <<~TEXT
      Create a response to the user's message, which is embedded in a JSON object. Set your response to the "message" property of a new JSON object with the same structure as the one shown in the "STRUCTURE" below. Then, update the contents of the "context" as instructed in the "INSTRUCTION" below. Finally, return the updated JSON object.

      STRUCTURE:

      ```json
      {
        "message": message,
        "context": {"topics": topics, "sentence_type": sentence_type, "sentiment": sentiment_emoji}
      }
      ```

      INSTRUCTIONS:

      - Your "response" is a string that represents the syntactic structure of the user's message.
      - The result of the syntactic parsing should be in the Penn Treebank format.
      - Use square brackets instead of parentheses for the syntactic parsing.
      - Paired brackets should be balanced and nested properly with a certain number of spaces from the left margin.
      - The parsing result should be enclosed in a “pre” tag and a “code” tag as illustrated below:

      ```example
      <pre><code>
      [S
        [NP
          [NNP John]
        ]
        [VP
          [VBZ loves]
          [NP
            [NNP Mary]
          ]
        ]
      ]
      </code></pre>
      ```


      - The "topics" property of "context" is a list that accumulates the topics of the user's messages.
      - The "sentence type" property of "context" is a text label that indicates the sentence type of the user's message, such as "persuasive", "questioning", "factual", "descriptive", etc.
      - The "sentiment" property of "context" is one or more emoji labels that indicate the sentiment of the user's message.

      Make sure the response is a valid JSON object.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Linguistic Analysis",
      "model": "gpt-3.5-turbo-1106",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "monadic": true
    }
  end
end
