module MonadicHelper
  def fetch_text_from_office(file: "")
    command = "office2txt.py \"#{file}\""
    res = send_command(command: command, container: "python")
    if res.to_s == ""
      "Error: The file looks like empty or not an office file."
    else
      res
    end
  end

  def fetch_text_from_pdf(pdf: "")
    command = "pdf2txt.py \"#{pdf}\" --format md --all-pages"
    res = send_command(command: command, container: "python")
    if res.to_s == ""
      "Error: The file looks like empty or not a PDF file."
    else
      res
    end
  end

  def fetch_text_from_file(file: "")
    command = "content_fetcher.rb \"#{file}\""
    res = send_command(command: command, container: "ruby")
    if res.to_s == ""
      "Error: The file looks like empty."
    else
      res
    end
  end

  def write_to_file(filename:, extension:, text:)
    if IN_CONTAINER
      data_dir = MonadicApp::SHARED_VOL
    else
      data_dir = MonadicApp::LOCAL_SHARED_VOL
    end

    container = "monadic-chat-python-container"
    filepath = File.join(data_dir, "#{filename}.#{extension}")

    # create a temporary file inside the data directory
    begin
      File.open(filepath, "w") do |f|
        f.write(text)
      end
    rescue Errno::ENOENT => e
      return "Error: Directory does not exist for file: #{filename}.#{extension}"
    rescue Errno::EACCES => e
      return "Error: Permission denied when writing file: #{filename}.#{extension}"
    rescue Errno::ENOSPC => e
      return "Error: Not enough disk space to save file: #{filename}.#{extension}"
    end

    # check the availability of the file with the interval of 1 second
    # for a maximum of 20 seconds
    success = false
    max_retrial = 20
    max_retrial.times do
      sleep 1.5
      if File.exist?(filepath)
        success = true
        break
      end
    end

    if success
      if IN_CONTAINER
        docker_command = <<~DOCKER
          docker cp #{filepath} #{container}:#{data_dir}
        DOCKER

        _stdout, stderr, status = Open3.capture3(docker_command)

        if status.exitstatus.zero?
          "The file #{filename}.#{extension} has been written successfully."
        else
          "Error: #{stderr}"
        end
      else
        "The file #{filename}.#{extension} has been written successfully."
      end
    else
      "Error: The file could not be written."
    end
  rescue IOError => e
    "Error: File I/O operation failed for #{filename}.#{extension}"
  rescue SystemCallError => e
    # Catches any system-level errors not specifically handled above
    "Error: System error occurred while writing file: #{e.message}"
  rescue StandardError => e
    # Keep as fallback for any unexpected errors - maintaining backward compatibility
    "Error: The code could not be executed.\n#{e}"
  end
end
