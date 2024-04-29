# frozen_string_literal: true

class DiscourseAnalysis < MonadicApp
  def icon
    "<i class='fas fa-scroll'></i>"
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

      - Your "response" is a summary of the user's messages so far up to the current one, which contains the main points of the conversation. The whole response should be a single paragraph. Make it contain as much information as possible from the user's messages.
      - The "topics" property of "context" is a list that accumulates the topics of the user's messages.
      - The "sentence type" property of "context" is a text label that indicates the sentence type of the user's message, such as "persuasive", "questioning", "factual", "descriptive", etc.
      - The "sentiment" property of "context" is one or more emoji labels that indicate the sentiment of the user's message.

      Make sure the response is a valid JSON object.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Discourse Analysis",
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "context_size": 20,
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
