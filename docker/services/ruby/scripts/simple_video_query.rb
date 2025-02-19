#!/usr/bin/env ruby

require "json"
require "http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 5
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 1
RETRY_DELAY = 1
MAX_FRAMES = 50

DEFAULT_QUERY = "Describe what happens in the video by analyzing the image data extracted from the video."

def video_query(json_path, query, model = "gpt-4o-mini")
  num_retrial = 0

  begin
    api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  end

  # Read the JSON file
  json_data = JSON.parse(File.read(json_path))

  # Validate JSON data
  unless json_data.is_a?(Array) && json_data.all? { |item| item.is_a?(String) }
    return "ERROR: The JSON file is not valid."
  end

  # Limit the number of images to MAX_FRAMES
  if json_data.size > MAX_FRAMES
    json_data = balance_images(json_data, MAX_FRAMES)
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

  content = [{ type: "text", text: query }]
  json_data.each do |image|
    if image.start_with?("data:image/")
      content << { type: "image_url", image_url: { url: image } }
    elsif image.match?(%r{\A[a-zA-Z0-9+/=]+\Z})
      # Assume it's base64 data without MIME type prefix
      base64_image_url = "data:image/png;base64,#{image}"
      content << { type: "image_url", image_url: { url: base64_image_url } }
    else
      uri = URI.parse(image)
      if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        content << { type: "image_url", image_url: { url: image } }
      else
        return "ERROR: Invalid image URL or base64 data."
      end
    end
  end

  body["messages"] = [
    { role: "user", content: content }
  ]

  target_uri = "#{API_ENDPOINT}/chat/completions"
  http = HTTP.headers(headers)

  res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)
  unless res.status.success?
    return "ERROR: #{JSON.parse(res.body)["error"]}"
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
  puts "ERROR: #{e.message}"
  exit
end

def balance_images(images, max_frames)
  total_images = images.size
  step = (total_images - 1).to_f / (max_frames - 1)
  balanced_images = []

  (0...max_frames).each do |i|
    index = (i * step).round
    balanced_images << images[index]
  end

  balanced_images
end

# Assuming the first argument is the path to the JSON file and the second is the query
json_path = ARGV[0]
query = ARGV[1] || DEFAULT_QUERY
model = ARGV[2] || "gpt-4o-mini"

if json_path.nil?
  puts "Usage: #{$PROGRAM_NAME} 'json_path' ['query']"
  exit
end

begin
  response = video_query(json_path, query, model)
  puts response
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  exit
end
