# frozen_string_literal: true

class MonadicApp

  TOKENIZER = FlaskAppClient.new
  attr_accessor :api_key
  attr_accessor :context

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
      {"message" => monad.to_s, "context" => @context}
    end
  end

  # sanitize the data to remove invalid characters
  def sanitize_data(data)
    if data.is_a? String
      return data.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
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
    begin
      snake.split("_").map(&:capitalize).join(" ")
    rescue
      snake
    end
  end

  # Convert a JSON object to HTML
  def json2html(hash, iteration: 0)
    iteration += 1
    output = +""
    hash.each do |key, value|
      value = UtilitiesHelper:: markdown_to_html(value) if key == "message"

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
          output += "<div class='mb-2' style='margin-left:#{margin}em'> <span class='fw-bold text-secondary'>#{key}: </span><br></ul>"
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
    begin
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
        system_command =<<~SYS
          chmod +x #{script_dir}/* && \
          chmod +x #{script_dir_local}/* && \
          export PATH="#{script_dir}:${PATH}" && \
          export PATH="#{script_dir_local}:${PATH}" && \
          cd #{shared_volume} && \
          #{command}
        SYS
      when "python"
        shared_volume = "/monadic/data"
        container = "monadic-chat-python-container"
        script_dir_local = "/monadic/data/scripts"
        system_command =<<~DOCKER
          docker exec #{container} bash -c 'chmod +x #{script_dir_local}/*'
          docker exec -w #{shared_volume} #{container} #{command}
        DOCKER
      end

      stdout, stderr, status = Open3.capture3(system_command)
      if block_given?
        yield(stdout, stderr, status)
      else
        if status.success?
          "#{success}#{stdout}"
        else
          "Error occurred: #{stderr}"
        end
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
  end

  def send_code(code:, command:, extention:)
    begin
      shared_volume = "/monadic/data/"
      if IN_CONTAINER
        data_dir = "/monadic/data/"
      else
        data_dir = File.expand_path(File.join(Dir.home, "monadic", "data"))
      end

      container = "monadic-chat-python-container"

      # create a temporary file inside the data directory
      temp_file = Tempfile.new(["code", ".#{extention}"], data_dir)
      temp_file.write(code)
      temp_file.close
      docker_command =<<~DOCKER
        docker cp #{temp_file.path} #{container}:#{shared_volume}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      unless status.success?
        return "Error occurred: #{stderr}"
      end

      local_files1 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]

      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{container} #{command} /monadic/data/#{File.basename(temp_file.path)}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        local_files2 = Dir[File.join(File.expand_path(File.join(Dir.home, "monadic", "data")), "*")]
        new_files = local_files2 - local_files1
        if new_files.length > 0
          new_files = new_files.map { |file| "/data/" + File.basename(file) }
          output = "The code has been executed successfully; Files generated: #{new_files.join(', ')}"
          output += "; Output: #{stdout}" if stdout.strip.length > 0
        else
          output = "The code has been executed successfully"
          output += "; Output: #{stdout}" if stdout.strip.length > 0
        end
        output
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: The code could not be executed."
    end
  end

  def selenium_job(url: "")
    command = "bash -c '/monadic/scripts/webpage_fetcher.py --url \"#{url}\" --filepath \"/monadic/data/\" --mode \"md\" '"
    send_command(command: command, container: "python") do |stdout, stderr, status|
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]
        sleep(1)
        begin
          contents = File.read(filename)
        rescue StandardError => e
          filepath = File.join(File.expand_path("~/monadic/data/"), File.basename(filename))
          contents = File.read(filepath)
        end
        contents
      else
        "Error occurred: #{stderr}"
      end
    end
  end
end
