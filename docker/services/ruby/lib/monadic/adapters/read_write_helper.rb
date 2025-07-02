require 'shellwords'

module MonadicHelper
  # Validate file path is within allowed directories
  def validate_file_path(file_path)
    return nil if file_path.nil? || file_path.empty?
    
    # Get the data directory path
    data_dir = Monadic::Utils::Environment.data_path
    
    # Expand paths to handle relative paths and symlinks
    begin
      real_file = File.expand_path(file_path)
      real_data_dir = File.expand_path(data_dir)
      
      # Check if file is within data directory
      if real_file.start_with?(real_data_dir)
        return file_path
      else
        return nil
      end
    rescue
      return nil
    end
  end
  
  def fetch_text_from_office(file: "")
    # Validate file path to prevent directory traversal
    return "Error: Invalid file path" unless validate_file_path(file)
    
    command = "office2txt.py #{Shellwords.escape(file)}"
    res = send_command(command: command, container: "python")
    
    if res.to_s == ""
      "Error: The file looks like empty or not an office file."
    elsif res.include?("No such file or directory") || res.include?("not found")
      "Error: Office file '#{file}' not found. Please ensure the file exists and the path is correct."
    elsif res.include?("Error:")
      res # Return the specific error message from the script
    else
      res
    end
  end

  def fetch_text_from_pdf(pdf: "")
    # Validate file path to prevent directory traversal
    return "Error: Invalid file path" unless validate_file_path(pdf)
    
    command = "pdf2txt.py #{Shellwords.escape(pdf)} --format md --all-pages"
    res = send_command(command: command, container: "python")
    
    if res.to_s == ""
      "Error: The file looks like empty or not a PDF file."
    elsif res.include?("PDF file not found:") || res.include?("No such file or directory")
      "Error: PDF file '#{pdf}' not found. Please ensure the file exists and the path is correct."
    elsif res.include?("Error processing PDF:") || res.include?("Error:")
      "Error: Unable to process PDF file '#{pdf}'. The file may be corrupted or in an unsupported format."
    else
      res
    end
  end

  def fetch_text_from_file(file: "")
    # Validate file path to prevent directory traversal
    return "Error: Invalid file path" unless validate_file_path(file)
    
    command = "content_fetcher.rb #{Shellwords.escape(file)}"
    res = send_command(command: command, container: "ruby")
    
    if res.to_s == ""
      "Error: The file looks like empty."
    elsif res.include?("does not exist or is not readable")
      "Error: File '#{file}' not found or is not readable. Please ensure the file exists and has proper permissions."
    elsif res.include?("ERROR:")
      res # Return the specific error message from the script
    else
      res
    end
  end

  def write_to_file(filename:, extension:, text:)
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
