# frozen_string_literal: true

# HTML response handler for WebSocket connections.
# Processes completed API responses: extracts thinking blocks, citations,
# ABC notation blocks, assembles final HTML message, handles context
# extraction for monadic apps, and broadcasts to client.

module WebSocketHelper
  private def handle_ws_html(connection, obj, session, thread, queue)
    thread&.join
    until queue.empty?
      last_one = queue.shift
      begin
        content = last_one["choices"][0]

        # Always use message content - monadic apps will have JSON in content field
        text = content["text"] || content["message"]["content"]

        # Append tool HTML fragments (e.g., ABC notation from Music Lab).
        # Tools store HTML in session[:tool_html_fragments]; the ABC block
        # extraction below will handle them through the normal pipeline.
        if session[:tool_html_fragments]
          stored_fragments = session.delete(:tool_html_fragments)
          text = text.to_s + "\n\n" + stored_fragments.join("\n\n")
        end
        Monadic::Utils::ExtraLogger.log { "[WebSocket] text extraction: content keys=#{content.keys}, text=#{text.class}:#{text.to_s[0..100]}..." } if CONFIG["EXTRA_LOGGING"] && session["parameters"]["app_name"]&.include?("Perplexity")
        # Extract thinking content uniformly from message
        thinking = content["message"]["thinking"] || content["message"]["reasoning_content"] || content["thinking"]

        # Check if text contains citation HTML that needs to be extracted
        citation_html = nil
        if text && text.include?("<div data-title='Citations'")
          # Extract citation HTML from the text
          if match = text.match(/(\n\n<div data-title='Citations'[^>]*>.*?<\/div>)/m)
            citation_html = match[1]
            # Remove citation HTML from text so it doesn't get processed by markdown
            text = text.sub(match[1], '')

            if CONFIG["EXTRA_LOGGING"]
              DebugHelper.debug("WebSocket: Extracted citation HTML from text", category: :api, level: :info)
              DebugHelper.debug("WebSocket: Citation HTML: #{citation_html[0..100]}...", category: :api, level: :debug)
            end
          end
        elsif CONFIG["EXTRA_LOGGING"]
          if text && text.match(/\[\d+\]/)
            DebugHelper.debug("WebSocket: Found citation references but no HTML: #{text.scan(/\[\d+\]/).join(', ')}", category: :api, level: :info)
          end
        end


        type_continue = "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results\n"
        code_truncated = "[CODE BLOCK TRUNCATED]"

        if content["finish_reason"] && content["finish_reason"] == "length"
          if text.scan(/(?:\A|\n)```/m).size.odd?
            text += "\n```\n\n> #{type_continue}\n#{code_truncated}"
          else
            text += "\n\n> #{type_continue}"
          end
        end

        if content["finish_reason"] && content["finish_reason"] == "safety"
          ws_session_id = Thread.current[:websocket_session_id]
          safety_error = { "type" => "error", "content" => "api_stopped_safety" }.to_json
          send_or_broadcast(safety_error, ws_session_id)
        end

        # Extract ABC blocks before markdown processing (they're already HTML)
        abc_blocks = []
        text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
          abc_blocks << match
          "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
        end

        params = get_session_params

        # Phase 2: Server-side HTML generation disabled
        # Client-side MarkdownRenderer handles all rendering
        # Keep text in original form with ABC blocks and citations intact

        # For ABC notation, keep the HTML blocks in the text
        # MarkdownRenderer will handle them properly
        final_text = text_for_markdown
        abc_blocks.each_with_index do |block, index|
          final_text = final_text.gsub("ABC_PLACEHOLDER_#{index}", block)
        end

        # Add response suffix if present
        if params["response_suffix"]
          final_text += "\n\n" + params["response_suffix"]
        end

        # Add citation HTML back to text
        if citation_html
          final_text += citation_html
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("WebSocket: Added citation HTML to final text", category: :api, level: :info)
          end
        end

       new_data = { "mid" => SecureRandom.hex(4),
                    "role" => "assistant",
                    "text" => final_text,
                    "lang" => detect_language(final_text),
                    "app_name" => params["app_name"],
                    "monadic" => params["monadic"],
                    "active" => true } # detect_language is called only once here

        if thinking && !thinking.to_s.strip.empty?
          new_data["thinking"] = thinking
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("WebSocket: Attaching thinking block (length=#{thinking.to_s.length})", category: :ui, level: :info)
          end
        end

        # Optional: Use provider-reported usage to set assistant tokens
        # This is disabled by default to avoid confusion and keep a
        # single source of truth (tiktoken_ruby) for token counting.
        # Enable via CONFIG["TOKEN_COUNT_SOURCE"] = "provider_only" or "hybrid".
        begin
          source = (defined?(CONFIG) && CONFIG && CONFIG["TOKEN_COUNT_SOURCE"]) ? CONFIG["TOKEN_COUNT_SOURCE"].to_s.downcase : ""
          provider_usage_enabled = %w[provider_only hybrid].include?(source)
        rescue StandardError
          provider_usage_enabled = false
        end

        if provider_usage_enabled
          usage = last_one["usage"] || last_one.dig("choices", 0, "usage")
          if usage && usage.is_a?(Hash)
            tokens = usage["output_tokens"] || usage["completion_tokens"]
            new_data["tokens"] = tokens.to_i if tokens
          end
        end

        # Get session ID for targeted broadcasting
        ws_session_id = Thread.current[:websocket_session_id]

        # Send HTML message (conversation content)
        html_message = {
          "type" => "html",
          "content" => new_data
        }.to_json
        send_or_broadcast(html_message, ws_session_id)

        session[:messages] << new_data
        sync_session_state!
        # Filter messages by current app_name to prevent cross-app conversation leakage
        params = get_session_params
    current_app_name = obj["app_name"] || params["app_name"]
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }
        past_messages_data = check_past_messages(params)

        # Send status updates
        if past_messages_data[:changed]
          status_message = { "type" => "change_status", "content" => messages }.to_json
          send_or_broadcast(status_message, ws_session_id)
        end

        info_message = { "type" => "info", "content" => past_messages_data }.to_json
        send_or_broadcast(info_message, ws_session_id)

        # Context extraction for monadic apps (automatic context tracking)
        # This runs AFTER the response is sent to the user, in a background thread
        # Uses direct HTTP API calls to avoid re-triggering WebSocket flow
        if params["monadic"]
          begin
            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Monadic mode detected, starting context extraction setup" }

            # Get the provider and context_schema from the app settings
            app_name = params["app_name"]
            app = APPS[app_name] if defined?(APPS) && app_name
            provider = app&.settings&.dig("provider") || app&.settings&.dig(:provider) || "openai"
            context_schema = app&.settings&.dig(:context_schema) || app&.settings&.dig("context_schema")

            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] app_name=#{app_name}, provider=#{provider}, context_schema=#{context_schema ? 'present' : 'nil'}" }

            # Find the last user message from session messages
            user_messages = messages.select { |m| m["role"] == "user" }
            last_user_message = user_messages.last
            # Support both "text" and "content" keys for user messages
            user_text = if last_user_message
              last_user_message["text"] ||
              last_user_message[:text] ||
              (last_user_message["content"].is_a?(String) ? last_user_message["content"] : nil) ||
              (last_user_message["content"].is_a?(Array) ? last_user_message["content"].map { |c| c.is_a?(Hash) ? (c["text"] || c[:text]) : c.to_s }.compact.join("\n") : nil) ||
              ""
            else
              ""
            end

            # Capture session data for thread (avoid closure issues)
            thread_session = session.dup
            thread_ws_session_id = ws_session_id
            thread_context_schema = context_schema

            # Only extract context if we have both user message and assistant response
            if !user_text.empty? && !final_text.to_s.empty?
              # Notify client that context extraction is starting
              start_message = { type: "context_extraction_started" }.to_json
              if defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_session)
                WebSocketHelper.send_to_session(start_message, thread_ws_session_id)
              end

              # Run context extraction in a separate thread to avoid blocking
              Thread.new do
                begin
                  process_and_broadcast_context(
                    thread_session,
                    user_text,
                    final_text,
                    provider,
                    thread_ws_session_id,
                    thread_context_schema
                  )
                rescue StandardError => ctx_err
                  Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Background error: #{ctx_err.message}\n[ContextExtractor] Backtrace: #{ctx_err.backtrace.first(3).join("\n")}" }
                end
              end
            end
          rescue StandardError => ctx_setup_err
            # Don't let context extraction setup errors affect the main flow
            Monadic::Utils::ExtraLogger.log { "[ContextExtractor] Setup error: #{ctx_setup_err.message}" }
          end
        end
      rescue StandardError => e
        STDERR.puts "Error processing request: #{e.message}"
        ws_session_id = Thread.current[:websocket_session_id]
        error_message = { "type" => "error", "content" => "something_went_wrong" }.to_json
        send_or_broadcast(error_message, ws_session_id)
      end
    end
  end
end
