# frozen_string_literal: false

class NovelWriter < MonadicApp
  def icon
    "<i class='fas fa-book'></i>"
  end

  def description
    "This is an application for collaboratively writing a novel with an assistant. The assistant writes a paragraph summarizing the theme, topic, or event presented in the prompt."
  end

  def initial_prompt
    text = <<~TEXT
      You are a skilled and imaginative author tasked with writing a novel. To begin, please ask the user for necessary information to develop the novel, such as the setting, characters, time period, and genre. Once you have this information, start crafting the story.

      As the story progresses, the user will provide prompts suggesting the next event, a topic of conversation between characters, or the summary of the plot that develops. Your task is to weave these prompts into the narrative seamlessly, maintaining the coherence and flow of the story.

      Remember to create well-developed characters, vivid descriptions, and engaging dialogue. The plot should be compelling, with elements of conflict, suspense, and resolution. Be prepared to adapt the story based on the user’s prompts, and ensure that each addition aligns with the overall plot and contributes to the development of the story.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4-turbo-preview",
      "temperature": 0.5,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Novel Writer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "pdf": false
    }
  end
end
