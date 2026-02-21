# frozen_string_literal: true

require "base64"
require "http"

# ImageAnalysisAgent provides provider-independent image analysis
# using each provider's native Vision API.
#
# Supported providers: OpenAI, Claude (Anthropic), Gemini (Google), Grok (xAI)
# Non-vision providers (Cohere, DeepSeek, Mistral, Perplexity, Ollama) fall back
# to the first available vision provider (preference: OpenAI).

module ImageAnalysisAgent
  VISION_MODELS = {
    "openai"    => "gpt-4o-mini",
    "anthropic" => "claude-haiku-4-5-20251001",
    "google"    => "gemini-2.0-flash",
    "xai"       => "grok-2-vision-1212"
  }.freeze

  VISION_API_KEYS = {
    "openai"    => "OPENAI_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY",
    "google"    => "GEMINI_API_KEY",
    "xai"       => "XAI_API_KEY"
  }.freeze

  VISION_PROVIDERS = VISION_MODELS.keys.freeze

  IMAGE_CONNECT_TIMEOUT = 10
  IMAGE_READ_TIMEOUT = 60
  IMAGE_WRITE_TIMEOUT = 30
  IMAGE_MAX_RETRIES = 1
  IMAGE_MAX_FILE_SIZE = 10 * 1024 * 1024 # 10MB

  def image_analysis_agent(message:, image_path:)
    # 1. Load and encode the image
    image_data = prepare_image_for_analysis(image_path)
    return image_data if image_data.is_a?(String) # Error message

    # 2. Determine the vision provider
    provider = resolve_vision_provider

    # 3. Get API key
    api_key_name = VISION_API_KEYS[provider]
    api_key = CONFIG[api_key_name]&.strip
    return "ERROR: No API key for provider '#{provider}'" if api_key.nil? || api_key.empty?

    # 4. Call provider-specific Vision API
    model = VISION_MODELS[provider]

    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "[ImageAnalysisAgent] Using provider: #{provider}, model: #{model}"
    end

    case provider
    when "openai"    then vision_query_openai(message, image_data, model, api_key)
    when "anthropic" then vision_query_claude(message, image_data, model, api_key)
    when "google"    then vision_query_gemini(message, image_data, model, api_key)
    when "xai"       then vision_query_grok(message, image_data, model, api_key)
    end
  rescue => e
    "ERROR: Image analysis failed: #{e.message}"
  end

  private

  def prepare_image_for_analysis(image_path)
    return "ERROR: Invalid file path (path traversal not allowed)" if image_path.to_s.include?("..")

    # Resolve path — check absolute, then shared volume locations
    path = if File.exist?(image_path)
             image_path
           elsif defined?(SHARED_VOL) && File.exist?(File.join(SHARED_VOL, image_path))
             File.join(SHARED_VOL, image_path)
           elsif defined?(LOCAL_SHARED_VOL) && File.exist?(File.join(LOCAL_SHARED_VOL, image_path))
             File.join(LOCAL_SHARED_VOL, image_path)
           end

    return "ERROR: Image file not found: #{image_path}" unless path && File.exist?(path)

    # Check file size
    file_size = File.size(path)
    if file_size > IMAGE_MAX_FILE_SIZE
      return "ERROR: Image file too large (#{file_size / 1024 / 1024}MB). Maximum: 10MB"
    end

    # Detect MIME type
    ext = File.extname(path).delete_prefix(".").downcase
    mime_type = case ext
                when "jpg", "jpeg" then "image/jpeg"
                when "png" then "image/png"
                when "gif" then "image/gif"
                when "webp" then "image/webp"
                else
                  return "ERROR: Unsupported image format: #{ext}. Supported: jpg, jpeg, png, gif, webp"
                end

    # Read and encode
    raw = File.binread(path)
    base64 = Base64.strict_encode64(raw)

    { base64: base64, mime_type: mime_type }
  end

  def resolve_vision_provider
    # Get the current app's provider
    provider_raw = settings["provider"] || settings[:provider] || ""

    # Normalize to vision provider key
    normalized = case provider_raw.to_s.downcase
                 when "openai" then "openai"
                 when "anthropic", "claude" then "anthropic"
                 when "google", "gemini" then "google"
                 when "xai", "grok" then "xai"
                 else nil
                 end

    # If provider supports vision and has API key, use it
    if normalized && VISION_PROVIDERS.include?(normalized)
      api_key_name = VISION_API_KEYS[normalized]
      api_key = CONFIG[api_key_name]&.strip
      return normalized unless api_key.nil? || api_key.empty?
    end

    # Fallback: try each vision provider in order
    VISION_PROVIDERS.each do |vp|
      api_key_name = VISION_API_KEYS[vp]
      api_key = CONFIG[api_key_name]&.strip
      return vp unless api_key.nil? || api_key.empty?
    end

    # Last resort
    "openai"
  end

  def vision_http_post(uri, headers, body)
    retries = 0
    begin
      res = HTTP.headers(headers)
               .timeout(connect: IMAGE_CONNECT_TIMEOUT,
                        write: IMAGE_WRITE_TIMEOUT,
                        read: IMAGE_READ_TIMEOUT)
               .post(uri, json: body)
      res
    rescue HTTP::Error, HTTP::TimeoutError => e
      if retries < IMAGE_MAX_RETRIES
        retries += 1
        sleep 1
        retry
      end
      raise e
    end
  end

  # --- Provider-specific Vision API implementations ---

  def vision_query_openai(message, image_data, model, api_key)
    uri = "https://api.openai.com/v1/chat/completions"
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    body = {
      model: model,
      temperature: 0.0,
      max_tokens: 1000,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: message },
            { type: "image_url", image_url: { url: "data:#{image_data[:mime_type]};base64,#{image_data[:base64]}" } }
          ]
        }
      ]
    }

    res = vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: OpenAI Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    JSON.parse(res.body.to_s).dig("choices", 0, "message", "content") || "ERROR: Empty response from OpenAI"
  end

  def vision_query_claude(message, image_data, model, api_key)
    uri = "https://api.anthropic.com/v1/messages"
    headers = {
      "Content-Type" => "application/json",
      "x-api-key" => api_key,
      "anthropic-version" => "2023-06-01"
    }
    body = {
      model: model,
      max_tokens: 1000,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: image_data[:mime_type],
                data: image_data[:base64]
              }
            },
            { type: "text", text: message }
          ]
        }
      ]
    }

    res = vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Claude Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    parsed = JSON.parse(res.body.to_s)
    content = parsed["content"]
    if content.is_a?(Array) && content.first
      content.first["text"] || "ERROR: Empty response from Claude"
    else
      "ERROR: Unexpected response format from Claude"
    end
  end

  def vision_query_gemini(message, image_data, model, api_key)
    uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
    headers = {
      "Content-Type" => "application/json"
    }
    body = {
      contents: [
        {
          parts: [
            {
              inline_data: {
                mime_type: image_data[:mime_type],
                data: image_data[:base64]
              }
            },
            { text: message }
          ]
        }
      ]
    }

    res = vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Gemini Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    parsed = JSON.parse(res.body.to_s)
    parsed.dig("candidates", 0, "content", "parts", 0, "text") || "ERROR: Empty response from Gemini"
  end

  def vision_query_grok(message, image_data, model, api_key)
    # Grok uses OpenAI-compatible API format
    uri = "https://api.x.ai/v1/chat/completions"
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    body = {
      model: model,
      temperature: 0.0,
      max_tokens: 1000,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: message },
            { type: "image_url", image_url: { url: "data:#{image_data[:mime_type]};base64,#{image_data[:base64]}" } }
          ]
        }
      ]
    }

    res = vision_http_post(uri, headers, body)
    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Grok Vision API error (#{res.status}): #{error.dig("error", "message") || res.body.to_s}"
    end

    JSON.parse(res.body.to_s).dig("choices", 0, "message", "content") || "ERROR: Empty response from Grok"
  end
end
