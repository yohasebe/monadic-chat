# frozen_string_literal: true

require_relative "./utils/string_utils"

Dir.glob(File.expand_path("helpers/**/*.rb", __dir__)).sort.each do |rb|
  require rb
end

user_helpers_dir = if IN_CONTAINER
                    "/monadic/data/plugins/**/helpers"
                  else
                    Dir.home + "/monadic/data/plugins/**/helpers"
                  end

Dir.glob(File.expand_path(user_helpers_dir + "/**/*.rb")).sort.each do |rb|
  require rb
end

class MonadicApp
  include MonadicAgent
  include MonadicHelper
  include StringUtils
  include TavilyHelper

  @model_data = {}
  @app_settings = {}

  class << self
    attr_reader :model_data, :app_settings
    
    def register_models(vendor_name, models)
      @model_data[vendor_name] ||= Set.new
      @model_data[vendor_name].merge(models)
    end

    def model_data
      @model_data ||= {}
    end
    
    def models_for_vendor(vendor_name)
      @model_data[vendor_name]&.to_a || []
    end
    
    def vendors
      @model_data.keys
    end

    def register_app_settings(app_name, settings)
      @app_settings[app_name] = settings
    end

    def app_settings(app_name)
      @app_settings[app_name] || {}
    end

    def all_app_settings
      @app_settings
    end
  end

  TOKENIZER = FlaskAppClient.new

  # script directory to store the system scripts
  SYSTEM_SCRIPT_DIR = "/monadic/scripts"
  # script directory to store the user scripts
  USER_SCRIPT_DIR = "/monadic/data/scripts"
  # shared volume between the containers
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

  # script directory in the dev mode (= when ruby-container is not used)
  LOCAL_SYSTEM_SCRIPT_DIR = File.expand_path(File.join(__dir__, "..", "..", "scripts"))
  # script directory in the local computer to store the user scripts
  LOCAL_USER_SCRIPT_DIR = File.expand_path(File.join(Dir.home, "monadic", "data", "scripts"))
  # shared volume in the local computer to share with the containers
  LOCAL_SHARED_VOL = File.expand_path(File.join(Dir.home, "monadic", "data"))

  # delay to wait for the command execution
  COMMAND_DELAY = 1.5

  AI_USER_INITIAL_PROMPT = <<~PROMPT
      The user is currently answering various types of questions, writing computer program code, making decent suggestions, and giving helpful advice on your message. Give the user requests, suggestions, or questions so that the conversation is engaging and interesting. If there are any errors in the responses you get, point them out and ask for correction. Use the same language as the user.

      Keep on pretending as if you were the "user" and as if the user were the "assistant" throughout the conversation.

      Do your best to make the conversation as natural as possible. Do not change subjects unless it is necessary, and keep the conversation going by asking questions or making comments relevant to the preceding and current topics.

      Your response should be concise and clear. Even if the preceding messages are formatted as json, you keep your response as plain text. do not use parentheses or brackets in your response.

      Remember you are the one who inquires for information, not providing the answers.
  PROMPT

  # access the flask app client so that it gets ready before the first request

  attr_accessor :api_key, :context, :embeddings_db, :settings

  def initialize
    @context = {}
    @api_key = ""
    @embeddings_db = nil
    @settings = {}

    if CONFIG["EXTRA_LOGGING"]
      # regenerate the log file
      File.open(EXTRA_LOG_FILE, "w") do |f|
        f.puts "Extra log file created at #{Time.now}\n\n"
      end
    end
  end

  # Wrap the user's message in a monad
  def monadic_unit(message)
    res = { "message": message,
            "context": @context }
    res.to_json
  end

  # Unwrap the monad and return the message
  def monadic_unwrap(monad)
    JSON.parse(monad)
  rescue JSON::ParserError
    { "message" => monad.to_s, "context" => @context }
  end

  # sanitize the data to remove invalid characters
  def sanitize_data(data)
    if data.is_a? String
      return data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    if data.is_a? Hash
      data.each do |key, value|
        data[key] = sanitize_data(value)
      end
    elsif data.is_a? Array
      data.map! do |value|
        sanitize_data(value)
      end
    end

    data
  end

  # Unwrap the monad and return the message after applying a given process (if any)
  def monadic_map(monad)
    obj = monadic_unwrap(monad)
    @context = block_given? ? yield(obj["context"]) : obj["context"]
    JSON.pretty_generate(sanitize_data(obj))
  end

  # Convert a monad to HTML
  def monadic_html(monad)
    obj = monadic_unwrap(monad)
    json2html(obj, mathjax: settings["mathjax"])
  end

  # Convert snake_case to space ceparated capitalized words
  def snake2cap(snake)
    snake.split("_").map(&:capitalize).join(" ")
  rescue StandardError
    snake
  end


  def json2html(hash, iteration: 0, exclude_empty: true, mathjax: false)
    return hash.to_s unless hash.is_a?(Hash)

    iteration += 1
    output = +""

    if hash.key?("message")
      message = hash["message"]
      output += StringUtils.markdown_to_html(message, mathjax: mathjax)
      output += "<hr />"
      hash = hash.reject { |k, _| k == "message" }
    end

    hash.each do |key, value|
      next if exclude_empty && (value.nil? || value == "" || (value.is_a?(Array) && value.empty?))

      key = snake2cap(key)
      data_key = key.downcase

      if key.downcase == "context"
        output += "<div class='json-item context' data-depth='#{iteration}' data-key='context'>"
        output += "<div class='json-header' onclick='toggleItem(this)'>"
        output += "<span>Context</span>"
        output += " <i class='fas fa-chevron-down float-right'></i> <span class='toggle-text'>click to toggle</span>"
        output += "</div>"
        output += "<div class='json-content'>"
        output += json2html(value, iteration: iteration, exclude_empty: exclude_empty, mathjax: mathjax)
        output += "</div></div>"
      else
        case value
        when Hash
          output += "<div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>"
          output += "<div class='json-header' onclick='toggleItem(this)'>"
          output += "<span>#{key}</span>"
          output += " <i class='fas fa-chevron-down float-right'></i> <span class='toggle-text'>click to toggle</span>"
          output += "</div>"
          output += "<div class='json-content'"
          output += json2html(value, iteration: iteration, exclude_empty: exclude_empty, mathjax: mathjax)
          output += "</div></div>"
        when Array
          if value.all? { |v| v.is_a?(String) }
            output += "<div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>"
            output += "<span>#{key}: [#{value.join(', ')}]</span>"
            output += "</div>"
          else
            output += "<div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>"
            output += "<div class='json-header' onclick='toggleItem(this)'>"
            output += "<span>#{key}</span>"
            output += " <i class='fas fa-chevron-down float-right'></i> <span class='toggle-text'>click to toggle</span>"
            output += "</div>"
            output += "<div class='json-content'>"
            output += "<ul class='no-bullets'>"
            value.each do |v|
              output += if v.is_a?(String)
                          v = StringUtils.markdown_to_html(v, mathjax: mathjax)
                          "<li>#{v}</li>"
                        else
                          "<li>#{json2html(v, iteration: iteration, exclude_empty: exclude_empty, mathjax: mathjax)}</li>"
                        end
            end
            output += "</ul>"
            output += "</div></div>"
          end
        else
          # Check if the value is a single paragraph
          if value.is_a?(String) && !value.include?("\n")
            output += "<div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>"
            output += "<span>#{key}: </span>"
            output += "<span>#{value}</span>"
            output += "</div>"
          else
            output += "<div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>"
            output += "<span>#{key}: </span>"
            value = StringUtils.markdown_to_html(value, mathjax: mathjax)
            output += "<span>#{value}</span>"
            output += "</div>"
          end
        end
      end
    end

    "<div class='json-container'>#{output}</div>"
  end

  def send_command(command:,
                   container: "python",
                   success: "Command executed successfully")

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
      "#{success}: #{stdout}"
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

  # This is currently not used in the app
  # Created to experiment with Google Gemini's function calling feature

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

  def current_time
    Time.now.to_s
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
      # stdout.to_s.encode('UTF-8').gsub(/\\u([0-9a-fA-F]{4})/) { 
      #   [$1.to_i(16)].pack('U*') 
      # }
      stdout
    else
      stdout.strip.empty? ? stderr : stdout
    end
  end

  def markdownify(text)
    model = CONFIG["AI_USER_MODEL"] || "gpt-4o"
    sys_prompt = <<~PROMPT
    Convert a text document to markdown format. The text is extracted using the jQuery's text() method. Thus it does not retain the original formatting and structure of the webpage. The text is extracted from the webpage: #{url}. Do your best to convert the text to markdown format so that it reflects the original structure, formatting, and content of the webpage. If you find program code in the text, make sure to enclose it in code blocks. If you find lists, make sure to convert them to markdown lists. Do not enclose the response in the Markdown code block; just provide the markdown text.
      PROMPT
    parameters = {
      "model" => model,
      "n" => 1,
      "stream" => false,
      "stop" => nil,
      "messages" => [
        {
          "role" => "system",
          "content" => sys_prompt
        },
        {
          "role" => "user",
          "content" => text
        }
      ]
    }
    send_query(parameters)
  end

  def self.fetch_webpage(url)
    max_retrials = 5
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
        # markdownify(stdout)
        stdout.strip
      end
    else
      stdout.strip.empty? ? stderr : stdout
    end
  end

  def check_vision_capability(model)
    self.class.check_vision_capability(model)
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
