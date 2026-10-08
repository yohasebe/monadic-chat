require 'shellwords'
require_relative '../utils/shared_path_guard'

# Path validation helper for read/write operations

module MonadicHelper
  # Keep validation and execution on the same canonical path.
  def validate_file_path(file_path)
    Monadic::Utils::SharedPathGuard.resolve_in_shared(file_path, must_exist: false)
  end

  def fetch_text_from_office(file: "")
    fetch_shared_document(file, "office2txt.py", "python")
  end

  def fetch_text_from_pdf(pdf: "")
    fetch_shared_document(pdf, "pdf2txt.py", "python", "--format", "md", "--all-pages")
  end

  def fetch_text_from_file(file: "")
    fetch_shared_document(file, "content_fetcher.rb", "ruby")
  end

  def fetch_shared_document(file, script, container, *options)
    path = Monadic::Utils::SharedPathGuard.command_path(file, container: container)
    return "Error: Invalid file path or file not found" unless path

    command = Shellwords.join([script, path, *options])
    send_command(command: command, container: container) do |stdout, _stderr, status|
      # Some converters report errors on stdout, including with exit status 0.
      # Do not let send_command discard that failure or return an empty error.
      output = stdout.to_s
      converter_error = script != "content_fetcher.rb" && output.match?(/\A\s*(?:error[: ]|PDF file not found:|The specified file could not be found:|No such file or directory)/i)
      if !status.success? || converter_error
        "Error: Unable to read or convert the requested file"
      elsif output.strip.empty?
        "Error: The file is empty or contains no readable text"
      else
        respond_to?(:truncate_output, true) ? truncate_output(output) : output
      end
    end
  end
  private :fetch_shared_document

  def write_to_file(filename:, extension:, text:)
    # Check for directory traversal attempts in filename
    if filename.include?("/") || filename.include?("\\")
      return "Error: Invalid filename - directory paths are not allowed"
    end
    
    # Sanitize filename and extension to prevent directory traversal
    safe_filename = File.basename(filename)
    safe_extension = extension.gsub(/[^a-zA-Z0-9]/, '')
    
    if Monadic::Utils::Environment.in_container?
      data_dir = MonadicApp::SHARED_VOL
    else
      data_dir = MonadicApp::LOCAL_SHARED_VOL
    end

    container = "monadic-chat-python-container"
    filepath = File.join(data_dir, "#{safe_filename}.#{safe_extension}")

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
      if Monadic::Utils::Environment.in_container?
        # Routed through Monadic::Shell so the container name and the
        # cp invocation share the same source of truth as every other
        # docker call. This is the H3 POC migration referenced in
        # docs_dev/architecture_hardening_plan.md.
        require_relative '../shell'
        _stdout, stderr, status = Monadic::Shell.cp_to_container(
          container: :python, host_path: filepath, container_path: data_dir
        )

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
