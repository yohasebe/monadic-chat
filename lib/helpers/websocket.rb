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
      tokens << MonadicApp::TOKENIZER.encode(m["text"]).size
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
      ws = Faye::WebSocket.new(env)

      ws.on :open do
        sid = @channel.subscribe { |obj| ws.send(obj) }
      end

      ws.on :message do |event|
        obj = JSON.parse(event.data)
        msg = obj["message"] || ""

        case msg
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
          token = obj["contents"]
          res = set_api_token(token)
          if res["type"] == "error"
            ws.send({ "type" => "token_not_found", "content" => "" }.to_json)
          else
            ws.send({ "type" => "token_verified", "content" => res["content"], "models" => res["models"] }.to_json)
          end
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
          end
          messages = session[:messages].filter { |m| m["type"] != "search" }
          @channel.push({ "type" => "apps", "content" => apps }.to_json) unless apps.empty?
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
          text = queue.pop["choices"][0]["text"]
          # if the current app has a monadic_html method, use it to generate html
          html = if session["parameters"]["monadic"]
                   APPS[session["parameters"]["app_name"]].monadic_html(text)
                 else
                   markdown_to_html(text)
                 end
          new_data = { "mid" => SecureRandom.hex(4), "role" => "assistant", "text" => text, "html" => html, "lang" => detect_language(text), "active" => true }
          @channel.push({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data
          messages = session[:messages].filter { |m| m["type"] != "search" }
          past_messages_data = check_past_messages(session[:parameters])
          @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
          @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
        when "SAMPLE"
          text = obj["content"]
          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => obj["role"],
                       "text" => text,
                       "html" => markdown_to_html(text),
                       "lang" => detect_language(text),
                       "active" => true }
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
          thread = Thread.new do
            buffer = []
            cutoff = false
            response = completion_api_request("user") do |fragment|
              if fragment["type"] == "error"
                @channel.push({ "type" => "error", "content" => fragment["content"] }.to_json)
              elsif fragment["type"] == "fragment" && !cutoff
                buffer << fragment["content"] unless fragment["content"].empty? || fragment["content"] == "DONE"
                ps = PragmaticSegmenter::Segmenter.new(text: buffer.join)
                segments = ps.segment
                if segments.size > 1
                  candidate = segments.first
                  splitted = candidate.split("---")
                  cutoff = true if splitted.size > 1
                  @channel.push({ "type" => "sentence", "content" => candidate, "lang" => detect_language(candidate) }.to_json) if splitted[0] != "" && candidate != ""
                  buffer = segments[1..]
                end
              end
              @channel.push(fragment.to_json)
            end
            unless cutoff
              candidate = buffer.join
              splitted = candidate.split("---")
              @channel.push({ "type" => "sentence", "content" => splitted[0], "lang" => detect_language(splitted[0]) }.to_json) if splitted[0] != ""
            end
            if response && response["type"] == "error"
              @channel.push({ "type" => "error", "content" => response["content"] }.to_json)
            else
              queue.push(response)
            end
          end
        end
      end

      ping_timer = EventMachine.add_periodic_timer(30) do
        ws&.ping("ping") do
          puts "Received PING"
        end
      end

      ws.on :close do |event|
        EventMachine.cancel_timer(ping_timer)
        p [:close, event.code, event.reason]
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
