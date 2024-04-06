#!/usr/bin/env ruby
require "http"
require "json"
require "optparse"

API_ENDPOINT = "https://api.perplexity.ai"
OPEN_TIMEOUT = 5
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 1
RETRY_DELAY = 1

# Option parsing
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: script.rb [options] 'message' [model]"
  opts.on("--check", "Check API key and model") do
    options[:check] = true
  end
end.parse!

def get_env_var(var_name)
  begin
    if File.file?("/.dockerenv")
      value = File.read("/monadic/data/.env").split("\n").find do |line|
        line.start_with?(var_name)
      end.split("=").last
    else
      value = File.read("#{Dir.home}/monadic/data/.env").split("\n").find do |line|
        line.start_with?(var_name)
      end.split("=").last
    end
    value.nil? ? false : value.strip
  rescue StandardError
    false
  end
end

if options[:check]
  api_key_status = get_env_var("PERPLEXITY_API_KEY") != false
  model_name = get_env_var("PERPLEXITY_MODEL") || "false"
  puts({"API_KEY" => api_key_status, "MODEL" => model_name}.to_json)
  exit
end

def query(message: "", model: "sonar-medium-online")
  num_retrial = 0
  begin
    if File.file?("/.dockerenv")
      api_key = File.read("/monadic/data/.env").split("\n").find do |line|
        line.start_with?("PERPLEXITY_API_KEY")
      end.split("=").last
    else
      api_key ||= File.read("#{Dir.home}/monadic/data/.env").split("\n").find do |line|
        line.start_with?("PERPLEXITY_API_KEY")
      end.split("=").last
    end
  rescue StandardError
    puts "ERROR: API key not found."
    exit
  end

  headers = {
    "accept" => "application/json",
    "content-type" => "application/json",
    "authorization" => "Bearer #{api_key.strip}"
  }

  body = {
    "model" => model,
    "max_tokens" => 1000,
    "temperature" => 0.0,
    "top_p" => 0.0,
    "top_k" => 0.0
  }

  body["messages"] = [
    { "role" => "user", "content" => message }
  ]

  target_uri = "#{API_ENDPOINT}/chat/completions"
  http = HTTP.headers(headers)
  res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

  unless res.status.success?
    JSON.parse(res.body)["error"]
    "ERROR: #{JSON.parse(res.body)["error"]}"
  end

  results = JSON.parse(res.body).dig("choices", 0, "message", "content")
  results
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

message = ARGV[0]
if message.nil?
  puts "Usage: #{$PROGRAM_NAME} 'message' [model]"
  exit
end

begin
  model = ARGV[1] || "sonar-medium-online"
  response = query(message: message, model: model)
  puts response
rescue => e
  puts "An error occurred: #{e.message}"
  exit
end
