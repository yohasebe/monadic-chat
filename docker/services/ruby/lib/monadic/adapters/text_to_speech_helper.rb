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

    save_path = if IN_CONTAINER
                  MonadicApp::SHARED_VOL
                else
                  MonadicApp::LOCAL_SHARED_VOL
                end

    textfile = "#{Time.now.to_i}.md"
    textpath = File.join(save_path, textfile)

    File.open(textpath, "w") do |f|
      f.write(text)
    end

    command = "tts_query.rb \"#{textpath}\" --provider=#{provider} --speed=#{speed} --voice=#{voice_id} --language=#{language} --instructions=\"#{instructions}\""
    send_command(command: command, container: "ruby")
  end
end
