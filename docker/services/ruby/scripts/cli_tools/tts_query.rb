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
  # Try ENV first (for test environment)
  elevenlabs_api_key = ENV["ELEVENLABS_API_KEY"]
  
  # Fall back to reading config file
  unless elevenlabs_api_key
    begin
      elevenlabs_api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }&.split("=")&.last
    rescue Errno::ENOENT
      begin
        elevenlabs_api_key = File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }&.split("=")&.last
      rescue Errno::ENOENT
        # Config file not found
      end
    end
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
    # Try ENV first (for test environment)
    api_key = ENV["ELEVENLABS_API_KEY"]
    
    # Fall back to reading config file
    unless api_key
      begin
        api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }&.split("=")&.last
      rescue Errno::ENOENT
        begin
          api_key = File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("ELEVENLABS_API_KEY") }&.split("=")&.last
        rescue Errno::ENOENT
          # Config file not found
        end
      end
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
    
    # Add voice settings including speed if not default
    # ElevenLabs speed range is typically 0.5 to 2.0, but we'll map from OpenAI's 0.25-4.0 range
    if speed.to_f != 1.0
      # Map OpenAI speed range (0.25-4.0) to ElevenLabs range (approx 0.5-2.0)
      elevenlabs_speed = if speed.to_f < 0.5
                          0.5
                        elsif speed.to_f > 2.0
                          2.0
                        else
                          speed.to_f
                        end
      
      body["voice_settings"] = {
        "stability" => 0.5,
        "similarity_boost" => 0.75,
        "speed" => elevenlabs_speed
      }
    end

    unless language == "auto"
      body["language_code"] = language
    end

    unless instructions == ""
      body["instructions"] = instructions
    end

    output_format = "mp3_44100_128"
    target_uri = "https://api.elevenlabs.io/v1/text-to-speech/#{voice}?output_format=#{output_format}"
  when "gemini"
    # Try ENV first (for test environment)
    api_key = ENV["GEMINI_API_KEY"]
    
    # Fall back to reading config file
    unless api_key
      begin
        api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("GEMINI_API_KEY") }&.split("=")&.last
      rescue Errno::ENOENT
        begin
          api_key = File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("GEMINI_API_KEY") }&.split("=")&.last
        rescue Errno::ENOENT
          # Config file not found
        end
      end
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
        "responseModalities" => ["AUDIO"],
        "speechConfig" => {
          "voiceConfig" => {
            "prebuiltVoiceConfig" => {
              "voiceName" => voice.to_s.downcase
            }
          }
        }
      }
    }
    
    # Use the Gemini 2.5 Flash Preview TTS model
    target_uri = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=#{api_key}"
  else # openai
    # Try ENV first (for test environment)
    api_key = ENV["OPENAI_API_KEY"]
    
    # Fall back to reading config file
    unless api_key
      begin
        api_key = File.read("/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }&.split("=")&.last
      rescue Errno::ENOENT
        begin
          api_key = File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line| line.start_with?("OPENAI_API_KEY") }&.split("=")&.last
        rescue Errno::ENOENT
          # Config file not found
        end
      end
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
      error_report = JSON.parse(res.body.to_s) rescue { "error" => { "message" => res.body.to_s } }
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
          decoded_audio = Base64.decode64(audio_data)
          
          # Log the actual format received
          STDERR.puts "INFO: Gemini returned audio in #{mime_type} format"
          
          # Handle PCM audio data by adding WAV header if needed
          if mime_type && mime_type.include?("L16") && mime_type.include?("pcm")
            # Extract sample rate from mime type
            sample_rate = 24000  # Default
            if mime_type =~ /rate=(\d+)/
              sample_rate = $1.to_i
            end
            
            # Create WAV header for 16-bit mono PCM
            require 'stringio'
            wav_data = StringIO.new
            wav_data.binmode
            
            # Write WAV header
            channels = 1
            bits_per_sample = 16
            byte_rate = sample_rate * channels * bits_per_sample / 8
            block_align = channels * bits_per_sample / 8
            data_size = decoded_audio.bytesize
            
            wav_data.write("RIFF")
            wav_data.write([36 + data_size].pack("V"))  # File size - 8
            wav_data.write("WAVE")
            wav_data.write("fmt ")
            wav_data.write([16].pack("V"))              # Subchunk1Size
            wav_data.write([1].pack("v"))               # AudioFormat (1 = PCM)
            wav_data.write([channels].pack("v"))        # NumChannels
            wav_data.write([sample_rate].pack("V"))     # SampleRate
            wav_data.write([byte_rate].pack("V"))       # ByteRate
            wav_data.write([block_align].pack("v"))     # BlockAlign
            wav_data.write([bits_per_sample].pack("v")) # BitsPerSample
            wav_data.write("data")
            wav_data.write([data_size].pack("V"))       # Subchunk2Size
            wav_data.write(decoded_audio)
            
            decoded_audio = wav_data.string
            mime_type = "audio/wav"
          end
          
          # Return both audio data and mime type for proper file extension handling
          response = {
            audio_data: decoded_audio,
            mime_type: mime_type
          }
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
#   tts_query.rb --list
#
# To convert text to speech:
#   tts_query.rb <textfile> --provider=<provider> --speed=<speed> --voice=<voice> --language=<language>

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
  
  # Determine file extension based on provider and response
  file_extension = if provider == "gemini" && response.is_a?(Hash) && response[:mime_type]
    # Extract extension from mime type (e.g., "audio/wav" -> "wav")
    mime_ext = response[:mime_type].split("/").last
    # Default to wav if we can't determine the format
    %w[mp3 wav ogg flac aac].include?(mime_ext) ? mime_ext : "wav"
  else
    "mp3"
  end
  
  filename = "#{outfile}.#{file_extension}"
  file_path = File.join(save_path, filename)

  # Save the audio file
  audio_content = if provider == "gemini" && response.is_a?(Hash)
    response[:audio_data]
  else
    response
  end

  File.open(file_path, "wb") do |f|
    f.write(audio_content)
  end

  # Save a copy in the current directory (skip for Gemini to avoid issues)
  if provider != "gemini"
    File.write(outfile, response)
  end
  
  # Display appropriate message based on file format
  if provider == "gemini" && file_extension != "mp3"
    puts "Text-to-speech audio saved to #{filename} (#{file_extension.upcase} format)"
  else
    puts "Text-to-speech audio MP3 saved to #{filename}"
  end
rescue StandardError => e
  puts "An error occurred: #{e.message}"
  puts e.backtrace.join("\n")
end
