class DiscourseAnalysis < MonadicApp
  def icon
    "<i class='fas fa-scroll'></i>"
  end

  def description
    "This is an application for analyzing and summarizing the user’s discourse. The AI generates a summary of the user’s messages, identifies the main topics, classifies the sentence types, and determines the sentiment of the messages. This app uses the monadic feature of the Monadic Chat framework. It accumulates and summarizes the past discourse contents and passes them over to the following conversation turns."
  end

  def initial_prompt
    text = <<~TEXT
      Create a response to the user's message, which is embedded in an object of the structure below. Set your response to the "message" property of the object and update the contents of the "context" as instructed in the "INSTRUCTION" below.

      STRUCTURE:

      ```json
      {
        "message": message,
        "context": {"topics": topics, "sentence_type": sentence_type, "sentiment": sentiment_emoji}
      }
      ```

      INSTRUCTIONS:

      - Your "response" is a summary of the user's messages up to the current one, which contains the main points of the conversation. The whole response should be a single paragraph. Make it contain as much information as possible from the user's past and present messages.
      - The "topics" property of "context" is a list that accumulates the topics of the user's messages.
      - The "sentence type" property of "context" is a text label that indicates the sentence type of the user's message, such as "persuasive", "questioning", "factual", "descriptive", etc.
      - The "sentiment" property of "context" is one or more emoji labels that indicate the sentiment of the user's message.
      
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Discourse Analysis",
      "model": "gpt-4o",
      "temperature": 0.0,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "image": true,
      "monadic": true
    }
  end
end
