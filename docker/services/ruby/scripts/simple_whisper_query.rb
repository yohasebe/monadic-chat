#!/usr/bin/env ruby

require 'securerandom'
require 'base64'
require 'http'

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 10
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 5
RETRY_DELAY = 1

def whisper_api_request(audiofile, outpath = ".", response_format = "text", lang_code = nil)
  num_retrial = 0

  begin
    api_key = File.read("/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/data/.env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  end

  url = "#{API_ENDPOINT}/audio/transcriptions"
  response = nil

  begin
    options = {
      "file" => HTTP::FormData::File.new(audiofile),
      "model" => "whisper-1",
      "response_format" => response_format
    }
    options["language"] = lang_code if lang_code
    form_data = HTTP::FormData.create(options)
    response = HTTP.headers(
      "Authorization" => "Bearer #{api_key}",
      "Content-Type" => form_data.content_type
    ).timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(url, body: form_data.to_s)
  rescue HTTP::Error, HTTP::TimeoutError => e
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      return { "type" => "error", "content" => "ERROR: #{e.message}" }
    end
  end

  if response.status.success?
    response.body
  else
    pp "Error: #{response.status} - #{response.body}"
    { "type" => "error", "content" => "Whisper API Error" }
  end
end

audiofile = ARGV[0]
outpath = ARGV[1] || "."
response_format = ARGV[2] || "srt"
lang_code = ARGV[3] || nil

if audiofile.nil?
  puts "ERROR: No audio file provided."
  exit 1
end

begin
  response = whisper_api_request(audiofile, outpath, response_format, lang_code)
  outfile = "#{outpath}/whisper_#{Time.now.strftime("%Y%m%d_%H%M%S")}.json" 
  res = JSON.parse(response)["text"]
  File.write(outfile, response)
  puts res
rescue => e
  puts "An error occurred: #{e.message}"
end

