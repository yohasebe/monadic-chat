require 'securerandom'
require 'shellwords'

module MonadicHelper
  def list_providers_and_voices
    command = "tts_query.rb --list"
    send_command(command: command, container: "ruby")
  end

  def text_to_speech(provider: "openai", text: "", speed: 1.0, voice_id: "alloy", language: "auto", instructions: "")
    if CONFIG["TTS_DICT"] && !CONFIG["TTS_DICT"].empty?
      # Sort keys by length in descending order to process longer patterns first
      sorted_keys = CONFIG["TTS_DICT"].keys.sort_by { |k| -k.length }
      
      # Process each key individually to handle special characters like newlines
      sorted_keys.each do |key|
        # Use Regexp.escape to properly handle special characters in the key
        escaped_key = Regexp.escape(key)
        # Apply substitution for each key with multiline flag
        text = text.gsub(/#{escaped_key}/m) { CONFIG["TTS_DICT"][key] }
      end
    end

    text = text.gsub(/"/, '\"')

    save_path = Monadic::Utils::Environment.shared_volume

    # Unique per call: Time.now.to_i has 1-second resolution, so concurrent
    # syntheses (e.g. parallel Conduit jobs) would otherwise collide on the
    # same .md input and .mp3 output filename. The random suffix prevents that.
    textfile = "#{Time.now.to_i}_#{SecureRandom.hex(4)}.md"
    textpath = File.join(save_path, textfile)

    File.open(textpath, "w") do |f|
      f.write(text)
    end

    # Every value can come from a model's tool call; each is escaped into a
    # single argument so none of them is read by the shell.
    command = [
      "tts_query.rb",
      Shellwords.escape(textpath),
      Shellwords.escape("--provider=#{provider}"),
      Shellwords.escape("--speed=#{speed}"),
      Shellwords.escape("--voice=#{voice_id}"),
      Shellwords.escape("--language=#{language}"),
      Shellwords.escape("--instructions=#{instructions}")
    ].join(" ")
    send_command(command: command, container: "ruby")
  end
end
