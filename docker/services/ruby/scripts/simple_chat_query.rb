#!/usr/bin/env ruby

require "http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 5
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 1
RETRY_DELAY = 1

def chat_query(message, model)
  num_retrial = 0

  begin
    api_key = File.read("/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
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
    "stream" => false
  }

  content = [{ "type" => "text", "text" => message }]

  body["messages"] = [
    { "role" => "system", "content" => initial_prompt },
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
filepath = ARGV[0]
model = ARGV[1] || "gpt-4o-mini"

if filepath.nil?
  puts "Usage: #{$PROGRAM_NAME} 'filepath' 'model (optional)'"
  exit
end

begin

  response = chat_query(text, model)
  puts response
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  exit
end
