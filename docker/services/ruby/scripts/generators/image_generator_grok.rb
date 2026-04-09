#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require_relative "../../lib/monadic/utils/ssl_configuration"
require_relative "../../lib/monadic/utils/model_spec"

if defined?(Monadic::Utils::SSLConfiguration)
  Monadic::Utils::SSLConfiguration.configure!
end

# Resolve default image model from providerDefaults SSOT
def default_grok_image_model
  Monadic::Utils::ModelSpec.default_image_model("xai")
rescue
  nil
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

# Parse command line arguments
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
end.parse!

# Validate required arguments
unless options[:prompt]
  puts "ERROR: A prompt is required. Use -p or --prompt to specify the prompt."
  exit 1
end

if options[:operation] == "edit" && options[:images].empty?
  puts "ERROR: At least one image is required for edit operation. Use -i or --image."
  exit 1
end

if options[:images].size > 3
  puts "ERROR: Maximum 3 images allowed for xAI edit API."
  exit 1
end

def generate_image(prompt, operation: "generate", aspect_ratio: nil, images: [], num_retrials: 3)
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
        model: default_grok_image_model,
        prompt: prompt,
        n: 1,
        response_format: "b64_json"
      }
      body[:aspect_ratio] = aspect_ratio if aspect_ratio

    when "edit"
      url = "https://api.x.ai/v1/images/edits"
      body = {
        model: default_grok_image_model,
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
    filename = "#{Time.now.to_i}.png"
    file_path = File.join(save_path, filename)

    File.open(file_path, "wb") do |f|
      f.write(image_data)
    end

    { original_prompt: prompt, revised_prompt: revised_prompt, success: true, filename: filename }
  else
    begin
      error_response = JSON.parse(res.body)
      error_msg = error_response.is_a?(Hash) && error_response['error'] ?
                 (error_response['error']['message'] rescue "Error with API response") :
                 "Error with API response: #{error_response.to_s[0..100]}"
      return { original_prompt: prompt, success: false, message: error_msg }
    rescue JSON::ParserError
      return { original_prompt: prompt, success: false, message: "Error parsing API response" }
    end
  end
rescue StandardError => e
  error_msg = "Error: #{e.message}"
  puts error_msg
  puts e.backtrace

  num_retrials -= 1
  if num_retrials.positive?
    sleep 1
    return generate_image(prompt, operation: operation, aspect_ratio: aspect_ratio, images: images, num_retrials: num_retrials)
  else
    return { original_prompt: prompt, success: false, message: "Error: Image operation failed after multiple attempts." }
  end
end

res = generate_image(options[:prompt], operation: options[:operation], aspect_ratio: options[:aspect_ratio], images: options[:images])
puts JSON.pretty_generate(res)
