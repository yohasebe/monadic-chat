# frozen_string_literal: true

require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require_relative "../../utils/system_prompt_injector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/extra_logger"
require_relative "../base_vendor_helper"
require "json"

module GrokHelper
  include BaseVendorHelper
  include InteractionUtils
  include FunctionCallErrorHandler
  # Maximum tool-call round-trips per user turn.
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.x.ai/v1"

  # Responses API search tool definitions
  XAI_WEB_SEARCH_TOOL = { "type" => "web_search" }.freeze
  XAI_X_SEARCH_TOOL = { "type" => "x_search" }.freeze

  define_timeouts "GROK", open: 20, read: 600, write: 120

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  # Get default model
  def self.get_default_model
    SystemDefaults.get_default_model('xai')
  end


    class << self
      attr_reader :cached_models

    def vendor_name
      "xAI"
    end

    # Get appropriate model based on websearch requirement
    def get_model_for_websearch(requested_model, websearch_needed)
      return requested_model unless websearch_needed

      # Check if model supports websearch via ModelSpec
      if !Monadic::Utils::ModelSpec.supports_web_search?(requested_model)
        fallback_model = Monadic::Utils::ModelSpec.get_websearch_fallback(requested_model)

        if fallback_model
          Monadic::Utils::ExtraLogger.log { "[Grok] Switching from #{requested_model} to #{fallback_model} for web search capability" }

          return fallback_model
        end
      end

      requested_model
    end
  end

  define_model_lister :grok,
    api_key_config: "XAI_API_KEY",
    endpoint_path: "/language-models" do |json|
      (json["models"] || []).map { |m| m["id"] }
    end

  # Convert Chat Completions tool format to Responses API flattened format
  # Input:  { "type" => "function", "function" => { "name" => ..., "description" => ..., "parameters" => ... } }
  # Output: { "type" => "function", "name" => ..., "description" => ..., "parameters" => ... }
  def convert_tools_to_responses_format(tools)
    return [] unless tools.is_a?(Array)

    tools.map do |tool|
      tool_json = tool.is_a?(Hash) ? tool : JSON.parse(tool.to_json)
      if tool_json["type"] == "function" && tool_json["function"]
        {
          "type" => "function",
          "name" => tool_json["function"]["name"],
          "description" => tool_json["function"]["description"],
          "parameters" => tool_json["function"]["parameters"]
        }
      else
        tool_json
      end
    end
  end

  # Convert Chat Completions messages array to Responses API input format
  # Key differences from OpenAI:
  # - System messages stay in input (xAI does NOT support the `instructions` parameter)
  # - User content uses "input_text", assistant uses "output_text"
  # - Images use "input_image" with "image_url" field
  # - Tool results use "function_call_output" with "call_id" and "output"
  # - Assistant tool_calls become separate "function_call" items
  def convert_messages_to_input(messages)
    return [] unless messages.is_a?(Array)

    messages.map do |msg|
      role = msg["role"] || msg[:role]
      content = msg["content"] || msg[:content]

      # Handle tool result messages
      if role == "tool"
        {
          "type" => "function_call_output",
          "call_id" => msg["tool_call_id"] || msg["call_id"] || msg[:tool_call_id] || msg[:call_id],
          "output" => content.to_s
        }
      # Handle assistant messages with tool_calls
      elsif role == "assistant" && (msg["tool_calls"] || msg[:tool_calls])
        tool_calls = msg["tool_calls"] || msg[:tool_calls]
        output_items = []

        # Add text content as a message item
        output_items << {
          "type" => "message",
          "role" => "assistant",
          "content" => [
            {
              "type" => "output_text",
              "text" => content.to_s
            }
          ]
        }

        # Add function calls
        tool_calls.each do |tool_call|
          call_id = tool_call["id"] || tool_call[:id]
          output_items << {
            "type" => "function_call",
            "id" => call_id,
            "call_id" => call_id,
            "name" => tool_call.dig("function", "name") || tool_call.dig(:function, :name),
            "arguments" => tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
          }
        end

        output_items
      # Handle assistant messages with assistant_function_calls (Responses API format)
      elsif role == "assistant" && (msg["assistant_function_calls"] || msg[:assistant_function_calls])
        func_calls = msg["assistant_function_calls"] || msg[:assistant_function_calls]
        output_items = []

        # Add text content as a message item
        output_items << {
          "type" => "message",
          "role" => "assistant",
          "content" => [
            {
              "type" => "output_text",
              "text" => content.to_s
            }
          ]
        }

        # Add function calls (already in Responses API format)
        func_calls.each do |fc|
          output_items << fc
        end

        output_items
      else
        # Standard message conversion
        text_type = (role == "assistant") ? "output_text" : "input_text"

        if content.is_a?(Array)
          # Convert content types for Responses API
          converted_content = content.map do |item|
            case item["type"]
            when "text"
              { "type" => text_type, "text" => item["text"] }
            when "image_url"
              { "type" => "input_image", "image_url" => item["image_url"]["url"] }
            else
              item
            end
          end
          { "role" => role, "content" => converted_content }
        else
          { "role" => role, "content" => [{ "type" => text_type, "text" => content.to_s }] }
        end
      end
    end.flatten.compact
  end

  # Configure tools for the API request body (app tools + PTD + SSOT + websearch)
  private def configure_grok_tools(body, model, obj, app, session, role, websearch_native)
    # Get tools from app settings
    app_instance = APPS[app]
    app_tools = app_instance&.settings&.[]("tools")

    if app_instance
      begin
        app_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
          app_name: app, session: session,
          app_settings: app_instance.settings, default_tools: app_tools
        )
      rescue StandardError => e
        DebugHelper.debug("Grok: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning) if defined?(DebugHelper)
      end
    end

    # Convert tools to Responses API flattened format
    app_tools = convert_tools_to_responses_format(app_tools) if app_tools && !app_tools.empty?

    # Include tools based on role and availability
    if role == "tool"
      if app_tools && !app_tools.empty?
        body["tools"] = app_tools
        body["tool_choice"] = "auto"
      end
    elsif obj["tools"] && !obj["tools"].empty?
      body["tools"] = app_tools || []
      body["tool_choice"] = obj["tool_choice"] || "auto"
      body.delete("tool_choice") if body["tools"].nil? || body["tools"].empty?
    elsif app_tools && !app_tools.empty?
      body["tools"] = app_tools
      body["tool_choice"] = obj["tool_choice"] || "auto"
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Parallel function calling
    if body["tools"] && !body["tools"].empty? && obj["parallel_function_calling"] == false
      body["parallel_function_calling"] = false
    end

    # SSOT: remove tools if model is not tool-capable
    begin
      spec_tool_capable = Monadic::Utils::ModelSpec.get_model_property(model, "tool_capability")
      tool_capable = spec_tool_capable.nil? ? true : !!spec_tool_capable
    rescue StandardError
      tool_capable = true
    end
    unless tool_capable
      body.delete("tools")
      body.delete("tool_choice")
      body.delete("parallel_function_calling")
    end

    if body["tools"]
      Monadic::Utils::ExtraLogger.log { "=== Grok Final Tools (role: #{role}) ===\nNumber of tools: #{body['tools'].length}\nTool names: #{body['tools'].map { |t| t['name'] || t.dig('function', 'name') }.inspect}" }
    end

    # Add Responses API search tools for native Grok web search
    if websearch_native
      body["tools"] ||= []

      web_search_tool = { "type" => "web_search" }
      if obj["allowed_websites"].is_a?(Array) && !obj["allowed_websites"].empty?
        web_search_tool["allowed_domains"] = obj["allowed_websites"]
      end
      if obj["excluded_websites"].is_a?(Array) && !obj["excluded_websites"].empty?
        web_search_tool["excluded_domains"] = obj["excluded_websites"]
      end
      body["tools"] << web_search_tool

      if obj.fetch("enable_x_search", true)
        x_search_tool = { "type" => "x_search" }
        if obj["included_x_handles"].is_a?(Array) && !obj["included_x_handles"].empty?
          x_search_tool["allowed_x_handles"] = obj["included_x_handles"]
        end
        if obj["excluded_x_handles"].is_a?(Array) && !obj["excluded_x_handles"].empty?
          x_search_tool["excluded_x_handles"] = obj["excluded_x_handles"]
        end
        x_search_tool["from_date"] = obj["date_from"] if obj["date_from"]
        x_search_tool["to_date"] = obj["date_to"] if obj["date_to"]
        body["tools"] << x_search_tool
      end

      Monadic::Utils::ExtraLogger.log {
        dropped = []
        dropped << "country=#{obj["web_country"]}" if obj["web_country"]
        dropped << "safe_search=#{obj["safe_search"]}" if obj["safe_search"]
        dropped << "post_favorite_count=#{obj["post_favorite_count"]}" if obj["post_favorite_count"]
        dropped << "post_view_count=#{obj["post_view_count"]}" if obj["post_view_count"]
        dropped << "enable_news_search" if obj.fetch("enable_news_search", false)
        dropped << "rss_links" if obj["rss_links"] && !obj["rss_links"].empty?
        dropped.empty? ? nil : "Grok Responses API: dropped unsupported search params: #{dropped.join(', ')}"
      }

      DebugHelper.debug("Grok: Native web search enabled via Responses API tools", category: :api, level: :debug)
      Monadic::Utils::ExtraLogger.log { "=== Grok API Request Started ===\nApp: #{app}\nWebsearch enabled: true\nSearch tools: #{body["tools"].select { |t| %w[web_search x_search].include?(t["type"]) }.inspect}" }
    end
  end

  # Build context_messages array from context for the API request
  # Returns [context_messages, messages_containing_img]
  private def build_grok_messages(context, role, obj, session, body, message_with_snippet, prompt_suffix, data, &block)
    messages_containing_img = false
    system_message_modified = false
    context_messages = context.compact.map do |msg|
      if msg["role"] == "system" && !system_message_modified
        system_message_modified = true
        augmented_text = Monadic::Utils::SystemPromptInjector.augment(
          base_prompt: msg["text"], session: session,
          options: {
            websearch_enabled: false, reasoning_model: false,
            websearch_prompt: nil, system_prompt_suffix: obj["system_prompt_suffix"]
          },
          separator: "\n\n---\n\n"
        )
        { "role" => msg["role"], "content" => [{ "type" => "text", "text" => augmented_text }] }
      else
        message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
        if msg["images"] && role == "user"
          msg["images"].each do |img|
            messages_containing_img = true
            message["content"] << {
              "type" => "image_url",
              "image_url" => { "url" => img["data"], "detail" => "high" }
            }
          end
        end
        message
      end
    end

    # Handle initiate_from_assistant case
    if context_messages.length == 1 && context_messages[0]["role"] == "system"
      initial_message = if app_name = obj["app_name"]
                          app_name.include?("CodeInterpreter") || app_name.include?("code_interpreter") ?
                            "Use the check_environment function to verify the Python environment, then introduce yourself and explain what you can do." :
                            "Please proceed according to your system instructions and introduce yourself."
                        else
                          "Please proceed according to your system instructions and introduce yourself."
                        end
      context_messages << { "role" => "user", "content" => [{ "type" => "text", "text" => initial_message }] }
    end

    # Handle tool role - send tool results back
    if role == "tool" && obj["function_returns"]
      if obj["assistant_function_calls"]
        context_messages << {
          "role" => "assistant",
          "content" => [{"type" => "text", "text" => ""}],
          "assistant_function_calls" => obj["assistant_function_calls"]
        }
      end

      obj["function_returns"].each do |result|
        context_messages << {
          "role" => "tool",
          "content" => result["content"] || result[:content],
          "tool_call_id" => result["call_id"] || result["tool_call_id"] || result[:call_id] || result[:tool_call_id]
        }
      end

      # Inject pending tool images
      if session[:pending_tool_images]&.any?
        injected_set = session[:images_injected_this_turn] ||= Set.new
        new_images = session[:pending_tool_images].reject { |f| injected_set.include?(f) }

        if new_images.any?
          image_parts = new_images.filter_map do |img_filename|
            img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
            next unless img

            injected_set << img_filename
            { "type" => "image_url", "image_url" => { "url" => "data:#{img[:media_type]};base64,#{img[:base64_data]}", "detail" => "high" } }
          end
          if image_parts.any?
            context_messages << {
              "role" => "user",
              "content" => [
                { "type" => "text", "text" => "[Screenshot of the browser after the action above. Use this visual context to continue with your task.]" },
                *image_parts
              ]
            }
          end
        end
        session.delete(:pending_tool_images)
      end

      Monadic::Utils::ExtraLogger.log { "Adding tool results to input for Grok Responses API\nAssistant function calls: #{obj['assistant_function_calls']&.length || 0} calls\nNumber of tool results: #{obj['function_returns'].length}\nTotal context messages being sent: #{context_messages.length}" }
    end

    # Decorate last message with prompt_suffix
    last_text = context.last["text"]
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    is_initial_greeting = context_messages.length == 2 &&
                         context_messages[0]["role"] == "system" &&
                         context_messages[1]["role"] == "user" &&
                         session[:messages].length <= 1
    last_message_is_tool = context_messages.last && context_messages.last["role"] == "tool"

    if last_text != "" && prompt_suffix.to_s != "" && !is_initial_greeting && !last_message_is_tool
      new_text = last_text + "\n\n" + prompt_suffix.strip
      if context_messages.dig(-1, "content")
        last_content = context_messages.last["content"]
        if last_content.is_a?(Array)
          last_content.each do |content_item|
            content_item["text"] = new_text if content_item["type"] == "text"
          end
        elsif last_content.is_a?(String)
          context_messages.last["content"] = new_text
        end
      end
    end

    if data
      context_messages << { "role" => "user", "content" => data.strip }
    end

    # Vision model switch if needed
    if messages_containing_img
      original_model = body["model"]
      begin
        spec_vision = Monadic::Utils::ModelSpec.get_model_property(original_model, "vision_capability")
        current_vision = spec_vision == true
      rescue StandardError
        current_vision = false
      end
      unless current_vision
        begin
          spec = Monadic::Utils::ModelSpec.load_spec
          candidates = spec.keys.select do |m|
            m.start_with?("grok-") && Monadic::Utils::ModelSpec.get_model_property(m, "vision_capability") == true
          end
          vision_model = candidates.include?("grok-4-1-fast-non-reasoning") ? "grok-4-1-fast-non-reasoning" : candidates.first
        rescue StandardError
          vision_model = nil
        end
        if vision_model && vision_model != original_model
          body["model"] = vision_model
          body.delete("stop")
          if block
            block.call({
              "type" => "system_info",
              "content" => "Model automatically switched from #{original_model} to #{body['model']} for image processing capability."
            })
          end
        end
      end
    end

    [context_messages, messages_containing_img]
  end

  # Execute the Grok API call with retries, handle streaming/non-streaming dispatch
  private def execute_grok_api_call(headers, body, app, session, call_depth, disable_streaming, original_user_model, &block)
    obj = session[:parameters]

    # Force text-only response when force-stop is active
    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      body.delete("tools")
      body.delete("tool_choice")
    end

    Monadic::Utils::ExtraLogger.log {
      msg = "Grok final API request:\nApp: #{app}, Model: #{body['model']}\nTools: #{body['tools']&.length || 0}, Input items: #{body['input']&.length || 0}"
      msg << "\nTool names: #{body['tools'].map { |t| t['name'] || t.dig('function', 'name') }.inspect}" if body['tools']&.any?
      msg
    }

    target_uri = "#{API_ENDPOINT}/responses"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    # Privacy Filter: mask user-message PII before sending to xAI. No-op when
    # the app does not declare `privacy do; enabled true; end` in MDSL. Grok
    # uses the Responses API shape (body["input"]).
    app_settings = (defined?(APPS) && APPS[app]) ? APPS[app].settings : nil
    if privacy_enabled_for?(app_settings, session) && body["input"].is_a?(Array)
      body["input"] = apply_privacy_to_messages(body["input"], session, app_settings)
    end

    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout, write: write_timeout, read: read_timeout)
               .post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_data = JSON.parse(res.body) rescue { "message" => res.body.to_s, "status" => res.status }

      Monadic::Utils::ExtraLogger.log { "[Grok] API Error: Status #{res.status.code}, Body: #{res.body.to_s[0..2000]}" }

      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "xAI",
        message: error_data.dig("error", "message") || error_data["message"] || "Unknown API error",
        code: res.status.code
      )
      error_res = { "type" => "error", "content" => formatted_error }
      block&.call error_res
      return [error_res]
    end

    if !body["stream"]
      # Non-streaming: parse Responses API output format
      parsed = JSON.parse(res.body)
      output = parsed["output"] || []
      frag = output.select { |item| item["type"] == "message" }
                   .flat_map { |item| Array(item["content"]) }
                   .select { |c| c["type"] == "output_text" }
                   .map { |c| c["text"] }
                   .join
      frag = "" if frag.nil?
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })

      # Check for function calls in output
      function_calls = output.select { |item| item["type"] == "function_call" }
      if function_calls.any?
        tool_calls = function_calls.map do |fc|
          { "id" => fc["call_id"] || fc["id"], "function" => { "name" => fc["name"], "arguments" => fc["arguments"] || "{}" } }
        end

        # Accumulate across multi-turn tool rounds within a single user request.
        # Without the `||= [] + ...` pattern, each new tool round would overwrite
        # prior rounds' calls and the model would lose the history of what it
        # already called. Mirrors the Claude / OpenAI multi-turn context fix.
        (obj["assistant_function_calls"] ||= []).concat(function_calls.map do |fc|
          { "type" => "function_call", "id" => fc["id"], "call_id" => fc["call_id"] || fc["id"],
            "name" => fc["name"], "arguments" => fc["arguments"] || "{}" }
        end)

        session[:call_depth_per_turn] += 1
        if session[:call_depth_per_turn] > MAX_FUNC_CALLS
          return [{ "type" => "error", "content" => Monadic::Utils::ErrorFormatter.api_error(
            provider: "xAI", message: "Maximum function call depth exceeded"
          ) }]
        end

        return process_functions(app, session, tool_calls, nil, session[:call_depth_per_turn], &block) || []
      end

      [{ "choices" => [{ "message" => { "role" => "assistant", "content" => frag }, "finish_reason" => "stop" }] }]
    else
      body["original_user_model"] = original_user_model
      process_responses_api_data(app: app, session: session, query: body, res: res.body, call_depth: call_depth, &block)
    end
  end

  # Execute a single Grok tool function: parse arguments, dispatch, handle Grok-specific post-processing
  # Returns [tool_result, error_stop]
  private def invoke_grok_tool_function(app, session, tool_call, function_name, &block)
    obj = session[:parameters]

    # Parse arguments
    function_call = tool_call["function"]
    begin
      argument_hash = function_call["arguments"].to_s.strip.empty? ? {} : JSON.parse(function_call["arguments"])
    rescue JSON::ParserError
      argument_hash = {}
    end

    # Fix Jupyter filenames if stored filename exists
    if obj["current_notebook_filename"] && argument_hash["filename"]
      jupyter_functions = %w[add_jupyter_cells delete_jupyter_cell update_jupyter_cell
                            get_jupyter_cells_with_results execute_and_fix_jupyter_cells
                            restart_jupyter_kernel interrupt_jupyter_execution
                            move_jupyter_cell insert_jupyter_cells]

      if jupyter_functions.include?(function_name)
        provided_filename = argument_hash["filename"].to_s.gsub(/\.ipynb$/, '')
        stored_filename = obj["current_notebook_filename"].gsub(/\.ipynb$/, '')
        shared_volume = Monadic::Utils::Environment.in_container? ? MonadicApp::SHARED_VOL : MonadicApp::LOCAL_SHARED_VOL
        provided_path = File.join(shared_volume, "#{provided_filename}.ipynb")

        if !File.exist?(provided_path)
          stored_base_name = stored_filename.gsub(/_\d{8}_\d{6}$/, '')
          provided_base_name = provided_filename.gsub(/_\d{8}_\d{6}$/, '')
          if stored_base_name == provided_base_name
            argument_hash["filename"] = stored_filename
          end
        end
      end
    end

    # Symbolize keys, skip null values
    argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
      next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

      memo[k.to_sym] = v
    end

    # Inject session for tools that need it
    method_obj = APPS[app].method(function_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |_type, name| name == :session }
      argument_hash[:session] = session
    end

    # Execute function
    begin
      function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      send_verification_notification(session, &block) if function_name == "report_verification"

      # Fix HTML-escaped SVG files (Grok-specific)
      fix_grok_svg_escaping(function_name, function_return)

      # Store Jupyter notebook filename
      store_grok_notebook_filename(function_name, function_return, obj)

      # Store image/video filenames
      store_grok_media_filename(function_name, function_return, obj, session)

      Monadic::Utils::ExtraLogger.log { "Tool executed: #{function_name}, result: #{function_return.to_s[0..200]}..." }

      Monadic::Utils::TtsTextExtractor.extract_tts_text(
        app: app, function_name: function_name,
        argument_hash: argument_hash, session: session
      )
    rescue StandardError => e
      DebugHelper.debug("Function call error in #{function_name}: #{e.message}", category: :api, level: :error)
      function_return = Monadic::Utils::ErrorFormatter.tool_error(
        provider: "xAI", tool_name: function_name, message: e.message
      )
    end

    # Check for repeated errors
    if handle_function_error(session, function_return, function_name, &block)
      error_result = { "call_id" => tool_call["id"], "name" => function_name, "content" => function_return.to_s }
      return [error_result, true]
    end

    # Collect _image for screenshot injection
    if function_return.is_a?(Hash) && function_return[:_image]
      session[:pending_tool_images] = Array(function_return[:_image])
      clean_return = function_return.reject { |k, _| k.to_s.start_with?("_") }
      content_str = JSON.generate(clean_return)
    else
      content_str = function_return.to_s
    end

    # Store gallery_html for server-side injection
    if function_return.is_a?(Hash) && function_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << function_return[:gallery_html]
    end

    tool_result = { "call_id" => tool_call["id"], "name" => function_name, "content" => content_str }
    [tool_result, false]
  end

  # Fix HTML-escaped SVG files created by Grok's code generation
  private def fix_grok_svg_escaping(function_name, function_return)
    return unless function_name == "run_code" && function_return.to_s.include?("File(s) generated")
    return unless function_return =~ /File\(s\) generated.*?: ([^;]+)/

    files = $1.split(",").map(&:strip)
    files.each do |file_path|
      next unless file_path.end_with?(".svg")

      actual_path = file_path.gsub("/data/", "")
      full_path = Monadic::Utils::Environment.in_container? ?
                    File.join("/monadic/data", actual_path) :
                    File.join(File.expand_path("~/monadic/data"), actual_path)

      begin
        if File.exist?(full_path)
          content = File.read(full_path)
          if content.include?("&lt;svg") || content.include?("&gt;")
            File.write(full_path, content.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", '"').gsub("&amp;", "&"))
          end
        end
      rescue StandardError
        # ignore
      end
    end
  end

  # Store Jupyter notebook filename from creation result
  private def store_grok_notebook_filename(function_name, function_return, obj)
    return unless %w[create_jupyter_notebook create_and_populate_jupyter_notebook].include?(function_name)
    return unless function_return.to_s.include?("created successfully")
    return unless function_return =~ /Notebook\s+(\S+\.ipynb)\s+created successfully/

    obj["current_notebook_filename"] = $1
    obj["current_notebook_link"] = "<a href='http://127.0.0.1:8889/lab/tree/#{$1}' target='_blank'>Open #{$1}</a>"
  end

  # Store image/video filenames from generation results
  private def store_grok_media_filename(function_name, function_return, obj, session)
    return unless function_return.is_a?(String)

    begin
      result = JSON.parse(function_return)
      return unless result["success"] && result["filename"]

      case function_name
      when "generate_image_with_grok"
        obj["current_image_filename"] = result["filename"]
        session[:grok_last_image] = result["filename"]
      when "generate_video_with_grok_imagine"
        obj["current_video_filename"] = result["filename"]
        session[:grok_last_video_filename] = result["filename"]
        session[:grok_last_video_request_id] = result["request_id"] if result["request_id"]
      end
    rescue JSON::ParserError
      # ignore
    end
  end

  # Post-process Grok's response: fix filenames, image paths, notebook URLs
  private def postprocess_grok_response(new_results, obj)
    return unless new_results.is_a?(Array) && !new_results.empty?

    content = new_results.dig(0, "choices", 0, "message", "content")
    return unless content

    # Fix image paths for Code Interpreter
    if obj["app_name"].to_s.include?("CodeInterpreter") || obj["display_name"].to_s.include?("Code Interpreter")
      if content =~ /File created: ([^\s]+\.(svg|png|jpg|jpeg|gif)).*Full path: \/monadic\/data/i
        filename = $1
        unless content.include?("<div class=\"generated_image\">")
          if content =~ /(Output:.*?```[^`]*```)/m
            image_html = "\n\n<div class=\"generated_image\">\n  <img src=\"/data/#{filename}\" />\n</div>"
            content = content.sub($1, $1 + image_html)
          end
        end
      end
    end

    # Fix notebook filenames
    if obj["current_notebook_filename"]
      actual_filename = obj["current_notebook_filename"]
      base_name = actual_filename.gsub(/_\d{8}_\d{6}\.ipynb$/, '')

      content = content.gsub(/\b#{Regexp.escape(base_name)}\.ipynb\b/i, actual_filename)
      content = content.gsub(/\b#{Regexp.escape(base_name)}_\d{8}_\d{6}\.ipynb\b/i, actual_filename)
      content = content.gsub(%r{http://localhost:8889/lab/tree/#{Regexp.escape(base_name)}_\d{8}_\d{6}\.ipynb}i,
                            "http://localhost:8889/lab/tree/#{actual_filename}")
    end

    # Fix image filenames
    if obj["current_image_filename"]
      actual_image_filename = obj["current_image_filename"]
      content = content.gsub(/\d{8}-\d{6}\.png/i, actual_image_filename)
      content = content.gsub(/(?<!\d)\d{10}\.png/i, actual_image_filename)
      content = content.gsub(/src="\/data\/\d{8}-\d{6}\.png"/i, "src=\"/data/#{actual_image_filename}\"")
      content = content.gsub(/src="\/data\/\d{10}\.png"/i, "src=\"/data/#{actual_image_filename}\"")
      content = content.gsub(/\/data\/[a-zA-Z0-9_-]+\.png/, "/data/#{actual_image_filename}")
    end

    new_results[0]["choices"][0]["message"]["content"] = content
  end

  # Build final text response from streaming results (texts hash, reasoning, usage)
  private def build_grok_text_response(texts:, query:, finish_reason:, reasoning_content:,
                                       usage_input_tokens:, usage_output_tokens:, usage_total_tokens:, &block)
    complete_text = texts.any? ? texts.values.join("") : ""
    effective_finish = texts.any? ? (finish_reason || "stop") : "stop"

    result = {
      "choices" => [{
        "message" => { "role" => "assistant", "content" => complete_text },
        "finish_reason" => effective_finish
      }],
      "model" => query["model"]
    }

    if usage_input_tokens || usage_output_tokens || usage_total_tokens
      result["usage"] = {
        "input_tokens" => usage_input_tokens,
        "output_tokens" => usage_output_tokens,
        "total_tokens" => usage_total_tokens
      }.compact
    end

    if reasoning_content && !reasoning_content.empty?
      result["choices"][0]["message"]["thinking"] = reasoning_content.join("")
    end

    block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => effective_finish })
    [result]
  end

  public

  # Simple non-streaming query using Responses API
  def send_query(options, model: nil)
    model ||= SystemDefaults.get_default_model('xai')

    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)

    # Get API key
    api_key = CONFIG["XAI_API_KEY"]
    if api_key.nil?
      require_relative '../../utils/error_handler'
      return ErrorHandler.format_error(
        category: :configuration,
        message: Monadic::Utils::ErrorFormatter.api_key_error(
          provider: "xAI",
          env_var: "XAI_API_KEY"
        ),
        suggestion: "Please set your xAI API key in the configuration"
      )
    end

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Build messages array (intermediate, will be converted to input)
    messages = []

    # Handle system message
    system_text = options["system"] || options["custom_system_message"] || options["initial_prompt"]
    if system_text
      messages << { "role" => "system", "content" => [{ "type" => "text", "text" => system_text.to_s }] }
    end

    # Add messages from options
    if options["messages"]
      options["messages"].each do |msg|
        content_str = (msg["content"] || msg["text"] || "").to_s
        next if content_str.strip.empty?
        messages << { "role" => msg["role"] || "user", "content" => [{ "type" => "text", "text" => content_str }] }
      end
    elsif options["message"]
      messages << { "role" => "user", "content" => [{ "type" => "text", "text" => options["message"].to_s }] }
    end

    messages << { "role" => "user", "content" => [{ "type" => "text", "text" => "Hello" }] } if messages.empty?

    # Build Responses API body
    body = {
      "model" => model,
      "input" => convert_messages_to_input(messages),
      "stream" => false,
      "store" => false,
      "temperature" => options["temperature"] || 0.7
    }

    body["max_output_tokens"] = options["max_tokens"] if options["max_tokens"]
    body["frequency_penalty"] = options["frequency_penalty"] if options["frequency_penalty"]
    body["presence_penalty"] = options["presence_penalty"] if options["presence_penalty"]


    # Handle websearch via search tools
    websearch = options["websearch"] == true || options["websearch"] == "true"
    if websearch
      model = GrokHelper.get_model_for_websearch(model, true)
      body["model"] = model
      body["tools"] ||= []
      body["tools"] << XAI_WEB_SEARCH_TOOL.dup
      body["tools"] << XAI_X_SEARCH_TOOL.dup
    end

    # Add tool definitions if provided
    if options["tools"] && options["tools"].any?
      raw_tools = options["tools"].map do |tool|
        if tool["function"]
          tool
        else
          {
            "type" => "function",
            "function" => {
              "name" => tool["name"] || tool[:name],
              "description" => tool["description"] || tool[:description] || "",
              "parameters" => tool["parameters"] || tool[:parameters] || { "type" => "object", "properties" => {} }
            }
          }
        end
      end
      body["tools"] ||= []
      body["tools"].concat(convert_tools_to_responses_format(raw_tools))
      body["tool_choice"] = "auto"
    end

    target_uri = API_ENDPOINT + "/responses"

    http = HTTP.headers(headers)
    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout, write: write_timeout, read: read_timeout).post(target_uri, json: body)
      break if res && res.status && res.status.success?
      sleep RETRY_DELAY
    end

    if res && res.status && res.status.success?
      begin
        parsed = JSON.parse(res.body.to_s)
        return parsed.to_s unless parsed.is_a?(Hash)

        output = parsed["output"] || []

        # Check for function calls in the output
        function_calls = output.select { |item| item["type"] == "function_call" }
        if function_calls.any?
          tool_calls = function_calls.map do |fc|
            {
              "name" => fc["name"],
              "args" => begin
                JSON.parse(fc["arguments"] || "{}")
              rescue JSON::ParserError
                {}
              end
            }
          end
          # Extract text content from message items
          text_content = output.select { |item| item["type"] == "message" }
                               .flat_map { |item| Array(item["content"]) }
                               .select { |c| c["type"] == "output_text" }
                               .map { |c| c["text"] }
                               .join
          return { text: text_content, tool_calls: tool_calls }
        end

        # Extract text from output
        text = output.select { |item| item["type"] == "message" }
                     .flat_map { |item| Array(item["content"]) }
                     .select { |c| c["type"] == "output_text" }
                     .map { |c| c["text"] }
                     .join
        return text unless text.empty?

        parsed.to_s
      rescue JSON::ParserError
        return res.body.to_s
      end
    else
      raw = res&.body.to_s
      parsed_err = begin JSON.parse(raw) rescue raw end
      msg = if parsed_err.is_a?(Hash)
              parsed_err.dig("error", "message") || parsed_err["error"] || parsed_err["message"] || raw
            else
              parsed_err.to_s
            end
      code = res&.status&.code
      return Monadic::Utils::ErrorFormatter.api_error(provider: "xAI", message: msg, code: code)
    end
  rescue StandardError => e
    require_relative '../../utils/error_handler'
    return ErrorHandler.format_provider_error(
      provider: "xAI Grok",
      error: e
    )
  end

  # Connect to xAI Responses API and get a response
  def api_request(role, session, call_depth: 0, disable_streaming: false, &block)
    # Reset call_depth counter and tool state for each new user turn
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
      session[:images_injected_this_turn] = Set.new
      session[:parameters]["function_returns"] = nil
      session[:parameters]["assistant_function_calls"] = nil
    end

    current_call_depth = session[:call_depth_per_turn] || 0
    num_retrial = 0

    obj = session[:parameters]
    if obj.nil?
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "xAI",
        message: "Session parameters not initialized",
        code: 500
      )
    end
    app = obj["app_name"]
    api_key = CONFIG["XAI_API_KEY"]

    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    presence_penalty = obj["presence_penalty"] ? obj["presence_penalty"].to_f : nil
    frequency_penalty = obj["frequency_penalty"] ? obj["frequency_penalty"].to_f : nil
    reasoning_effort = obj["reasoning_effort"]
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    # Check for websearch configuration
    websearch = obj["websearch"] == "true" || obj["websearch"] == true

    # Dynamically switch model if websearch is needed but not supported
    original_model = model
    model = GrokHelper.get_model_for_websearch(model, websearch)

    if model != original_model
      Monadic::Utils::ExtraLogger.log { "[Grok] Model switched from #{original_model} to #{model} for web search capability" }
    end

    websearch_native = websearch && Monadic::Utils::ModelSpec.supports_web_search?(model)
    unless websearch_native
      DebugHelper.debug("Grok websearch disabled (requested=#{websearch}, supports=#{Monadic::Utils::ModelSpec.supports_web_search?(model)})", category: :api, level: :info)
    end

    Monadic::Utils::ExtraLogger.log { "=== Grok websearch parameter check ===\nobj[\"websearch\"] = #{obj["websearch"].inspect} (type: #{obj["websearch"].class})\nwebsearch enabled = #{websearch}" }

    message = nil
    data = nil

    # Grok image API supports generation only (no image upload/edit).
    # If user provided images, return an explicit error to avoid confusing 400s.
    if obj["images"] && obj["images"].is_a?(Array) && !obj["images"].empty?
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "xAI",
        message: "Image upload/edit is not supported for Grok image generation. Please provide a text prompt only, or use the OpenAI Image Generator for edits/masks.",
        code: 400
      )
      error_res = { "type" => "error", "content" => formatted_error }
      block&.call error_res
      return [error_res]
    end

    # NOTE: Auto-attach of last generated image was removed because it caused
    # stale images to appear after session reset. Image editing now relies on
    # the model explicitly calling monadic_load_state to retrieve the filename,
    # which is already described in the system prompt.

    # Skip message processing for tool role (but still process context)
    if role != "tool"
      message = obj["message"].to_s

      # Reset model switch notification flag for new user messages
      if role == "user"
        session.delete(:model_switch_notified)
      end

      html = markdown_to_html(obj["message"], math: obj["math"])

      if message != "" && role == "user"

        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "role" => role,
                  "lang" => detect_language(message),
                  "app_name" => obj["app_name"]
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
        block&.call res

        # Check if this user message was already added by websocket.rb (for context extraction)
        # to avoid duplicate consecutive user messages that cause API errors
        existing_msg = session[:messages].find do |m|
          m["role"] == "user" && m["text"] == obj["message"]
        end

        if existing_msg
          # Update existing message with additional fields instead of adding new one
          existing_msg.merge!(res["content"])
        else
          session[:messages] << res["content"]
        end
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }
    strip_inactive_image_data(session)

    # Prune old orchestration history to prevent the model from seeing stale
    # tool results and making duplicate calls, while keeping enough rounds
    # for iterative edit/variation workflows.
    if @clear_orchestration_history
      keep_rounds = @orchestration_keep_rounds || 1
      first_msg = context.first
      user_indices = context.each_index.select { |i| context[i]&.[]("role") == "user" }

      needed = keep_rounds + 1
      if user_indices.length >= needed
        keep_from = user_indices[-needed]
        context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
      elsif user_indices.length >= 2
        keep_from = user_indices.first
        context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
      else
        last_user_msg = context.reverse.find { |msg| msg&.[]("role") == "user" }
        context = [first_msg]
        context << last_user_msg if last_user_msg && first_msg != last_user_msg
      end
      context.compact.each { |msg| msg["active"] = true }

      Monadic::Utils::ExtraLogger.log { "Grok: Pruning orchestration history (keep #{keep_rounds} rounds, #{context.size} messages kept)" }
    end

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request (Responses API format)
    body = {
      "model" => model,
      "store" => false
    }

    # Store the original model for comparison later
    original_user_model = model

    # Disable streaming when processing tool results to avoid hanging
    body["stream"] = !disable_streaming
    # SSOT: supports_streaming gate (default true when unspecified)
    begin
      spec_supports_streaming = Monadic::Utils::ModelSpec.get_model_property(model, "supports_streaming")
      streaming_source = spec_supports_streaming.nil? ? "fallback" : "spec"
      supports_streaming = spec_supports_streaming.nil? ? true : !!spec_supports_streaming
    rescue StandardError
      streaming_source = "fallback"
      supports_streaming = true
    end
    body["stream"] = false unless supports_streaming
    body["temperature"] = temperature if temperature
    body["presence_penalty"] = presence_penalty if presence_penalty
    body["frequency_penalty"] = frequency_penalty if frequency_penalty
    body["max_output_tokens"] = max_tokens if max_tokens


    if obj["response_format"]
      body["response_format"] = APPS[app].settings["response_format"]
    end

    configure_grok_tools(body, model, obj, app, session, role, websearch_native)

    context_messages, _messages_containing_img = build_grok_messages(
      context, role, obj, session, body, message_with_snippet, prompt_suffix, data, &block
    )

    # Convert context_messages to Responses API input format
    body["input"] = convert_messages_to_input(context_messages)

    execute_grok_api_call(headers, body, app, session, call_depth, disable_streaming, original_user_model, &block)
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = "The request has timed out."
      DebugHelper.debug(error_message, category: :api, level: :error)
      formatted_error = Monadic::Utils::ErrorFormatter.network_error(
          provider: "xAI",
          message: error_message,
          timeout: true
        )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      [res]
    end
  rescue StandardError => e
    DebugHelper.debug("API request error: #{e.message}", category: :api, level: :error)
    DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
    DebugHelper.debug("Error details: #{e.inspect}", category: :api, level: :debug)
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "xAI",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => formatted_error }
    block&.call res
    [res]
  end

  def process_responses_api_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log_json("Processing Grok Responses API query (Call depth: #{call_depth})", query)

    obj = session[:parameters]
    if obj.nil?
      # Initialize parameters if nil
      session[:parameters] = {}
      obj = session[:parameters]
    end

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil
    fragment_sequence = 0  # Sequence number for fragments to ensure ordering
    reasoning_content = []  # Store reasoning content for Grok models
    current_reasoning_id = nil
    # Track usage reported by Responses API
    usage_input_tokens = nil
    usage_output_tokens = nil
    usage_total_tokens = nil

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      begin
        # Check for completion patterns
        if /\Rdata: \[DONE\]\R/ =~ buffer || /\Revent: done\R/ =~ buffer
          break
        end
      rescue StandardError
        next
      end

      scanner = StringScanner.new(buffer)
      # Responses API uses SSE format with data: prefix
      # Use multiline mode (m flag) to allow . to match newlines within JSON
      pattern = /data: (\{.*?\})(?=\n|\z)/m

      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            Monadic::Utils::ExtraLogger.log { JSON.pretty_generate(json) }

            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            # Handle different event types for Responses API
            event_type = json["type"]

            case event_type
            when "response.created"
              # Response created - log for debugging
              Monadic::Utils::ExtraLogger.log { "Grok response.created" }

            when "response.in_progress"
              # xAI sends proper delta events, so skip in_progress to avoid duplication
              next

            when "response.output_text.delta"
              # Text fragment from streaming
              fragment = json["delta"]

              if fragment && !fragment.empty?
                id = json["response_id"] || json["item_id"] || "default"
                texts[id] ||= String.new

                texts[id] << fragment

                if fragment.length > 0
                  res_event = {
                    "type" => "fragment",
                    "content" => fragment,
                    "sequence" => fragment_sequence,
                    "timestamp" => Time.now.to_f,
                    "is_first" => fragment_sequence == 0
                  }
                  fragment_sequence += 1
                  block&.call res_event
                end
              end

            when "response.output_text.done"
              # Text output completed - finalize text
              text = json["text"]
              if text
                id = json["item_id"] || "default"
                texts[id] = text  # Final text
              end

            when "response.output_item.added"
              # New output item added
              item = json["item"]
              if item && item["type"] == "function_call"
                # Store the function name and ID for later use
                item_id = item["id"]
                if item_id
                  tools[item_id] ||= {}
                  tools[item_id]["name"] = item["name"] if item["name"]
                  tools[item_id]["call_id"] = item["call_id"] if item["call_id"]
                  tools[item_id]["arguments"] ||= ""
                end
                res_event = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res_event
              end

            when "response.output_item.done"
              # Output item completed
              item = json["item"]
              if item && item["type"] == "function_call"
                item_id = item["id"]
                if item_id
                  tools[item_id] ||= {}
                  tools[item_id]["name"] = item["name"] if item["name"]
                  tools[item_id]["arguments"] = item["arguments"] if item["arguments"]
                  tools[item_id]["call_id"] = item["call_id"] if item["call_id"]
                  tools[item_id]["completed"] = true
                end
              end

            when "response.function_call_arguments.delta", "response.function_call.arguments.delta", "response.function_call.delta"
              # Tool call arguments fragment
              item_id = json["item_id"]
              delta = json["delta"]

              if item_id && delta
                tools[item_id] ||= {}
                tools[item_id]["arguments"] ||= ""
                tools[item_id]["arguments"] += delta
              end

            when "response.function_call_arguments.done", "response.function_call.arguments.done", "response.function_call.done"
              # Tool call arguments completed
              item_id = json["item_id"]
              arguments = json["arguments"]
              name = json["name"]

              if item_id
                tools[item_id] ||= {}
                tools[item_id]["arguments"] = arguments if arguments
                tools[item_id]["name"] = name if name
                tools[item_id]["completed"] = true
              end

            when "response.reasoning_summary_text.delta"
              # Reasoning summary delta (streaming)
              rid = json["item_id"] || current_reasoning_id
              delta = json["delta"]

              if delta && !delta.to_s.empty?
                current_reasoning_id = rid if rid
                reasoning_content << delta.to_s

                # Send reasoning delta to frontend (like Claude's thinking)
                res_event = {
                  "type" => "thinking",
                  "content" => delta.to_s
                }
                block&.call res_event
              end

            when "response.reasoning_summary_text.done", "response.reasoning_summary_part.done"
              # Reasoning summary completed - text is already accumulated from deltas
              rid = json["item_id"] || current_reasoning_id
              if rid
                current_reasoning_id = nil
              end

            when "response.web_search_call.in_progress"
              # Web search started
              res_event = { "type" => "wait", "content" => "<i class='fas fa-search'></i> SEARCHING WEB" }
              block&.call res_event

            when "response.web_search_call.searching"
              # Web search in progress - could show progress if needed

            when "response.web_search_call.completed"
              # Web search completed
              Monadic::Utils::ExtraLogger.log { "Grok web search completed: item_id=#{json["item_id"]}" }

            when "response.completed", "response.done"
              # Response completed - extract usage and set finish_reason
              response_data = json["response"] || json
              # Capture usage if present
              usage = response_data["usage"] || json["usage"]
              if usage.is_a?(Hash)
                usage_input_tokens = usage["input_tokens"] || usage["prompt_tokens"] || usage_input_tokens
                usage_output_tokens = usage["output_tokens"] || usage["completion_tokens"] || usage_output_tokens
                usage_total_tokens = usage["total_tokens"] || (usage_input_tokens.to_i + usage_output_tokens.to_i if usage_input_tokens && usage_output_tokens) || usage_total_tokens
              end

              finish_reason = response_data["stop_reason"] || json["stop_reason"] || "stop"

            when "response.error"
              # Error occurred
              error_msg = json.dig("error", "message") || "Unknown error"
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "xAI",
                message: error_msg
              )
              res_event = { "type" => "error", "content" => formatted_error }
              block&.call res_event

              return [res_event]

            else
              # Handle legacy format fallback (choices[0].delta.reasoning_content)
              if json.dig("choices", 0, "delta", "reasoning_content")
                reasoning = json.dig("choices", 0, "delta", "reasoning_content")
                unless reasoning.to_s.strip.empty? || reasoning == "Thinking..."
                  reasoning_content << reasoning
                  res_event = {
                    "type" => "thinking",
                    "content" => reasoning
                  }
                  block&.call res_event
                end
              elsif json.dig("choices", 0, "delta", "content")
                # Legacy chat completions format fallback
                fragment = json.dig("choices", 0, "delta", "content").to_s
                if fragment.length > 0
                  id = json["id"] || "default"
                  texts[id] ||= String.new
                  texts[id] << fragment
                  res_event = {
                    "type" => "fragment",
                    "content" => fragment,
                    "sequence" => fragment_sequence,
                    "timestamp" => Time.now.to_f,
                    "is_first" => fragment_sequence == 0
                  }
                  fragment_sequence += 1
                  block&.call res_event
                end
              elsif event_type
                Monadic::Utils::ExtraLogger.log { "Grok unknown event type: #{event_type}" }
              end
            end

          rescue JSON::ParserError
            # if the JSON parsing fails, the next chunk should be appended to the buffer
            # and the loop should continue to the next iteration
          rescue StandardError => e
            Monadic::Utils::ExtraLogger.log { "[Grok Events] Error: #{e.message}\n[Grok Events] Backtrace: #{e.backtrace.first(5).join("\n")}" }
          end
        else
          buffer = scanner.rest
          break
        end
      end
    rescue StandardError => e
      DebugHelper.debug("JSON parsing error: #{e.message}", category: :api, level: :error)
      DebugHelper.debug("Backtrace: #{e.backtrace.join("\n")}", category: :api, level: :debug)
      DebugHelper.debug("Error details: #{e.inspect}", category: :api, level: :debug)
    end

    # Handle tool calls if any were collected
    if tools.any? && tools.any? { |_, tool| tool["completed"] }
      session[:call_depth_per_turn] += 1

      if session[:call_depth_per_turn] > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => Monadic::Utils::ErrorFormatter.api_error(
          provider: "xAI",
          message: "Maximum function call depth exceeded"
        ) }]
      end

      # Build tool_calls in standard format for process_functions
      tool_calls = []
      tools.each do |item_id, tool_data|
        if tool_data["completed"] && tool_data["arguments"]
          tool_calls << {
            "id" => tool_data["call_id"] || item_id,
            "function" => {
              "name" => tool_data["name"] || "unknown",
              "arguments" => tool_data["arguments"]
            }
          }
        end
      end

      if tool_calls.any?
        # Store assistant function calls in Responses API format for context.
        # Accumulate across rounds so prior turns' calls remain visible.
        (obj["assistant_function_calls"] ||= []).concat(tools.filter_map do |item_id, tool_data|
          next unless tool_data["completed"]
          {
            "type" => "function_call",
            "id" => item_id,
            "call_id" => tool_data["call_id"] || item_id,
            "name" => tool_data["name"] || "unknown",
            "arguments" => tool_data["arguments"] || "{}"
          }
        end)

        Monadic::Utils::ExtraLogger.log {
          lines = ["Grok tool calls collected from streaming:"]
          tool_calls.each { |tc| lines << "  - #{tc.dig('function', 'name')}: id=#{tc['id']}" }
          lines.join("\n")
        }

        # Process the tools and get results
        new_results = process_functions(app, session, tool_calls, nil, session[:call_depth_per_turn], &block)
        return new_results || []
      end
    end

    build_grok_text_response(
      texts: texts, query: query, finish_reason: finish_reason,
      reasoning_content: reasoning_content,
      usage_input_tokens: usage_input_tokens, usage_output_tokens: usage_output_tokens,
      usage_total_tokens: usage_total_tokens, &block
    )
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Grok] Unexpected error: #{e.message}\n[Grok] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    formatted_error = Monadic::Utils::ErrorFormatter.api_error(
      provider: "xAI",
      message: "Unexpected error: #{e.message}"
    )
    res_event = { "type" => "error", "content" => formatted_error }
    block&.call res_event
    [res_event]
  end

  def build_tool_response(tool_results)
    response_parts = []

    tool_results.each do |result|
      result_name = result["name"] || result[:name]
      result_content = (result["content"] || result[:content]).to_s

      case result_name
      when "create_jupyter_notebook"
        if result_content.include?("created successfully")
          # Match format: "Notebook filename.ipynb created successfully. Access it at: URL"
          if result_content =~ /Notebook\s+(\S+\.ipynb)\s+created successfully/
            notebook_filename = $1
            response_parts << "Created notebook: **#{notebook_filename}**"
            response_parts << "<a href=\"http://127.0.0.1:8889/lab/tree/#{notebook_filename}\" target=\"_blank\">Open #{notebook_filename} in JupyterLab</a>"
          elsif result_content.include?("Access it at:")
            # URL is already in the response, just format it nicely
            response_parts << "Notebook created successfully"
            response_parts << result_content.split("Access it at:").last.strip
          else
            response_parts << result_content
          end
        else
          response_parts << result_content
        end

      when "add_jupyter_cells"
        response_parts << "Added cells to the notebook"
        # Extract notebook URL if present in the result
        if result_content =~ /Access the notebook at:\s*(http[^\s]+)/
          notebook_url = $1
          response_parts << "<a href=\"#{notebook_url}\" target=\"_blank\">Open notebook in JupyterLab</a>"
        elsif result_content =~ /(\S+\.ipynb)/
          # Fallback: extract filename and construct URL
          notebook_filename = $1
          response_parts << "<a href=\"http://127.0.0.1:8889/lab/tree/#{notebook_filename}\" target=\"_blank\">Open #{notebook_filename} in JupyterLab</a>"
        end

      when "run_jupyter"
        if result_content.include?("started")
          response_parts << "JupyterLab server started"
        elsif result_content.include?("already running")
          response_parts << "JupyterLab was already running"
        else
          response_parts << result_content
        end

      when "run_code"
        output_content = result_content
        response_parts << "**Code Output:**\n```\n#{output_content}\n```"

        # Check if image files were generated (similar to Gemini's handling)
        if output_content =~ /File created: ([^\s]+\.(svg|png|jpg|jpeg|gif)).*Full path: \/monadic\/data/i
          filename = $1
          # Add HTML for displaying the image
          response_parts << "<div class=\"generated_image\">\n  <img src=\"/data/#{filename}\" />\n</div>"

          Monadic::Utils::ExtraLogger.log { "Grok auto-injected image HTML for: /data/#{filename}" }
        end

      when "generate_image_with_grok"
        # Parse the tool result to build proper HTML response
        begin
          if result_content.is_a?(String)
            content_json = JSON.parse(result_content)
            if content_json["success"] && content_json["filename"]
              # Build the HTML response as specified in the system prompt
              response_parts << "<div class=\"revised_prompt\">"
              response_parts << "  <b>Revised Prompt</b>: #{content_json["revised_prompt"]}"
              response_parts << "</div>"
              response_parts << "<div class=\"generated_image\">"
              response_parts << "  <img src=\"/data/#{content_json["filename"]}\">"
              response_parts << "</div>"
            else
              # Generation failed or success: false
              error_msg = content_json["error"] || content_json["message"] || "Image generation failed"
              response_parts << error_msg
            end
          else
            # Non-string result (e.g. Hash) — defensive fallback
            response_parts << result_content.to_s
          end
        rescue JSON::ParserError => e
          response_parts << "Error processing image generation result: #{e.message}"
        end

      when "generate_video_with_grok_imagine"
        begin
          if result_content.is_a?(String)
            content_json = JSON.parse(result_content)
            if content_json["success"] && content_json["filename"]
              response_parts << "<div class=\"prompt\" style=\"margin-bottom: 15px;\">"
              response_parts << "  <b>Video Generated</b>"
              response_parts << "</div>"
              response_parts << "<div class=\"generated_video\">"
              response_parts << "  <video controls width=\"600\">"
              response_parts << "    <source src=\"/data/#{content_json["filename"]}\" type=\"video/mp4\" />"
              response_parts << "  </video>"
              response_parts << "</div>"
            else
              error_msg = content_json["message"] || content_json["error"] || "Video generation failed"
              response_parts << error_msg
            end
          else
            response_parts << result_content
          end
        rescue JSON::ParserError => e
          response_parts << "Error processing video generation result: #{e.message}"
        end

      else
        response_parts << "Executed: #{result_name}"
      end
    end

    response_parts.join("\n\n")
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    if obj.nil?
      # Initialize parameters if nil
      session[:parameters] = {}
      obj = session[:parameters]
    end
    tool_results = []

    tools.each do |tool_call|
      function_name = tool_call.dig("function", "name")
      next if function_name.nil?

      record_tool_call(session, function_name)
      block&.call({ "type" => "tool_executing", "content" => function_name })

      tool_result, error_stop = invoke_grok_tool_function(app, session, tool_call, function_name, &block)
      tool_results << tool_result if tool_result
      next if error_stop
    end

    # Store tool results in session for API request.
    # Accumulate across rounds so prior turns' results remain visible to
    # the model on the next API call. Mirrors the Claude / OpenAI fix.
    (obj["function_returns"] ||= []).concat(tool_results)

    # Check if we've reached max call depth
    if call_depth >= MAX_FUNC_CALLS
      summary = "Completed #{tool_results.length} tool execution(s):\n\n"
      tool_results.each do |result|
        result_content = (result['content'] || result[:content]).to_s
        result_name = result['name'] || result[:name]
        summary += "- #{result_name}: #{result_content[0..100]}#{result_content.length > 100 ? '...' : ''}\n"
      end

      return [{
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => summary
          },
          "finish_reason" => "stop"
        }]
      }]
    end

    # Check if we should stop due to repeated errors
    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected. Stopping." } }] }]
    end

    # CORRECT FLOW: Send tool results back to Grok to get natural language response
    # According to documentation, we must send tool results with function_call_output back to Grok

    Monadic::Utils::ExtraLogger.log { "Sending tool results back to Grok (depth: #{call_depth})\nNumber of tool results: #{tool_results.length}" }

    # Build a helpful response that includes actual results
    response_content = build_tool_response(tool_results)

    # Determine if we can skip the recursive API call (media generation or Jupyter with complete response)
    has_image_generation = tool_results.any? { |r| (r["name"] || r[:name]) == "generate_image_with_grok" }
    has_video_generation = tool_results.any? { |r| (r["name"] || r[:name]) == "generate_video_with_grok_imagine" }
    has_jupyter_operation = tool_results.any? { |r|
      %w[create_jupyter_notebook add_jupyter_cells create_and_populate_jupyter_notebook].include?(r["name"] || r[:name])
    }

    skip_api_call = has_image_generation ||
                    has_video_generation ||
                    (has_jupyter_operation && response_content.include?("<a href="))

    if skip_api_call
      # Build the response directly without calling Grok
      # Send the response through the streaming callback
      block&.call({ "type" => "fragment", "content" => response_content })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })

      new_results = [{
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => response_content
          },
          "finish_reason" => "stop"
        }]
      }]
    else
      new_results = api_request("tool", session, call_depth: call_depth + 1, disable_streaming: true, &block)
    end

    # Post-process Grok's response to replace incorrect filenames and fix image paths
    postprocess_grok_response(new_results, obj)

    # If Grok returns empty or inadequate response after tool execution, provide a fallback
    content_check = new_results&.dig(0, "choices", 0, "message", "content").to_s.strip
    tool_calls_check = new_results&.dig(0, "choices", 0, "message", "tool_calls")

    is_inadequate = new_results.nil? || new_results.empty? ||
                    (content_check.empty? && (tool_calls_check.nil? || tool_calls_check.empty?)) ||
                    (obj["current_image_filename"] && !content_check.include?("<img") &&
                     !content_check.include?("generated_image") &&
                     (tool_calls_check.nil? || tool_calls_check.empty?))

    if is_inadequate
      fallback_content = response_content || "Tools executed successfully."

      # Add information from session if available
      if obj["current_notebook_link"]
        fallback_content += "\n\n#{obj["current_notebook_link"]}"
      end

      return [{
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => fallback_content
          },
          "finish_reason" => "stop"
        }]
      }]
    end

    return new_results
  end
end
