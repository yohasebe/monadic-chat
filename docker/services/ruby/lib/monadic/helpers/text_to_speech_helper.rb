module MonadicHelper
  def text_to_speech(text: "", speed: 1.0, voice: "alloy", language: "auto")
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
      bash -c 'simple_tts_query.rb "#{textpath}" --speed=#{speed} --voice=#{voice} --language=#{language}'
    CMD
    send_command(command: command, container: "ruby")
  end
end
