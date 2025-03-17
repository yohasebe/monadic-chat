#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require "fileutils"

# Define constants for API and configuration

API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict"
CONFIG_PATHS = ["/monadic/config/env", "#{Dir.home}/monadic/config/env"]
DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"]

# Define valid parameter values

VALID_ASPECT_RATIOS = ["1:1", "3:4", "4:3", "9:16", "16:9"]
VALID_SAFETY_LEVELS = [
  "BLOCK_LOW_AND_ABOVE",
  "BLOCK_MEDIUM_AND_ABOVE",
  "BLOCK_ONLY_HIGH"
]
VALID_PERSON_GENERATION = ["DONT_ALLOW", "ALLOW_ADULT"]

# Default options

DEFAULT_OPTIONS = {
  sample_count: 4,                   # Default to 4 images
  aspect_ratio: "1:1",               # Default aspect ratio
  safety_filter_level: "BLOCK_MEDIUM_AND_ABOVE",  # Default safety level
  person_generation: "ALLOW_ADULT"   # Default person generation setting
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

# Find or create a directory to save images

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
    FileUtils.mkdir_p("./imagen_output")
    return "./imagen_output/"
  rescue
    return "./"  # Last resort, use current directory
  end
end

# Save base64 image data to file

def save_image(base64_data, aspect_ratio, index)
  return nil if base64_data.nil?
  
  begin
    image_data = Base64.decode64(base64_data)
    save_path = get_save_path()
    timestamp = Time.now.to_i
    filename = "#{timestamp}_#{index}_#{aspect_ratio.gsub(':', 'x')}.png"
    file_path = File.join(save_path, filename)
    
    File.open(file_path, "wb") do |f|
      f.write(image_data)
    end
    
    # Make sure this message appears in stdout for LLM to extract filename
    puts "Successfully saved image to: #{file_path}"
    return filename
  rescue StandardError => e
    STDERR.puts "WARNING: Failed to save image #{index}: #{e.message}"
    return nil
  end
end

# Make API request to generate images

def request_image_generation(prompt, sample_count, aspect_ratio, safety_filter_level, person_generation, api_key)
  url = "#{API_ENDPOINT}?key=#{api_key}"
  
  headers = {
    "Content-Type": "application/json"
  }

  body = {
    instances: [
      {
        prompt: prompt
      }
    ],
    parameters: {
      sampleCount: sample_count,
      aspectRatio: aspect_ratio,
      safetyFilterLevel: safety_filter_level,
      personGeneration: person_generation
    }
  }

  STDERR.puts "Sending request to: #{API_ENDPOINT}"
  STDERR.puts "Request body: #{JSON.pretty_generate(body)}"
  
  response = HTTP.headers(headers).post(url, json: body)
  STDERR.puts "Raw Response Status: #{response.status}"
  STDERR.puts "Raw Response Headers: #{response.headers.to_h}"
  STDERR.puts "Raw Response Body: #{response.body.to_s}"
  
  response
end

# Process API response

def process_response(response, prompt, aspect_ratio, params)
  # Debugging code removed
  
  if response.status.success?
    begin
      begin
        json = JSON.parse(response.body)
        if json.is_a?(Hash) && !json.empty?
          # Process hash response
        elsif json.is_a?(Array)
          # Process array response
        else
          # Log critical error to stderr
          STDERR.puts "Error: API response has empty or unsupported structure"
          return {
            original_prompt: prompt,
            success: false,
            message: "Error: API response has empty or unsupported structure",
            response_type: json.class,
            raw_body: response.body.to_s[0..200]
          }
        end
      rescue JSON::ParserError => e
        STDERR.puts "JSON parsing failed: #{e.message}"
        STDERR.puts "Raw body content: #{response.body.to_s[0..500]}"
        return {
          original_prompt: prompt,
          success: false,
          message: "Error parsing API response: #{e.message}",
          raw_body_preview: response.body.to_s[0..200]
        }
      end
      
      # Skip these conditions as they're now handled above
      if json.is_a?(Hash) && (json["predictions"].nil? || json["predictions"].empty?)
        return { 
          original_prompt: prompt, 
          success: false, 
          message: "Error: No predictions in API response.",
          response_keys: json.keys
        }
      end

      results = []
      puts "Found #{json["predictions"].length} predictions"
      
      json["predictions"].each_with_index do |prediction, index|
        
        # Use bytesBase64Encoded field which is the correct field name in Imagen API

        base64_data = prediction["bytesBase64Encoded"]
        
        if base64_data.nil?
          puts "No image data found in prediction #{index}"
          next
        end
        
        filename = save_image(base64_data, aspect_ratio, index)
        
        results << {
          filename: filename,
          aspect_ratio: aspect_ratio
        } if filename
      end

      if results.empty?
        return { 
          original_prompt: prompt, 
          success: false, 
          message: "No images were successfully generated or saved",
          response_structure: json.keys,
          predictions_found: json["predictions"] ? json["predictions"].length : 0
        }
      end

      result = { 
        original_prompt: prompt, 
        success: true, 
        images: results,
        generated_image_count: results.length,
        parameters: params
      }
      # No need for debug output in production
      return result
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

# Main function to generate images

def generate_image(prompt, sample_count, aspect_ratio, safety_filter_level, person_generation, num_retrials: 3)
  params = {
    sample_count: sample_count,
    aspect_ratio: aspect_ratio,
    safety_filter_level: safety_filter_level,
    person_generation: person_generation
  }
  
  begin
    api_key = get_api_key()
    # Output to stdout - LLM will extract information from this
    puts "Generating #{sample_count} images with prompt: \"#{prompt}\"..."
    puts "Using parameters: #{params.inspect}"
    
    response = request_image_generation(
      prompt, 
      sample_count, 
      aspect_ratio, 
      safety_filter_level, 
      person_generation, 
      api_key
    )
    
    return process_response(response, prompt, aspect_ratio, params)
    
  rescue HTTP::Error, HTTP::TimeoutError => e
    error_msg = "ERROR: API request failed - #{e.message}"
    STDERR.puts error_msg
    return { original_prompt: prompt, success: false, message: error_msg }
  rescue StandardError => e
    error_msg = "Error: #{e.message}"
    STDERR.puts error_msg
    STDERR.puts e.backtrace
    
    num_retrials -= 1
    if num_retrials.positive?
      STDERR.puts "Retrying... (#{num_retrials} attempts left)"
      sleep 1
      return generate_image(prompt, sample_count, aspect_ratio, safety_filter_level, person_generation, num_retrials: num_retrials)
    else
      return { original_prompt: prompt, success: false, message: "Error: Image generation failed after multiple attempts." }
    end
  end
end

# Parse command line options

def parse_options
  options = DEFAULT_OPTIONS.dup
  
  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: imagen_image_generation.rb [options]"
    
    opts.on("-p", "--prompt PROMPT", "The prompt to generate an image for") do |prompt|
      options[:prompt] = prompt
    end
    
    opts.on("-n", "--number NUMBER", Integer, "Number of images to generate (1-4)") do |num|
      unless (1..4).include?(num)
        puts "ERROR: Number of images must be between 1 and 4"
        exit
      end
      options[:sample_count] = num
    end
    
    opts.on("-a", "--aspect-ratio RATIO", "Aspect ratio (1:1, 3:4, 4:3, 9:16, 16:9)") do |ratio|
      unless VALID_ASPECT_RATIOS.include?(ratio)
        puts "ERROR: Invalid aspect ratio. Valid values are: #{VALID_ASPECT_RATIOS.join(', ')}"
        exit
      end
      options[:aspect_ratio] = ratio
    end
    
    opts.on("-s", "--safety-level LEVEL", "Safety filter level") do |level|
      unless VALID_SAFETY_LEVELS.include?(level)
        puts "ERROR: Invalid safety level. Valid values are: #{VALID_SAFETY_LEVELS.join(', ')}"
        exit
      end
      options[:safety_filter_level] = level
    end
    
    opts.on("-g", "--person-generation MODE", "Person generation mode") do |mode|
      unless VALID_PERSON_GENERATION.include?(mode)
        puts "ERROR: Invalid person generation mode. Valid values are: #{VALID_PERSON_GENERATION.join(', ')}"
        exit
      end
      options[:person_generation] = mode
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end

    opts.on("-d", "--debug", "Enable debug mode") do
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
  puts "\n# Basic usage with defaults"
  puts "#{$PROGRAM_NAME} -p \"Fuzzy bunnies in my kitchen\""
  puts "\n# Generate 2 images with specific aspect ratio"
  puts "#{$PROGRAM_NAME} -p \"Fuzzy bunnies in my kitchen\" -n 2 -a \"16:9\""
  puts "\n# With all options specified"
  puts "#{$PROGRAM_NAME} \\"
  puts "  -p \"Fuzzy bunnies in my kitchen\" \\"
  puts "  -n 2 \\"
  puts "  -a \"16:9\" \\"
  puts "  -s \"BLOCK_ONLY_HIGH\" \\"
  puts "  -g \"DONT_ALLOW\""
  puts "\n# For debugging"
  puts "#{$PROGRAM_NAME} -p \"Fuzzy bunnies\" -d"
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
  
  # Generate the image with the provided options

  res = generate_image(
    options[:prompt],
    options[:sample_count],
    options[:aspect_ratio],
    options[:safety_filter_level],
    options[:person_generation]
  )
  
  # Only output the JSON to stdout for the caller to consume
  puts res.to_json
end
