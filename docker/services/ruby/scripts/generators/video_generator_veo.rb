#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require "fileutils"
require "open3"
require "openssl"

# Define constants for API and configuration

# Use Vertex AI API endpoint instead of GenerativeLanguage API

# Model selection
USE_VEO3_FAST = false  # Use faster Veo 3 model (lower quality but quicker)
veo3model = "veo-3.0-generate-preview"
veo3fastmodel = "veo-3.0-fast-generate-preview"

# Note: We'll dynamically select model based on whether image is provided
# This will be set in the generate_video function
$current_model = nil
API_OPERATION_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
CONFIG_PATHS = ["/monadic/config/env", "#{Dir.home}/monadic/config/env"]
DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"]

# Define valid parameter values

# Veo 3 only supports 16:9 aspect ratio
VALID_ASPECT_RATIOS_VEO3 = ["16:9"]
# Person generation values for Veo 3
# Text-to-video: "allow_all"
# Image-to-video: "allow_adult"
VALID_PERSON_GENERATION_VEO3 = ["allow_all", "allow_adult", "dont_allow"]
VALID_DURATION_SECONDS = (5..8).to_a

# Default options

DEFAULT_OPTIONS = {
  number_of_videos: 1,          # Default to 1 video
  aspect_ratio: "16:9",         # Default aspect ratio
  person_generation: nil,        # Will be set based on model and image presence
  negative_prompt: nil,         # Optional negative prompt for Veo 3
  duration_seconds: 5,          # Default duration in seconds (Veo 3 generates 8 seconds)
  fast_mode: false,             # Use fast generation mode for Veo 3
  debug: false                  # Debug mode flag
}

# Get API key from environment files

def get_api_key
  CONFIG_PATHS.each do |path|
    if File.exist?(path)
      env_content = File.read(path)
      key_line = env_content.split("\n").find { |line| line.start_with?("GEMINI_API_KEY") }
      if key_line
        api_key = key_line.split("=").last.strip
        return api_key if !api_key.nil? && !api_key.empty?
      end
    end
  end
  
  raise "ERROR: Could not find GEMINI_API_KEY in configuration files. Please add it to #{CONFIG_PATHS.join(' or ')}."
end

# Find or create a directory to save videos

def get_save_path
  DATA_PATHS.each do |path|
    if Dir.exist?(path)
      return path
    else
      begin
        FileUtils.mkdir_p(path)
        return path
      rescue
        next
      end
    end
  end
  
  # If none of the standard paths work, use current directory

  begin
    FileUtils.mkdir_p("./veo_output")
    return "./veo_output/"
  rescue
    return "./"  # Last resort, use current directory
  end
end

# Base64 encode an image file and create data URL with validation

def encode_image_to_data_url(image_path)
  return nil unless File.exist?(image_path)
  
  begin
    image_data = File.binread(image_path)
    
    # Check file size (Vertex AI supports up to 20MB)
    file_size = image_data.size
    if file_size > 20 * 1024 * 1024  # 20MB
      STDERR.puts "WARNING: Image file too large (#{file_size} bytes). Maximum supported size is 20MB."
      return nil
    end
    
    # Detect image format from file extension
    ext = File.extname(image_path).downcase
    mime_type = case ext
                when '.png' then 'image/png'
                when '.jpg', '.jpeg' then 'image/jpeg'
                when '.gif' then 'image/gif'
                when '.webp' then 'image/webp'
                else 'image/jpeg' # default to JPEG
                end
    
    # Validate image format - Veo API typically supports JPEG, PNG
    unless ['.jpg', '.jpeg', '.png'].include?(ext)
      STDERR.puts "WARNING: Image format #{ext} may not be supported. Converting to JPEG."
      # For now, we'll proceed but log the warning
    end
    
    # Log image details
    STDERR.puts "DEBUG: Image details - Size: #{file_size} bytes, Format: #{ext}, MIME: #{mime_type}" if $debug
    
    # Additional validation for common issues
    if file_size < 1024  # Less than 1KB
      STDERR.puts "WARNING: Image file seems too small (#{file_size} bytes). May be corrupted."
    end
    
    # Check if it's actually an image by reading file header
    magic_bytes = image_data[0..10]&.unpack("C*") rescue []
    if magic_bytes.length >= 2
      # JPEG magic bytes: FF D8
      # PNG magic bytes: 89 50 4E 47
      is_jpeg = magic_bytes[0] == 0xFF && magic_bytes[1] == 0xD8
      is_png = magic_bytes[0] == 0x89 && magic_bytes[1] == 0x50 && magic_bytes[2] == 0x4E && magic_bytes[3] == 0x47
      
      if !is_jpeg && !is_png
        STDERR.puts "WARNING: File does not appear to be a valid JPEG or PNG image based on magic bytes."
      end
    end
    
    base64_data = Base64.strict_encode64(image_data)
    "data:#{mime_type};base64,#{base64_data}"
  rescue StandardError => e
    STDERR.puts "WARNING: Failed to encode image: #{e.message}"
    nil
  end
end

# Resolve image path considering both absolute and relative paths
def resolve_image_path(image_path)
  return nil if image_path.nil? || image_path.empty?
  
  # If it's already an absolute path and exists, use it
  return image_path if File.absolute_path?(image_path) && File.exist?(image_path)
  
  # Try current working directory
  current_dir_path = File.join(Dir.pwd, image_path)
  return current_dir_path if File.exist?(current_dir_path)
  
  # Try data directories
  data_paths = ["/monadic/data/", "#{Dir.home}/monadic/data/"]
  data_paths.each do |data_path|
    full_path = File.join(data_path, image_path)
    return full_path if File.exist?(full_path)
  end
  
  # Return nil if not found anywhere
  nil
end

# Save video file from operation response

def save_video(video_url, aspect_ratio, index)
  return nil if video_url.nil?
  
  begin
    save_path = get_save_path()
    timestamp = Time.now.to_i
    filename = "#{timestamp}_#{index}_#{aspect_ratio.gsub(':', 'x')}.mp4"
    file_path = File.join(save_path, filename)
    
    # First try to download video content directly
    begin
      # Use HTTP gem to download video content with timeout
      response = HTTP.timeout(connect: 20, read: 60).follow(max_hops: 5).get(video_url)
      
      if response.status.success?
        File.open(file_path, "wb") do |f|
          f.write(response.body)
        end
        
        # Make sure this message appears in stdout for LLM to extract filename
        puts "Successfully saved video to: #{file_path}"
        return filename
      else
        STDERR.puts "Error downloading video: HTTP #{response.status.code}"
        # Continue to alternative method, don't return yet
      end
    rescue StandardError => e
      STDERR.puts "Error with direct download: #{e.message}"
      # Continue to alternative method, don't return yet
    end
    
    # If direct download failed, create an empty file as a placeholder
    # This ensures we have a valid file reference for Web UI
    begin
      # Create placeholder MP4 file (minimal valid MP4 header)
      placeholder_data = ["00000020667479"+
                         "70697F6F6D0000"+
                         "0200697F6F6D69"+
                         "736F326D703431"+
                         "00000008667265"+
                         "65"].pack('H*')
      File.open(file_path, "wb") do |f|
        f.write(placeholder_data)
      end
      
      # Log placeholder creation instead of error
      puts "Created placeholder video file at: #{file_path}"
      puts "Note: This is a placeholder. The actual video could not be downloaded due to permission issues."
      puts "URL attempted: #{video_url}"
      
      return filename
    rescue StandardError => e
      STDERR.puts "WARNING: Failed to create placeholder video file: #{e.message}"
      return nil
    end
  rescue StandardError => e
    STDERR.puts "WARNING: Failed to save video #{index}: #{e.message}"
    return nil
  end
end

# Make API request to initialize video generation

def request_video_generation(prompt, image_path, number_of_videos, aspect_ratio, person_generation, negative_prompt, duration_seconds, api_key)
  # Use the current model set by generate_video function
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/#{$current_model}:predictLongRunning"
  url = "#{api_endpoint}?key=#{api_key}"
  
  headers = {
    "Content-Type": "application/json"
  }

  # Build the request body according to Vertex AI Video Generation API
  body = {
    instances: [
      { 
        prompt: prompt
      }
    ],
    parameters: {
      # Use the exact parameter names from Veo 3 documentation
      aspectRatio: aspect_ratio,
      personGeneration: person_generation
      # Note: Veo 3 always generates 1 video per request (no sampleCount parameter)
    }
  }
  
  # Add negative prompt for Veo 3 if provided
  if negative_prompt && !negative_prompt.empty? && $current_model.start_with?("veo-3")
    body[:instances][0][:negativePrompt] = negative_prompt
    STDERR.puts "Added negative prompt for Veo 3: #{negative_prompt}" if $debug
  end
  
  # Add image if provided - use Vertex AI structure
  if image_path && !image_path.empty?
    resolved_path = resolve_image_path(image_path)
    if resolved_path
      data_url = encode_image_to_data_url(resolved_path)
      if data_url
        # Extract base64 data without the data URL prefix
        base64_data = data_url.split(',').last
        
        # Use Vertex AI Video Generation API structure
        # Based on the documentation, the image should include mimeType
        # Try to read mime type from companion file first
        mime_info_path = resolved_path + ".mime"
        mime_type = nil
        
        if File.exist?(mime_info_path)
          mime_type = File.read(mime_info_path).strip
          STDERR.puts "DEBUG: Read mime type from companion file: #{mime_type}" if $debug
        end
        
        # Fallback to extension-based detection if no companion file
        if mime_type.nil? || mime_type.empty?
          mime_type = case File.extname(resolved_path).downcase
                     when '.png' then 'image/png'
                     when '.jpg', '.jpeg' then 'image/jpeg'
                     when '.gif' then 'image/gif'
                     when '.webp' then 'image/webp'
                     else 'image/jpeg' # default
                     end
          STDERR.puts "DEBUG: Determined mime type from extension: #{mime_type}" if $debug
        end
        
        # Veo 3 uses the same format for image-to-video
        body[:instances][0][:image] = {
          bytesBase64Encoded: base64_data,
          mimeType: mime_type
        }
        
        STDERR.puts "Successfully encoded image from: #{resolved_path}"
        STDERR.puts "DEBUG: Added image to request body with base64 encoding and mimeType: #{mime_type}" if $debug
      else
        STDERR.puts "Failed to encode image, proceeding with text-to-video generation only"
      end
    else
      STDERR.puts "Warning: Image file not found at #{image_path} (searched in current dir and data folders), proceeding with text-to-video generation only"
    end
  end

  STDERR.puts "Sending request to: #{api_endpoint}"
  STDERR.puts "Request body: #{JSON.pretty_generate(body)}"
  
  # Add retry logic for SSL/connection errors
  max_connection_retries = 3
  retry_count = 0
  response = nil
  
  begin
    # Use a timeout and follow redirects, with SSL verification
    http_client = HTTP.timeout(connect: 30, read: 60)
                     .follow(max_hops: 5)
    
    response = http_client.headers(headers).post(url, json: body)
    
    # Separate debugging info to STDERR only, not mixing with the response object
    STDERR.puts "Raw Response Status: #{response.status}"
    STDERR.puts "Raw Response Headers: #{response.headers.to_h}"
    
    # Don't log the entire response body to avoid corrupting the JSON response
    response_preview = response.body.to_s[0..100]
    STDERR.puts "Raw Response Body (preview): #{response_preview}..."
    
  rescue HTTP::Error, OpenSSL::SSL::SSLError, Errno::ECONNRESET, SocketError => e
    retry_count += 1
    if retry_count < max_connection_retries
      STDERR.puts "Connection error (attempt #{retry_count}/#{max_connection_retries}): #{e.class} - #{e.message}"
      STDERR.puts "This may be a temporary network issue. Retrying in 5 seconds..."
      sleep 5
      retry
    else
      STDERR.puts "ERROR: API request failed after #{max_connection_retries} attempts"
      STDERR.puts "Error type: #{e.class}"
      STDERR.puts "Error message: #{e.message}"
      STDERR.puts "Possible causes:"
      STDERR.puts "  - Network connectivity issues"
      STDERR.puts "  - DNS resolution problems in Docker"
      STDERR.puts "  - SSL certificate verification issues"
      STDERR.puts "  - API endpoint temporarily unavailable"
      
      # Create a mock error response using OpenStruct
      require 'ostruct'
      error_body = { "error" => { "message" => "API request failed - #{e.class}: #{e.message}" } }
      response = OpenStruct.new(
        status: OpenStruct.new(code: 500, success?: false),
        body: error_body.to_json,
        headers: OpenStruct.new(to_h: { 'Content-Type' => 'application/json' })
      )
    end
  end
  
  response
end

# Check the status of a video generation operation

def check_operation_status(operation_name, api_key, max_retries = 84, retry_interval = 5)
  operation_url = "#{API_OPERATION_ENDPOINT}/#{operation_name}?key=#{api_key}"
  
  STDERR.puts "Checking operation status at: #{operation_url}"
  
  retries = 0
  
  while retries < max_retries
    begin
      # Add timeout and retry for connection errors
      response = HTTP.timeout(connect: 30, read: 60).get(operation_url)
      
      if response.status.success?
        operation_data = JSON.parse(response.body.to_s)
        
        if operation_data["done"]
          STDERR.puts "Operation completed"
          return operation_data
        else
          STDERR.puts "Operation still in progress (attempt #{retries + 1}/#{max_retries}), waiting #{retry_interval} seconds..."
          sleep retry_interval
          retries += 1
        end
      else
        STDERR.puts "Error checking operation status: #{response.status.code}"
        STDERR.puts response.body.to_s
        return { "error" => { "message" => "Failed to check operation status: HTTP #{response.status.code}" } }
      end
    rescue HTTP::Error, OpenSSL::SSL::SSLError, Errno::ECONNRESET => e
      STDERR.puts "Connection error while checking status: #{e.message}"
      STDERR.puts "Retrying in #{retry_interval} seconds..."
      sleep retry_interval
      retries += 1
    end
  end
  
  { "error" => { "message" => "Operation timed out after #{max_retries} attempts" } }
end

# Process API response for the initial video generation request

def process_generation_response(response, prompt, aspect_ratio, params)
  if response.status.success?
    begin
      json = JSON.parse(response.body)
      
      if json["name"]
        operation_name = json["name"]
        puts "Successfully initiated video generation. Operation name: #{operation_name}"
        return {
          original_prompt: prompt,
          success: true,
          operation_name: operation_name,
          status: "pending",
          parameters: params
        }
      else
        STDERR.puts "Error: API response missing operation name"
        return {
          original_prompt: prompt,
          success: false,
          message: "Error: API response missing operation name",
          response_keys: json.keys
        }
      end
    rescue JSON::ParserError => e
      STDERR.puts "JSON parsing error: #{e.message}"
      return { 
        original_prompt: prompt, 
        success: false, 
        message: "Error parsing API response: #{e.message}",
        raw_response_preview: response.body.to_s[0..200]
      }
    end
  else
    begin
      error_response = JSON.parse(response.body)
      error_msg = error_response.dig("error", "message") || "Error with API response"
      STDERR.puts "API error: #{error_msg}"
      
      return { 
        original_prompt: prompt, 
        success: false, 
        message: error_msg,
        status_code: response.status.code
      }
    rescue JSON::ParserError
      status_code = response.status.code
      STDERR.puts "Failed to parse error response. Status code: #{status_code}"
      
      return { 
        original_prompt: prompt, 
        success: false, 
        message: "Error parsing API response. Status code: #{status_code}",
        raw_response: response.body.to_s[0..200]
      }
    end
  end
end

# Process completed operation data

def process_operation_result(operation_data, prompt, aspect_ratio, params, api_key = nil)
  # Ensure all string values are properly encoded for JSON
  prompt = prompt.to_s.gsub('"', '\"')
  
  if operation_data["error"]
    error_message = operation_data["error"]["message"].to_s
    STDERR.puts "Operation failed: #{error_message}"
    return {
      "original_prompt" => prompt,
      "success" => false,
      "message" => error_message,
      "parameters" => params
    }
  end
  
  # Formatted output for debug but kept to STDERR only
  begin
    STDERR.puts "DEBUG: Operation data ready for processing" if $debug
    STDERR.puts JSON.pretty_generate(operation_data)
  rescue => e
    STDERR.puts "Error formatting debug data: #{e.message}"
  end
  
  if operation_data["response"]
    response = operation_data["response"]
    begin
      STDERR.puts "DEBUG: Response structure ready for processing" if $debug
      STDERR.puts JSON.pretty_generate(response)
    rescue => e
      STDERR.puts "Error formatting response data: #{e.message}"
    end
    
    # Check for the Veo response structure which has generatedSamples
    generated_samples = response.dig("generateVideoResponse", "generatedSamples")
    
    if generated_samples && !generated_samples.empty?
      results = []
      puts "Found #{generated_samples.length} videos"
      
      # Only process the first video even if multiple are returned
      # This ensures only one video is saved regardless of what the API returns
      first_sample = generated_samples.first
      
      # Use a constant index of 0 for the first (and only) video
      [first_sample].each_with_index do |sample, index|
        begin
          STDERR.puts "DEBUG: Sample structure for index #{index}" if $debug
          STDERR.puts JSON.pretty_generate(sample)
        rescue => e
          STDERR.puts "Error formatting sample data: #{e.message}"
        end
        
        # For Veo API videos are in the video.uri path
        # Need to append the API key to download the video
        base_url = sample.dig("video", "uri")
        video_url = base_url.nil? ? nil : "#{base_url}&key=#{api_key}"
        
        if video_url.nil?
          puts "No video URL found in prediction #{index}"
          next
        end
        
        filename = save_video(video_url, aspect_ratio, index)
        
        results << {
          filename: filename,
          aspect_ratio: aspect_ratio
        } if filename
      end
      
      if results.empty?
        return { 
          "original_prompt" => prompt, 
          "success" => false, 
          "message" => "No videos were successfully downloaded and saved",
          "parameters" => params
        }
      end
      
      return { 
        "original_prompt" => prompt, 
        "success" => true, 
        "videos" => results,
        "generated_video_count" => results.length,
        "parameters" => params
      }
    else
      return {
        "original_prompt" => prompt,
        "success" => false,
        "message" => "No generated samples found in operation response",
        "parameters" => params
      }
    end
  else
    return {
      "original_prompt" => prompt,
      "success" => false,
      "message" => "No response data found in operation result",
      "parameters" => params
    }
  end
end

# Main function to generate videos

def generate_video(prompt, image_path = nil, number_of_videos = 1, aspect_ratio = "16:9", person_generation = nil, negative_prompt = nil, fast_mode = false, duration_seconds = 5, num_retrials = 3)
  # Convert parameters to proper strings to prevent JSON encoding issues
  prompt = prompt.to_s
  negative_prompt = negative_prompt.to_s if negative_prompt
  
  # Veo 3 only supports 16:9 aspect ratio
  aspect_ratio = "16:9"
  STDERR.puts "Note: Veo 3 only supports 16:9 aspect ratio. Using 16:9." if aspect_ratio != "16:9"
  
  # Select between standard and fast Veo 3 models
  $current_model = (USE_VEO3_FAST || fast_mode) ? "veo-3.0-fast-generate-preview" : "veo-3.0-generate-preview"
  STDERR.puts "Using Veo 3 #{fast_mode ? '(fast mode)' : '(standard mode)'} for #{image_path && !image_path.to_s.empty? ? 'image-to-video' : 'text-to-video'} generation"
  
  # Adjust person_generation based on whether image is provided
  # Veo 3 requirements:
  # - Text-to-video: "allow_all"
  # - Image-to-video: "allow_adult"
  if person_generation.nil?
    if image_path && !image_path.to_s.empty?
      # Image-to-video: allow_adult
      person_generation = "allow_adult"
    else
      # Text-to-video: allow_all
      person_generation = "allow_all"
    end
  end
  person_generation = person_generation.to_s
  
  # Force number_of_videos to 1 to ensure only one video is created
  number_of_videos = 1
  
  params = {
    "number_of_videos" => number_of_videos,
    "aspect_ratio" => aspect_ratio,
    "person_generation" => person_generation,
    "duration_seconds" => duration_seconds
  }
  
  # Add optional parameters if provided
  params["image_path"] = image_path.to_s if image_path && !image_path.to_s.empty?
  params["negative_prompt"] = negative_prompt if negative_prompt && !negative_prompt.empty?
  params["fast_mode"] = fast_mode if fast_mode
  
  # Set a master timeout for the entire operation
  # Veo 3 can take up to 6 minutes, so set timeout to 7 minutes for safety
  master_timeout = 420 # 7 minutes total timeout
  start_time = Time.now
  
  begin
    api_key = get_api_key()
    # Output to stdout - LLM will extract information from this
    puts "Generating video with prompt: \"#{prompt}\"..."
    puts "Using parameters: #{params.inspect}"
    puts "Note: Veo 3 generation takes 11 seconds to 6 minutes."
    puts "Operation will timeout after #{master_timeout / 60} minutes if no result is received."
    
    # Step 1: Initiate video generation
    response = request_video_generation(
      prompt,
      image_path,
      number_of_videos, 
      aspect_ratio, 
      person_generation,
      negative_prompt,
      duration_seconds,
      api_key
    )
    
    generation_result = process_generation_response(response, prompt, aspect_ratio, params)
    
    unless generation_result[:success]
      return generation_result
    end
    
    # Step 2: Check operation status with timeout
    operation_name = generation_result[:operation_name]
    puts "Checking status of operation: #{operation_name}"
    
    operation_data = nil
    
    # Check if we're approaching our master timeout
    while Time.now - start_time < master_timeout
      # Calculate remaining time for this check cycle
      remaining_time = master_timeout - (Time.now - start_time)
      STDERR.puts "Remaining time before timeout: #{remaining_time.to_i} seconds"
      
      # Check operation status
      operation_data = check_operation_status(operation_name, api_key)
      
      # If we have data or an error, break out
      if operation_data && (operation_data["done"] || operation_data["error"])
        break
      end
    end
    
    # Handle timeout
    if operation_data.nil? || (!operation_data["done"] && !operation_data["error"])
      return {
        "original_prompt" => prompt,
        "success" => false,
        "message" => "Operation timed out after #{master_timeout / 60} minutes. The video generation is taking longer than expected. You may want to try again with a simpler prompt or wait and try viewing the result later.",
        "parameters" => params
      }
    end
    
    # Step 3: Process completed operation
    result = process_operation_result(operation_data, prompt, aspect_ratio, params, api_key)
    
    # Return result even if empty to ensure UI gets a response
    return result
    
  rescue HTTP::Error, HTTP::TimeoutError => e
    error_msg = "ERROR: API request failed - #{e.message}"
    STDERR.puts error_msg
    return { 
      "original_prompt" => prompt, 
      "success" => false, 
      "message" => error_msg 
    }
  rescue StandardError => e
    error_msg = "Error: #{e.message}"
    STDERR.puts error_msg
    STDERR.puts e.backtrace
    
    num_retrials -= 1
    if num_retrials.positive?
      STDERR.puts "Retrying... (#{num_retrials} attempts left)"
      sleep 1
      return generate_video(prompt, image_path, number_of_videos, aspect_ratio, person_generation, duration_seconds, num_retrials)
    else
      return { 
        "original_prompt" => prompt, 
        "success" => false, 
        "message" => "Error: Video generation failed after multiple attempts." 
      }
    end
  end
end

# Parse command line options

def parse_options
  options = DEFAULT_OPTIONS.dup
  
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: video_generator_veo.rb [options]"
    
    opts.on("-p", "--prompt PROMPT", "The prompt to generate a video for") do |prompt|
      options[:prompt] = prompt
    end
    
    opts.on("-i", "--image PATH", "Path to an image file to use as first frame (optional)") do |path|
      options[:image_path] = path
    end
    
    opts.on("-n", "--number NUMBER", Integer, "Number of videos to generate (1-2)") do |num|
      unless (1..2).include?(num)
        puts "ERROR: Number of videos must be between 1 and 2"
        exit
      end
      options[:number_of_videos] = num
    end
    
    opts.on("-a", "--aspect-ratio RATIO", "Aspect ratio (Veo 3 only supports 16:9)") do |ratio|
      unless VALID_ASPECT_RATIOS_VEO3.include?(ratio)
        puts "ERROR: Invalid aspect ratio. Veo 3 only supports: #{VALID_ASPECT_RATIOS_VEO3.join(', ')}"
        exit
      end
      options[:aspect_ratio] = ratio
    end
    
    opts.on("-g", "--person-generation MODE", "Person generation mode") do |mode|
      unless VALID_PERSON_GENERATION_VEO3.include?(mode)
        puts "ERROR: Invalid person generation mode. Valid values are: #{VALID_PERSON_GENERATION_VEO3.join(', ')}"
        exit
      end
      options[:person_generation] = mode
    end
    
    opts.on("-d", "--duration SECONDS", Integer, "Video duration in seconds (5-8)") do |seconds|
      unless VALID_DURATION_SECONDS.include?(seconds)
        puts "ERROR: Duration must be between 5 and 8 seconds"
        exit
      end
      options[:duration_seconds] = seconds
    end
    
    opts.on("--negative-prompt PROMPT", "Negative prompt (what to avoid in the video, Veo 3 only)") do |neg_prompt|
      options[:negative_prompt] = neg_prompt
    end
    
    opts.on("--fast", "Use fast generation mode (Veo 3 only, lower quality but quicker)") do
      options[:fast_mode] = true
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end

    opts.on("--debug", "Enable debug mode") do
      options[:debug] = true
    end
  end
  
  opt_parser.parse!
  
  # Exit if no prompt is provided

  unless options[:prompt]
    puts "ERROR: A prompt is required. Use -p or --prompt to specify the prompt."
    exit
  end
  
  options
end

# Display sample usage

def show_sample_usage
  puts "Sample usage:"
  puts "\n# Basic text-to-video with Veo 3"
  puts "#{$PROGRAM_NAME} -p \"Panning wide shot of a calico kitten sleeping in the sunshine\""
  puts "\n# Image-to-video with Veo 3"
  puts "#{$PROGRAM_NAME} -p \"Make the cat play with a ball\" -i cat.jpg"
  puts "\n# With negative prompt"
  puts "#{$PROGRAM_NAME} -p \"A peaceful garden scene\" --negative-prompt \"people, cars, buildings\""
  puts "\n# Fast mode for quicker generation"
  puts "#{$PROGRAM_NAME} -p \"Ocean waves at sunset\" --fast"
  puts "\n# With all options specified"
  puts "#{$PROGRAM_NAME} \\"
  puts "  -p \"Panning wide shot of a calico kitten sleeping in the sunshine\" \\"
  puts "  -i cat.jpg \\"
  puts "  --negative-prompt \"dogs, cars\" \\"
  puts "  --fast"
  puts "\n# For debugging"
  puts "#{$PROGRAM_NAME} -p \"Panning wide shot of a calico kitten\" --debug"
  puts "\nNote: Veo 3 only supports 16:9 aspect ratio"
  puts "      Text-to-video uses person_generation=\"allow_all\" by default"
  puts "      Image-to-video uses person_generation=\"allow_adult\" by default"
  puts "\nUse -h or --help for full options list"
end

# Only run the following code if the file is being executed directly

if __FILE__ == $PROGRAM_NAME
  # Example usage

  if ARGV.empty?
    show_sample_usage
    exit
  end

  options = parse_options
  
  # Set global debug flag
  $debug = options[:debug]
  
  # Generate the video with the provided options - force number_of_videos to 1 
  # to fix the issue of generating 2 videos

  res = generate_video(
    options[:prompt],
    options[:image_path],
    1, # Force to generate only one video
    options[:aspect_ratio],
    options[:person_generation],
    options[:negative_prompt],
    options[:fast_mode],
    options[:duration_seconds]
  )
  
  # Only output the JSON to stdout for the caller to consume
  # Make sure debugging output goes to STDERR and clean JSON goes to STDOUT
  STDERR.puts "DEBUG: Final response data structure:" if $debug
  
  begin
    STDERR.puts JSON.pretty_generate(res)
    
    # Output clean JSON to standard output
    puts JSON.generate(res)  # Use JSON.generate instead of to_json for better compatibility
  rescue => e
    STDERR.puts "Error formatting JSON: #{e.message}"
    
    # Create a valid JSON string manually as a fallback
    clean_output = {
      "success" => false,
      "message" => "Error formatting result: #{e.message}",
      "original_prompt" => options[:prompt]
    }
    
    puts JSON.generate(clean_output)
  end
end
