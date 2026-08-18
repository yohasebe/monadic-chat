#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require "securerandom"
require_relative "../../lib/monadic/utils/ssl_configuration"
require_relative "../../lib/monadic/utils/model_spec"
require_relative "../../lib/monadic/utils/error_formatter"

if defined?(Monadic::Utils::SSLConfiguration)
  Monadic::Utils::SSLConfiguration.configure!
end

# Resolve default image model from providerDefaults SSOT
def default_grok_image_model
  Monadic::Utils::ModelSpec.default_image_model("xai")
rescue
  nil
end

# Selectable image models (SSOT: providerDefaults.xai.image).
def grok_image_models
  Monadic::Utils::ModelSpec.get_provider_models("xai", "image") || []
rescue
  []
end

# Unknown or blank input resolves to the default, so a stale or hallucinated
# model name never reaches the API.
def resolve_grok_image_model(requested)
  name = requested.to_s.strip
  return default_grok_image_model if name.empty?
  return name if grok_image_models.include?(name)

  warn "Unknown image model #{name.inspect}; using the default" if ENV["EXTRA_LOGGING"]
  default_grok_image_model
end

# xAI error text names the account's team UUID when a model is not enabled for
# it. This message reaches the chat and is saved with the conversation, so the
# identifier is scrubbed before it leaves the script; the EXTRA_LOGGING trace
# keeps the untouched text for debugging.
def scrub_account_ids(text)
  Monadic::Utils::ErrorFormatter.scrub_identifiers(text)
end

# Determine MIME type from file extension
def get_mime_type(file_path)
  case File.extname(file_path).downcase
  when ".png" then "image/png"
  when ".jpg", ".jpeg" then "image/jpeg"
  when ".gif" then "image/gif"
  when ".webp" then "image/webp"
  else "image/png"
  end
end

# Encode an image file as a data URI string
def encode_image_as_data_uri(file_path)
  mime = get_mime_type(file_path)
  data = Base64.strict_encode64(File.binread(file_path))
  "data:#{mime};base64,#{data}"
end

# Resolve image file path from shared folders
def resolve_image_path(filename)
  return filename if File.exist?(filename)

  basename = File.basename(filename)
  ["/monadic/data/", File.expand_path("~/monadic/data/")].each do |dir|
    path = File.join(dir, basename)
    return path if File.exist?(path)
  end
  nil
end

# Parse command line arguments. Kept as a function (with the invocation behind
# a __FILE__ guard at the bottom) so specs can require this file and exercise
# the pieces in-process instead of spawning the script — spawning is what let a
# unit test reach the real API and bill for an image.
def parse_options(argv)
  options = { operation: "generate", images: [] }
  OptionParser.new do |opts|
    opts.banner = "Usage: image_generator_grok.rb [options]"

    opts.on("-p", "--prompt PROMPT", "The prompt to generate/edit an image") do |prompt|
      options[:prompt] = prompt
    end

    opts.on("-o", "--operation OPERATION", "Operation: generate, edit") do |op|
      options[:operation] = op
      unless %w[generate edit].include?(op)
        puts "ERROR: Invalid operation '#{op}'. Must be 'generate' or 'edit'."
        exit 1
      end
    end

    opts.on("-a", "--aspect-ratio RATIO", "Aspect ratio (1:1, 16:9, 9:16, 4:3, 3:4)") do |ratio|
      options[:aspect_ratio] = ratio
    end

    opts.on("-i", "--image IMAGE", "Image file path for editing (can be specified multiple times, max 3)") do |img|
      options[:images] << img
    end

    opts.on("-m", "--model MODEL", "Image model to use (defaults to the provider default)") do |model|
      options[:model] = model
    end
  end.parse!(argv)
  options
end

# Returns nil when the options are usable, or the error message to print.
def validate_options(options)
  return "ERROR: A prompt is required. Use -p or --prompt to specify the prompt." unless options[:prompt]

  if options[:operation] == "edit" && options[:images].empty?
    return "ERROR: At least one image is required for edit operation. Use -i or --image."
  end
  return "ERROR: Maximum 3 images allowed for xAI edit API." if options[:images].size > 3

  nil
end

def generate_image(prompt, operation: "generate", aspect_ratio: nil, images: [], model: nil, num_retrials: 3)
  model ||= default_grok_image_model
  begin
    api_key = File.read("/monadic/config/env").split("\n").find do |line|
      line.start_with?("XAI_API_KEY")
    end.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find do |line|
      line.start_with?("XAI_API_KEY")
    end.split("=").last
  end

  res = nil

  begin
    headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    }

    case operation
    when "generate"
      url = "https://api.x.ai/v1/images/generations"
      body = {
        model: model,
        prompt: prompt,
        n: 1,
        response_format: "b64_json"
      }
      body[:aspect_ratio] = aspect_ratio if aspect_ratio

    when "edit"
      url = "https://api.x.ai/v1/images/edits"
      body = {
        model: model,
        prompt: prompt,
        n: 1,
        response_format: "b64_json"
      }

      # Resolve and encode images as data URIs
      encoded_images = images.map do |img_path|
        resolved = resolve_image_path(img_path)
        unless resolved
          return { original_prompt: prompt, success: false, message: "Image file not found: #{img_path}" }
        end
        { type: "image_url", url: encode_image_as_data_uri(resolved) }
      end

      # xAI uses "image" for single, "images" for multiple
      if encoded_images.size == 1
        body[:image] = encoded_images.first
      else
        body[:images] = encoded_images
      end
    end

    puts "Sending #{operation} request with prompt: #{prompt}" if ENV["EXTRA_LOGGING"]
    res = HTTP.headers(headers).timeout(120).post(url, json: body)
  rescue HTTP::Error, HTTP::TimeoutError => e
    error_msg = "ERROR: #{e.message}"
    return { original_prompt: prompt, success: false, message: error_msg }
  end

  if res.status.success?
    json = JSON.parse(res.body)
    data = json["data"].first
    base64_data = data["b64_json"]
    revised_prompt = data["revised_prompt"]

    if base64_data.nil?
      error_msg = "Error: No image data received from the API."
      return { original_prompt: prompt, success: false, message: error_msg }
    else
      image_data = Base64.decode64(base64_data)
    end

    primary_save_path = "/monadic/data/"
    secondary_save_path = File.expand_path("~/monadic/data/")

    save_path = Dir.exist?(primary_save_path) ? primary_save_path : secondary_save_path
    # Random suffix: Time.now.to_i has 1-second resolution, so concurrent
    # generations (e.g. parallel Conduit jobs) would otherwise collide on the
    # same output filename. The caller reads the name from this script's output.
    filename = "#{Time.now.to_i}_#{SecureRandom.hex(4)}.png"
    file_path = File.join(save_path, filename)

    File.open(file_path, "wb") do |f|
      f.write(image_data)
    end

    { original_prompt: prompt, revised_prompt: revised_prompt, success: true, filename: filename }
  else
    error_msg = begin
      error_response = JSON.parse(res.body)
      if error_response.is_a?(Hash) && error_response['error']
        (error_response['error']['message'] rescue "Error with API response")
      else
        "Error with API response: #{error_response.to_s[0..100]}"
      end
    rescue JSON::ParserError
      "Error parsing API response"
    end

    # Whether a model is available to this account can only be learned by
    # asking: the API answers "does not exist OR you have no access" as one
    # error. Retry once with the default so a bad choice degrades to a working
    # image. The model != fallback guard also stops the retry from recursing.
    fallback = default_grok_image_model
    if fallback && model != fallback
      warn "Image model #{model.inspect} failed (#{error_msg}); retrying with #{fallback.inspect}" if ENV["EXTRA_LOGGING"]
      retried = generate_image(prompt, operation: operation, aspect_ratio: aspect_ratio,
                               images: images, model: fallback, num_retrials: 0)
      if retried.is_a?(Hash) && retried[:success]
        retried[:fallback_from] = model
        retried[:message] = "Requested model #{model} was unavailable; generated with #{fallback} instead."
        return retried
      end
    end

    return { original_prompt: prompt, success: false, message: scrub_account_ids(error_msg) }
  end
rescue StandardError => e
  error_msg = "Error: #{e.message}"
  puts error_msg
  puts e.backtrace

  num_retrials -= 1
  if num_retrials.positive?
    sleep 1
    return generate_image(prompt, operation: operation, aspect_ratio: aspect_ratio, images: images,
                          model: model, num_retrials: num_retrials)
  else
    return { original_prompt: prompt, success: false, message: "Error: Image operation failed after multiple attempts." }
  end
end

if __FILE__ == $PROGRAM_NAME
  options = parse_options(ARGV)
  if (message = validate_options(options))
    puts message
    exit 1
  end

  res = generate_image(options[:prompt], operation: options[:operation], aspect_ratio: options[:aspect_ratio],
                       images: options[:images], model: resolve_grok_image_model(options[:model]))
  puts JSON.pretty_generate(res)
end
