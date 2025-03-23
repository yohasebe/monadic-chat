#!/usr/bin/env ruby

require "securerandom"
require "base64"
require "http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 10
READ_TIMEOUT = 180
WRITE_TIMEOUT = 60
MAX_RETRIES = 5
RETRY_DELAY = 1

def stt_api_request(audiofile, response_format = "text", lang_code = nil, model = "gpt-4o-transcribe")
  num_retrial = 0

  begin
    api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
  end

  url = "#{API_ENDPOINT}/audio/transcriptions"
  response = nil

  begin
    options = {
      file: HTTP::FormData::File.new(audiofile),
      model: model,
      response_format: response_format
    }
    options["language"] = lang_code if lang_code

    if response_format == "json"
      options["include[]"] = ["logprobs"]
    end

    form_data = HTTP::FormData.create(options)
    response = HTTP.headers(
      "Content-Type": form_data.content_type,
      Authorization: "Bearer #{api_key}"
    ).timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(url, body: form_data.to_s)
  rescue HTTP::Error, HTTP::TimeoutError => e
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      return { type: "error", content: "ERROR: #{e.message}" }
    end
  end

  if response.status.success?
    response.body
  else
    pp "Error: #{response.status} - #{response.body}"
    { type: "error", content: "Speech-to-Text API Error" }
  end
end

audiofile = ARGV[0]
outpath = ARGV[1] || "."
response_format = ARGV[2] || "json"  # Changed default from srt to json
lang_code = ARGV[3] || nil
model = ARGV[4] || "gpt-4o-transcribe"  # Added model parameter with default

if audiofile.nil?
  puts "ERROR: No audio file provided."
  exit 1
end

begin
  # Detect the file format from the extension
  format = File.extname(audiofile).sub(/^\./, '') # Remove leading dot
  
  # Normalize format to one that OpenAI API supports
  # OpenAI API supports: "mp3", "mp4", "mpeg", "mpga", "m4a", "wav", or "webm"
  format = "mp3" if format == "mpeg" || format == "audio/mpeg"
  format = "mp4" if format == "mp4a-latm"
  format = "wav" if %w[x-wav wave].include?(format)
  
  # Default to mp3 for empty or unsupported formats for better compatibility
  format = "mp3" if format.empty? || !%w[mp3 mp4 mpeg mpga m4a wav webm].include?(format)
  
  puts "Using audio format: #{format}, model: #{model}"
  
  response = stt_api_request(audiofile, response_format, lang_code, model)
  outfile = "#{outpath}/stt_#{Time.now.strftime("%Y%m%d_%H%M%S")}.json"
  File.write(outfile, response)
  puts response
rescue StandardError => e
  pp e.message
  pp e.backtrace
  pp e.inspect
  puts "An error occurred: #{e.message}"
end
