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
    def chat(prompt, **opts)
      Timeout.timeout(@timeout) do
        helper = helper_for(@provider)
        options = build_options(prompt: prompt, messages: opts[:messages])
        throttle!
        log_request(kind: 'chat', app: opts[:app], prompt: (prompt if prompt && !prompt.empty?), messages: options[:messages])
        res = request_with_retry { helper.send_query(options) }
        # Normalize to hash with :text
        res = res.is_a?(String) ? { text: res } : res
        log_response(res)
        res
      end
    end

    def chat_messages(messages, **opts)
      chat('', **opts.merge(messages: messages))
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
        # Use Imagen 3 direct endpoint as in GeminiHelper
        model = 'imagen-3.0-generate-002'
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
    def build_options(prompt:, messages: nil, websearch: false)
      preface = "Ignore any missing or prior context. Respond directly and concisely."
      opts = {}
      if messages.is_a?(Array)
        opts[:messages] = messages
      else
        case @provider
        when 'anthropic'
          # Claude expects system at top-level, messages without system role
          opts[:system] = preface
          opts[:messages] = [ { role: 'user', content: prompt } ]
        when 'gemini'
          # Keep simple user message; default to no reasoning param unless explicitly enabled
          opts[:messages] = [ { role: 'user', content: prompt } ]
          # Conditionally set reasoning_effort only if requested via env
          requested_reasoning = (ENV['GEMINI_REASONING'] || ENV['REASONING_EFFORT']).to_s.strip
          opts[:reasoning_effort] = requested_reasoning unless requested_reasoning.empty?
          # Allow larger/default max tokens; configurable via env overrides
          max_tokens = (ENV['GEMINI_MAX_TOKENS'] || ENV['API_MAX_TOKENS'] || '1024').to_i
          opts[:max_tokens] = max_tokens if max_tokens > 0
        else
          # Default providers: user only with preface merged
          opts[:messages] = [ { role: 'user', content: "#{preface} #{prompt}" } ]
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
