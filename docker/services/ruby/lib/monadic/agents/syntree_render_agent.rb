require_relative "basic_agent"

module MonadicAgent
  def syntree_render_agent(text:)
    return "Error: input text is required." if text.to_s.empty?

    tempname = Time.now.to_i.to_s

    write_to_file(filename: tempname, extension: "txt", text: text)

    datadir = if IN_CONTAINER
                File.expand_path(File.join(__dir__, "..", "data"))
              else
                File.expand_path(File.join(Dir.home, "monadic", "data"))
              end

    datafile = File.join(datadir, "#{tempname}.txt")

    success = false
    max_retrial = 20
    max_retrial.times do
      sleep 1.5
      if File.exist?(datafile)
        success = true
        break
      end
    end

    if success
      command = "bash -c 'rsyntaxtree -o . #{datafile}'"
      send_command(command: command, container: "ruby", success: "Syntax tree rendered successfully")
    else
      return "Error: syntax tree rendering failed."
    end

    syntree_file = File.join(datadir, "syntree.png")

    success = false
    max_retrial = 20
    max_retrial.times do
      sleep 1.5
      if File.exist?(syntree_file)
        success = true
        break
      end
    end

    result_file = File.join(datadir, "#{tempname}.png")

    if success
      command = "bash -c 'mv #{syntree_file} #{result_file}'"
      send_command(command: command, container: "ruby",
                   success: "Syntax tree rendered successfully as #{tempname}.png")
    else
      "Error: syntax tree rendering failed."
    end
  end
end
