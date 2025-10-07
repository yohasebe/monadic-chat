#!/usr/bin/env ruby

require "http"
require "json"
require "optparse"
require "fileutils"
require "openssl"

# Configure SSL context - simplified for compatibility
ssl_context = OpenSSL::SSL::SSLContext.new
ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE

# Configure HTTP gem to use this SSL context
HTTP.default_options = {
  ssl_context: ssl_context
}

# Data paths to try (container path first, then local path)
DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"]

# Helper function to get the first available data path
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
  # Fallback to current directory if none of the paths are accessible
  "./"
end

# Parse command line arguments
options = {
  model: "sora-2",
  size: "1280x720",
  seconds: "8",
  max_wait: 420 # 7 minutes maximum wait time for video generation
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: video_generator_openai.rb [options]"

  opts.on("-p", "--prompt PROMPT", "The prompt to generate a video for") do |prompt|
    options[:prompt] = prompt
  end

  opts.on("-m", "--model MODEL", "Model: sora-2, sora-2-pro") do |model|
    options[:model] = model
    unless %w[sora-2 sora-2-pro].include?(model)
      puts JSON.generate({
        success: false,
        error: "Invalid model. Allowed models are sora-2, sora-2-pro."
      })
      exit 1
    end
  end

  opts.on("-s", "--size SIZE", "Video size (1280x720, 1920x1080, 1080x1920, 720x1280)") do |size|
    options[:size] = size
  end

  opts.on("-d", "--duration SECONDS", "Video duration in seconds (4, 8, 16)") do |seconds|
    options[:seconds] = seconds
  end

  opts.on("-i", "--image IMAGE", "Input image path for image-to-video") do |image|
    options[:image_path] = image
  end

  opts.on("-r", "--remix VIDEO_ID", "Remix existing video by ID") do |video_id|
    options[:remix_video_id] = video_id
  end

  opts.on("--max-wait SECONDS", "Maximum wait time in seconds (default: 420)") do |seconds|
    options[:max_wait] = seconds.to_i
  end

  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
end.parse!

# Validate required parameters
if options[:prompt].nil? || options[:prompt].strip.empty?
  puts JSON.generate({
    success: false,
    error: "Prompt is required"
  })
  exit 1
end

# Get API key
api_key = ENV["OPENAI_API_KEY"]
if api_key.nil? || api_key.strip.empty?
  puts JSON.generate({
    success: false,
    error: "OPENAI_API_KEY environment variable is not set"
  })
  exit 1
end

# Get the appropriate save path (works in both container and local environments)
shared_folder = get_save_path()

# Build request payload
payload = {
  model: options[:model],
  prompt: options[:prompt],
  size: options[:size],
  seconds: options[:seconds]
}

# Handle image-to-video
if options[:image_path] && !options[:image_path].strip.empty?
  image_full_path = if File.absolute_path?(options[:image_path])
                      options[:image_path]
                    else
                      File.join(shared_folder, options[:image_path])
                    end

  unless File.exist?(image_full_path)
    puts JSON.generate({
      success: false,
      error: "Image file not found: #{options[:image_path]}"
    })
    exit 1
  end

  # Read and encode image
  image_data = File.binread(image_full_path)
  image_type = case File.extname(image_full_path).downcase
               when ".jpg", ".jpeg" then "image/jpeg"
               when ".png" then "image/png"
               when ".webp" then "image/webp"
               else
                 puts JSON.generate({
                   success: false,
                   error: "Unsupported image format. Use JPEG, PNG, or WebP."
                 })
                 exit 1
               end
end

begin
  # Step 1: Create video generation job
  if options[:remix_video_id] && !options[:remix_video_id].strip.empty?
    # Remix existing video
    url = "https://api.openai.com/v1/videos/#{options[:remix_video_id]}/remix"
    response = HTTP.auth("Bearer #{api_key}")
                   .headers("Content-Type" => "application/json")
                   .post(url, json: { prompt: options[:prompt] })
  else
    # Create new video
    url = "https://api.openai.com/v1/videos"

    if options[:image_path] && !options[:image_path].strip.empty?
      # Multipart form data for image-to-video
      form_data = {
        prompt: options[:prompt],
        model: options[:model],
        size: options[:size],
        seconds: options[:seconds],
        input_reference: HTTP::FormData::File.new(image_full_path, content_type: image_type)
      }
      response = HTTP.auth("Bearer #{api_key}")
                     .post(url, form: form_data)
    else
      # JSON payload for text-to-video
      response = HTTP.auth("Bearer #{api_key}")
                     .headers("Content-Type" => "application/json")
                     .post(url, json: payload)
    end
  end

  if response.status >= 400
    error_body = JSON.parse(response.body.to_s) rescue { "error" => { "message" => response.body.to_s } }
    puts JSON.generate({
      success: false,
      error: error_body.dig("error", "message") || "API request failed with status #{response.status}"
    })
    exit 1
  end

  job = JSON.parse(response.body.to_s)
  video_id = job["id"]

  $stderr.puts "Video generation started: #{video_id}" if options[:verbose]

  # Step 2: Poll for completion
  max_attempts = options[:max_wait] / 10 # Check every 10 seconds
  attempts = 0

  loop do
    sleep 10
    attempts += 1

    status_response = HTTP.auth("Bearer #{api_key}")
                          .get("https://api.openai.com/v1/videos/#{video_id}")

    if status_response.status >= 400
      puts JSON.generate({
        success: false,
        error: "Failed to check video status"
      })
      exit 1
    end

    status_job = JSON.parse(status_response.body.to_s)
    current_status = status_job["status"]
    progress = status_job["progress"] || 0

    $stderr.puts "Status: #{current_status}, Progress: #{progress}%" if options[:verbose]

    case current_status
    when "completed"
      # Step 3: Download video
      content_response = HTTP.auth("Bearer #{api_key}")
                             .get("https://api.openai.com/v1/videos/#{video_id}/content")

      if content_response.status >= 400
        puts JSON.generate({
          success: false,
          error: "Failed to download video content"
        })
        exit 1
      end

      # Save video to shared folder
      timestamp = Time.now.to_i
      filename = "video_#{video_id.gsub('video_', '')}.mp4"
      output_path = File.join(shared_folder, filename)

      File.binwrite(output_path, content_response.body.to_s)

      # Also download thumbnail if available
      thumb_response = HTTP.auth("Bearer #{api_key}")
                           .get("https://api.openai.com/v1/videos/#{video_id}/content?variant=thumbnail")

      if thumb_response.status == 200
        thumb_filename = "thumbnail_#{video_id.gsub('video_', '')}.webp"
        thumb_path = File.join(shared_folder, thumb_filename)
        File.binwrite(thumb_path, thumb_response.body.to_s)
      end

      puts JSON.generate({
        success: true,
        video_id: video_id,
        filename: filename,
        path: output_path,
        model: status_job["model"],
        size: status_job["size"],
        seconds: status_job["seconds"]
      })
      exit 0

    when "failed"
      error_message = status_job.dig("error", "message") || "Video generation failed"
      puts JSON.generate({
        success: false,
        error: error_message
      })
      exit 1

    when "queued", "in_progress"
      if attempts >= max_attempts
        puts JSON.generate({
          success: false,
          error: "Video generation timeout after #{options[:max_wait]} seconds"
        })
        exit 1
      end
      # Continue polling
    end
  end

rescue => e
  puts JSON.generate({
    success: false,
    error: "Unexpected error: #{e.message}"
  })
  $stderr.puts e.backtrace.join("\n") if options[:verbose]
  exit 1
end
