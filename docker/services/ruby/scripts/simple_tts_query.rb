#!/usr/bin/env ruby

require "http"
require "json"
require "net/http"

API_ENDPOINT = "https://api.openai.com/v1"
OPEN_TIMEOUT = 10
READ_TIMEOUT = 60
WRITE_TIMEOUT = 60
MAX_RETRIES = 5
RETRY_DELAY = 1

def list_openai_voices
  %w(alloy ash ballad coral echo fable onyx nova sage shimmer).map do |voice|
    {
      "name" => voice.capitalize,
      "voice_id" => voice
    }
  end
end

def list_elevenlabs_voices
  begin
    elevenlabs_api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }.split("=").last
  rescue Errno::ENOENT
    elevenlabs_api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }.split("=").last
  end

  return [] unless elevenlabs_api_key

  begin
    url = URI("https://api.elevenlabs.io/v1/voices")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(url)
    request["xi-api-key"] = elevenlabs_api_key
    response = http.request(request)
    voices = response.read_body
    JSON.parse(voices)&.dig("voices")&.map do |voice|
      {
        "display_name" => voice["name"],
        "voice_id" => voice["voice_id"]
      }
    end
  rescue StandardError => e
    []
  end
end

def list_gemini_voices
  # Gemini TTS voices - updated based on API response
  [
    { "name" => "Aoede", "voice_id" => "aoede" },
    { "name" => "Charon", "voice_id" => "charon" },
    { "name" => "Fenrir", "voice_id" => "fenrir" },
    { "name" => "Kore", "voice_id" => "kore" },
    { "name" => "Orus", "voice_id" => "orus" },
    { "name" => "Puck", "voice_id" => "puck" },
    { "name" => "Schedar", "voice_id" => "schedar" },
    { "name" => "Zephyr", "voice_id" => "zephyr" }
  ]
end

def list_providers
  providers = {
    "openai" => {
      "name" => "openai",
      "voices" => list_openai_voices,
    },
    "elevenlabs" => {
      "name" => "elevenlabs",
      "voices" => list_elevenlabs_voices
    },
    "gemini" => {
      "name" => "gemini",
      "voices" => list_gemini_voices
    }
  }

  # remove empty providers
  providers.reject { |_, provider| provider["voices"].empty? }
end

def tts_api_request(text,
                    provider: "openai",
                    response_format: "mp3",
                    speed: "1.0",
                    voice: "alloy",
                    language: "auto",
                    instructions: ""
                   )
  num_retrial = 0
  response = nil

  case provider
  when "elevenlabs", "elevenlabs-flash", "elevenlabs-multilingual"
    api_key = nil
    begin
      api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }.split("=").last
    rescue Errno::ENOENT
      api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }.split("=").last
    end

    if api_key.nil?
      return { type: "error", content: "ERROR: ELEVENLABS_API_KEY is not set." }
    end
    
    model = case provider
            when "elevenlabs-multilingual"
              "eleven_multilingual_v2"
            when "elevenlabs-flash", "elevenlabs"
              "eleven_flash_v2_5"
            else
              "eleven_flash_v2_5"
            end
    
    headers = {
      "Content-Type" => "application/json",
      "xi-api-key" => api_key
    }
    body = {
      "text" => text,
      "model_id" => model,
    }

    unless language == "auto"
      body["language_code"] = language
    end

    unless instructions == ""
      body["instructions"] = instructions
    end

    output_format = "mp3_44100_128"
    target_uri = "https://api.elevenlabs.io/v1/text-to-speech/#{voice}?output_format=#{output_format}"
  when "gemini"
    api_key = nil
    begin
      api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("GEMINI_API_KEY") }.split("=").last
    rescue Errno::ENOENT
      api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("GEMINI_API_KEY") }.split("=").last
    end

    if api_key.nil?
      return { type: "error", content: "ERROR: GEMINI_API_KEY is not set." }
    end

    # Import HTTP for API calls
    require 'json'
    
    headers = {
      "Content-Type" => "application/json"
    }
    
    # Construct the text with voice instructions (lowercase voice names)
    voice_instruction = case voice.downcase
    when "zephyr"
      "Say cheerfully with bright tone: "
    when "puck"
      "Say with upbeat energy: "
    when "charon"
      "Say in an informative tone: "
    when "kore"
      "Say warmly: "
    when "fenrir"
      "Say expressively: "
    when "aoede"
      "Say creatively: "
    when "orus"
      "Say clearly: "
    when "schedar"
      "Say professionally: "
    else
      ""
    end
    
    prompt_text = voice_instruction + text
    
    body = {
      "contents" => [{
        "parts" => [{
          "text" => prompt_text
        }]
      }],
      "generationConfig" => {
        "response_modalities" => ["AUDIO"],
        "speech_config" => {
          "voice_config" => {
            "prebuilt_voice_config" => {
              "voice_name" => voice.to_s.downcase
            }
          }
        }
      }
    }
    
    # Use the Gemini 2.5 Flash model with TTS capability (default)
    target_uri = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=#{api_key}"
  else # openai
    begin
      api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
    rescue Errno::ENOENT
      api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }.split("=").last
    end

    if api_key.nil?
      return { type: "error", content: "ERROR: OPENAI_API_KEY is not set." }
    end

    headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    }

    model = "gpt-4o-mini-tts"

    body = {
      input: text,
      model: model,
      voice: voice,
      response_format: response_format
    }
    
    # Only add speed if it's not 1.0
    if speed.to_f != 1.0
      body[:speed] = speed.to_f
    end

    unless language == "auto"
      body["language"] = language
    end

    target_uri = "#{API_ENDPOINT}/audio/speech"
  end

  http = HTTP.headers(headers)
  begin
    res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)
    unless res.status.success?
      error_report = JSON.parse(res.body.to_s)
      error_message = error_report["error"] ? error_report["error"]["message"] : "API request failed"
      return { type: "error", content: "ERROR: #{error_message}" }
    end
    
    # Handle Gemini response format
    if provider == "gemini"
      begin
        gemini_response = JSON.parse(res.body.to_s)
        
        # Extract audio data from Gemini response
        if gemini_response["candidates"] && 
           gemini_response["candidates"][0] && 
           gemini_response["candidates"][0]["content"] && 
           gemini_response["candidates"][0]["content"]["parts"] &&
           gemini_response["candidates"][0]["content"]["parts"][0] &&
           gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]
          
          audio_data = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
          mime_type = gemini_response["candidates"][0]["content"]["parts"][0]["inlineData"]["mimeType"]
          
          # Decode base64 audio data
          require 'base64'
          response = Base64.decode64(audio_data)
        else
          return { type: "error", content: "ERROR: Invalid response format from Gemini API" }
        end
      rescue JSON::ParserError => e
        return { type: "error", content: "ERROR: Failed to parse Gemini response: #{e.message}" }
      end
    else
      response = res.body
    end
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

# To list providers and voices:
#   simple_tts_query.rb --list
#
# To convert text to speech:
#   simple_tts_query.rb <textfile> --provider=<provider> --speed=<speed> --voice=<voice> --language=<language>

# Check if --list option is specified

if ARGV.include?("--list")
  providers = list_providers
  puts JSON.pretty_generate(providers)
  exit 0
end

# Get the text file path from command line arguments

textpath = ARGV[0]

# Validate text file

unless textpath && File.exist?(textpath)
  puts "ERROR: Text file not found or not provided."
  puts "Usage:"
  puts "  To list providers and voices:"
  puts "    #{$PROGRAM_NAME} --list"
  puts "  To convert text to speech:"
  puts "    #{$PROGRAM_NAME} <textfile> --provider=<provider> --speed=<speed> --voice=<voice> --language=<language>"
  exit 1
end

# Read the text content

text = File.read(textpath)

# Parse command line options with default values

provider = ARGV.find { |arg| arg.start_with?("--provider=") }&.split("=")&.last || "openai"
speed = ARGV.find { |arg| arg.start_with?("--speed=") }&.split("=")&.last || "1.0"
voice = ARGV.find { |arg| arg.start_with?("--voice=") }&.split("=")&.last || "alloy"
# If language is not specified, "auto" is used by default

language = ARGV.find { |arg| arg.start_with?("--language=") }&.split("=")&.last || "auto"

response_format = "mp3"

# Validate text content

if text.nil? || text.empty?
  puts "ERROR: No text content in the file."
  exit 1
end

begin
  # Make API request to convert text to speech

  response = tts_api_request(text,
                           provider: provider,
                           response_format: response_format,
                           speed: speed,
                           voice: voice,
                           language: language)

  # Handle API error response

  if response.is_a?(Hash) && response["type"] == "error"
    puts response["content"]
    exit 1
  end

  # Define save paths

  primary_save_path = "/monadic/data/"
  secondary_save_path = File.expand_path("~/monadic/data/")

  # Select appropriate save path based on directory existence

  save_path = Dir.exist?(primary_save_path) ? primary_save_path : secondary_save_path

  # Create output filename from input filename

  outfile = File.basename(textpath, ".*")
  filename = "#{outfile}.mp3"
  file_path = File.join(save_path, filename)

  # Save the audio file

  File.open(file_path, "wb") do |f|
    f.write(response)
  end

  # Save a copy in the current directory

  File.write(outfile, response)
  puts "Text-to-speech audio MP3 saved to #{filename}"
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts e.backtrace.join("\n")
end
