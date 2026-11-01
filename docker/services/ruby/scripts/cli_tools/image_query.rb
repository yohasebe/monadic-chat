#!/usr/bin/env ruby

require "securerandom"
require_relative "../../lib/monadic/utils/shared_path_guard"
require "base64"
require "tmpdir"
require "open3"
require "http"
require_relative "../../lib/monadic/utils/secret_references"

begin
  require_relative "../../lib/monadic/utils/model_spec"
rescue LoadError
  # ModelSpec not available in this environment
end

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 5
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 1
RETRY_DELAY = 1

def get_base64(image_path, max_dimension = 512)
  # The image is read as a plain file of the shared folder (never through a
  # link) and measured and resized as a copy in a folder of its own outside
  # it, so ImageMagick opens no path in the shared folder.
  original = Monadic::Utils::SharedPathGuard.read_file!(image_path, &:read)
  Dir.mktmpdir("image_query") do |work|
    source = File.join(work, "source#{File.extname(image_path)}")
    File.binwrite(source, original)
    resize_to_base64(source, original, max_dimension)
  end
end

def resize_to_base64(source, original, max_dimension)
  # Use `identify` to get dimensions with ImageMagick
  output, _status = Open3.capture2("identify", "-format", "%w %h", source)
  width, height = output.split.map(&:to_f)

  # Calculate the aspect ratio
  aspect_ratio = width / height

  # Determine the new dimensions while preserving the aspect ratio
  if aspect_ratio >= 1
    # Width is the long side
    new_width = [2000, max_dimension].min
    new_height = (new_width / aspect_ratio).round
  else
    # Height is the long side
    new_height = [768, max_dimension].min
    new_width = (new_height * aspect_ratio).round
  end

  # Ensure the short side does not exceed its limit
  if new_width > new_height && new_height > 768
    new_height = 768
    new_width = (new_height * aspect_ratio).round
  elsif new_height > new_width && new_width > 2000
    new_width = 2000
    new_height = (new_width / aspect_ratio).round
  end

  base64_data = ""
  if width > new_width || height > new_height
    resized = File.join(File.dirname(source), "resized#{File.extname(source)}")
    geometry = format("%dx%d", new_width, new_height)
    system("magick", source, "-resize", geometry, resized)
    base64_data = Base64.strict_encode64(File.binread(resized))
  else
    base64_data = Base64.strict_encode64(original)
  end
  base64_data
end

def img2url(image_path, max_dimension = 512)
  base64_data = get_base64(image_path, max_dimension)
  file_extension = File.extname(image_path).delete_prefix(".").downcase
  mime_type = case file_extension
              when "jpg", "jpeg"
                "image/jpeg"
              when "png"
                "image/png"
              when "gif"
                "image/gif"
              else
                "application/octet-stream" # Default MIME type
              end
  "data:#{mime_type};base64,#{base64_data}"
end

def image_query(message, image, model = nil)
  model ||= (defined?(Monadic::Utils::ModelSpec) && Monadic::Utils::ModelSpec.default_vision_model("openai"))
  num_retrial = 0

  api_key = Monadic::Utils::SecretReferences.config_value("OPENAI_API_KEY")

  if image && File.file?(image)
    image_path = image
    image_url = nil
  elsif image
    # check if the image is a valid URL
    uri = URI.parse(image)
    if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      image_path = nil
      image_url = image
    else
      image_path = nil
      image_url = nil
    end
  else
    image_path = nil
    image_url = nil
  end

  headers = {
    "Content-Type": "application/json",
    Authorization: "Bearer #{api_key}"
  }

  body = {
    model: model,
    temperature: 0.0,
    n: 1,
    stream: false,
    max_tokens: 1000,
    presence_penalty: 0.0,
    frequency_penalty: 0.0
  }

  content = [{ type: "text", text: message }]
  if image_path
    # unless the image_path refers to an existing valid png/jpg/jpeg/gif file, return an error message
    unless File.file?(image_path) && %w[.png .jpg .jpeg .gif].include?(File.extname(image_path).downcase)
      return "ERROR: The image file is not valid."
    end

    base64_image_url = img2url(image_path)
    content << { type: "image_url", image_url: { url: base64_image_url } }
  elsif image_url
    content << { type: "image_url", image_url: { url: image_url } }
  end

  body["messages"] = [
    { role: "user", content: content }
  ]

  target_uri = "#{API_ENDPOINT}/chat/completions"
  http = HTTP.headers(headers)

  res = http.timeout(connect: OPEN_TIMEOUT,
                     write: WRITE_TIMEOUT,
                     read: READ_TIMEOUT).post(target_uri, json: body)
  unless res.status.success?
    JSON.parse(res.body)["error"]
    "ERROR: #{JSON.parse(res.body)["error"]}"
  end

  JSON.parse(res.body).dig("choices", 0, "message", "content")
rescue HTTP::Error, HTTP::TimeoutError
  if num_retrial < MAX_RETRIES
    num_retrial += 1
    sleep RETRY_DELAY
    retry
  else
    error_message = "The request has timed out."
    puts "ERROR: #{error_message}"
    exit
  end
rescue StandardError => e
  pp e.message
  pp e.backtrace
  pp e.inspect
  puts "ERROR: #{e.message}"
  exit
end

# Assuming the first argument is the message and the second is the image path/url
message = ARGV[0]
image_path_or_url = ARGV[1]
model = ARGV[2] || (defined?(Monadic::Utils::ModelSpec) && Monadic::Utils::ModelSpec.default_vision_model("openai"))

if message.nil? || image_path_or_url.nil?
  puts "Usage: #{$PROGRAM_NAME} 'message' 'image_path_or_url' 'model'"
  exit
end

begin
  response = image_query(message, image_path_or_url, model)
  puts response
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  exit
end
