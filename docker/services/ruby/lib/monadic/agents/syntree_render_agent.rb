require_relative "basic_agent"

module MonadicAgent
  def syntree_render_agent(text:, format: "svg", wait: 1)
    return "Error: input text is required." if text.to_s.empty?

    tempname = Time.now.to_i.to_s

    write_to_file(filename: tempname, extension: "txt", text: text)

    sleep wait

    success_msg = "Syntree generated successfully"
    command = "bash -c 'rsyntaxtree -f #{format} -o . #{tempname}.txt'"
    res = send_command(command: command, container: "ruby", success: success_msg)

    if /\A#{success_msg}/ =~ res.strip
      sleep wait
      command = "bash -c 'mv syntree.#{format} #{tempname}.#{format}'"
      send_command(command: command, container: "ruby",
                   success: "Syntax tree generated successfully as #{tempname}.#{format}")
    else
      "Error: syntax tree generation failed. #{res}"
    end
  end
end
