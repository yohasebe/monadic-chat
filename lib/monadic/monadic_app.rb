# frozen_string_literal: true

class MonadicApp
  TOKENIZER = Tiktoken.get_encoding("cl100k_base")

  attr_accessor :api_key
  attr_reader :context

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
    /(?:```json\s*)?{(.+)\s*}(?:\s*```)?/m =~ monad
    json = "{#{Regexp.last_match(1)}}"
    JSON.parse(json)
  end

  # Unwrap the monad and return the message after applying a given process (if any)
  def monadic_map(monad)
    obj = monadic_unwrap(monad)
    @context = block_given? ? yield(obj["context"]) : obj["context"]

    <<~MONAD

      ```json
      #{JSON.pretty_generate(obj)}
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
  end

  # Convert a JSON object to HTML
  def json2html(hash, iteration: 0)
    iteration += 1
    output = +""
    hash.each do |key, value|
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

  def generate_image(hash, num_retrials: 10)
    prompt = hash[:prompt]
    num = hash[:num] || 1
    size = hash[:size] || 256
    format = hash[:format] || "url"

    raise "Size must be 256, 512, or 1024" unless [256, 512, 1024].include?(size)
    raise "Number of images must be between 1 and 10" unless (1..10).include?(num)

    url = "https://api.openai.com/v1/images/generations"
    res = nil

    begin
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      }

      body = {
        "prompt" => prompt,
        "n" => num,
        "size" => "#{size}x#{size}",
        "response_format" => format
      }

      res = HTTP.headers(headers).post(url, json: body)
    rescue HTTP::Error, HTTP::TimeoutError => e
      return { "type" => "error", "content" => "ERROR: #{e.message}" }
    end

    if res.status.success?
      puts "Image generated successfully"
      img = JSON.parse(res.body)
      "<img class='generate_image' src='#{img["data"][0]["url"]}' />"
    else
      pp "Error: #{res.status} - #{res.body}"
      { "type" => "error", "content" => "DALL-E 2 API Error" }
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    num_retrials -= 1
    if num_retrials.positive?
      sleep 1
      generate_image(hash, num_retrials: num_retrials)
    else
      <<~TEXT
        "SEARCH SNIPPETS: ```
        information not found"
        ```
      TEXT
    end
  end
end
