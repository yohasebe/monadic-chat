#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"
require "fileutils"
require_relative "../../lib/monadic/utils/ssl_configuration"

if defined?(Monadic::Utils::SSLConfiguration)
  Monadic::Utils::SSLConfiguration.configure!
end

# Parse command line arguments

options = { 
  operation: "generate",
  model: "dall-e-3",
  size: "1024x1024",
  quality: "auto",
  output_format: "png",
  background: "auto",
  n: 1
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: image_generator_openai.rb [options]"

  opts.on("-o", "--operation OPERATION", "Operation: generate, edit, variation") do |op|
    options[:operation] = op
    unless %w[generate edit variation].include?(op)
      puts "ERROR: Invalid operation. Allowed operations are generate, edit, variation."
      exit
    end
  end

  opts.on("-m", "--model MODEL", "Model: dall-e-2, dall-e-3, gpt-image-1, gpt-image-1-mini") do |model|
    options[:model] = model
    unless %w[dall-e-2 dall-e-3 gpt-image-1 gpt-image-1-mini].include?(model)
      puts "ERROR: Invalid model. Allowed models are dall-e-2, dall-e-3, gpt-image-1, gpt-image-1-mini."
      exit
    end
  end

  opts.on("-p", "--prompt PROMPT", "The prompt to generate an image for") do |prompt|
    options[:prompt] = prompt
  end

  opts.on("-i", "--image IMAGE", "Input image(s) for edit or variation operations") do |image|
    options[:images] ||= []
    options[:images] << image
  end

  opts.on("--mask MASK", "Mask image for edit operation") do |mask|
    options[:mask] = mask
  end
  
  opts.on("--original-name NAME", "Original filename for preserving names (especially for mask images)") do |name|
    options[:original_image_name] = name
  end

  opts.on("-s", "--size SIZE", "Image size (256x256, 512x512, 1024x1024, 1024x1536, 1536x1024, 1792x1024, 1024x1792, auto)") do |size|
    options[:size] = size
  end

  opts.on("-q", "--quality QUALITY", "Image quality") do |quality|
    options[:quality] = quality
  end

  opts.on("-f", "--format FORMAT", "Output format for gpt-image-1 (png, jpeg, webp)") do |format|
    options[:output_format] = format
  end

  opts.on("-b", "--background BACKGROUND", "Background for gpt-image-1 (transparent, opaque, auto)") do |bg|
    options[:background] = bg
  end

  opts.on("--compression COMPRESSION", "Compression level for jpeg/webp (0-100)") do |comp|
    options[:output_compression] = comp.to_i
  end
  
  opts.on("--fidelity FIDELITY", "Input fidelity for edits (high/low)") do |fidelity|
    options[:input_fidelity] = fidelity
  end

  opts.on("-n", "--count COUNT", "Number of images to generate") do |count|
    options[:n] = count.to_i
  end

  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
end.parse!


if ["gpt-image-1", "gpt-image-1-mini"].include?(options[:model])

  unless %w[low medium high auto].include?(options[:quality])
    puts "WARNING: Invalid quality '#{options[:quality]}' for #{options[:model]}. Using 'auto' instead."
    options[:quality] = "auto"
  end
else

  if options[:quality] != "standard" && !options[:quality].nil?
    puts "WARNING: Invalid quality '#{options[:quality]}' for #{options[:model]}. Using 'standard' instead."
    options[:quality] = "standard"
  end
end

# Validate required options based on operation

case options[:operation]
when "generate"
  unless options[:prompt]
    puts "ERROR: A prompt is required for generate operation. Use -p or --prompt."
    exit
  end
when "edit"
  unless options[:prompt] && options[:images]
    puts "ERROR: A prompt and at least one input image are required for edit operation."
    exit
  end
when "variation"
  unless options[:images]
    puts "ERROR: An input image is required for variation operation."
    exit
  end
  if options[:model] != "dall-e-2"
    puts "WARNING: The variation operation is only supported with the dall-e-2 model."
    options[:model] = "dall-e-2"
  end
end

def get_api_key
  api_key = nil
  
  # Try both possible config file locations
  config_paths = ["/monadic/config/env", "#{Dir.home}/monadic/config/env"]
  
  config_paths.each do |config_path|
    next unless File.exist?(config_path)
    
    begin
      api_key = File.read(config_path).split("\n").find do |line|
        line.start_with?("OPENAI_API_KEY=")
      end&.split("=", 2)&.last&.strip
      
      break if api_key
    rescue => e
      puts "WARNING: Error reading #{config_path}: #{e.message}"
    end
  end
  
  unless api_key
    puts "ERROR: Unable to find OpenAI API key in config files:"
    config_paths.each { |path| puts "  - #{path}" }
    puts "Please add OPENAI_API_KEY=your-key to ~/monadic/config/env"
    exit 1
  end
  
  api_key
end

# Function to get MIME type based on file extension

def get_mime_type(file_path)
  ext = File.extname(file_path).downcase.delete('.')
  case ext
  when 'jpg', 'jpeg'
    'image/jpeg'
  when 'png'
    'image/png'
  when 'webp'
    'image/webp'
  else
    # Try to detect from file content

    begin
      file_data = File.binread(file_path, 16) # Read first 16 bytes
      if file_data.start_with?("\xFF\xD8") # JPEG magic number
        'image/jpeg'
      elsif file_data.start_with?("\x89PNG\r\n\x1A\n") # PNG magic number
        'image/png'
      elsif file_data.start_with?("RIFF") && file_data[8, 4] == "WEBP" # WEBP magic number
        'image/webp'
      else
        puts "WARNING: Unable to determine MIME type for #{file_path}. Defaulting to image/jpeg"
        'image/jpeg' # Default to JPEG as fallback
      end
    rescue
      puts "WARNING: Unable to read file #{file_path}. Defaulting to image/jpeg"
      'image/jpeg' # Default to JPEG as fallback
    end
  end
end

def generate_image(options, num_retrials = 3)
  api_key = get_api_key
  
  begin
    case options[:operation]
    when "generate"
      url = "https://api.openai.com/v1/images/generations"
      headers = {
        "Content-Type": "application/json",
        Authorization: "Bearer #{api_key}"
      }
      
      body = {
        model: options[:model],
        prompt: options[:prompt],
        n: options[:n]
      }
      
      # Add response_format only for DALL-E models

      if ["gpt-image-1", "gpt-image-1-mini"].include?(options[:model])
        # GPT Image models specific parameters

        body[:size] = options[:size] if options[:size]
        body[:quality] = options[:quality] if options[:quality]
        body[:output_format] = options[:output_format] if options[:output_format]
        body[:background] = options[:background] if options[:background]
        body[:output_compression] = options[:output_compression] if options[:output_compression]
      else
        # DALL-E models use b64_json format
        body[:response_format] = "b64_json"
        body[:size] = options[:size] if options[:size]
        body[:quality] = options[:quality] if options[:quality]
      end
      
      puts "Sending request to generate image with prompt: #{options[:prompt]}" if options[:verbose]
      puts "Request body: #{body.to_json}" if options[:verbose]
      res = HTTP.headers(headers).post(url, json: body)
      
    when "edit"
      url = "https://api.openai.com/v1/images/edits"

      if ["gpt-image-1", "gpt-image-1-mini"].include?(options[:model])
        # For GPT Image models, prepare multipart form with image[] array

        form = {}

        # Add basic parameters

        form[:model] = options[:model]
        form[:prompt] = options[:prompt]
        form[:n] = options[:n].to_s

        # Add specific parameters for GPT Image models

        form[:size] = options[:size] if options[:size]
        form[:quality] = options[:quality] if options[:quality]
        form[:output_format] = options[:output_format] if options[:output_format]
        form[:background] = options[:background] if options[:background]
        form[:output_compression] = options[:output_compression].to_s if options[:output_compression]
        form[:input_fidelity] = options[:input_fidelity] if options[:input_fidelity]
        
        # Add images with proper MIME types

        options[:images].each do |img_path|
          mime_type = get_mime_type(img_path)
          form[:"image[]"] ||= []
          
          image_file = HTTP::FormData::File.new(
            img_path,
            content_type: mime_type,
            filename: File.basename(img_path)
          )
          
          if form[:"image[]"].is_a?(Array)
            form[:"image[]"] << image_file
          else
            form[:"image[]"] = [form[:"image[]"], image_file]
          end
        end
        
        # Add mask if provided

        if options[:mask]
          mime_type = get_mime_type(options[:mask])
          form[:mask] = HTTP::FormData::File.new(
            options[:mask],
            content_type: mime_type,
            filename: File.basename(options[:mask])
          )
        end
        
        puts "Sending request to edit image with prompt: #{options[:prompt]}" if options[:verbose]
        puts "Form data keys: #{form.keys}" if options[:verbose]
        
        # Debug information

        if options[:verbose]
          form.each do |key, value|
            if value.is_a?(HTTP::FormData::File)
              puts "  #{key}: File (#{value.content_type})"
            elsif value.is_a?(Array) && value.all? { |v| v.is_a?(HTTP::FormData::File) }
              puts "  #{key}: Array of Files (#{value.map { |v| v.content_type }.join(', ')})"
            else
              puts "  #{key}: #{value}"
            end
          end
        end
        
        res = HTTP.headers(Authorization: "Bearer #{api_key}").post(url, form: form)
      else
        # For DALL-E models, use standard approach

        form = {}
        
        # Add text parameters

        form[:model] = options[:model]
        form[:prompt] = options[:prompt]
        form[:n] = options[:n].to_s
        form[:response_format] = "b64_json"
        form[:size] = options[:size] if options[:size]
        
        # Add image file

        mime_type = get_mime_type(options[:images].first)
        form[:image] = HTTP::FormData::File.new(
          options[:images].first,
          content_type: mime_type,
          filename: File.basename(options[:images].first)
        )
        
        # Add mask if provided

        if options[:mask]
          mime_type = get_mime_type(options[:mask])
          form[:mask] = HTTP::FormData::File.new(
            options[:mask],
            content_type: mime_type,
            filename: File.basename(options[:mask])
          )
        end
        
        puts "Sending request to edit image with prompt: #{options[:prompt]}" if options[:verbose]
        res = HTTP.headers(Authorization: "Bearer #{api_key}").post(url, form: form)
      end
      
    when "variation"
      url = "https://api.openai.com/v1/images/variations"
      
      # Use raw multipart form data approach

      form = {
        model: options[:model],
        n: options[:n].to_s,
        response_format: "b64_json"
      }
      
      form[:size] = options[:size] if options[:size]
      
      # Add image file with MIME type

      mime_type = get_mime_type(options[:images].first)
      form[:image] = HTTP::FormData::File.new(
        options[:images].first,
        content_type: mime_type,
        filename: File.basename(options[:images].first)
      )
      
      puts "Sending request to create variation of image" if options[:verbose]
      res = HTTP.headers(Authorization: "Bearer #{api_key}").post(url, form: form)
    end
    
    if res.status.success?
      json = JSON.parse(res.body.to_s)
      
      # Save images and prepare result

      result = {
        operation: options[:operation],
        model: options[:model],
        original_prompt: options[:prompt],
        success: true,
        images: []
      }
      
      # Create output directory

      output_dir = "./"
      FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
      
      json["data"].each_with_index do |data, idx|
        base64_data = data["b64_json"]
        revised_prompt = data["revised_prompt"] if data.key?("revised_prompt")
        
        if base64_data
          image_data = Base64.decode64(base64_data)
          timestamp = Time.now.to_i
          ext = options[:output_format] || "png"
          
          # Check if this is a mask image (passed in through original_image_name option)
          if options[:original_image_name] && options[:original_image_name].start_with?("mask__")
            # Preserve the mask__ prefix in the filename
            filename = options[:original_image_name]
          elsif options[:operation] == "edit" && options[:mask] && File.basename(options[:mask]).start_with?("mask__")
            # If this is an edit operation and we have a mask file, ensure the mask prefix is preserved
            # This handles cases where the mask image is being processed as part of an image generation
            mask_basename = File.basename(options[:mask])
            filename = "mask__#{options[:model]}_#{timestamp}_#{idx}.#{ext}"
          else
            # Generate a standard filename for regular images
            filename = "#{options[:operation]}_#{options[:model]}_#{timestamp}_#{idx}.#{ext}"
          end
          file_path = File.join(output_dir, filename)
          
          File.open(file_path, "wb") do |f|
            f.write(image_data)
          end
          
          result[:images] << {
            path: file_path,
            revised_prompt: revised_prompt
          }
        end
      end
      
      return result
    else
      begin
        error_response = JSON.parse(res.body.to_s)
        error_msg = error_response.dig('error', 'message') || "Error with API response: #{res.status}"
        puts "ERROR: #{error_msg}"
        puts "Response body: #{res.body}" if options[:verbose]
      rescue JSON::ParserError
        puts "ERROR: Failed to parse error response. Status: #{res.status}"
        puts "Response body: #{res.body}" if options[:verbose]
      end
      
      if num_retrials > 0
        puts "Retrying... (#{num_retrials} attempts left)"
        sleep 1
        return generate_image(options, num_retrials - 1)
      else
        return { 
          operation: options[:operation],
          model: options[:model],
          original_prompt: options[:prompt],
          success: false, 
          message: "Failed after multiple attempts." 
        }
      end
    end
  rescue StandardError => e
    puts "ERROR: #{e.message}"
    puts e.backtrace if options[:verbose]
    
    if num_retrials > 0
      puts "Retrying... (#{num_retrials} attempts left)"
      sleep 1
      return generate_image(options, num_retrials - 1)
    else
      return { 
        operation: options[:operation],
        model: options[:model],
        original_prompt: options[:prompt],
        success: false, 
        message: "Error: #{e.message}" 
      }
    end
  end
end

# Execute the operation and print the result

result = generate_image(options)
puts JSON.pretty_generate(result)

if result[:success]
  puts "\nOperation completed successfully!"
  puts "Original prompt: #{result[:original_prompt]}"
  
  result[:images].each do |img|
    puts "Saved file: #{img[:path]}"
    puts "Revised prompt: #{img[:revised_prompt]}" if img[:revised_prompt]
  end
else
  puts "\nOperation failed: #{result[:message]}"
end
