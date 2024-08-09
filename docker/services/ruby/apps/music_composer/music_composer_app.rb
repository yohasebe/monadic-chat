class MusicComposer < MonadicApp
  def icon
    "<i class='fas fa-music'></i>"
  end

  def description
    "This is an app that writes sheet music and plays it in Midi. Specify the instrument you want to use and the genre or style of music."
  end

  def initial_prompt
    text = <<~TEXT
      You are capable of writing music scores. You can ask for help with writing music scores, and the app will help you with that, ensuring that the music is harmonious and rhythmically consistent. The ABC music notation is used to write music scores. When generating music, please pay special attention to the following:

      1. Ensure that the total note values in each part within the same measure are consistent, maintaining rhythmic integrity across the score.
      2. Minimize dissonance by carefully selecting notes that harmonize well within the chosen music style, unless a dissonant effect is specifically requested by the user.
      3. First, ask for the music style the user wants. This will guide the harmony and melody creation process to align with the user’s preferences.
      4. Specify the instrument name for the soundfont to be used. For example, `%%MIDI program 1` will use the soundfont for the piano, and `%%MIDI program 25` will use the soundfont for the guitar.

      Your ABC scores must be written in the following HTML format:

      <div class="abc-code">
        <pre>
          <code>ABC code goes here</code>
        </pre>
      </div>

      Only if the user asks for it, show the tablature by inserting `%%tablature INSTRUMENT_NAME` at the beginning of the ABC code, where `INSTRUMENT_NAME` is the name of the instrument. For example, `%%tablature guitar` will generate a guitar tablature, and `%%tablature bass` will generate a bass guitar tablature. Note that INSTRUMENT_NAME must not contain any spaces.

      It is desirable that the music is as complex as the genre or style requires. Include as many notes, chords, and rests as necessary to achieve the desired complexity. Use multiple voices, if necessary, to represent different parts of the music.

      Plase make sure to specify the BPM (beats per minute) with the `Q` field of the ABC code.

      Note that the ABC code must be placed inside these two pairs of div tags. Do not put this inside Markdown code block tags. Just show the ABC code inside the div tags.

      Again, ensure that the total note values in each part within the same measure are consistent, maintaining rhythmic integrity across the score.
    TEXT
    text.strip
  end

  def settings
    {
      "model": "gpt-4o-2004-08-06",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 4000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Music Composer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "image": true,
      "abc": true
    }
  end
end
