# frozen_string_literal: true

# Mock of monadic_app.rb for testing purposes
# This avoids loading all the helpers and plugins

require_relative '../lib/monadic/utils/string_utils'
require 'open3'
require 'digest'
require 'tempfile'
require 'fileutils'
require 'stringio'
require 'json'
require 'set'

# Define necessary constants in a module to avoid global namespace pollution
module MonadicAppTest
  IN_CONTAINER = false unless defined?(IN_CONTAINER)
  CONFIG = {} unless defined?(CONFIG)

  # Simple mock for helpers
  module MonadicHelper
    JUPYTER_LOG_FILE = Dir.home + "/monadic/log/jupyter.log"
    JUPYTER_PORT = 8888
    
    def lib_installer(command: "", packager: "")
      install_command = case packager
                        when "pip"
                          "pip install #{command}"
                        when "apt"
                          "apt-get install -y #{command}"
                        else
                          "echo 'Invalid packager'"
                        end
      
      send_command(command: install_command,
                   container: "python",
                   success: "The library has been installed successfully.\n",
                   success_with_output: "The install command has been has been executed with the following output:\n")
    end
    
    def run_bash_command(command: "")
      send_command(command: command,
                   container: "python",
                   success: "The command has been executed.\n",
                   success_with_output: "Command has been executed with the following output:\n")
    end
  end

  class MonadicApp
    include StringUtils
    include MonadicHelper
    
    # Constants
    SYSTEM_SCRIPT_DIR = "/monadic/scripts"
    USER_SCRIPT_DIR = "/monadic/data/scripts"
    SHARED_VOL = "/monadic/data"
    
    COMMAND_LOG_FILE = if IN_CONTAINER
                         "/monadic/log/command.log"
                       else
                         Dir.home + "/monadic/log/command.log"
                       end
    
    EXTRA_LOG_FILE = if IN_CONTAINER
                       "/monadic/log/extra.log"
                     else
                       Dir.home + "/monadic/log/extra.log"
                     end
    
    LOCAL_SYSTEM_SCRIPT_DIR = File.expand_path(File.join(Dir.home, "monadic", "scripts"))
    LOCAL_USER_SCRIPT_DIR = File.expand_path(File.join(Dir.home, "monadic", "data", "scripts"))
    LOCAL_SHARED_VOL = File.expand_path(File.join(Dir.home, "monadic", "data"))
    
    COMMAND_DELAY = 1.5
    
    AI_USER_INITIAL_PROMPT = "Test prompt"
    
    class << self
      def model_data
        @model_data ||= {}
      end
      
      def app_settings
        @app_settings ||= {}
      end
    end
    
    attr_accessor :api_key, :context, :embeddings_db, :settings
    
    def initialize
      @context = {}
      @api_key = ""
      @embeddings_db = nil
      @settings = {}
    end
    
    def send_command(command:,
                    container: "python",
                    success: "Command has been executed.\n",
                    success_with_output: "Command has been executed with the following output: \n"
                   )
      
      case container.to_s
      when "ruby"
        if IN_CONTAINER
          system_script_dir = SYSTEM_SCRIPT_DIR
          user_system_script_dir = USER_SCRIPT_DIR
          shared_volume = SHARED_VOL
        else
          system_script_dir = LOCAL_SYSTEM_SCRIPT_DIR
          user_system_script_dir = LOCAL_USER_SCRIPT_DIR
          shared_volume = LOCAL_SHARED_VOL
        end
        system_command = <<~SYS
          find #{system_script_dir} -type f -exec chmod +x {} + 2>/dev/null | : && \
          find #{user_system_script_dir} -type f -exec chmod +x {} + 2>/dev/null | : && \
          export PATH="#{system_script_dir}:${PATH}" && \
          export PATH="#{user_system_script_dir}:${PATH}" && \
          cd #{shared_volume} && \
          #{command}
        SYS
      when "python"
        container = "monadic-chat-python-container"
        system_command = <<~DOCKER
          docker exec #{container} bash -c 'find #{USER_SCRIPT_DIR} -type f -exec chmod +x {} +'
          docker exec -w #{SHARED_VOL} #{container} #{command}
        DOCKER
      else
        container = "monadic-chat-#{container}-container"
        system_command = <<~DOCKER
          docker exec #{container} bash -c 'find #{USER_SCRIPT_DIR} -type f -exec chmod +x {} +'
          docker exec -w #{SHARED_VOL} #{container} #{command}
        DOCKER
      end
      
      stdout, stderr, status = self.capture_command(system_command)
      
      if block_given?
        yield(stdout, stderr, status)
      elsif status.success?
        if stdout.strip.empty?
          success
        else
          "#{success_with_output}#{stdout}"
        end
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
    
    def send_code(code:, command:, extension:, success: "The code has been executed successfully", max_retries: 3, retry_delay: 1.5, keep_file: false)
      retries = 0
      last_error = nil
      
      begin
        # Set appropriate paths based on environment
        if IN_CONTAINER
          data_dir = SHARED_VOL
          files_dir = SHARED_VOL
        else
          data_dir = LOCAL_SHARED_VOL
          files_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
        end
        
        container = "monadic-chat-python-container"
        
        # Generate timestamp-based filename
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        filename = "code_#{timestamp}.#{extension}"
        
        if keep_file
          # Create a permanent file with timestamp-based name
          file_path = File.join(data_dir, filename)
          File.write(file_path, code)
        else
          # Create a temporary file with timestamp-based name
          temp_file = Tempfile.new(["code_#{timestamp}", ".#{extension}"], data_dir)
          temp_file.write(code)
          temp_file.close
          file_path = temp_file.path
        end
        
        # Get the list of files with their content digest before execution
        local_files1 = {}
        Dir[File.join(files_dir, "*")].each do |f|
          begin
            local_files1[f] = File.exist?(f) ? Digest::MD5.file(f).hexdigest : nil
          rescue => e
            # Skip if file access error occurs
            next
          end
        end
        
        # Copy the file to the container
        docker_command = <<~DOCKER
          docker cp #{file_path} #{container}:#{SHARED_VOL}
        DOCKER
        
        stdout, stderr, status = self.capture_command(docker_command)
        unless status.success?
          raise "Error occurred: #{stderr}"
        end
        
        # Execute the code in the container
        docker_command = <<~DOCKER
          docker exec -w #{SHARED_VOL} #{container} #{command} /monadic/data/#{File.basename(file_path)}
        DOCKER
        
        stdout, stderr, status = self.capture_command(docker_command)
        
        # Wait briefly for filesystem synchronization
        sleep COMMAND_DELAY
        
        if status.success?
          # Get the list of files with their content digest after execution
          local_files2 = {}
          Dir[File.join(files_dir, "*")].each do |f|
            begin
              local_files2[f] = File.exist?(f) ? Digest::MD5.file(f).hexdigest : nil
            rescue => e
              # Skip if file access error occurs
              next
            end
          end
          
          # Detect new or modified files
          changed_files = []
          
          # Detect newly created files
          new_files = local_files2.keys - local_files1.keys
          changed_files.concat(new_files)
          
          # Detect files with modified content
          modified_files = local_files2.select do |file, digest|
            local_files1[file] && local_files1[file] != digest
          end.keys
          changed_files.concat(modified_files)
          
          # Exclude the execution file itself
          changed_files = changed_files - [file_path]
          changed_files.uniq!
          
          # Prepare the success message with file information
          if !changed_files.empty?
            file_paths = changed_files.map { |file| "/data/" + File.basename(file) }
            output = "#{success}; File(s) generated or modified: #{file_paths.join(", ")}"
            output += "; Output: #{stdout}" if stdout.strip.length.positive?
          else
            output = "#{success} (No files generated or modified)"
            output += "; Output: #{stdout}" if stdout.strip.length.positive?
          end
          
          # Clean up temporary file if keep_file is false
          temp_file.unlink if !keep_file && temp_file
          
          output
        else
          # Create detailed error information
          last_error = {
            message: stderr,
            type: detect_error_type(stderr),
            code_snippet: code,
            attempt: retries + 1
          }
          raise StandardError, generate_error_suggestions(last_error)
        end
      rescue StandardError => e
        if retries < max_retries
          retries += 1
          sleep(retry_delay)
          retry
        else
          "Error executing code: #{e.message}"
        end
      end
    end
    
    def detect_error_type(error_message)
      case error_message
      when /SyntaxError/
        "SyntaxError"
      when /ImportError|ModuleNotFoundError/
        "ImportError"
      when /NameError/
        "NameError"
      when /TypeError/
        "TypeError"
      when /ValueError/
        "ValueError"
      when /IndexError/
        "IndexError"
      when /KeyError/
        "KeyError"
      else
        "UnknownError"
      end
    end
    
    def generate_error_suggestions(error)
      case error[:type]
      when "SyntaxError"
        "Check the code syntax: verify indentation, matching brackets, and proper statement termination."
      when "ImportError"
        "Required library might be missing. Check if all necessary packages are installed."
      when "NameError"
        "Variable or function might be undefined. Verify all names are properly defined before use."
      when "TypeError"
        "Operation might be performed on incompatible types. Check variable types and operations."
      when "ValueError"
        "Invalid value provided for operation. Verify input values and their formats."
      when "IndexError"
        "Array index out of bounds. Check array lengths and index values."
      when "KeyError"
        "Dictionary key not found. Verify key existence before access."
      else
        "Unexpected error occurred. Review the code logic and implementation."
      end
    end
    
    def run_code(code: nil, command: nil, extension: nil, success: "The code has been executed successfully")
      return "Error: code, command, and extension are required." if !code || !command || !extension
      
      send_code(code: code, command: command, extension: extension, success: success)
    end
    
    def run_script(code: nil, command: nil, extension: nil, success: "The code has been executed successfully")
      # remove escape characters from the code
      if code
        code = code.gsub(/\\n/) { "\n" }
        code = code.gsub(/\\'/) { "'" }
        code = code.gsub(/\\"/) { '"' }
        code = code.gsub(/\\\\/) { "\\" }
      end
      
      # return the error message unless all the arguments are provided
      return "Error: code, command, and extension are required." if !code || !command || !extension
      
      send_code(code: code, command: command, extension: extension, success: success)
    end
    
    def capture_command(command)
      self.class.capture_command(command)
    end
    
    def self.capture_command(command)
      unless command
        return ["Error: command is required.", nil, 1]
      end
      
      stdout, stderr, status = Open3.capture3(command)
      
      # output log data of input and output
      # create a log (COMMAND_LOG_FILE) to store the command and its output
      File.open(COMMAND_LOG_FILE, "a") do |f|
        f.puts "Time: #{Time.now}"
        f.puts "Command: #{command}"
        f.puts "Error: #{stderr}" if stderr.strip.length.positive?
        f.puts "Output: #{stdout}"
        f.puts "-----------------------------------"
      end
      
      [stdout, stderr, status]
    end
    
    def self.doc2markdown(filename)
      basename = File.basename(filename)
      # get the file extension
      extension = File.extname(basename).downcase
      container = "monadic-chat-python-container"
      case extension
      when ".pdf"
        docker_command = <<~DOCKER
          docker exec -w #{SHARED_VOL} #{container} bash -c 'pdf2txt.py "#{basename}" --format md'
        DOCKER
      when ".docx", ".xlsx", ".pptx"
        docker_command = <<~DOCKER
          docker exec -w #{SHARED_VOL} #{container} bash -c 'office2txt.py "#{basename}"'
        DOCKER
      else
        docker_command = <<~DOCKER
          docker exec -w #{SHARED_VOL} #{container} bash -c 'simple_content_fetcher.py "#{basename}"'
        DOCKER
      end
      
      stdout, stderr, status = self.capture_command(docker_command)
      
      # Wait briefly for filesystem synchronization
      sleep COMMAND_DELAY
      
      if status.success?
        stdout
      else
        stdout.strip.empty? ? stderr : stdout
      end
    end
    
    def self.fetch_webpage(url)
      container = "monadic-chat-python-container"
      docker_command = <<~DOCKER
        docker exec -w #{SHARED_VOL} #{container} bash -c 'webpage_fetcher.py --url \"#{url}\" --mode md --keep-unknown --output stdout'
      DOCKER
      
      stdout, stderr, status = self.capture_command(docker_command)
      
      # Wait briefly for filesystem synchronization
      sleep 1
      
      if status.success?
        if stdout.strip.empty?
          "Webpage content could not be fetched."
        else
          stdout.strip
        end
      else
        stdout.strip.empty? ? stderr : stdout
      end
    end
    
    def self.check_vision_capability(model)
      capable_model_names = [
        "o1",
        "4o",
      ]
      
      rejected_model_names = [
        "o1-preview",
        "o1-mini"
      ]
      
      if model.match?(/\b(#{capable_model_names.join("|")})\b/) &&
          !model.match?(/\b(#{rejected_model_names.join("|")})\b/)
        model
      else
        nil
      end
    end
  end
end