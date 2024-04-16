# frozen_string_literal: true

module WebSocketHelper
  # Handle websocket connection

  # check if the total tokens of past messages is less than max_tokens in obj
  # token count is calculated using tiktoken_ruby gem
  def check_past_messages(obj)
    # filter out any messages of type "search"
    messages = session[:messages].filter { |m| m["type"] != "search" }

    res = false
    max_tokens = obj["max_tokens"].to_i
    context_size = obj["context_size"].to_i
    tokens = []

    # calculate token count for each message and mark as active
    messages.each do |m|
      tokens << MonadicApp::TOKENIZER.count_tokens(m["text"])
      m["active"] = true
    end

    # calculate total token count of all messages
    count_tokens = tokens.sum

    # filter out inactive messages
    active_messages = messages.filter { |m| m["active"] }

    # remove oldest messages until total token count and message count are within limits
    loop do
      break if active_messages.empty? || (tokens.sum <= max_tokens && active_messages.size <= context_size)

      res = true
      tokens.shift
      active_messages[0]["active"] = false
      active_messages.shift
    end

    # return information about state of messages array
    { changed: res,
      count_tokens: count_tokens,
      count_active_tokens: tokens.sum,
      count_messages: messages.size,
      count_active_messages: active_messages.size }
  end

  def websocket_handler(env)
    EventMachine.run do
      queue = Queue.new
      thread = nil
      sid = nil

      @channel = EventMachine::Channel.new
      ws = Faye::WebSocket.new(env, nil, { ping: 15 })

      ws.on :open do
        sid = @channel.subscribe { |obj| ws.send(obj) }
      end

      ws.on :message do |event|
        obj = JSON.parse(event.data)
        msg = obj["message"] || ""

        case msg
        when "TTS"
          text = obj["text"]
          voice = obj["voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          model = obj["model"]
          res_hash = tts_api_request(text, voice, speed, response_format, model)
          @channel.push(res_hash.to_json)
        when "TTS_STREAM"
          thread = Thread.new do
            text = obj["text"]
            voice = obj["voice"]
            speed = obj["speed"]
            response_format = obj["response_format"]
            model = obj["model"]
            tts_api_request(text, voice, speed, response_format, model) do |fragment|
              @channel.push(fragment.to_json)
            end
          end
        when "CANCEL"
          thread&.kill
          thread = nil
          queue.clear
        when "PDF_TITLES"
          ws.send({ "type" => "pdf_titles", "content" => list_pdf_titles }.to_json)
        when "DELETE_PDF"
          title = obj["contents"]
          res = EMBEDDINGS_DB.delete_by_title(title)
          if res
            ws.send({ "type" => "pdf_deleted", "res" => "success", "content" => "<b>#{title}</b> deleted successfully" }.to_json)
          else
            ws.send({ "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting <b>#{title}</b>" }.to_json)
          end
        when "CHECK_TOKEN"
          if obj["initial"].to_s == "true"
            token = settings.api_key
          else
            token = obj["contents"]
          end

          res = set_api_key(token) if token

          if token && res.is_a?(Hash) && res.key?("type")
            if res["type"] == "error"
              ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
            else
              ws.send({ "type" => "token_verified", "token" => token, "content" => res["content"], "models" => res["models"] }.to_json)
            end
          else
            ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
          end
        when "NUM_TOKENS"
          half_max = obj["max_tokens"].to_i / 2
          doc = TextSplitter.new(text: obj["message"], max_tokens: half_max, separator: "\n", overwrap_lines: 0)
          split_texts = doc.split_text
          total_num_tokens = split_texts.map { |t| t["tokens"] }.sum
          ws.send({ "type" => "num_tokens", "content" => total_num_tokens }.to_json)
        when "PING"
          @channel.push({ "type" => "pong" }.to_json)
        when "RESET"
          session[:messages].clear
          session[:parameters].clear
          session[:error] = nil
          session[:obj] = nil
        when "LOAD"
          if session[:error]
            ws.send({ "type" => "error", "content" => session[:error] }.to_json)
            session[:error] = nil
          end

          apps = {}
          APPS.each do |k, v|
            apps[k] = {}
            v.settings.each do |p, m|
              apps[k][p] = m ? m.to_s : nil
            end
            v.api_key = settings.api_key
          end
          messages = session[:messages].filter { |m| m["type"] != "search" }
          @channel.push({ "type" => "apps", "content" => apps, "version" => session[:version], "docker" => session[:docker] }.to_json) unless apps.empty?
          @channel.push({ "type" => "parameters", "content" => session[:parameters] }.to_json) unless session[:parameters].empty?
          @channel.push({ "type" => "past_messages", "content" => messages }.to_json) unless session[:messages].empty?
          past_messages_data = check_past_messages(session[:parameters])
          @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
          @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
        when "DELETE"
          session[:messages].delete_if { |m| m["mid"] == obj["mid"] }
          past_messages_data = check_past_messages(session[:parameters])
          messages = session[:messages].filter { |m| m["type"] != "search" }
          @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
          @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
        when "HTML"
          thread&.join
          while !queue.empty?
            last_one = queue.shift
            begin
              content = last_one["choices"][0]
              text = content["text"] || content["message"]["content"]
              # if the current app has a monadic_html method, use it to generate html
              html = if session["parameters"]["monadic"]
                        APPS[session["parameters"]["app_name"]].monadic_html(text)
                     else
                       markdown_to_html(text)
                     end
              if session["parameters"]["response_suffix"]
                html += "\n\n" + session["parameters"]["response_suffix"]
              end

              new_data = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => text, "html" => html, "lang" => detect_language(text), "active" => true }
              @channel.push({ "type" => "html", "content" => new_data }.to_json)
              session[:messages] << new_data
              messages = session[:messages].filter { |m| m["type"] != "search" }
              past_messages_data = check_past_messages(session[:parameters])
              @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
              @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
            rescue StandardError => e
              pp queue
              pp e.message
              pp e.backtrace
              @channel.push({ "type" => "error", "content" => "Something went wrong" }.to_json)
            end
          end
        when "SAMPLE"
          text = obj["content"]
          image = obj["image"]
          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => obj["role"],
                       "text" => text,
                       "html" => markdown_to_html(text),
                       "lang" => detect_language(text),
                       "active" => true }
          new_data["image"] = image if image
          @channel.push({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data
        when "AUDIO"
          if obj["content"].nil?
            @channel.push({ "type" => "error", "content" => "Voice input is empty" }.to_json)
          else

            blob = Base64.decode64(obj["content"])
            res = whisper_api_request(blob, obj["format"], obj["lang_code"])
            if res["text"] && res["text"] == ""
              @channel.push({ "type" => "error", "content" => "The text imput is empty" }.to_json)
            elsif res["type"] && res["type"] == "error"
              @channel.push({ "type" => "error", "content" => res["content"] }.to_json)
            else
              @channel.push({ "type" => "whisper", "content" => res["text"] }.to_json)
            end
          end
        else
          session[:parameters].merge! obj

          if obj["auto_speech"]
            voice = obj["tts_voice"]
            speed = obj["tts_speed"]
            response_format = "mp3"
            model = "tts-1"
          end

          thread = Thread.new do
            buffer = []
            cutoff = false

            app_name = obj["app_name"]
            app_obj = APPS[app_name]
            if app_obj.respond_to?(:api_request)
              api_request = app_obj.method(:api_request)
            else
              api_request = method(:openai_api_request)
            end

            responses = api_request.call("user", session) do |fragment|
              if fragment["type"] == "error"
                @channel.push({ "type" => "error", "content" => "E1:#{fragment.to_s}" }.to_json)
              elsif fragment["type"] == "fragment"
                text = fragment["content"]
                buffer << text unless text.empty? || text == "DONE"
                ps = PragmaticSegmenter::Segmenter.new(text: buffer.join)
                segments = ps.segment
                if !cutoff && segments.size > 1
                  candidate = segments.first
                  splitted = candidate.split("---")
                  if splitted.size > 1
                    cutoff = true
                  end

                  if obj["auto_speech"]
                    text = splitted[0]
                    if text != "" && candidate != ""
                      res_hash = tts_api_request(text, voice, speed, response_format, model) 
                      @channel.push(res_hash.to_json)
                    end
                  end

                  buffer = segments[1..]
                end
              end
              @channel.push(fragment.to_json)
            end

            if obj["auto_speech"] && !cutoff
              text = buffer.join
              res_hash = tts_api_request(text, voice, speed, response_format, model)
              @channel.push(res_hash.to_json)
            end

            responses.each do |response|
              if response.key?("type") && response["type"] == "error"
                content = response.dig("choices", 0, "message", "content")
                @channel.push({ "type" => "error", "content" => response.to_s }.to_json)
              else
                content = response.dig("choices", 0, "message", "content").gsub(/\bsandbox:\//, "/")
                response.dig("choices", 0, "message")["content"] = content
                queue.push(response)
              end
            end
          end
        end
      end

      ws.on :close do |event|
        pp [:close, event.code, event.reason]
        ws = nil
        @channel.unsubscribe(sid)
      end

      ws.rack_response
    end
  rescue StandardError => e
    # show the details of the error on the console
    puts e.inspect
    puts e.backtrace
  end
end
