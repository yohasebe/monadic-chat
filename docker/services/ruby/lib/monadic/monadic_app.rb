# frozen_string_literal: true

SINGLETON_TOKENIZER = FlaskAppClient.new

class MonadicApp
  TOKENIZER = SINGLETON_TOKENIZER

  # access the flask app client so that it gets ready before the first request

  attr_accessor :api_key, :context

  def initialize
    @context = {}
    @api_key = ""
  end

  # Wrap the user's message in a monad
  def monadic_unit(message)
    res = { "message": message,
            "context": @context }
    <<~MONAD
      ```json
      #{res.to_json}
      ```
    MONAD
  end

  # Unwrap the monad and return the message
  def monadic_unwrap(monad)
    if /(?:```json\s*)?{(.+)\s*}(?:\s*```)?/m =~ monad
      json = "{#{Regexp.last_match(1)}}"
      JSON.parse(json)
    else
      { "message" => monad.to_s, "context" => @context }
    end
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

    <<~MONAD

      ```json
      #{JSON.pretty_generate(sanitize_data(obj))}
      ```

    MONAD
  end

  # Convert a monad to HTML
  def monadic_html(monad)
    obj = monadic_unwrap(monad)
    json2html(obj)
  end

  # Convert snake_case to space ceparated capitalized words
  def snake2cap(snake)
    snake.split("_").map(&:capitalize).join(" ")
  rescue StandardError
    snake
  end

  # Convert a JSON object to HTML
  def json2html(hash, iteration: 0)
    iteration += 1
    output = +""
    hash.each do |key, value|
      value = UtilitiesHelper.markdown_to_html(value) if key == "message"

      key = snake2cap(key)
      margin = iteration - 2
      case value
      when Hash
        if iteration == 1
          output += "<div class='mb-2'>"
          output += json2html(value, iteration: iteration)
          output += "</div>"
        else
          output += "<div class='mb-2' style='margin-left:#{margin}em'> <span class='fw-bold text-secondary'>#{key}: </span><br>"
          output += json2html(value, iteration: iteration)
          output += "</div>"
        end
      when Array
        if iteration == 1
          output += "<li class='mb-2'>"
          output += json2html(value, iteration: iteration)
          output += "</li>"
        else
          output += "<div class='mb-2' style='margin-left:#{margin}em'> <span class='fw-bold text-secondary'>#{key}: </span><br><ul class='no-bullets'>"
          value.each do |v|
            output += if v.is_a?(String)
                        "<li style='margin-left:#{margin}em'>#{v} </li>"
                      else
                        json2html(v, iteration: iteration)
                      end
          end
        end
        output += "</ul></div>"
      else
        output += if iteration == 1
                    "<div class='mb-3' style='margin-left:#{margin + 1}em'>#{value}</div><hr />"
                  else
                    "<div style='margin-left:#{margin}em'> <span class='fw-bold text-secondary'>#{key}: </span>#{value}</div>"
                  end
      end
    end

    "<div class='mb-3'>#{output}</div>"
  end

  def send_command(command:,
                   container:,
                   success: "")
    case container.to_s
    when "ruby"
      if IN_CONTAINER
        script_dir = "/monadic/scripts"
        script_dir_local = "/monadic/data/scripts"
        shared_volume = "/monadic/data"
      else
        script_dir = File.expand_path(File.join(__dir__, "..", "..", "scripts"))
        script_dir_local = File.expand_path(File.join(Dir.home, "monadic", "data", "scripts"))
        shared_volume = File.expand_path(File.join(Dir.home, "monadic", "data"))
      end
      system_command = <<~SYS
        find #{script_dir} -type f -exec chmod +x {} + 2>/dev/null | : && \
        find #{script_dir_local} -type f -exec chmod +x {} + 2>/dev/null | : && \
        export PATH="#{script_dir}:${PATH}" && \
        export PATH="#{script_dir_local}:${PATH}" && \
        cd #{shared_volume} && \
        #{command}
      SYS
    when "python"
      shared_volume = "/monadic/data"
      container = "monadic-chat-python-container"
      script_dir = "/monadic/data/scripts"
      system_command = <<~DOCKER
        docker exec #{container} bash -c 'find #{script_dir} -type f -exec chmod +x {} +'
        docker exec -w #{shared_volume} #{container} #{command}
      DOCKER
    end

    stdout, stderr, status = Open3.capture3(system_command)

    log = <<~LOG
      ### original command

      #{system_command}
      ---
      ### stdout

      #{stdout}
      ---
      ### stderr

      #{stderr}
      ---
      ### status

      #{status}
    LOG

    File.open(File.join(Dir.home, "response.txt"), "w") { |file| file.write(log) }

    if block_given?
      yield(stdout, stderr, status)
    elsif status.success?
      "#{success}#{stdout}"
    else
      "Error occurred: #{stderr}"
    end
  rescue StandardError => e
    "Error occurred: #{e.message}"
  end

  def write_to_file(filename:, extension:, text:)
    shared_volume = "/monadic/data/"
    if IN_CONTAINER
      data_dir = "/monadic/data/"
    else
      data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
    end

    container = "monadic-chat-python-container"

    filepath = File.join(data_dir, "#{filename}.#{extension}")

    # create a temporary file inside the data directory
    File.open(filepath, "w") do |f|
      f.write(text)
    end

    docker_command = <<~DOCKER
      docker cp #{filepath} #{container}:#{shared_volume}
    DOCKER
    _stdout, stderr, status = Open3.capture3(docker_command)
    if status.success
      "The file has been written successfully."
    else
      "Error occurred: #{stderr}"
    end
  rescue StandardError
    "Error occurred: The code could not be executed."
  end

  def send_code(code:, command:, extension:)
    shared_volume = "/monadic/data/"
    if IN_CONTAINER
      data_dir = "/monadic/data/"
    else
      data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
    end

    container = "monadic-chat-python-container"

    # create a temporary file inside the data directory
    temp_file = Tempfile.new(["code", ".#{extension}"], data_dir)

    temp_file.write(code)
    temp_file.close
    docker_command = <<~DOCKER
      docker cp #{temp_file.path} #{container}:#{shared_volume}
    DOCKER
    stdout, stderr, status = Open3.capture3(docker_command)
    unless status.success?
      return "Error occurred: #{stderr}"
    end

    local_files1 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]

    docker_command = <<~DOCKER
      docker exec -w #{shared_volume} #{container} #{command} /monadic/data/#{File.basename(temp_file.path)}
    DOCKER
    stdout, stderr, status = Open3.capture3(docker_command)
    if status.success?
      local_files2 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]
      new_files = local_files2 - local_files1
      if !new_files.empty?
        new_files = new_files.map { |file| "/data/" + File.basename(file) }
        output = "The code has been executed successfully; Files generated: #{new_files.join(", ")}"
        output += "; Output: #{stdout}" if stdout.strip.length.positive?
      else
        output = "The code has been executed successfully"
        output += "; Output: #{stdout}" if stdout.strip.length.positive?
      end
      output
    else
      "Error occurred: #{stderr}"
    end
  rescue StandardError
    "Error occurred: The code could not be executed."
  end

  def selenium_job(url: "")
    command = "bash -c '/monadic/scripts/webpage_fetcher.py --url \"#{url}\" --filepath \"/monadic/data/\" --mode \"md\" '"
    # we wait for the following command to finish before returning the output
    send_command(command: command, container: "python") do |stdout, stderr, status|
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]
        if IN_CONTAINER
          begin
            filename = File.join("/monadic/data/", File.basename(filename))
          rescue StandardError
            filename = File.join(File.expand_path("~/monadic/data/"), File.basename(filename))
          end
        else
          filename = File.join(File.expand_path("~/monadic/data/"), File.basename(filename))
        end
        retrials = 3
        sleep(5)
        begin
          contents = File.read(filename)
        rescue StandardError
          if retrials.positive?
            retrials -= 1
            sleep(5)
            retry
          else
            "Error occurred: The #{filename} could not be read."
          end
        end
        contents
      else
        "Error occurred: #{stderr}"
      end
    end
  end

  ### API functions

  def run_code(code: "", command: "", extension: "")
    return "Error: code, command, and extension are required." if !code || !command || !extension

    send_code(code: code, command: command, extension: extension)
  end

  # This is currently not used in the app
  # Created to experiment with Google Gemini's function calling feature
  def run_script(code: "", command: "", extension: "")
    # remove escape characters from the code
    code = code.gsub(/\\n/) { "\n" }
    code = code.gsub(/\\'/) { "'" }
    code = code.gsub(/\\"/) { '"' }
    code = code.gsub(/\\\\/) { "\\" }

    # return the error message unless all the arguments are provided
    return "Error: code, command, and extension are required." if !code || !command || !extension

    send_code(code: code, command: command, extension: extension)
  end

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
                 success: "The library #{command} has been installed successfully.\n")
  end

  def add_jupyter_cells(filename:, cells:)
    return "Error: filename is required." if filename.empty? || filename == ""
    return "Error: cells is required." if cells.empty? || cells == ""

    tempfile = Time.now.to_i.to_s
    write_to_file(filename: tempfile, extension: "json", text: cells.to_json)

    if IN_CONTAINER
      begin
        filepath = File.join("/monadic/data/", tempfile + ".json")
      rescue StandardError
        filepath = File.join(File.expand_path("~/monadic/data/"), tempfile + ".json")
      end
    else
      filepath = File.join(File.expand_path("~/monadic/data/"), tempfile + ".json")
    end

    success = false
    max_retrial = 5
    max_retrial.times do
      sleep 1.0
      if File.exist?(filepath)
        success = true
        break
      end
    end
    results1 = if success
                 command = "bash -c 'jupyter_controller.py add_from_json #{filename} #{tempfile}' "
                 send_command(command: command,
                              container: "python",
                              success: "The cells have been added to the notebook successfully.\n")
               else
                 false
               end
    if results1
      results2 = run_jupyter_cells(filename: filename)
      results1 + "\n\n" + results2
    else
      "Error: The cells could not be added to the notebook."
    end
  end

  def run_jupyter_cells(filename:)
    command = "jupyter nbconvert --to notebook --execute #{filename} --ExecutePreprocessor.timeout=60 --allow-errors --inplace"
    send_command(command: command,
                 container: "python",
                 success: "The notebook has been executed and updated with the results successfully.\n")
  end

  def create_jupyter_notebook(filename:)
    begin
      # filename extension is not required and removed if provided
      filename = filename.to_s.split(".")[0]
    rescue StandardError
      filename = ""
    end
    command = "bash -c 'jupyter_controller.py create #{filename}'"
    send_command(command: command, container: "python")
  end

  def run_jupyter(command: "")
    command = case command
              when "start", "run"
                "bash -c 'run_jupyter.sh run'"
              when "stop"
                "bash -c 'run_jupyter.sh stop'"
              else
                return "Error: Invalid command."
              end
    send_command(command: command,
                 container: "python",
                 success: "Success: Access Jupter Lab at 127.0.0.1:8888/lab\n")
  end

  def run_bash_command(command: "")
    send_command(command: command,
                 container: "python",
                 success: "Command executed successfully.\n")
  end

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

  def analyze_image(message: "", image_path: "")
    message = message.gsub(/"/, '\"')
    command = <<~CMD
      bash -c 'simple_image_query.rb "#{message}" "#{image_path}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def analyze_audio(audio: "")
    command = <<~CMD
      bash -c 'simple_whisper_query.rb "#{audio}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def text_to_speech(text: "", speed: 1.0, voice: "alloy", language: "auto")
    text = text.gsub(/"/, '\"')

    primary_save_path = "/monadic/data/"
    secondary_save_path = File.expand_path("~/monadic/data/")

    save_path = Dir.exist?(primary_save_path) ? primary_save_path : secondary_save_path
    textfile = "#{Time.now.to_i}.md"
    textpath = File.join(save_path, textfile)

    File.open(textpath, "w") do |f|
      f.write(text)
    end

    command = <<~CMD
      bash -c 'simple_tts_query.rb "#{textpath}" --speed=#{speed} --voice=#{voice} --language=#{language}'
    CMD
    send_command(command: command, container: "ruby")
  end

  def generate_image(prompt: "", size: "1024x1024")
    command = <<~CMD
      bash -c 'simple_image_generation.rb -p "#{prompt}" -s "#{size}"'
    CMD
    send_command(command: command, container: "ruby")
  end

  def search_wikipedia(search_query: "", language_code: "en")
    number_of_results = 10

    base_url = "https://api.wikimedia.org/core/v1/wikipedia/"
    endpoint = "/search/page"
    url = base_url + language_code + endpoint
    parameters = { "q": search_query, "limit": number_of_results }

    search_uri = URI(url)
    search_uri.query = URI.encode_www_form(parameters)

    search_response = perform_request_with_retries(search_uri)
    search_data = JSON.parse(search_response)

    <<~TEXT
      ```json
      #{search_data.to_json}
      ```
    TEXT
  end

  def perform_request_with_retries(uri)
    retries = 2
    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5) do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request)
      end
      response.body
    rescue Net::OpenTimeout
      if retries.positive?
        retries -= 1
        retry
      else
        raise
      end
    end
  end

  def cosine_similarity(a, b)
    raise ArgumentError, "a and b must be of the same size" if a.size != b.size

    dot_product = a.zip(b).map { |x, y| x * y }.sum
    magnitude_a = Math.sqrt(a.map { |x| x**2 }.sum)
    magnitude_b = Math.sqrt(b.map { |x| x**2 }.sum)
    dot_product / (magnitude_a * magnitude_b)
  end

  def most_similar_text_index(topic, texts)
    embeddings = get_embeddings(topic)
    texts_embeddings = texts.map { |t| get_embeddings(t) }.compact
    cosine_similarities = texts_embeddings.map { |e| cosine_similarity(embeddings, e) }
    cosine_similarities.each_with_index.max[1]
  end

  def split_text(text)
    tokenized = MonadicApp::TOKENIZER.get_tokens_sequence(text)
    segments = []
    while tokenized.size < MAX_TOKENS_WIKI.to_i
      segment = tokenized[0..MAX_TOKENS_WIKI.to_i]
      segments << MonadicApp::TOKENIZER.decode_tokens(segment)
      tokenized = tokenized[MAX_TOKENS_WIKI.to_i..]
    end
    segments << flask_app_client.decode_tokens(tokenized)
    segments
  rescue StandardError
    [text]
  end

  def get_embeddings(text, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key = ENV["OPENAI_API_KEY"]

    request["Authorization"] = "Bearer #{api_key}"
    request.body = {
      model: "text-embedding-3-small",
      input: text
    }.to_json

    response = nil
    retries.times do |i|
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      break if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "Error: #{e.message}. Retrying in #{i + 1} seconds..."
      sleep(i + 1)
    end

    begin
      JSON.parse(response.body)["data"][0]["embedding"]
    rescue StandardError
      nil
    end
  end

  def extract_frames(file:, fps: 1)
    command = <<~CMD
      bash -c 'extract_frames.py "#{file}" ./ --fps #{fps} --format png --json --audio'
    CMD
    send_command(command: command, container: "python")
  end

  def analyze_video(json:, audio: nil, query: nil)
    if json.nil?
      return "Error: JSON file is required for analyzing the video."
    end

    query = query ? " \"#{query}\"" : ""

    video_command = <<~CMD
      bash -c 'simple_video_query.rb "#{json}#{query}"'
    CMD
    description = send_command(command: video_command, container: "ruby")

    if audio
      audio_command = <<~CMD
        bash -c 'simple_whisper_query.rb "#{audio}"'
      CMD
      audio_description = send_command(command: audio_command, container: "ruby")
      description += "\n\n---\n\n"
      description += "Audio Transcript:\n#{audio_description}"
    end

    description
  end

  def ai_user_initial_prompt
    text = <<~TEXT
      The user is currently answering various types of questions, writing computer program code, making decent suggestions, and giving helpful advice on your message. Give the user requests, suggestions, or questions so that the conversation is engaging and interesting. If there are any errors in the responses you get, point them out and ask for correction. Use the same language as the user.

      Keep on pretending as if you were the "user" and as if the user were the "assistant" throughout the conversation.

      Do your best to make the conversation as natural as possible. Do not change subjects unless it is necessary, and keep the conversation going by asking questions or making comments relevant to the preceding and current topics.

      Your response should be consice and clear. Even if the preceding messages are formatted as json, you keep your response as plain text. do not use parentheses or brackets in your response.

      Remember you are the one who inquires for information, not providing the answers.
    TEXT
    text.strip
  end
end
