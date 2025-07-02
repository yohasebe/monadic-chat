require 'shellwords'

module MonadicHelper
  # Validate file path is within allowed directories
  def validate_file_path(file_path)
    return nil if file_path.nil? || file_path.empty?
    
    # Get the data directory path
    data_dir = Monadic::Utils::Environment.data_path
    
    begin
      # Normalize and expand paths
      expanded_file = File.expand_path(file_path)
      expanded_data_dir = File.expand_path(data_dir)
      
      # If file exists, resolve symlinks with realpath
      if File.exist?(expanded_file)
        real_file = File.realpath(expanded_file)
        real_data_dir = File.realpath(expanded_data_dir)
      else
        # File doesn't exist yet, check the directory path
        dir_path = File.dirname(expanded_file)
        if File.exist?(dir_path)
          real_file = File.join(File.realpath(dir_path), File.basename(expanded_file))
          real_data_dir = File.realpath(expanded_data_dir)
        else
          # Neither file nor directory exists, use expanded paths
          real_file = expanded_file
          real_data_dir = expanded_data_dir
        end
      end
      
      # Ensure proper directory separator at the end of data_dir
      real_data_dir_with_sep = real_data_dir.end_with?(File::SEPARATOR) ? 
                               real_data_dir : 
                               real_data_dir + File::SEPARATOR
      
      # Check if file is within data directory
      if real_file.start_with?(real_data_dir_with_sep)
        return file_path
      else
        return nil
      end
    rescue StandardError => e
      # Log error for debugging but don't expose details to user
      puts "Path validation error: #{e.message}" if ENV["DEBUG"]
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
