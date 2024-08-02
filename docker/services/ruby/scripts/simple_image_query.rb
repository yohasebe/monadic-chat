#!/usr/bin/env ruby

require "securerandom"
require "base64"
require "http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 5
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 1
RETRY_DELAY = 1

def get_base64(image_path, max_dimension = 512)
  # Use `identify` to get dimensions with ImageMagick
  output = `identify -format "%w %h" '#{image_path}'`
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
    tempfile_path = File.join(File.dirname(image_path), "#{SecureRandom.uuid}#{File.extname(image_path)}")
    # Use `convert` to resize the image with ImageMagick
    command = "convert '#{image_path}' -resize #{new_width}x#{new_height} '#{tempfile_path}'"

    system(command)
    base64_data = Base64.strict_encode64(File.open(tempfile_path, "rb").read)
    File.delete tempfile_path
  else
    base64_data = Base64.strict_encode64(File.open(image_path, "rb").read)
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

def image_query(message, image, model = "gpt-4o-mini")
  num_retrial = 0

  begin
    api_key = File.read("/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  end

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
    "Content-Type" => "application/json",
    "Authorization" => "Bearer #{api_key}"
  }

  body = {
    "model" => model,
    "temperature" => 0.0,
    "top_p" => 0.0,
    "n" => 1,
    "stream" => false,
    "max_tokens" => 1000,
    "presence_penalty" => 0.0,
    "frequency_penalty" => 0.0
  }

  content = [{ "type" => "text", "text" => message }]
  if image_path
    # unless the image_path refers to an existing valid png/jpg/jpeg/gif file, return an error message
    unless File.file?(image_path) && %w[.png .jpg .jpeg .gif].include?(File.extname(image_path).downcase)
      return "ERROR: The image file is not valid."
    end

    base64_image_url = img2url(image_path)
    content << { "type" => "image_url", "image_url" => { "url" => base64_image_url } }
  elsif image_url
    content << { "type" => "image_url", "image_url" => { "url" => image_url } }
  end

  body["messages"] = [
    { "role" => "user", "content" => content }
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
model = ARGV[2] || "gpt-4o-mini"

if message.nil? || image_path_or_url.nil?
  puts "Usage: #{$PROGRAM_NAME} 'message' 'image_path_or_url'"
  exit
end

begin
  response = image_query(message, image_path_or_url, model)
  puts response
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  exit
end
