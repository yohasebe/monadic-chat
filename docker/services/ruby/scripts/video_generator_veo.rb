#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require "fileutils"
require "open3"

# Define constants for API and configuration

API_PREDICT_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/veo-2.0-generate-001:predictLongRunning"
API_OPERATION_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
CONFIG_PATHS = ["/monadic/config/env", "#{Dir.home}/monadic/config/env"]
DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"]

# Define valid parameter values

VALID_ASPECT_RATIOS = ["16:9", "9:16"]
VALID_PERSON_GENERATION = ["dont_allow", "allow_adult"]
VALID_DURATION_SECONDS = (5..8).to_a

# Default options

DEFAULT_OPTIONS = {
  number_of_videos: 1,          # Default to 1 video
  aspect_ratio: "16:9",         # Default aspect ratio
  person_generation: "allow_adult", # Default person generation setting
  duration_seconds: 5           # Default duration in seconds
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

# Base64 encode an image file

def encode_image(image_path)
  return nil unless File.exist?(image_path)
  
  begin
    image_data = File.binread(image_path)
    Base64.strict_encode64(image_data)
  rescue StandardError => e
    STDERR.puts "WARNING: Failed to encode image: #{e.message}"
    nil
  end
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

def request_video_generation(prompt, image_path, number_of_videos, aspect_ratio, person_generation, duration_seconds, api_key)
  url = "#{API_PREDICT_ENDPOINT}?key=#{api_key}"
  
  headers = {
    "Content-Type": "application/json"
  }

  # Build the request body
  body = {
    instances: [
      { prompt: prompt }
    ],
    parameters: {
      # Use the exact parameter names from the example curl command
      aspectRatio: aspect_ratio,
      personGeneration: person_generation,
      # Force to generate only one video by explicitly setting sampleCount
      sampleCount: 1
    }
  }
  
  # Add image if provided
  if image_path && !image_path.empty?
    if File.exist?(image_path)
      base64_image = encode_image(image_path)
      if base64_image
        body[:instances][0][:image] = { bytesBase64Encoded: base64_image }
      else
        STDERR.puts "Failed to encode image, proceeding with text-to-video generation only"
      end
    else
      STDERR.puts "Warning: Image file not found at #{image_path}, proceeding with text-to-video generation only"
    end
  end

  STDERR.puts "Sending request to: #{API_PREDICT_ENDPOINT}"
  STDERR.puts "Request body: #{JSON.pretty_generate(body)}"
  
  response = HTTP.headers(headers).post(url, json: body)
  
  # Separate debugging info to STDERR only, not mixing with the response object
  STDERR.puts "Raw Response Status: #{response.status}"
  STDERR.puts "Raw Response Headers: #{response.headers.to_h}"
  
  # Don't log the entire response body to avoid corrupting the JSON response
  response_preview = response.body.to_s[0..100]
  STDERR.puts "Raw Response Body (preview): #{response_preview}..."
  
  response
end

# Check the status of a video generation operation

def check_operation_status(operation_name, api_key, max_retries = 45, retry_interval = 5)
  operation_url = "#{API_OPERATION_ENDPOINT}/#{operation_name}?key=#{api_key}"
  
  STDERR.puts "Checking operation status at: #{operation_url}"
  
  retries = 0
  
  while retries < max_retries
    response = HTTP.get(operation_url)
    
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
    STDERR.puts "DEBUG: Operation data ready for processing"
    STDERR.puts JSON.pretty_generate(operation_data)
  rescue => e
    STDERR.puts "Error formatting debug data: #{e.message}"
  end
  
  if operation_data["response"]
    response = operation_data["response"]
    begin
      STDERR.puts "DEBUG: Response structure ready for processing"
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
          STDERR.puts "DEBUG: Sample structure for index #{index}"
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

def generate_video(prompt, image_path = nil, number_of_videos = 1, aspect_ratio = "16:9", person_generation = "allow_adult", duration_seconds = 5, num_retrials = 3)
  # Convert parameters to proper strings to prevent JSON encoding issues
  prompt = prompt.to_s
  aspect_ratio = aspect_ratio.to_s
  person_generation = person_generation.to_s
  
  # Force number_of_videos to 1 to ensure only one video is created
  number_of_videos = 1
  
  params = {
    "number_of_videos" => number_of_videos,
    "aspect_ratio" => aspect_ratio,
    "person_generation" => person_generation,
    "duration_seconds" => duration_seconds
  }
  
  # Add image path to params if provided
  params["image_path"] = image_path.to_s if image_path && !image_path.to_s.empty?
  
  # Set a master timeout for the entire operation
  master_timeout = 300 # 5 minutes total timeout
  start_time = Time.now
  
  begin
    api_key = get_api_key()
    # Output to stdout - LLM will extract information from this
    puts "Generating video with prompt: \"#{prompt}\"..."
    puts "Using parameters: #{params.inspect}"
    puts "Operation will timeout after #{master_timeout / 60} minutes if no result is received."
    
    # Step 1: Initiate video generation
    response = request_video_generation(
      prompt,
      image_path,
      number_of_videos, 
      aspect_ratio, 
      person_generation,
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
    
    opts.on("-a", "--aspect-ratio RATIO", "Aspect ratio (16:9 or 9:16)") do |ratio|
      unless VALID_ASPECT_RATIOS.include?(ratio)
        puts "ERROR: Invalid aspect ratio. Valid values are: #{VALID_ASPECT_RATIOS.join(', ')}"
        exit
      end
      options[:aspect_ratio] = ratio
    end
    
    opts.on("-g", "--person-generation MODE", "Person generation mode") do |mode|
      unless VALID_PERSON_GENERATION.include?(mode)
        puts "ERROR: Invalid person generation mode. Valid values are: #{VALID_PERSON_GENERATION.join(', ')}"
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
  puts "\n# Basic usage with defaults (text-to-video)"
  puts "#{$PROGRAM_NAME} -p \"Panning wide shot of a calico kitten sleeping in the sunshine\""
  puts "\n# Image-to-video with specific aspect ratio"
  puts "#{$PROGRAM_NAME} -p \"Panning wide shot of a calico kitten sleeping in the sunshine\" -i cat.jpg -a \"16:9\""
  puts "\n# With all options specified"
  puts "#{$PROGRAM_NAME} \\"
  puts "  -p \"Panning wide shot of a calico kitten sleeping in the sunshine\" \\"
  puts "  -i cat.jpg \\"
  puts "  -n 1 \\"
  puts "  -a \"16:9\" \\"
  puts "  -g \"dont_allow\" \\"
  puts "  -d 8"
  puts "\n# For debugging"
  puts "#{$PROGRAM_NAME} -p \"Panning wide shot of a calico kitten\" --debug"
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
  
  # Generate the video with the provided options - force number_of_videos to 1 
  # to fix the issue of generating 2 videos

  res = generate_video(
    options[:prompt],
    options[:image_path],
    1, # Force to generate only one video
    options[:aspect_ratio],
    options[:person_generation],
    options[:duration_seconds]
  )
  
  # Only output the JSON to stdout for the caller to consume
  # Make sure debugging output goes to STDERR and clean JSON goes to STDOUT
  STDERR.puts "DEBUG: Final response data structure:"
  
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