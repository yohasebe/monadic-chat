module MonadicAgent
  def fetch_text_from_office(file: "")
    command = <<~CMD
      bash -c 'office2txt.py "#{file}"'
    CMD
    send_command(command: command, container: "python")
  end

  def fetch_text_from_pdf(pdf: "")
    command = <<~CMD
      bash -c 'pdf2txt.py "#{pdf}" --format text'
    CMD
    send_command(command: command, container: "python")
  end

  def fetch_text_from_file(file: "")
    command = <<~CMD
      bash -c 'simple_content_fetcher.rb "#{file}"'
    CMD
    send_command(command: command, container: "ruby")
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
    File.open(filepath, "w") do |f|
      f.write(text)
    end

    docker_command = <<~DOCKER
      docker cp #{filepath} #{container}:#{data_dir}
    DOCKER
    _stdout, stderr, status = Open3.capture3(docker_command)

    if status.exitstatus.zero?
      "The file #{filename}.#{extension} has been written successfully."
    else
      "Error occurred: #{stderr}"
    end
  rescue StandardError
    "Error occurred: The code could not be executed."
  end
end
