require 'fileutils'
require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/json_repair"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require_relative "../../utils/system_prompt_injector"
require_relative "../../utils/extra_logger"
require_relative "../base_vendor_helper"
require_relative "../../monadic_performance"

module ClaudeHelper
  include BaseVendorHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicPerformance
  # Maximum tool-call round-trips per user turn.
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.anthropic.com/v1"
  MAX_RETRIES = 5
  RETRY_DELAY = 2

  define_timeouts "CLAUDE", open: 10, read: 600, write: 120

  # ENV key for emergency override
  LEGACY_MODE_ENV = "CLAUDE_LEGACY_MODE"

  # Convert OpenAI-format tools to Claude format
  # Claude API requires 'type: "custom"' for custom tools (as of 2025)
  # OpenAI uses 'type: "function"' with a nested 'function' object
  def self.convert_tool_to_claude_format(tool)
    return tool unless tool.is_a?(Hash)

    # Already in Claude format (has type: "custom" or is a native tool)
    tool_type = tool["type"] || tool[:type]
    if tool_type == "custom" ||
       tool_type&.start_with?("web_search") ||
       tool_type&.start_with?("code_execution") ||
       tool_type&.start_with?("bash_") ||
       tool_type&.start_with?("text_editor_") ||
       tool_type&.start_with?("memory_")
      return tool
    end

    # Convert OpenAI format (type: "function" with nested function object)
    if tool_type == "function" && (tool["function"] || tool[:function])
      func = tool["function"] || tool[:function]
      return {
        "type" => "custom",
        "name" => func["name"] || func[:name],
        "description" => func["description"] || func[:description],
        "input_schema" => func["parameters"] || func[:parameters] || {
          "type" => "object",
          "properties" => {},
          "required" => []
        }
      }
    end

    # Tool has name but wrong type - just fix the type
    if tool["name"] || tool[:name]
      converted = tool.dup
      converted["type"] = "custom"
      converted.delete(:type)

      # Ensure input_schema exists (Claude requires it)
      unless converted["input_schema"] || converted[:input_schema]
        converted["input_schema"] = {
          "type" => "object",
          "properties" => {},
          "required" => []
        }
      end

      return converted
    end

    tool
  end


  # Native Anthropic web search tool
  NATIVE_WEBSEARCH_TOOL = {
    type: "web_search_20250305",
    name: "web_search",
    max_uses: 10
  }

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT



  attr_accessor :thinking, :signature

  class << self
    attr_reader :cached_models

    def vendor_name
      "Anthropic"
    end

  end

  define_model_lister :anthropic,
    api_key_config: "ANTHROPIC_API_KEY",
    endpoint_path: "/models",
    headers: ->(api_key) { { "x-api-key" => api_key, "anthropic-version" => "2023-06-01" } },
    fallback_provider: "anthropic" do |json|
      (json["data"] || []).map { |m| m["id"] }.reject { |id| id.include?("claude-2") }
    end

  def initialize
    @thinking = nil
    @signature = nil
    super
  end

  # (removed duplicate public send_query to keep a single SSOT-driven implementation)

  private
  # Resolve tool capability from SSOT with legacy override and source tag
  def resolve_tool_capability(model)
    spec_tool_capable = Monadic::Utils::ModelSpec.get_model_property(model, "tool_capability")
    source = spec_tool_capable.nil? ? "fallback" : "spec"
    value = spec_tool_capable.nil? ? true : !!spec_tool_capable
    if ENV[LEGACY_MODE_ENV] == "true"
      value = true
      source = "legacy"
    end
    [value, source]
  end

  # Function to write logs to file - enabled for debugging AI User issues
  def log_to_file(message, type="general")
    return unless CONFIG["DEBUG_AI_USER"]
    
    begin
      log_dir = File.join(Dir.home, "monadic", "log")
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
      
      file_name = case type
                  when "ai_user"
                    "claude_ai_user_debug.log"
                  else
                    "claude_debug.log"
                  end
      
      File.open(File.join(log_dir, file_name), "a") do |f|
        f.puts("[#{Time.now}] #{message}")
      end
    rescue => e
      # Silent fail for logging
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    # Resolve model via SSOT only (no hardcoded fallback)
    model = model.to_s.strip
    model = nil if model.empty?
    model ||= SystemDefaults.get_default_model('anthropic')
    
    # First try CONFIG, then fall back to ENV for the API key
    api_key = CONFIG["ANTHROPIC_API_KEY"]
    
    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "x-api-key" => api_key
    }

    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Model details are logged to dedicated log files
    
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Basic request body
    # Get max_tokens with fallback to model default
    require_relative "../../utils/model_token_utils"
    max_tokens_value = options["max_tokens"] || ModelTokenUtils.get_max_tokens(model)
    
    body = {
      "model" => model,
      "max_tokens" => max_tokens_value,
      "temperature" => options["temperature"] || 0.7,
      "cache_control" => { "type" => "ephemeral" }
    }
    
    # Extract system message - Claude API expects this as a top-level parameter
    if options["system"]
      body["system"] = options["system"]
    elsif options["ai_user_system_message"]
      body["system"] = options["ai_user_system_message"]
    end
    
    # Handle messages - check if custom messages are provided (e.g., from SecondOpinionAgent)
    if options["messages"]
      # Convert messages to Claude's expected format
      body["messages"] = options["messages"].map do |msg|
        content = msg["content"]
        # Ensure content is in the expected format for Claude API
        if content.is_a?(String)
          {
            "role" => msg["role"],
            "content" => [
              {
                "type" => "text",
                "text" => content
              }
            ]
          }
        else
          # Already in the correct format
          msg
        end
      end
    else
      # Default AI User message for backward compatibility
      body["messages"] = [{
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "What might the user say next in this conversation? Please respond as if you were the user."
          }
        ]
      }]
    end
    
    # NOTE: Thinking/reasoning is intentionally disabled for AI User messages
    # AI User responses should be quick and simple, not requiring extended reasoning

    # Add tool definitions if provided (for testing tool-calling apps)
    if options["tools"] && options["tools"].any?
      # Convert to Anthropic format
      body["tools"] = options["tools"].map do |tool|
        if tool["input_schema"]
          # Already in Anthropic format
          tool
        else
          # Convert from simple/OpenAI format to Anthropic format
          func = tool["function"] || tool
          {
            "name" => func["name"] || func[:name],
            "description" => func["description"] || func[:description] || "",
            "input_schema" => func["parameters"] || func[:parameters] || { "type" => "object", "properties" => {} }
          }
        end
      end
    end

    # Set API endpoint
    target_uri = "#{API_ENDPOINT}/messages"

    # Make the request
    http = HTTP.headers(headers)
    
    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout,
                       write: write_timeout,
                       read: read_timeout).post(target_uri, json: body)
      break if res && res.status && res.status.success?
      sleep RETRY_DELAY
    end

    # Process response
    if res && res.status && res.status.success?
      begin
        parsed_response = JSON.parse(res.body)

        # Check for tool calls in the response (Anthropic uses type: "tool_use")
        if parsed_response["content"] && parsed_response["content"].is_a?(Array)
          tool_use_blocks = parsed_response["content"].select { |item| item["type"] == "tool_use" }
          if tool_use_blocks.any?
            tool_calls = tool_use_blocks.map do |tc|
              {
                "name" => tc["name"],
                "args" => tc["input"] || {}
              }
            end
            text_blocks = parsed_response["content"].select { |item| item["type"] == "text" }
            text_content = text_blocks.map { |block| block["text"] }.join("\n")
            return { text: text_content, tool_calls: tool_calls }
          end
        end

        # Extract content from response - try all known formats

        # Format 1: Direct content array in response root
        if parsed_response["content"] && parsed_response["content"].is_a?(Array)
          text_blocks = parsed_response["content"].select { |item| item["type"] == "text" }
          return text_blocks.map { |block| block["text"] }.join("\n") if text_blocks.any?
        end
        
        # Format 2: Content in message.content
        if parsed_response["message"] && parsed_response["message"]["content"].is_a?(Array)
          text_blocks = parsed_response["message"]["content"].select { |item| item["type"] == "text" }
          return text_blocks.map { |block| block["text"] }.join("\n") if text_blocks.any?
        end
        
        # Format 3: Direct completion in response
        if parsed_response["completion"]
          return parsed_response["completion"]
        end
        
        # Format 4: Text in response
        if parsed_response["text"]
          return parsed_response["text"]
        end
        
        # Extract any content from anywhere in the response
        def extract_text_from_hash(hash, depth=0)
          return nil if depth > 3 || !hash.is_a?(Hash)
          
          hash.each do |key, value|
            if key == "text" && value.is_a?(String)
              return value
            elsif value.is_a?(Hash)
              result = extract_text_from_hash(value, depth+1)
              return result if result
            elsif value.is_a?(Array)
              value.each do |item|
                if item.is_a?(Hash)
                  if item["type"] == "text" && item["text"]
                    return item["text"]
                  end
                  
                  result = extract_text_from_hash(item, depth+1)
                  return result if result
                end
              end
            end
          end
          nil
        end
        
        # Try recursive extraction
        text = extract_text_from_hash(parsed_response)
        return text if text
        
        # If all else fails, return the entire response for debugging
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Claude",
          message: "Could not extract text content from API response"
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Claude", 
          message: "Failed to process API response: #{e.message}"
        )
      end
    else
      error_response = (res && res.body) ? JSON.parse(res.body) : { "error" => "No response received" }
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Claude",
        message: error_response.dig("error", "message") || error_response["error"] || "No response received",
        code: res&.status&.code
      )
    end
  rescue StandardError => e
    return Monadic::Utils::ErrorFormatter.api_error(
      provider: "Claude",
      message: e.message
    )
  end

  # Build system prompts array with unified prompt injection.
  private def build_claude_system_prompts(session, obj, use_native_websearch)
    system_prompts = []

    session[:messages].each do |msg|
      next unless msg["role"] == "system"

      # Use unified system prompt injector only for the first system prompt
      if system_prompts.empty?
        text = Monadic::Utils::SystemPromptInjector.augment(
          base_prompt: msg["text"],
          session: session,
          options: {
            websearch_enabled: use_native_websearch,
            reasoning_model: false,
            websearch_prompt: WEBSEARCH_PROMPT,
            system_prompt_suffix: obj["system_prompt_suffix"]
          },
          separator: "\n\n"
        )

        Monadic::Utils::ExtraLogger.log { "Claude System Prompt Injection:\n  - Base prompt length: #{msg['text'].length}\n  - Augmented prompt length: #{text.length}\n  - Injections applied: #{text != msg['text']}" }
      else
        text = msg["text"]
      end

      sp = { type: "text", text: text }

      if system_prompts.empty?
        Monadic::Utils::ExtraLogger.log { "[DEBUG] First system prompt created:\n  - Text length: #{text.length}\n  - First 200 chars: #{text[0..200].inspect}#{text.length > 200 ? "\n  - Last 200 chars: #{text[-200..-1].inspect}" : ""}" }
      end

      system_prompts << sp
    end

    system_prompts
  end

  # Configure thinking mode parameters (budget_tokens, adaptive effort, max_tokens).
  # Returns a config hash: { thinking_enabled, budget_tokens, adaptive_effort, max_tokens }.
  private def configure_claude_thinking(obj, model, user_max_tokens, app)
    supports_thinking = Monadic::Utils::ModelSpec.supports_thinking?(obj["model"])
    use_adaptive = supports_thinking &&
                   Monadic::Utils::ModelSpec.supports_adaptive_thinking?(obj["model"])

    monadic_with_structured_outputs = obj["monadic"].to_s == "true" &&
                                      Monadic::Utils::ModelSpec.supports_structured_outputs?(obj["model"])

    if supports_thinking && obj["reasoning_effort"] && obj["reasoning_effort"] != "none" && !monadic_with_structured_outputs
      thinking_enabled = true

      if use_adaptive
        budget_tokens = nil
        adaptive_effort = case obj["reasoning_effort"]
                          when "minimal" then "low"
                          when "low"     then "low"
                          when "medium"  then "medium"
                          when "high"    then "high"
                          else "medium"
                          end
        max_tokens = user_max_tokens
      else
        adaptive_effort = nil
        case obj["reasoning_effort"]
        when "minimal"
          budget_tokens = [[(user_max_tokens * 0.25).to_i, 1024].max, 8000].min
          max_tokens = user_max_tokens
        when "low"
          budget_tokens = [(user_max_tokens * 0.5).to_i, 16000].min
          max_tokens = user_max_tokens
        when "medium"
          budget_tokens = [(user_max_tokens * 0.7).to_i, 32000].min
          max_tokens = user_max_tokens
        when "high"
          budget_tokens = [(user_max_tokens * 0.8).to_i, 48000].min
          max_tokens = user_max_tokens
        else
          budget_tokens = [(user_max_tokens * 0.5).to_i, 16000].min
          max_tokens = user_max_tokens
        end
      end
    else
      thinking_enabled = false
      budget_tokens = nil
      adaptive_effort = nil
      max_tokens = user_max_tokens

      if monadic_with_structured_outputs
        Monadic::Utils::ExtraLogger.log { "Claude: Thinking mode disabled for monadic app with structured outputs\n  Model: #{obj["model"]}\n  App: #{app}" }
      end
    end

    if budget_tokens && budget_tokens >= max_tokens
      budget_tokens = (max_tokens * 0.8).to_i
    end

    # Determine if thinking display should be omitted (faster streaming)
    # Only supported on adaptive thinking models (Opus 4.6, Sonnet 4.6)
    omit_display = thinking_enabled && use_adaptive && obj["show_thinking"].to_s == "false"

    { thinking_enabled: thinking_enabled, budget_tokens: budget_tokens,
      adaptive_effort: adaptive_effort, max_tokens: max_tokens,
      omit_thinking_display: omit_display }
  end

  # Build HTTP headers and base request body (model, stream, system, thinking, context management).
  # Returns [headers, body].
  private def build_claude_headers_and_body(model, obj, app, session, system_prompts, thinking_config, temperature, role)
    spec_beta = Monadic::Utils::ModelSpec.get_model_property(model, "beta_flags")
    app_beta = APPS[app]&.settings&.[]("betas")

    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "anthropic-dangerous-direct-browser-access": "true",
      "x-api-key" => CONFIG["ANTHROPIC_API_KEY"],
    }

    beta_flags = []
    beta_flags.concat(Array(spec_beta)) if spec_beta
    beta_flags.concat(Array(app_beta)) if app_beta

    # Advisor Tool beta header (auto-added when the app opts in via MDSL advisor_tool block)
    advisor_settings = claude_advisor_settings(app)
    beta_flags << "advisor-tool-2026-03-01" if advisor_settings

    beta_flags.uniq!
    headers["anthropic-beta"] = beta_flags.join(",") if beta_flags.any?

    spec_supports_streaming = Monadic::Utils::ModelSpec.get_model_property(model, "supports_streaming")
    supports_streaming = spec_supports_streaming.nil? ? true : !!spec_supports_streaming
    supports_streaming = true if ENV[LEGACY_MODE_ENV] == "true"

    body = {
      "system" => system_prompts,
      "model" => obj["model"],
      "stream" => supports_streaming,
      "cache_control" => { "type" => "ephemeral" }
    }

    # Context management
    # Default-on for models that support it: clear_thinking + clear_tool_uses
    # are automatically attached. Apps can override with custom edits via
    # MDSL `context_management do edits [...] end`, or disable entirely with
    # `context_management false` — in that case only the context_size sliding
    # window (client-side) trims history. The beta header is still attached
    # when the model supports it so that the server recognizes our opt-out.
    begin
      supports_context_management = Monadic::Utils::ModelSpec.supports_context_management?(obj["model"])
      app_context_management = APPS[app]&.settings&.[]("context_management")
      app_context_management = APPS[app]&.settings&.[](:context_management) if app_context_management.nil?
      opted_out = (app_context_management == false)

      if supports_context_management && role != "tool" && !opted_out
        if app_context_management
          body["context_management"] = app_context_management
        else
          edits = []
          if thinking_config[:thinking_enabled]
            edits << {
              "type" => "clear_thinking_20251015",
              "keep" => { "type" => "thinking_turns", "value" => 1 }
            }
          end
          edits << {
            "type" => "clear_tool_uses_20250919",
            "trigger" => { "type" => "input_tokens", "value" => 100000 },
            "keep" => { "type" => "tool_uses", "value" => 5 },
            "clear_at_least" => { "type" => "input_tokens", "value" => 10000 }
          }
          body["context_management"] = { "edits" => edits }
        end
      elsif opted_out
        Monadic::Utils::ExtraLogger.log { "Claude: context_management opt-out (context_size sliding window only)" }
      end

      beta_headers = []
      beta_headers.concat(headers["anthropic-beta"].split(",").map(&:strip)) if headers["anthropic-beta"]
      beta_headers << "context-management-2025-06-27" if supports_context_management && role != "tool" && !opted_out
      beta_headers << "model-context-window-exceeded-2025-08-26"
      headers["anthropic-beta"] = beta_headers.uniq.join(",") unless beta_headers.empty?
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "Claude: Failed to check context management support: #{e.message}" }
    end

    # Thinking / temperature / max_tokens
    if thinking_config[:thinking_enabled]
      body["max_tokens"] = thinking_config[:max_tokens]
      body["temperature"] = 1
      if thinking_config[:adaptive_effort]
        thinking_params = { "type": "adaptive" }
        body["output_config"] = { "effort": thinking_config[:adaptive_effort] }
      else
        thinking_params = { "type": "enabled", "budget_tokens": thinking_config[:budget_tokens] }
      end
      # Omit thinking display content for faster streaming when user toggles off
      # Only supported on models with supports_adaptive_thinking (Opus 4.6, Sonnet 4.6)
      if thinking_config[:omit_thinking_display]
        thinking_params["display"] = "omitted"
      end
      body["thinking"] = thinking_params
    else
      body["temperature"] = temperature if temperature
      body["max_tokens"] = thinking_config[:max_tokens] if thinking_config[:max_tokens]
    end

    # Skills container
    app_skills = APPS[app]&.settings&.[]("skills")
    if app_skills && app_skills.is_a?(Array) && !app_skills.empty?
      body["container"] = {
        "skills" => app_skills.map { |skill_name| { "type" => "anthropic", "skill_id" => skill_name } }
      }
    end

    [headers, body]
  end

  # Merge tools_param and filtered app tools, removing tavily and deduplicating.
  private def build_claude_final_tools(tools_param, filtered_tools)
    final_tools = []
    if tools_param && !tools_param.empty?
      filtered_param = Array(tools_param).reject do |tool|
        tool_name = tool.dig("name") || tool.dig("function", "name")
        ["tavily_search", "tavily_fetch"].include?(tool_name)
      end
      converted_param = filtered_param.map { |t| ClaudeHelper.convert_tool_to_claude_format(t) }
      final_tools.concat(converted_param)
    end
    final_tools.concat(filtered_tools)
    final_tools.compact!
    final_tools.uniq! { |tool| "#{tool.dig("type") || tool.dig(:type)}-#{tool.dig("name") || tool.dig(:name)}" }
    final_tools
  end

  # Add code_execution tool when Skills are configured.
  private def add_claude_skills_tool(body, app_skills)
    return unless app_skills && app_skills.is_a?(Array) && !app_skills.empty?

    body["tools"] ||= []
    body["tools"] << { "type" => "code_execution_20250825", "name" => "code_execution" }

    Monadic::Utils::ExtraLogger.log { "Claude: code_execution_20250825 tool added for Skills" }
  end

  # Fetch the Advisor Tool settings for an app, supporting both symbol and string keys.
  # Returns nil if the app has not opted in.
  private def claude_advisor_settings(app)
    settings = APPS[app]&.settings
    return nil unless settings
    cfg = settings[:advisor_tool] || settings["advisor_tool"]
    return nil if cfg.nil? || (cfg.respond_to?(:empty?) && cfg.empty?)
    cfg
  end

  # Add the Anthropic Advisor Tool entry to the tools array when configured.
  # The advisor tool is a server-side tool: the executor decides when to invoke it,
  # and Anthropic runs a sub-inference on the advisor model server-side.
  private def add_claude_advisor_tool(body, app)
    advisor_cfg = claude_advisor_settings(app)
    return unless advisor_cfg

    model_value  = advisor_cfg[:model]    || advisor_cfg["model"]    || "claude-opus-4-7"
    max_uses_val = advisor_cfg[:max_uses] || advisor_cfg["max_uses"]
    caching_val  = advisor_cfg[:caching]  || advisor_cfg["caching"]

    tool_entry = {
      "type"  => "advisor_20260301",
      "name"  => "advisor",
      "model" => model_value
    }
    tool_entry["max_uses"] = max_uses_val if max_uses_val
    if caching_val.is_a?(Hash)
      normalized = caching_val.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      tool_entry["caching"] = normalized
    end

    body["tools"] ||= []
    unless body["tools"].any? { |t| t.is_a?(Hash) && (t["type"] == "advisor_20260301" || t[:type] == "advisor_20260301") }
      body["tools"] << tool_entry
      Monadic::Utils::ExtraLogger.log { "Claude: advisor_20260301 tool added (advisor_model=#{model_value}, max_uses=#{max_uses_val || 'unlimited'})" }
    end
  end

  # Configure tools on the request body for both user and tool roles.
  # Handles tool parsing, PTD filtering, websearch, Skills, and tool_choice.
  private def configure_claude_tools(body, obj, app, session, role, thinking_enabled, use_native_websearch)
    app_settings = APPS[app]&.settings
    app_tools = app_settings && (app_settings[:tools] || app_settings["tools"]) ? (app_settings[:tools] || app_settings["tools"]) : []
    app_skills = APPS[app]&.settings&.[]("skills")
    tool_capable, _tool_capable_source = resolve_tool_capability(obj["model"])

    # Parse tools_param from JSON string
    tools_param = obj["tools"]
    if tools_param.is_a?(String)
      begin
        tools_param = JSON.parse(tools_param)
      rescue JSON::ParserError
        tools_param = nil
      end
    end

    if role != "tool"
      websearch_enabled = obj["websearch"] == "true" || obj["websearch"] == true
      include_web_search_tool = websearch_enabled && use_native_websearch
      web_search_tool = { "type" => "web_search_20250305", "name" => "web_search", "max_uses" => 5 }

      combined_tools = []
      app_tool_list = app_tools.is_a?(Array) ? app_tools : (app_tools ? [app_tools] : [])
      combined_tools.concat(app_tool_list)
      combined_tools << web_search_tool if include_web_search_tool

      filtered_tools = combined_tools
      if app_settings && (app_settings[:progressive_tools] || app_settings["progressive_tools"])
        begin
          filtered_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
            app_name: app, session: session, app_settings: app_settings, default_tools: combined_tools
          )
        rescue StandardError => e
          DebugHelper.debug("Claude: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning)
          filtered_tools = combined_tools
        end
      end

      final_tools = build_claude_final_tools(tools_param, filtered_tools)

      if final_tools.empty?
        body.delete("tools")
      else
        body["tools"] = final_tools.map { |t| ClaudeHelper.convert_tool_to_claude_format(t) }
      end

      add_claude_skills_tool(body, app_skills)
      add_claude_advisor_tool(body, app)

      # Add web_search if not yet present
      if websearch_enabled && use_native_websearch
        progressive_settings = app_settings && (app_settings[:progressive_tools] || app_settings["progressive_tools"])
        already_has = body["tools"]&.any? { |t| t.is_a?(Hash) && (t["type"] == "web_search_20250305" || t[:type] == "web_search_20250305") }
        unless progressive_settings || already_has
          DebugHelper.debug("Claude: Adding web_search_20250305 tool for web search", category: :api, level: :debug)
          body["tools"] ||= []
          body["tools"] << { "type" => "web_search_20250305", "name" => "web_search", "max_uses" => 5 }

          Monadic::Utils::ExtraLogger.log { "Claude: web_search_20250305 tool added to request\nTools array: #{body["tools"].inspect}" }
        end
      end
    else
      # Tool role: attach tools for Claude to know what's available
      function_list = app_tools.is_a?(Array) ? app_tools : (app_tools ? [app_tools] : [])

      filtered_function_tools = function_list
      if app_settings
        begin
          filtered_function_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
            app_name: app, session: session, app_settings: app_settings, default_tools: function_list
          )
        rescue StandardError => e
          DebugHelper.debug("Claude: Progressive tool filtering (tool role) skipped due to #{e.message}", category: :api, level: :warning)
          filtered_function_tools = function_list
        end
      end

      final_tools = build_claude_final_tools(tools_param, filtered_function_tools)

      if final_tools.empty?
        body.delete("tools")
      else
        body["tools"] = final_tools.map { |t| ClaudeHelper.convert_tool_to_claude_format(t) }
      end

      add_claude_skills_tool(body, app_skills)
      add_claude_advisor_tool(body, app)

      Monadic::Utils::ExtraLogger.log {
        msg = "Claude processing tool results:\nTools included: #{body["tools"] ? "Yes (#{body["tools"].length} tools)" : "No"}"
        msg += "\nTool names: #{body["tools"].map { |t| t["name"] || t.dig("function", "name") }.join(", ")}" if body["tools"]
        msg
      }
    end

    # Filter non-tool-capable models: keep only server-side tools (web_search, advisor)
    if body["tools"] && !tool_capable
      body["tools"].select! do |t|
        next false unless t.is_a?(Hash)
        type = t["type"] || t[:type]
        type == "web_search_20250305" || type == "advisor_20260301"
      end
    end

    # Clean up and set tool_choice
    if body["tools"] && !body["tools"].empty?
      body["tools"].uniq!
      if !body["tool_choice"]
        has_websearch = body["tools"].any? { |t| t.is_a?(Hash) && (t["type"] == "web_search_20250305" || t[:type] == "web_search_20250305") }
        advisor_enabled = !claude_advisor_settings(app).nil?

        if role == "tool"
          # Tool-role requests (submitting tool results). The model decides
          # whether to call more tools or respond with text — we don't force
          # a tool call. However, when advisor is enabled we still want to
          # forbid parallel tool calls so the advisor's inline guidance can
          # influence the next single tool choice rather than racing with it.
          if advisor_enabled
            body["tool_choice"] = { "type" => "auto", "disable_parallel_tool_use" => true }
          end
        elsif thinking_enabled
          # With extended thinking, Claude only accepts tool_choice.type "auto"
          # or "none" (not "any" or "tool"). Only set tool_choice when we
          # actually need to add `disable_parallel_tool_use` — otherwise the
          # default behavior (auto, parallel allowed) is fine.
          if advisor_enabled
            body["tool_choice"] = { "type" => "auto", "disable_parallel_tool_use" => true }
          end
        elsif tool_capable || has_websearch
          tool_choice_value = { "type" => "any" }
          # When the Advisor Tool is enabled, disable parallel tool use so the
          # advisor's guidance can influence the next decision rather than
          # racing in parallel with tool calls whose results it cannot see.
          # Parallel calls cause the advisor to make judgments on incomplete
          # transcripts (it sees invocations but not results), which leads to
          # hallucinated criticism of work already in flight.
          tool_choice_value["disable_parallel_tool_use"] = true if advisor_enabled
          body["tool_choice"] = tool_choice_value
        end
      end
    else
      body.delete("tools")
      body.delete("tool_choice")
    end
  end

  # Build body["messages"] from context, handle images, PDFs, and initiate_from_assistant.
  # Returns true on success, or an Array (early return) on vision/PDF error.
  private def build_claude_messages(body, context, obj, model, role, session, &block)
    messages = context.compact.map do |msg|
      content = { "type" => "text", "text" => msg["text"] }
      { "role" => msg["role"], "content" => [content] }
    end

    if messages.empty? && obj["ai_user"] != "true"
      messages << { "role" => "user", "content" => [{ "type" => "text", "text" => "Hello." }] }
    end

    if !messages.empty? && messages.last["role"] == "user"
      content = messages.last["content"]

      if obj["images"]
        begin
          spec_vision = Monadic::Utils::ModelSpec.get_model_property(model, "vision_capability")
          supports_vision = spec_vision.nil? ? true : !!spec_vision
          spec_pdf = Monadic::Utils::ModelSpec.get_model_property(model, "supports_pdf")
          supports_pdf = spec_pdf.nil? ? true : !!spec_pdf
        rescue StandardError => e
          supports_vision = true
          supports_pdf = true
          DebugHelper.debug("[CLAUDE_SSOT] Failed to get capabilities: #{e.message}", category: :api, level: :warn)
        end
        if ENV[LEGACY_MODE_ENV] == "true"
          supports_vision = true
          supports_pdf = true
        end

        obj["images"].each do |file|
          if file["type"] == "application/pdf"
            unless supports_pdf
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Claude", message: "This model does not support PDF input.", code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end
            doc = {
              "type" => "document",
              "source" => { "type" => "base64", "media_type" => "application/pdf", "data" => file["data"].split(",")[1] }
            }
            content.unshift(doc)
          else
            unless supports_vision
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Claude", message: "This model does not support image input (vision).", code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end
            img = {
              "type" => "image",
              "source" => { "type" => "base64", "media_type" => file["type"], "data" => file["data"].split(",")[1] }
            }
            content << img
          end
        end
      end
    end

    body["messages"] = messages

    # Handle initiate_from_assistant case
    has_user_message = body["messages"].any? { |msg| msg["role"] == "user" }
    if !has_user_message && obj["initiate_from_assistant"]
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => "Please proceed according to your system instructions and introduce yourself." }]
      }
    end

    nil # success — messages set in body
  end

  # Execute the HTTP API call, handle retries, and route to streaming processing.
  private def execute_claude_api_call(headers, body, app, session, call_depth, websearch_enabled, use_native_websearch, &block)
    target_uri = "#{API_ENDPOINT}/messages"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    if Monadic::Utils::ExtraLogger.enabled? || ENV["DEBUG_CLAUDE"]
      Monadic::Utils::ExtraLogger.log {
        msg = "\nClaude API Headers:\n  x-api-key: #{headers["x-api-key"]&.slice(0, 20)}...\n  anthropic-beta: #{headers["anthropic-beta"]}"
        if headers["anthropic-beta"]
          msg += "\n    Beta headers breakdown:"
          headers["anthropic-beta"].split(",").each { |beta| msg += "\n      - #{beta.strip}" }
        end
        msg += "\n  anthropic-version: #{headers["anthropic-version"]}\n  Model: #{body["model"]}\n  Thinking mode: #{body["thinking"] ? "enabled" : "disabled"}\n  Output format present: #{body["output_format"] ? "yes" : "no"}"
        if body["output_format"]
          msg += "\n    Type: #{body["output_format"]["type"]}\n    Schema keys: #{body["output_format"]["schema"]&.keys&.join(", ")}"
        end
        msg += "\n  Body keys: #{body.keys.join(", ")}"
        msg
      }
    end

    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: open_timeout,
                         write: write_timeout,
                         read: read_timeout).post(target_uri, json: body)
      break if res.status.success?
      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      Monadic::Utils::ExtraLogger.log { "[Claude API Error] #{error_report}" }
      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "Claude",
        message: error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      return [res]
    end

    # Debug logging for web search
    if websearch_enabled && use_native_websearch
      DebugHelper.debug("Claude final request with web search - tools: #{body["tools"]&.map { |t| "#{t["type"]}:#{t["name"]}" }.join(", ")}", category: :api, level: :debug)

      Monadic::Utils::ExtraLogger.log {
        msg = "Claude final API request:\nURL: #{API_ENDPOINT}/messages\nModel: #{body["model"]}\nTools present: #{body["tools"] ? "Yes (#{body["tools"].length} tools)" : "No"}"
        msg += "\nTools: #{JSON.pretty_generate(body["tools"])}" if body["tools"]
        msg
      }
    end

    process_json_data(app: app, session: session, query: body, res: res.body, call_depth: call_depth, &block)
  end

  public
  def api_request(role, session, call_depth: 0, &block)
    # Reset call_depth counter for each new user turn
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:tool_call_sequence] = []
      session[:parallel_dispatch_called] = nil
      session[:images_injected_this_turn] = Set.new
      # Clear accumulated tool-turn context from any previous user request.
      # function_returns is built up across multiple tool rounds within a
      # single user request (see assemble_claude_tool_context); starting a
      # new user turn means the accumulator should reset.
      session[:parameters]&.delete("function_returns")
    end

    current_call_depth = session[:call_depth_per_turn] || 0
    num_retrial = 0

    Monadic::Utils::ExtraLogger.log { "\n=== Claude API Request Started ===\nRole: #{role}\nApp: #{session[:parameters]["app_name"]}\nSession parameters: #{session[:parameters].inspect}" }

    api_key = CONFIG["ANTHROPIC_API_KEY"]
    obj = session[:parameters]
    app = obj["app_name"]
    model = obj["model"]

    session[:messages] ||= []

    # Check if web search is enabled
    websearch = obj["websearch"] == "true" || obj["websearch"] == true

    Monadic::Utils::ExtraLogger.log { "Claude websearch parameter check:\nobj[\"websearch\"] = #{obj["websearch"].inspect} (type: #{obj["websearch"].class})\nwebsearch enabled = #{websearch}" }

    use_native_websearch = websearch &&
                          Monadic::Utils::ModelSpec.supports_web_search?(model) &&
                          CONFIG["ANTHROPIC_NATIVE_WEBSEARCH"] != "false"
    obj["use_native_websearch"] = use_native_websearch

    # Build system prompts
    system_prompts = build_claude_system_prompts(session, obj, use_native_websearch)

    temperature = obj["temperature"]&.to_f

    # Handle max_tokens
    max_tokens = obj["max_tokens"]&.to_i
    if max_tokens.nil? || max_tokens == 0
      require_relative "../../utils/model_token_utils"
      max_tokens = ModelTokenUtils.get_max_tokens(model)
      DebugHelper.debug("Claude: Using default max_tokens #{max_tokens} for model #{model}", category: :api, level: :info)
    end

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message = obj["message"].to_s

    # Push the user message to the client as early as possible
    if message != "" && role == "user"
      @thinking = nil
      @signature = nil
      res = { "type" => "user",
              "content" => {
                "role" => role,
                "mid" => request_id,
                "text" => obj["message"],
                "html" => markdown_to_html(obj["message"]),
                "lang" => detect_language(obj["message"]),
                "app_name" => obj["app_name"],
                "active" => true
              } }

      res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)
      block&.call res

      existing_msg = session[:messages].find do |m|
        m["role"] == "user" && m["text"] == obj["message"]
      end

      if existing_msg
        existing_msg.merge!(res["content"])
      else
        session[:messages] << res["content"]
      end

      Monadic::Utils::ExtraLogger.log { "Claude: user message pushed early (mid=#{request_id})" }
    end

    # Validate API key
    if api_key.nil? || api_key.to_s.strip.empty?
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Claude",
        env_var: "ANTHROPIC_API_KEY"
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Configure thinking
    thinking_config = configure_claude_thinking(obj, model, max_tokens, app)

    # Build context
    begin
      session[:messages].each { |msg| msg["active"] = false }

      context = session[:messages].filter do |msg|
        msg["role"] == "user" || msg["role"] == "assistant"
      end.last(context_size).each { |msg| msg["active"] = true }

      session[:messages].filter do |msg|
        msg["role"] == "system"
      end.each { |msg| msg["active"] = true }
      strip_inactive_image_data(session)
    rescue StandardError
      context = []
    end

    # Build headers and base body
    headers, body = build_claude_headers_and_body(model, obj, app, session, system_prompts, thinking_config, temperature, role)

    # Configure tools
    configure_claude_tools(body, obj, app, session, role, thinking_config[:thinking_enabled], use_native_websearch)

    # Build messages
    messages_result = build_claude_messages(body, context, obj, model, role, session, &block)
    return messages_result if messages_result # nil on success, Array on error

    # Handle tool role: add function_returns to messages
    if role == "tool"
      body["messages"] += obj["function_returns"]
    end

    # Force text-only response when force-stop is active
    if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Capability audit (optional)
    Monadic::Utils::ExtraLogger.log { "Claude SSOT capabilities for #{obj["model"]}: body_keys=#{body.keys.join(",")}" }

    # Execute API call
    websearch_enabled = obj["websearch"] == "true" || obj["websearch"] == true
    execute_claude_api_call(headers, body, app, session, call_depth, websearch_enabled, use_native_websearch, &block)
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      error_message = Monadic::Utils::ErrorFormatter.network_error(
        provider: "Claude",
        message: "Request timed out",
        timeout: true
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      [res]
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[Claude] Unexpected error: #{e.message}\n[Claude] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    error_message = Monadic::Utils::ErrorFormatter.api_error(
      provider: "Claude",
      message: "Unexpected error: #{e.message}"
    )
    res = { "type" => "error", "content" => error_message }
    block&.call res
    [res]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log_json("Processing query (Call depth: #{call_depth})", query)

    # Processing JSON data for app: #{app}, call depth: #{call_depth}

    obj = session[:parameters]
    buffer = String.new
    texts = []
    fragment_sequence = 0  # Sequence number for fragments to ensure ordering
    thinking = []
    redacted_thinking = []
    thinking_signature = nil
    tool_calls = []
    finish_reason = nil
    chunk_count = 0
    # Track usage tokens reported by Anthropic streaming
    usage_input_tokens = nil
    usage_output_tokens = nil
    usage_total_tokens = nil

    content_type = "text"

    res.each do |chunk|
      chunk_count += 1
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      begin
        break if /\Rdata: \[DONE\]\R/ =~ buffer
      rescue StandardError
        next
      end

      # Skip encoding cleanup - buffer.valid_encoding? check above is sufficient
      # Encoding cleanup with replace: "" can delete valid bytes from incomplete multibyte characters
      # that will become complete when the next chunk arrives
      # buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      # buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      # Use multiline mode (m flag) to allow . to match newlines within JSON
      pattern = /data: (\{.*?\})(?=\n|\z)/m
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            Monadic::Utils::ExtraLogger.log_json("Claude stream chunk", json)

            # Handle API errors (including content filtering)
            if json.dig("type") == "error"
              error_type = json.dig("error", "type")
              error_message = json.dig("error", "message")

              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Claude",
                message: "#{error_type}: #{error_message}"
              )

              res = { "type" => "error", "content" => formatted_error }
              block&.call res

              # Return error result immediately
              return [{
                "choices" => [{
                  "finish_reason" => "error",
                  "message" => {
                    "content" => formatted_error
                  }
                }]
              }]
            end

            # Capture usage from message lifecycle events
            if json.dig("type") == "message_start"
              usage = json.dig("message", "usage")
              if usage
                usage_input_tokens = usage["input_tokens"] if usage.key?("input_tokens")
                usage_output_tokens = usage["output_tokens"] if usage.key?("output_tokens")
                usage_total_tokens = (usage_input_tokens.to_i + usage_output_tokens.to_i) if usage_input_tokens && usage_output_tokens
              end
            elsif json.dig("type") == "message_delta"
              usage = json["usage"]
              if usage
                usage_input_tokens = usage["input_tokens"] if usage.key?("input_tokens")
                usage_output_tokens = usage["output_tokens"] if usage.key?("output_tokens")
                usage_total_tokens = (usage_input_tokens.to_i + usage_output_tokens.to_i) if usage_input_tokens && usage_output_tokens

                # Advisor Tool bills sub-inference under usage.iterations[] with
                # type "advisor_message". Top-level usage already excludes advisor
                # tokens (per Anthropic docs), so we only log the breakdown here
                # rather than adjust the aggregate. This keeps token accounting
                # consistent with non-advisor requests while making the cost of
                # advisor calls visible in debug logs.
                iterations = usage["iterations"]
                if iterations.is_a?(Array) && !iterations.empty?
                  advisor_iters  = iterations.select { |it| it.is_a?(Hash) && it["type"] == "advisor_message" }
                  executor_iters = iterations.select { |it| it.is_a?(Hash) && it["type"] == "message" }
                  if advisor_iters.any?
                    advisor_in  = advisor_iters.sum { |it| it["input_tokens"].to_i }
                    advisor_out = advisor_iters.sum { |it| it["output_tokens"].to_i }
                    executor_in  = executor_iters.sum { |it| it["input_tokens"].to_i }
                    executor_out = executor_iters.sum { |it| it["output_tokens"].to_i }
                    Monadic::Utils::ExtraLogger.log {
                      "Claude: usage.iterations breakdown\n" \
                      "  advisor_calls: #{advisor_iters.length}\n" \
                      "  advisor  input: #{advisor_in}, output: #{advisor_out}\n" \
                      "  executor input: #{executor_in}, output: #{executor_out}\n" \
                      "  top-level reflects executor only"
                    }
                  end
                end
              end
            end

            # Skip content_block_stop - it causes excessive line breaks with web search
            # Web search returns multiple content blocks, each triggering this event
            # if json.dig("type") == "content_block_stop"
            #   res = { "type" => "fragment", "content" => "\n\n" }
            #   block&.call res
            # end

            # Handle content type changes
            new_content_type = json.dig("content_block", "type")
            if new_content_type == "tool_use" || new_content_type == "server_tool_use"
              # Prevent duplicate tool_use registration from repeated content_block_start events
              tool_use_id = json["content_block"]["id"]
              unless tool_calls.any? { |tc| tc["id"] == tool_use_id }
                json["content_block"]["input"] = ""
                tool_calls << json["content_block"]

                Monadic::Utils::ExtraLogger.log { "Claude: #{new_content_type} registered\n  id: #{json["content_block"]["id"]}\n  name: #{json["content_block"]["name"]}" }
              else
                Monadic::Utils::ExtraLogger.log { "Claude: Skipping duplicate #{new_content_type}\n  id: #{tool_use_id}" }
              end

              # Check for file_id in Skills output
              if json["content_block"]["output"] && json["content_block"]["output"]["file_id"]
                tool_calls.last["file_id"] = json["content_block"]["output"]["file_id"]
              end
            elsif new_content_type == "advisor_tool_result"
              # Advisor Tool (advisor_20260301) server-side sub-inference result.
              # Arrives fully formed in a single content_block_start event (no deltas).
              # We surface the advice to the UI so users can see the planner's output,
              # and we intentionally do NOT append to tool_calls — the advisor is a
              # server-executed tool whose invocation is tracked by the paired
              # server_tool_use block.
              advisor_content = json.dig("content_block", "content")
              advisor_result_type = advisor_content.is_a?(Hash) ? advisor_content["type"] : nil
              tool_use_id = json.dig("content_block", "tool_use_id")

              if advisor_result_type == "advisor_result"
                advice_text = advisor_content["text"].to_s
                Monadic::Utils::ExtraLogger.log { "Claude: advisor_tool_result received\n  tool_use_id: #{tool_use_id}\n  length: #{advice_text.length} chars" }
                if advice_text.length > 0
                  block&.call({ "type" => "wait", "content" => "<i class='fas fa-user-tie'></i> ADVISOR CONSULTED" })
                end
              elsif advisor_result_type == "advisor_redacted_result"
                Monadic::Utils::ExtraLogger.log { "Claude: advisor_tool_result (redacted) received\n  tool_use_id: #{tool_use_id}" }
                block&.call({ "type" => "wait", "content" => "<i class='fas fa-user-tie'></i> ADVISOR CONSULTED" })
              elsif advisor_result_type == "advisor_tool_result_error"
                error_code = advisor_content["error_code"]
                Monadic::Utils::ExtraLogger.log { "Claude: advisor_tool_result error\n  code: #{error_code}\n  tool_use_id: #{tool_use_id}" }
              end
            elsif new_content_type == "bash_code_execution_tool_result" || new_content_type == "text_editor_code_execution_tool_result"
              # Handle Skills tool results (file_id can be in different locations depending on the tool type)
              tool_use_id = json.dig("content_block", "tool_use_id")

              # Try different paths for file_id based on the tool result type
              file_id = nil
              if new_content_type == "bash_code_execution_tool_result"
                content_array = json.dig("content_block", "content", "content")
                if content_array.is_a?(Array)
                  content_array.each do |item|
                    if item["type"] == "bash_code_execution_output" && item["file_id"]
                      file_id = item["file_id"]
                      break
                    end
                  end
                end
              elsif new_content_type == "text_editor_code_execution_tool_result"
                # text_editor result may have file_id in content.file_ids array
                file_ids = json.dig("content_block", "content", "file_ids")
                file_id = file_ids.first if file_ids.is_a?(Array) && !file_ids.empty?
              end

              Monadic::Utils::ExtraLogger.log { "Claude: #{new_content_type} received\n  tool_use_id: #{tool_use_id}\n  file_id found: #{file_id.inspect}" }

              if file_id
                # Find the matching tool call by tool_use_id
                matching_tool = tool_calls.find { |tc| tc["id"] == tool_use_id }
                if matching_tool
                  matching_tool["file_id"] = file_id

                  Monadic::Utils::ExtraLogger.log { "Claude: file_id extracted and attached\n  file_id: #{file_id}\n  tool_use_id: #{tool_use_id}\n  tool_name: #{matching_tool["name"]}" }
                else
                  Monadic::Utils::ExtraLogger.log { "Claude: WARNING - No matching tool call found for tool_use_id: #{tool_use_id}" }
                end
              end
            end
            content_type = new_content_type if new_content_type

            if content_type == "tool_use"
              if json.dig("delta", "partial_json")

                fragment = json.dig("delta", "partial_json").to_s

                tool_calls.last["input"] << fragment
                
                # Debug logging for tool input accumulation
                Monadic::Utils::ExtraLogger.log { "[Tool Input Fragment] Length: #{fragment.length}, Content: #{fragment[0..100].inspect}\n[Tool Input Total] Length: #{tool_calls.last["input"].length}" }
              end
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "tool_use"
                  finish_reason = "tool_use"
                  res1 = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res1
                when "pause_turn"
                  finish_reason = "pause_turn"
                when "refusal"
                  finish_reason = "refusal"
                when "stop_sequence"
                  finish_reason = "stop_sequence"
                when "model_context_window_exceeded"
                  finish_reason = "model_context_window_exceeded"
                end
              end
            else
              # Handle text content
              if json.dig("delta", "text")
                fragment = json.dig("delta", "text").to_s
                
                if fragment.length > 0
                  texts << fragment

                  res = {
                    "type" => "fragment",
                    "content" => fragment,
                    "sequence" => fragment_sequence,
                    "timestamp" => Time.now.to_f,
                    "is_first" => fragment_sequence == 0
                  }
                  fragment_sequence += 1
                  block&.call res
                end
              elsif json.dig("delta", "thinking")
                fragment = json.dig("delta", "thinking").to_s
                thinking << fragment

                res = {
                  "type" => "thinking",
                  "content" => fragment
                }
                block&.call res
              elsif json.dig("delta", "signature")
                fragment = json.dig("delta", "signature").to_s
                thinking_signature = fragment
              elsif json.dig("delta", "redacted_thinking")
                fragment = json.dig("delta", "redacted_thinking").to_s
                redacted_thinking << fragment
              end

              # Handle stop reasons
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "max_tokens"
                  finish_reason = "length"
                when "end_turn"
                  finish_reason = "stop"
                when "pause_turn"
                  finish_reason = "pause_turn"
                when "refusal"
                  finish_reason = "refusal"
                when "stop_sequence"
                  finish_reason = "stop_sequence"
                when "model_context_window_exceeded"
                  finish_reason = "model_context_window_exceeded"
                end
              end
            end
          rescue JSON::ParserError
            # if the JSON parsing fails, the next chunk should be appended to the buffer
            # and the loop should continue to the next iteration
          end
        else
          buffer = scanner.rest
          break
        end
      end
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Claude Streaming] Error: #{e.message}\n[Claude Streaming] Backtrace: #{e.backtrace.first(5).join("\n")}" }
    end

    thinking_result = if thinking.empty?
                        nil
                      else
                        thinking.join("")
                      end

    redacted_thinking_result = if redacted_thinking.empty?
                                 nil
                               else
                                 redacted_thinking.join("")
                               end

    @thinking = @thinking.to_s + thinking_result if thinking_result
    @signature = thinking_signature if thinking_signature

    text_result = if texts.empty?
               nil
             else
               texts.join("")
             end

    # Process tool calls if any exist
    if tool_calls.any? && session[:call_depth_per_turn] <= MAX_FUNC_CALLS
      # Preserve pre-tool text so it can be prepended to the final response.
      # Without this, streamed text from Round 1 (e.g. mathematical explanation)
      # is lost when Round 2 (post-tool) replaces the temp-card content.
      pre_tool_text = text_result

      result = assemble_claude_tool_context(app, session, tool_calls, text_result, thinking_result,
                                             thinking_signature, redacted_thinking_result, &block)
      if result && !result.empty? && pre_tool_text && !pre_tool_text.strip.empty?
        # Prepend Round 1 text to the final result content
        if result.is_a?(Array) && result.first.is_a?(Hash)
          msg = result.first.dig("choices", 0, "message") || result.first["message"]
          if msg && msg["content"]
            msg["content"] = pre_tool_text + "\n\n" + msg["content"]
          end
        end
      end
      return result unless result.nil? || result.empty?
    end

    if text_result || tool_calls.any?
      if session[:call_depth_per_turn] > MAX_FUNC_CALLS && tool_calls.any?
        res = { "type" => "fragment", "content" => "NOTICE: Maximum function call depth exceeded" }
        block&.call res

        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
        return [{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }]
      end

      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res

      result = [{
        "choices" => [{
          "finish_reason" => finish_reason,
          "message" => { "thinking" => @thinking, "content" => text_result }
        }]
      }]

      if usage_input_tokens || usage_output_tokens
        result[0]["usage"] = {
          "input_tokens" => usage_input_tokens,
          "output_tokens" => usage_output_tokens,
          "total_tokens" => usage_total_tokens
        }.compact
      end
      result
    else
      # Check for JupyterNotebook app fallback handling
      jupyter_result = handle_claude_jupyter_fallback(obj, session, &block)
      return jupyter_result if jupyter_result

      # Claude returned end_turn with no content after tool processing
      tts_text = session[:tts_text]
      response_content = ""

      if tts_text && !tts_text.to_s.strip.empty?
        response_content = tts_text.to_s
        res = { "type" => "fragment", "content" => response_content }
        block&.call res
      end

      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => finish_reason || "stop", "message" => { "content" => response_content } }] }]
    end
  end

  # Assemble tool call context from streaming results, parse inputs, and invoke process_functions.
  # Returns result Array if tools were processed, nil/empty to continue.
  private def assemble_claude_tool_context(app, session, tool_calls, text_result, thinking_result,
                                            thinking_signature, redacted_thinking_result, &block)
    session[:call_depth_per_turn] += 1

    # Multi-turn tool sequences within a single user request accumulate here.
    # We start from the previous turn's function_returns (if any) so that each
    # new tool turn extends the full history rather than replacing it.
    # Without this, the model sees only the latest turn's tool_use in the
    # next request and may hallucinate that earlier work never happened.
    previous_returns = session[:parameters] && session[:parameters]["function_returns"]
    context = previous_returns.is_a?(Array) ? previous_returns.dup : []
    context << { "role" => "assistant", "content" => [] }

    if thinking_result || @thinking.to_s != ""
      thinking = thinking_result || @thinking.to_s
      signature = thinking_signature || @signature
      context.last["content"] << {
        "type" => "thinking",
        "thinking" => thinking,
        "signature" => signature
      }
    end

    if redacted_thinking_result
      context.last["content"] << { "type" => "redacted_thinking", "data" => redacted_thinking_result }
    end

    if text_result
      context.last["content"] << { "type" => "text", "text" => text_result }
    end

    # Parse tool call inputs and add to context
    tool_calls.each do |tool_call|
      begin
        if tool_call["input"].to_s.strip.empty?
          input_hash = {}
        else
          input_hash = JSON.parse(tool_call["input"])
        end
      rescue JSON::ParserError => e
        Monadic::Utils::ExtraLogger.log { "[Claude Tool Call JSON Parse Error]\nTool: #{tool_call["name"]}\nRaw input length: #{tool_call["input"].to_s.length}\nRaw input (first 500 chars): #{tool_call["input"].to_s[0..500].inspect}\nRaw input (last 100 chars): #{tool_call["input"].to_s[-100..-1].inspect}\nError: #{e.message}" }

        if tool_call["name"] == "run_script"
          input_hash = JSONRepair.extract_run_script_params(tool_call["input"])
          Monadic::Utils::ExtraLogger.log { "Attempted JSON repair for run_script\nExtracted params: #{input_hash.inspect}\n#{'-' * 50}" }
        elsif tool_call["name"] == "run_code"
          input_hash = JSONRepair.extract_run_code_params(tool_call["input"])
          Monadic::Utils::ExtraLogger.log { "Attempted JSON repair for run_code\nExtracted params: #{input_hash.inspect}\n#{'-' * 50}" }
        else
          input_hash = JSONRepair.attempt_repair(tool_call["input"])
        end

        input_hash = {} if input_hash["_json_repair_failed"]
      end

      tool_call["input"] = input_hash

      next if tool_call["type"] == "server_tool_use"

      context.last["content"] << {
        "type" => "tool_use",
        "id" => tool_call["id"],
        "name" => tool_call["name"],
        "input" => tool_call["input"]
      }
    end

    process_functions(app, session, tool_calls, context, session[:call_depth_per_turn], &block)
  end

  # Handle JupyterNotebook app fallback when Claude returns empty response.
  # Returns result Array if fallback was triggered, nil otherwise.
  # Handle server_tool_use tool calls (executed by Anthropic, not by us).
  # Downloads any associated file_id and notifies the user.
  # Returns true if the tool was a server_tool_use (caller should skip to next).
  private def handle_claude_server_tool(tool_call, tool_name, &block)
    return false unless tool_call["type"] == "server_tool_use"

    Monadic::Utils::ExtraLogger.log { "\n=== Skipping Server Tool (executed by Anthropic) ===\nTool name: #{tool_name}\nTool ID: #{tool_call["id"]}\nHas file_id: #{!tool_call["file_id"].nil?}" }

    # Check if this server tool resulted in a file generation
    if tool_call["file_id"]
      file_id = tool_call["file_id"]
      file_result = download_file_from_api(file_id)

      if file_result
        save_result = save_to_documents(file_result[:data], file_result[:filename])

        Monadic::Utils::ExtraLogger.log { "File downloaded and saved successfully\n  Path: #{save_result[:relative]}\n  Size: #{save_result[:size]} bytes" }

        # Notify user about the file
        block&.call({
          "type" => "fragment",
          "content" => "\n\n✅ **File saved:** `#{save_result[:relative]}` (#{(save_result[:size] / 1024.0).round(2)} KB)\n\n"
        })
      else
        Monadic::Utils::ExtraLogger.log { "ERROR: Failed to download file from API\n  file_id: #{file_id}" }
      end
    end

    true
  end

  # Invoke a single tool function: parse arguments, call the method, handle errors,
  # and build the tool_result entry (including _image injection and gallery_html).
  # Returns [tool_result_entry, error_stop] tuple.
  private def invoke_claude_tool_function(app, session, tool_call, tool_name, &block)
    begin
      argument_hash = tool_call["input"]
    rescue StandardError
      argument_hash = {}
    end

    # Debug logging
    Monadic::Utils::ExtraLogger.log { "\n=== Processing Function Call ===\nTool name: #{tool_name}\nRaw input: #{tool_call["input"].inspect}\nArgument hash before conversion: #{argument_hash.inspect}" }

    argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
      memo[k.to_sym] = v
      memo
    end

    Monadic::Utils::ExtraLogger.log { "Argument hash after conversion: #{argument_hash.inspect}\nApp instance class: #{APPS[app].class}\nMethod exists?: #{APPS[app].respond_to?(tool_name.to_sym)}" }

    app_instance = APPS[app]

    # Inject session for tools that need it (e.g., monadic state tools)
    method_obj = app_instance.method(tool_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |type, name| name == :session }
      argument_hash[:session] = session
    end

    begin
      if argument_hash.empty?
        tool_return = app_instance.send(tool_name.to_sym)
      else
        tool_return = app_instance.send(tool_name.to_sym, **argument_hash)
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG Tools] #{tool_name} returned: #{tool_return.to_s[0..500]}" }

      send_verification_notification(session, &block) if tool_name == "report_verification"

      Monadic::Utils::TtsTextExtractor.extract_tts_text(
        app: app,
        function_name: tool_name,
        argument_hash: argument_hash,
        session: session
      )
    rescue => e
      Monadic::Utils::ExtraLogger.log { "ERROR calling function: #{e.class} - #{e.message}\nBacktrace: #{e.backtrace.first(5).join("\n")}" }
      tool_return = Monadic::Utils::ErrorFormatter.tool_error(
        provider: "Claude",
        tool_name: tool_name,
        message: e.message
      )
    end

    unless tool_return
      tool_return = "Empty result"
    end

    # Check for repeated errors (same pattern as OpenAI helper)
    if handle_function_error(session, tool_return, tool_name, &block)
      # Return [entry, true] to signal error stop to orchestrator
      entry = {
        type: "tool_result",
        tool_use_id: tool_call["id"],
        content: tool_return.is_a?(Hash) || tool_return.is_a?(Array) ? JSON.generate(tool_return) : tool_return.to_s
      }
      return [entry, true]
    end

    # Check if this tool call resulted in a file generation (from Skills)
    if tool_call["file_id"]
      file_id = tool_call["file_id"]
      file_result = download_file_from_api(file_id)

      if file_result
        save_result = save_to_documents(file_result[:data], file_result[:filename])
        tool_return = tool_return.to_s + "\n\n✅ File saved to #{save_result[:relative]} (#{save_result[:size]} bytes)"
      else
        tool_return = tool_return.to_s + "\n\n⚠️ Error downloading file from Skills API"
      end
    end

    Monadic::Utils::ExtraLogger.log { "Tool return: #{tool_return.to_s[0..200]}..." }

    tool_result_entry = {
      type: "tool_result",
      tool_use_id: tool_call["id"]
    }

    # Check for _image key in tool return for direct image injection
    # Supports both single filename (String) and multiple filenames (Array) for tiled screenshots
    # Dedup: skip images already injected in this turn to prevent verify→regenerate loops
    if tool_return.is_a?(Hash) && tool_return[:_image]
      clean_return = tool_return.reject { |k, _| k.to_s.start_with?("_") }
      result_content = [
        { type: "text", text: JSON.generate(clean_return) }
      ]
      injected_set = session[:images_injected_this_turn] ||= Set.new
      Array(tool_return[:_image]).each do |img_filename|
        next if injected_set.include?(img_filename)

        image_block = build_tool_image_block(img_filename)
        if image_block
          result_content << image_block
          injected_set << img_filename
        end
      end
      tool_result_entry[:content] = result_content
    else
      tool_result_entry[:content] = tool_return.is_a?(Hash) || tool_return.is_a?(Array) ? JSON.generate(tool_return) : tool_return.to_s
    end

    # Store gallery_html for server-side injection (bypasses LLM text reproduction)
    if tool_return.is_a?(Hash) && tool_return[:gallery_html]
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << tool_return[:gallery_html]
    end

    [tool_result_entry, false]
  end

  private def handle_claude_jupyter_fallback(obj, session, &block)
    app_name = obj["app_name"].to_s
    return nil unless app_name.include?("JupyterNotebook") && app_name.include?("Claude")

    tool_results = session[:parameters]["tool_results"] || []
    has_successful_jupyter_result = tool_results.any? do |r|
      content = r.dig("functionResponse", "response", "content")
      content.is_a?(String) && !content.include?("ERRORS DETECTED") && (
        content.include?("executed successfully") ||
        content.include?("Notebook") && content.include?("created successfully") ||
        content.include?("Cells added to notebook")
      )
    end

    if has_successful_jupyter_result
      notebook_info = tool_results.find do |r|
        content = r.dig("functionResponse", "response", "content")
        content.is_a?(String) && content.include?(".ipynb")
      end
      notebook_content = notebook_info&.dig("functionResponse", "response", "content") || ""

      success_msg = "Notebook created and executed successfully."
      if notebook_content =~ /(http:\/\/[^\s]+\.ipynb)/
        link = $1
        filename = link.split("/").last
        success_msg += "\n\nAccess it at: <a href='#{link}' target='_blank'>#{filename}</a>"
      end

      block&.call({ "type" => "fragment", "content" => success_msg })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => success_msg } }] }]
    end

    notebook_error_result = tool_results.find do |r|
      content = r.dig("functionResponse", "response", "content")
      content.is_a?(String) && content.include?("ERRORS DETECTED")
    end

    if notebook_error_result
      error_content = notebook_error_result.dig("functionResponse", "response", "content")
      if error_content =~ /⚠️\s*ERRORS DETECTED.*?(?=\n\nAccess the notebook|$)/m
        error_summary = $&
      else
        error_summary = "Notebook execution errors occurred."
      end
      error_msg = "Errors occurred during notebook execution.\n\n#{error_summary}"
      block&.call({ "type" => "fragment", "content" => error_msg })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => error_msg } }] }]
    end

    nil
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]

    # Log tool calls for debugging
    Monadic::Utils::ExtraLogger.log {
      msg = "[DEBUG Tools] Processing #{tools.length} tool calls:"
      tools.each { |tc| msg += "\n  - #{tc['name']} with input: #{tc['input'].to_s[0..200]}" }
      msg
    }

    tools.each do |tool_call|
      tool_name = tool_call["name"]
      record_tool_call(session, tool_name)
      block&.call({ "type" => "tool_executing", "content" => tool_name })

      # Skip server_tool_use (executed by Anthropic, not by us)
      next if handle_claude_server_tool(tool_call, tool_name, &block)

      # Invoke the tool function and build the result entry
      # Returns [tool_result_entry, error_stop]
      tool_result_entry, error_stop = invoke_claude_tool_function(app, session, tool_call, tool_name, &block)
      if tool_result_entry
        content << tool_result_entry
        next if error_stop # stop_retrying flag is set
      end
    end

    # Only add tool results message if there are actual results to send
    if content.any?
      context << { role: "user", content: content }
      obj["function_returns"] = context

      # Stop if repeated errors detected (set by handle_function_error above)
      if should_stop_for_errors?(session)
        res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
        block&.call res
        return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected. Stopping." } }] }]
      end

      api_request("tool", session, call_depth: call_depth, &block)
    else
      # All tools were server_tool_use, no need to send tool results
      Monadic::Utils::ExtraLogger.log { "All tools were server_tool_use, no tool_result needed" }
      []
    end
  end


  # Build a Claude image block from a screenshot filename for tool result injection.
  # Delegates to shared ToolImageUtils for file reading and base64 encoding.
  def build_tool_image_block(filename)
    img = Monadic::Utils::ToolImageUtils.encode_image_for_api(filename)
    return nil unless img

    {
      type: "image",
      source: {
        type: "base64",
        media_type: img[:media_type],
        data: img[:base64_data]
      }
    }
  end

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

  # Download file from Anthropic Files API (for Skills)
  def download_file_from_api(file_id)
    api_key = CONFIG["ANTHROPIC_API_KEY"]
    return nil unless api_key

    headers = {
      "x-api-key" => api_key,
      "anthropic-version" => "2023-06-01",
      "anthropic-beta" => "files-api-2025-04-14"
    }

    target_uri = "#{API_ENDPOINT}/files/#{file_id}/content"
    http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)
      if res.status.success?
        # Log headers for debugging
        Monadic::Utils::ExtraLogger.log { "Files API response headers:\n  Content-Disposition: #{res.headers["Content-Disposition"].inspect}\n  Content-Type: #{res.headers["Content-Type"].inspect}" }

        # Extract filename from Content-Disposition header
        filename = extract_filename_from_header(res.headers["Content-Disposition"], res.headers["Content-Type"])
        # Read body as string (HTTP::Response::Body needs to be converted)
        file_data = res.body.to_s
        { data: file_data, filename: filename }
      else
        nil
      end
    rescue => e
      Monadic::Utils::ExtraLogger.log { "ERROR downloading file: #{e.message}" }
      nil
    end
  end

  # Extract filename from Content-Disposition header
  def extract_filename_from_header(content_disposition, content_type = nil)
    # Try to extract from Content-Disposition header
    if content_disposition
      # First try RFC 5987 format: filename*=UTF-8''encoded-filename
      if content_disposition =~ /filename\*=([^']+)'([^']*)'(.+)/
        charset = $1
        # language = $2  # Not used but part of the format
        encoded_filename = $3

        # URL decode the filename
        require 'uri'
        filename = URI.decode_www_form_component(encoded_filename)

        Monadic::Utils::ExtraLogger.log { "Decoded filename from RFC 5987:\n  Charset: #{charset}\n  Encoded: #{encoded_filename}\n  Decoded: #{filename}" }

        return filename
      end

      # Fallback to standard filename parameter
      match = content_disposition.match(/filename=(?:"([^"]+)"|([^;\s]+))/)
      return match[1] || match[2] if match
    end

    # Generate default filename with extension based on Content-Type
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    extension = get_extension_from_content_type(content_type)
    "document_#{timestamp}#{extension}"
  end

  # Get file extension from Content-Type header
  def get_extension_from_content_type(content_type)
    return "" unless content_type

    case content_type
    when /application\/vnd\.openxmlformats-officedocument\.wordprocessingml\.document/
      ".docx"
    when /application\/vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet/
      ".xlsx"
    when /application\/vnd\.openxmlformats-officedocument\.presentationml\.presentation/
      ".pptx"
    when /application\/pdf/
      ".pdf"
    when /text\/plain/
      ".txt"
    when /application\/json/
      ".json"
    else
      ""
    end
  end

  # Save file to documents directory
  def save_to_documents(file_data, filename)
    # Use the correct base path depending on environment
    base_path = if Monadic::Utils::Environment.in_container?
                  MonadicApp::SHARED_VOL
                else
                  MonadicApp::LOCAL_SHARED_VOL
                end

    docs_dir = File.join(base_path, "documents")
    FileUtils.mkdir_p(docs_dir) unless File.directory?(docs_dir)

    file_path = File.join(docs_dir, filename)
    File.binwrite(file_path, file_data)

    # Create platform-independent relative path display
    home_display = if RUBY_PLATFORM =~ /mingw|mswin|cygwin/
                     # Windows: use %USERPROFILE% or actual username
                     ENV['USERPROFILE'] ? File.basename(ENV['USERPROFILE']) : Dir.home
                   else
                     # Unix-like: use ~
                     "~"
                   end

    relative_path = File.join(home_display, "monadic", "data", "documents", filename)

    {
      path: file_path,
      relative: relative_path,
      size: file_data.bytesize
    }
  end

  # Ensure send_query is publicly callable by external agents (e.g., AIUserAgent)
  public :send_query
end
