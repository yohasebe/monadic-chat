module MonadicAgent
  def syntree_render_agent(text:, format: "svg")
    return "Error: input text is required." if text.to_s.empty?

    shared_volume = if IN_CONTAINER
                      MonadicApp::SHARED_VOL
                    else
                      MonadicApp::LOCAL_SHARED_VOL
                    end

    max_retrials = 10
    sleep_interval = 1.5
    tempname = Time.now.to_i.to_s

    write_to_file(filename: tempname, extension: "txt", text: text)

    filepath1 = File.join(shared_volume, tempname + ".txt")

    success1 = false
    max_retrials.times do
      if File.exist?(filepath1)
        success1 = true
        break
      end
      sleep sleep_interval
    end

    if success1
      command = "bash -c 'rsyntaxtree -f #{format} -o . -u #{tempname} #{tempname}.txt'"
      success_msg1 = "Syntree generated successfully"
      res1 = send_command(command: command, container: "ruby", success: success_msg1)

      if /\A#{success_msg1}/ =~ res1.strip
        filepath2 = File.join(shared_volume, tempname + "." + format)

        success2 = false
        max_retrials.times do
          if File.exist?(filepath2)
            success2 = true
            break
          end
          sleep sleep_interval
        end

        if success2
          "Syntax tree generated successfully as #{tempname + "." + format}"
        else
          "Error: syntax tree generation failed: #{res1}"
        end
      end
    else
      "Error: syntax tree generation failed. Temp file not found."
    end
  end
end
