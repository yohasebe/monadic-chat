module MonadicHelper
  def list_providers_and_voices
    command = <<~CMD
      bash -c 'simple_tts_query.rb --list'
    CMD
    send_command(command: command, container: "ruby")
  end

  def text_to_speech(provider: "openai", text: "", speed: 1.0, voice_id: "alloy", language: "auto")
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

    command = <<~CMD
      bash -c 'simple_tts_query.rb #{textpath}" --provider=#{provider} --speed=#{speed} --voice=#{voice_id} --language=#{language}'
    CMD
    send_command(command: command, container: "ruby")
  end
end
