#!/usr/bin/env ruby

require "http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 10
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 5
RETRY_DELAY = 1

def tts_api_request(text, response_format: "mp3", speed: "1.0", voice: "alloy", language: "auto")
  num_retrial = 0

  begin
    api_key = File.read("/monadic/config/env").split("
").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/config/env").split("
").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  end

  target_url = "#{API_ENDPOINT}/audio/speech"
  response = nil

  body = {
    input: text,
    model: "tts-1",
    voice: voice,
    speed: speed,
    response_format: response_format
  }

  unless language == "auto"
    body["language"] = language
  end

  headers = {
    "Content-Type": "application/json",
    Authorization: "Bearer #{api_key}"
  }

  http = HTTP.headers(headers)
  begin
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_url, json: body)
    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      return { type: "error", content: "ERROR: #{error_report["message"]}" }
    end
    response = res.body.to_s
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      return { type: "error", content: "ERROR: The request has timed out." }
    end
  end

  response
end

# Usage:
# simple_tts_query.rb "#{text}" --speed #{speed} --voice #{voice} --language #{language}

textpath = ARGV[0]
text = File.read(textpath)

speed = ARGV.find { |arg| arg.start_with?("--speed") }&.split("=")&.last || "1.0"
voice = ARGV.find { |arg| arg.start_with?("--voice") }&.split("=")&.last || "alloy"
# if language is not specified, "auto" is used by default
language = ARGV.find { |arg| arg.start_with?("--language") }&.split("=")&.last || "auto"

response_format = "mp3"

if text.nil? || text.empty?
  puts "ERROR: No text provided."
  exit 1
end

begin
  response = tts_api_request(text,
                             response_format: response_format,
                             speed: speed,
                             voice: voice,
                             language: language)

  if response.is_a?(Hash) && response["type"] == "error"
    puts response["content"]
    exit 1
  end

  primary_save_path = "/monadic/data/"
  secondary_save_path = File.expand_path("~/monadic/data/")

  # check if the directory exists
  save_path = Dir.exist?(primary_save_path) ? primary_save_path : secondary_save_path
  # create filename "*.mp3" from textpath
  outfile = File.basename(textpath, ".*")
  filename = "#{outfile}.mp3"
  file_path = File.join(save_path, filename)

  File.open(file_path, "wb") do |f|
    f.write(response)
  end

  File.write(outfile, response)
  puts "Text-to-speech audio MP3 saved to #{filename} 🎉"
rescue StandardError => e
  puts "An error occurred: #{e.message} 😞"
  puts e.backtrace.join("
")
end
