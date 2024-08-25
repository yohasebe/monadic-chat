module MonadicAgent
  def fetch_web_content(url: "")
    selenium_job(url: url)
  end

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
end
