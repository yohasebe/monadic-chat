# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'timeout'
require 'net/http'
require 'base64'

module ProviderMatrixHelper
  PROVIDER_TIMEOUTS = {
    'openai' => 45,
    'anthropic' => 60,
    'gemini' => 60,
    'mistral' => 60,
    'cohere' => 90,
    'perplexity' => 90,
    'deepseek' => 75,
    'xai' => 75,
    'ollama' => 90
  }.freeze

  PROVIDER_QPS = {
    'openai' => 0.5,
    'anthropic' => 0.5,
    'gemini' => 0.4,
    'mistral' => 0.4,
    'cohere' => 0.3,
    'perplexity' => 0.3,
    'deepseek' => 0.35,
    'xai' => 0.35,
    'ollama' => 1.0
  }.freeze

  PROVIDER_MAX_RETRIES = {
    'openai' => 3,
    'anthropic' => 3,
    'gemini' => 3,
    'mistral' => 3,
    'cohere' => 4,
    'perplexity' => 4,
    'deepseek' => 4,
    'xai' => 3,
    'ollama' => 2
  }.freeze

  PROVIDER_RETRY_BASE = {
    'openai' => 0.6,
    'anthropic' => 0.6,
    'gemini' => 0.6,
    'mistral' => 0.6,
    'cohere' => 1.0,
    'perplexity' => 1.0,
    'deepseek' => 0.7,
    'xai' => 0.7,
    'ollama' => 0.5
  }.freeze

  def require_run_api!
    skip('RUN_API is not enabled') unless ENV['RUN_API'] == 'true'
  end

  def require_run_media!
    require_run_api!
    skip('RUN_MEDIA is not enabled') unless ENV['RUN_MEDIA'] == 'true'
  end

  def providers_from_env
    list = (ENV['PROVIDERS'] || '').split(',').map(&:strip).reject(&:empty?)
    return list unless list.empty?
    # Default providers (Ollama is opt-in due to local dependency)
    defaults = %w[openai anthropic gemini mistral cohere perplexity deepseek xai]
    defaults << 'ollama' if ENV['INCLUDE_OLLAMA'] == 'true'
    defaults
  end

  def with_provider(name)
    name = name.to_s
    unless api_key_available?(name)
      skip("API key missing for provider: #{name}")
    end
    yield ProviderClient.new(name)
  end

  def api_key_available?(provider)
    key_map = {
      'openai' => 'OPENAI_API_KEY',
      'anthropic' => 'ANTHROPIC_API_KEY',
      'gemini' => 'GEMINI_API_KEY',
      'mistral' => 'MISTRAL_API_KEY',
      'cohere' => 'COHERE_API_KEY',
      'perplexity' => 'PERPLEXITY_API_KEY',
      'deepseek' => 'DEEPSEEK_API_KEY',
      'xai' => 'XAI_API_KEY',
      'ollama' => 'OLLAMA_HOST'
    }
    env_key = key_map[provider]
    return false unless env_key
    val = ENV[env_key]
    val && !val.empty?
  end

  class ProviderClient
    def initialize(provider)
      @provider = provider.to_s
      @timeout = fetch_provider_setting('API_TIMEOUT', PROVIDER_TIMEOUTS, 45, cast: :to_f)
      # Simple rate limiting (QPS)
      qps = fetch_provider_setting('API_RATE_QPS', PROVIDER_QPS, 1.0, cast: :to_f)
      @min_interval = qps > 0 ? 1.0 / qps : 0.0
      @last_request_at = 0.0
      # Retry configs
      @max_retries = fetch_provider_setting('API_MAX_RETRIES', PROVIDER_MAX_RETRIES, 3, cast: :to_i)
      @retry_base = fetch_provider_setting('API_RETRY_BASE', PROVIDER_RETRY_BASE, 0.5, cast: :to_f)
    end

    # Thin wrappers over vendor helpers
    # Options:
    #   max_turns: Maximum conversation turns (default: 1). If > 1, will follow up
    #              when the AI asks clarifying questions instead of answering directly.
    def chat(prompt, **opts)
      max_turns = opts.delete(:max_turns) || 1

      # Apps that require database/embedding operations need longer timeouts
      timeout = if ['Vector Search', 'PDF Navigator', 'User Docs'].include?(opts[:app])
                  @timeout * 2  # Double timeout for vector/database apps
                else
                  @timeout
                end

      Timeout.timeout(timeout * max_turns) do
        helper = helper_for(@provider)

        # Get app's system prompt and tools if app is specified and available
        app_system_prompt = nil
        app_tools = nil
        if opts[:app] && defined?(APPS) && APPS.is_a?(Hash) && APPS[opts[:app]]
          app = APPS[opts[:app]]
          app_system_prompt = app.settings['initial_prompt'] || app.settings[:initial_prompt]
          # Extract tool definitions for providers that support them
          raw_tools = app.settings['tools'] || app.settings[:tools]
          app_tools = extract_tool_definitions(raw_tools)
        end

        # Build initial messages
        messages = build_messages_for_provider(prompt, app_system_prompt)

        current_turn = 0
        last_response = nil

        while current_turn < max_turns
          current_turn += 1
          options = build_options_from_messages(messages, app_system_prompt)

          # Add tool definitions for providers that support tool calling
          if app_tools && app_tools.any? && %w[openai anthropic gemini xai grok mistral cohere deepseek perplexity].include?(@provider)
            # Deduplicate tools by name
            unique_tools = app_tools.uniq { |t| t['name'] || t[:name] }
            options[:tools] = unique_tools
            if ENV['DEBUG']
              tool_names = unique_tools.map { |t| t['name'] || t[:name] }.join(', ')
              puts "  [tools] Passing #{unique_tools.length} tool(s) to #{@provider}: #{tool_names}"
            end
          end

          throttle!
          log_request(kind: 'chat', app: opts[:app], prompt: (prompt if prompt && !prompt.empty?), messages: options[:messages])
          res = request_with_retry { helper.send_query(options) }
          # Normalize to hash with :text
          res = res.is_a?(String) ? { text: res } : res
          log_response(res)
          last_response = res

          # If response contains tool calls, return immediately
          # Tool calls are valid responses that should be evaluated by the test
          if res[:tool_calls] && res[:tool_calls].any?
            puts "  [tool_call] Turn #{current_turn}: Model made #{res[:tool_calls].length} tool call(s)" if ENV['DEBUG']
            break
          end

          # If we've reached max turns or there's an error, stop
          break if current_turn >= max_turns
          break if res[:text].nil? || res[:text].empty?
          break if res[:text].to_s.include?('API Error')

          # Check if the response is asking for clarification
          if needs_followup?(res[:text])
            # Add assistant response and user followup to messages
            # IMPORTANT: Use string keys to match provider helpers
            followup = followup_message
            puts "  [followup] Turn #{current_turn}: AI asked for details, responding with: #{followup[0..50]}..." if ENV['DEBUG']
            messages << { "role" => "assistant", "content" => res[:text] }
            messages << { "role" => "user", "content" => followup }
          else
            # Got a substantive response, we're done
            puts "  [followup] Turn #{current_turn}: Got substantive response (#{res[:text].to_s.length} chars)" if ENV['DEBUG']
            break
          end
        end

        last_response
      end
    end

    # Extract tool definitions from app settings in a format suitable for the provider
    def extract_tool_definitions(raw_tools)
      return [] unless raw_tools

      # Handle Gemini format with function_declarations
      if raw_tools.is_a?(Hash) && raw_tools['function_declarations']
        return raw_tools['function_declarations']
      end

      # Handle array of tool definitions
      if raw_tools.is_a?(Array)
        return raw_tools.map do |tool|
          if tool.is_a?(Hash)
            # Handle OpenAI/Grok format: { type: "function", function: { name: "...", ... } }
            if tool['function'] || tool[:function]
              func = tool['function'] || tool[:function]
              {
                'name' => func['name'] || func[:name],
                'description' => func['description'] || func[:description] || '',
                'parameters' => func['parameters'] || func[:parameters] || { 'type' => 'object', 'properties' => {} }
              }
            else
              # Simple format: { name: "...", description: "...", parameters: {...} }
              {
                'name' => tool['name'] || tool[:name],
                'description' => tool['description'] || tool[:description] || '',
                'parameters' => tool['parameters'] || tool[:parameters] || { 'type' => 'object', 'properties' => {} }
              }
            end
          else
            nil
          end
        end.compact
      end

      []
    end

    # Check if the response is asking for clarification/details
    def needs_followup?(response_text)
      return false if response_text.nil? || response_text.empty?

      # Patterns that indicate the AI is asking for more information
      clarification_patterns = [
        /what.*would you like/i,
        /could you.*provide/i,
        /could you.*tell me/i,
        /can you.*specify/i,
        /please.*provide/i,
        /please.*tell me/i,
        /what.*prefer/i,
        /do you.*want/i,
        /would you.*like me to/i,
        /let me know/i,
        /more details/i,
        /more information/i,
        /clarify/i,
        /specify/i,
        /which.*option/i,
        /何か.*ありますか/,
        /教えて.*ください/,
        /お知らせください/,
        /ご希望/,
        /詳細.*教えて/
      ]

      # Check if response is short AND matches clarification patterns
      # (Long responses with these phrases might still be substantive)
      is_short = response_text.length < 500
      has_clarification = clarification_patterns.any? { |p| response_text.match?(p) }

      is_short && has_clarification
    end

    # Message to send when following up on a clarification request
    def followup_message
      [
        "おまかせでお願いします。適当に決めてください。",
        "Please proceed with your best judgment. Use reasonable defaults.",
        "Go ahead with whatever you think is best."
      ].sample
    end

    # Build initial messages array for the conversation
    # IMPORTANT: Use string keys ("role", "content") to match provider helpers
    def build_messages_for_provider(prompt, system_prompt)
      preface = system_prompt || "Respond directly and concisely to the user's request."

      case @provider
      when 'anthropic'
        # For Anthropic, system is separate - just return user messages
        [{ "role" => "user", "content" => prompt }]
      else
        # For other providers, include system message
        [
          { "role" => "system", "content" => preface },
          { "role" => "user", "content" => prompt }
        ]
      end
    end

    # Build options from messages array
    # Note: messages array uses string keys ("role", "content")
    def build_options_from_messages(messages, system_prompt)
      preface = system_prompt || "Respond directly and concisely to the user's request."
      opts = {}

      case @provider
      when 'anthropic'
        opts[:system] = preface
        opts[:messages] = messages
      when 'cohere'
        opts[:preamble] = preface
        # Remove system messages for Cohere (use string key to match message format)
        opts[:messages] = messages.reject { |m| m["role"] == "system" }
      when 'gemini'
        opts[:messages] = messages
        # Pass tool definitions if available - allows testing tool-calling behavior
      else
        opts[:messages] = messages
      end

      # Apply temperature if set
      if ENV.key?('API_TEMPERATURE') && !ENV['API_TEMPERATURE'].to_s.strip.empty?
        opts[:temperature] = ENV['API_TEMPERATURE'].to_f
      end

      opts
    end

    def chat_messages(messages, **opts)
      chat('', **opts.merge(messages: messages))
    end

    # Get initial assistant message for apps with initiate_from_assistant: true
    # These apps should generate an introduction without a real user prompt.
    # This mirrors actual app behavior: system prompt only, no user message.
    # Each provider helper automatically adds a minimal trigger message as needed.
    # @param app [String] The app name
    # @param timeout [Integer] Request timeout
    # @return [Hash] Response hash with :text and optionally :tool_calls
    def initial_message(app:, timeout: nil)
      timeout ||= @timeout

      Timeout.timeout(timeout) do
        helper = helper_for(@provider)

        # Get app's system prompt and tools if available
        app_system_prompt = nil
        app_tools = nil
        if defined?(APPS) && APPS.is_a?(Hash) && APPS[app]
          app_obj = APPS[app]
          app_system_prompt = app_obj.settings['initial_prompt'] || app_obj.settings[:initial_prompt]
          raw_tools = app_obj.settings['tools'] || app_obj.settings[:tools]
          app_tools = extract_tool_definitions(raw_tools)
        end

        # Build options with system prompt only (no user message)
        # This mirrors actual initiate_from_assistant behavior
        # Each provider helper will add the appropriate trigger message
        options = {}

        case @provider
        when 'anthropic'
          # Claude: system as separate parameter, needs at least one message
          options[:system] = app_system_prompt || "You are a helpful assistant."
          # Claude API requires at least one message - use a minimal trigger
          options[:messages] = [{ "role" => "user", "content" => "Please introduce yourself and explain what you can help with." }]
          options[:initiate_from_assistant] = true
        when 'cohere'
          # Cohere: preamble, needs at least one message
          options[:preamble] = app_system_prompt || "You are a helpful assistant."
          options[:messages] = [{ "role" => "user", "content" => "Please introduce yourself." }]
          options[:initiate_from_assistant] = true
        when 'gemini'
          # Gemini: system message + user trigger
          options[:messages] = [
            { "role" => "system", "content" => app_system_prompt || "You are a helpful assistant." },
            { "role" => "user", "content" => "Please introduce yourself." }
          ]
          options[:initiate_from_assistant] = true
        else
          # Other providers: system message + user trigger
          # Most APIs require at least one user message
          options[:messages] = [
            { "role" => "system", "content" => app_system_prompt || "You are a helpful assistant." },
            { "role" => "user", "content" => "Please introduce yourself and explain what you can help with." }
          ]
          options[:initiate_from_assistant] = true
        end

        # Add tool definitions if available
        if app_tools && app_tools.any? && %w[openai anthropic gemini xai grok mistral cohere deepseek perplexity].include?(@provider)
          unique_tools = app_tools.uniq { |t| t['name'] || t[:name] }
          options[:tools] = unique_tools
          if ENV['DEBUG']
            tool_names = unique_tools.map { |t| t['name'] || t[:name] }.join(', ')
            puts "  [initial_message] Passing #{unique_tools.length} tool(s) to #{@provider}: #{tool_names}"
          end
        end

        throttle!
        log_request(kind: 'initial_message', app: app, prompt: '(initiate_from_assistant)', messages: options[:messages])
        res = request_with_retry { helper.send_query(options) }
        res = res.is_a?(String) ? { text: res } : res
        log_response(res)
        res
      end
    end

    # Encourage native/assisted web search where provider supports it
    def web_search(query, **opts)
      Timeout.timeout(@timeout) do
        helper = helper_for(@provider)
        options = build_options(prompt: query, websearch: true)
        throttle!
        log_request(kind: 'web_search', app: opts[:app] || 'Web Search', prompt: query)
        res = request_with_retry { helper.send_query(options) }
        res = res.is_a?(String) ? { text: res } : res
        log_response(res)
        res
      end
    end

    # Minimal code interpretation; for OpenAI, tools may be added by helper when applicable
    def code_interpret(prompt, **opts)
      Timeout.timeout(@timeout) do
        helper = helper_for(@provider)
        # Try to hint tool usage for providers that support it via Responses API
        options = { message: prompt }
        # For OpenAI Responses API, helpers map string tool names
        options[:tools] = ['code_interpreter'] if @provider == 'openai'
        throttle!
        log_request(kind: 'code_interpreter', app: opts[:app] || 'Code Interpreter', prompt: prompt)
        res = request_with_retry { helper.send_query(options) }
        res = res.is_a?(String) ? { text: res } : res
        log_response(res)
        res
      end
    end

    # Backward-compatible wrapper that always uses real provider APIs
    def image_generate(prompt, size: '128x128', **_opts)
      image_generate_api(prompt, size: size)
    end

    # Real image generation via provider APIs (OpenAI, Gemini Imagen, xAI)
    def image_generate_api(prompt, size: '256x256')
      Timeout.timeout(@timeout) do
        case @provider
      when 'openai'
        api_key = ENV['OPENAI_API_KEY']
        raise 'OPENAI_API_KEY not set' unless api_key && !api_key.empty?
        uri = URI('https://api.openai.com/v1/images/generations')
        body = { prompt: prompt, size: size }
        res = request_with_retry do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          req = Net::HTTP::Post.new(uri)
          req['Authorization'] = "Bearer #{api_key}"
          req['Content-Type'] = 'application/json'
          req.body = JSON.generate(body)
          throttle!
          log_request(kind: 'image_generate', app: 'Image Generator', prompt: prompt)
          http.request(req)
        end
        raise res unless res.is_a?(Net::HTTPResponse)
        raise "HTTP #{res.code}: #{res.body[0,200]}" unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body) rescue {}
        if data['data'] && data['data'][0]
          if data['data'][0]['b64_json']
            return { bytes: Base64.decode64(data['data'][0]['b64_json']) }
          elsif data['data'][0]['url']
            # For URL responses, just return URL string
            return { url: data['data'][0]['url'] }
          end
        end
        raise 'Unexpected image API response'
      when 'gemini'
        api_key = ENV['GEMINI_API_KEY']
        raise 'GEMINI_API_KEY not set' unless api_key && !api_key.empty?
        # Use Imagen 4 fast model as default in GeminiHelper
        model = 'imagen-4.0-fast-generate-001'
        uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:predict?key=#{api_key}")
        body = {
          instances: [{ prompt: prompt }],
          parameters: { sampleCount: 1, aspectRatio: '1:1', personGeneration: 'ALLOW_ADULT' }
        }
        res = request_with_retry do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          req = Net::HTTP::Post.new(uri)
          req['Content-Type'] = 'application/json'
          req.body = JSON.generate(body)
          throttle!
          log_request(kind: 'image_generate', app: 'Image Generator', prompt: prompt)
          http.request(req)
        end
        raise res unless res.is_a?(Net::HTTPResponse)
        raise "HTTP #{res.code}: #{res.body[0,200]}" unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body) rescue {}
        pred = data['predictions']&.first
        if pred && pred['bytesBase64Encoded']
          return { bytes: Base64.decode64(pred['bytesBase64Encoded']) }
        else
          raise 'Unexpected Imagen response'
        end
      when 'xai', 'grok'
        api_key = ENV['XAI_API_KEY']
        raise 'XAI_API_KEY not set' unless api_key && !api_key.empty?
        uri = URI('https://api.x.ai/v1/images/generations')
        body = { model: 'grok-2-image', prompt: prompt, n: 1, response_format: 'b64_json' }
        res = request_with_retry do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          req = Net::HTTP::Post.new(uri)
          req['Authorization'] = "Bearer #{api_key}"
          req['Content-Type'] = 'application/json'
          req.body = JSON.generate(body)
          throttle!
          log_request(kind: 'image_generate', app: 'Image Generator', prompt: prompt)
          http.request(req)
        end
        raise res unless res.is_a?(Net::HTTPResponse)
        raise "HTTP #{res.code}: #{res.body[0,200]}" unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body) rescue {}
        entry = data['data']&.first
        if entry && entry['b64_json']
          return { bytes: Base64.decode64(entry['b64_json']) }
        elsif entry && entry['url']
          return { url: entry['url'] }
        else
          raise 'Unexpected xAI image response'
        end
      else
        raise NotImplementedError, "image_generate_api not implemented for #{@provider}"
      end
    end
    rescue => e
      "[#{@provider}] API Error: #{e.message}"
    end

    private

    def throttle!
      return if @min_interval <= 0
      now = Time.now.to_f
      elapsed = now - @last_request_at
      if elapsed < @min_interval
        sleep(@min_interval - elapsed)
      end
      @last_request_at = Time.now.to_f
    end

    def retryable_error?(result, error=nil)
      msg = nil
      msg = error.message if error
      msg ||= result if result.is_a?(String)
      return false unless msg
      !!(msg =~ /(429|too\s+many\s+requests|rate\s*limit|temporar|timeout|unavailable|5\d{2})/i)
    end

    def sleep_backoff(attempt)
      # Exponential backoff with jitter
      base = @retry_base > 0 ? @retry_base : 0.5
      delay = base * (2 ** (attempt - 1))
      jitter = delay * (rand * 0.1)
      sleep(delay + jitter)
    end

    def request_with_retry
      attempt = 0
      begin
        attempt += 1
        res = yield
        # Retry on rate-limit/service errors embedded in string results
        if retryable_error?(res)
          raise RuntimeError, res
        end
        return res
      rescue => e
        if attempt < @max_retries && retryable_error?(nil, e)
          sleep_backoff(attempt)
          retry
        else
          # Return formatted error string to keep test surface simple
          return "[#{@provider}] API Error: #{e.message}"
        end
      end
    end

    private

    def fetch_provider_setting(base_key, defaults, fallback, cast:)
      env_specific = ENV["#{base_key}_#{@provider.upcase}"]
      value = env_specific unless env_specific.nil? || env_specific.empty?
      if value.nil? || value.to_s.empty?
        global = ENV[base_key]
        value = global unless global.nil? || global.empty?
      end
      if (value.nil? || value.to_s.empty?) && defaults
        value = defaults[@provider]
      end
      value = fallback if value.nil? || value.to_s.empty?

      case cast
      when :to_i
        value.to_i
      when :to_f
        value.to_f
      else
        value
      end
    end
  
    # Provider-specific option builder
    # IMPORTANT: Use string keys ("role", "content") to match provider helpers
    def build_options(prompt:, messages: nil, websearch: false, system_prompt: nil)
      # Use app's system prompt if provided, otherwise use a simple preface
      preface = system_prompt || "Respond directly and concisely to the user's request."
      opts = {}
      if messages.is_a?(Array)
        opts[:messages] = messages
      else
        case @provider
        when 'anthropic'
          # Claude expects system at top-level, messages without system role
          opts[:system] = preface
          opts[:messages] = [{ "role" => "user", "content" => prompt }]
        when 'gemini'
          # Gemini: use system message (GeminiHelper converts it to user message internally)
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
          # Conditionally set reasoning_effort only if requested via env
          requested_reasoning = (ENV['GEMINI_REASONING'] || ENV['REASONING_EFFORT']).to_s.strip
          opts[:reasoning_effort] = requested_reasoning unless requested_reasoning.empty?
          # Allow larger/default max tokens; configurable via env overrides
          max_tokens = (ENV['GEMINI_MAX_TOKENS'] || ENV['API_MAX_TOKENS'] || '1024').to_i
          opts[:max_tokens] = max_tokens if max_tokens > 0
        when 'openai'
          # OpenAI: use system message
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
        when 'mistral'
          # Mistral: use system message
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
        when 'deepseek'
          # DeepSeek: use system message
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
        when 'cohere'
          # Cohere: use preamble
          opts[:preamble] = preface
          opts[:messages] = [{ "role" => "user", "content" => prompt }]
        when 'xai', 'grok'
          # xAI/Grok: use system message
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
        when 'perplexity'
          # Perplexity: use system message
          opts[:messages] = [
            { "role" => "system", "content" => preface },
            { "role" => "user", "content" => prompt }
          ]
        else
          # Default: include system context in user message
          opts[:messages] = [{ "role" => "user", "content" => "#{preface}\n\n#{prompt}" }]
        end
      end
      opts[:websearch] = true if websearch
      # Do not force temperature globally; many models (per model_spec) fix or ignore it.
      # Allow explicit override via ENV if needed: API_TEMPERATURE
      if ENV.key?('API_TEMPERATURE') && !ENV['API_TEMPERATURE'].to_s.strip.empty?
        opts[:temperature] = ENV['API_TEMPERATURE'].to_f
      end
      opts
    end

    def log_request(kind:, app:, prompt:, messages: nil)
      return unless ENV['API_LOG'] == 'true'
      msg = if messages
        "messages=#{messages.size}"
      else
        "prompt=\"#{truncate(prompt)}\""
      end
      puts("[api] provider=#{@provider} app=#{app || '-'} kind=#{kind} #{msg}")
    end

    def log_response(res)
      return unless ENV['API_LOG'] == 'true'
      if res.is_a?(Hash)
        text = res[:text] || res['text']
        puts("[api] ok len=#{text.to_s.length}")
      else
        puts("[api] ok raw")
      end
    end

    def truncate(s, n=120)
      return '' if s.nil?
      str = s.to_s
      str.length > n ? str[0, n] + '…' : str
    end

    def helper_for(provider)
      # Return an instance that includes the helper module, matching app behavior
      case provider.to_s
      when 'openai'
        require_relative '../../lib/monadic/adapters/vendors/openai_helper'
        Class.new { include OpenAIHelper }.new
      when 'anthropic', 'claude'
        require_relative '../../lib/monadic/adapters/vendors/claude_helper'
        Class.new { include ClaudeHelper }.new
      when 'gemini'
        require_relative '../../lib/monadic/adapters/vendors/gemini_helper'
        Class.new { include GeminiHelper }.new
      when 'mistral'
        require_relative '../../lib/monadic/adapters/vendors/mistral_helper'
        Class.new { include MistralHelper }.new
      when 'cohere'
        require_relative '../../lib/monadic/adapters/vendors/cohere_helper'
        Class.new { include CohereHelper }.new
      when 'perplexity'
        require_relative '../../lib/monadic/adapters/vendors/perplexity_helper'
        Class.new { include PerplexityHelper }.new
      when 'deepseek'
        require_relative '../../lib/monadic/adapters/vendors/deepseek_helper'
        Class.new { include DeepSeekHelper }.new
      when 'xai', 'grok'
        require_relative '../../lib/monadic/adapters/vendors/grok_helper'
        Class.new { include GrokHelper }.new
      when 'ollama'
        require_relative '../../lib/monadic/adapters/vendors/ollama_helper'
        Class.new { include OllamaHelper }.new
      else
        raise ArgumentError, "Unknown provider: #{provider}"
      end
    end

    public
    # Capability hints per provider (used for explicit skips or filtering)
    def supports_code_interpreter?
      @provider == 'openai'
    end

    def supports_web_search?
      %w[openai anthropic gemini perplexity xai].include?(@provider)
    end
  end
end
