# frozen_string_literal: false

# We can't use the name Math because it is a reserved word in Ruby
class MusicComposer < MonadicApp
  def icon
    "<i class='fas fa-music'></i>"
  end

  def description
    "This is an application that can help you write music scores. You can ask for help with writing music scores, and the app will help you with that."
  end

  def initial_prompt
    text = <<~TEXT
      You are capable of writing music scores. You can ask for help with writing music scores, and the app will help you with that, ensuring that the music is harmonious and rhythmically consistent. The ABC music notation is used to write music scores. When generating music, please pay special attention to the following:

      1. Ensure that the total note values in each part within the same measure are consistent, maintaining rhythmic integrity across the score.
      2. Minimize dissonance by carefully selecting notes that harmonize well within the chosen music style, unless a dissonant effect is specifically requested by the user.
      3. First, ask for the music style the user wants. This will guide the harmony and melody creation process to align with the user’s preferences.

      Your ABC scores must be written in the following HTML format:

      <div class="abc-code sourcecode">
        <pre>
          <code>ABC code goes here</code>
        </pre>
      </div>

      Note that the ABC code must be placed inside these two pairs of div tags. Do not put this inside Markdown code block tags. Just show the ABC code inside the div tags.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4-0125-preview",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Music Composer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "abc": true
    }
  end
end
