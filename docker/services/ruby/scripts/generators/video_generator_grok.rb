#!/usr/bin/env ruby

require "http"
require "json"
require "optparse"
require "fileutils"
require_relative "../../lib/monadic/utils/ssl_configuration"
require_relative "../../lib/monadic/utils/model_spec"

if defined?(Monadic::Utils::SSLConfiguration)
  Monadic::Utils::SSLConfiguration.configure!
end

# Resolve default video model from providerDefaults SSOT
def default_grok_video_model
  Monadic::Utils::ModelSpec.default_video_model("xai") || "grok-imagine-video"
rescue
  "grok-imagine-video"
end

# Data paths to try (container path first, then local path)
DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"]

def get_save_path
  DATA_PATHS.each do |path|
    if Dir.exist?(path)
      return path
    else
      begin
        FileUtils.mkdir_p(path)
        return path
      rescue StandardError
        next
      end
    end
  end
  "./"
end

# Parse command line arguments
options = {
  duration: 5,
  aspect_ratio: "16:9",
  resolution: "720p",
  max_wait: 420
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: video_generator_grok.rb [options]"

  opts.on("-p", "--prompt PROMPT", "The prompt to generate a video for") do |prompt|
    options[:prompt] = prompt
  end

  opts.on("-d", "--duration SECONDS", Integer, "Video duration in seconds (1-15, default: 5)") do |d|
    options[:duration] = d
  end

  opts.on("-a", "--aspect-ratio RATIO", "Aspect ratio (16:9, 9:16, 1:1, default: 16:9)") do |ratio|
    options[:aspect_ratio] = ratio
  end

  opts.on("-r", "--resolution RES", "Resolution (480p, 720p, default: 720p)") do |res|
    options[:resolution] = res
  end

  opts.on("-i", "--image IMAGE", "Input image path for image-to-video") do |image|
    options[:image_path] = image
  end

  opts.on("--max-wait SECONDS", Integer, "Maximum wait time in seconds (default: 420)") do |seconds|
    options[:max_wait] = seconds
  end

  opts.on("--verbose", "Enable verbose output") do
    options[:verbose] = true
  end
end.parse!

# Validate required parameters
if options[:prompt].nil? || options[:prompt].strip.empty?
  puts JSON.generate({ success: false, error: "Prompt is required" })
  exit 1
end

# Validate duration
if options[:duration] < 1 || options[:duration] > 15
  puts JSON.generate({ success: false, error: "Duration must be between 1 and 15 seconds" })
  exit 1
end

# Validate aspect ratio
unless %w[16:9 9:16 1:1].include?(options[:aspect_ratio])
  puts JSON.generate({ success: false, error: "Invalid aspect ratio. Allowed: 16:9, 9:16, 1:1" })
  exit 1
end

# Validate resolution
unless %w[480p 720p].include?(options[:resolution])
  puts JSON.generate({ success: false, error: "Invalid resolution. Allowed: 480p, 720p" })
  exit 1
end

# Get API key
api_key = nil
begin
  api_key = File.read("/monadic/config/env").split("\n").find { |line|
    line.start_with?("XAI_API_KEY")
  }&.split("=", 2)&.last
rescue Errno::ENOENT
  api_key = File.read("#{Dir.home}/monadic/config/env").split("\n").find { |line|
    line.start_with?("XAI_API_KEY")
  }&.split("=", 2)&.last rescue nil
end

if api_key.nil? || api_key.strip.empty?
  puts JSON.generate({ success: false, error: "XAI_API_KEY is not set" })
  exit 1
end

shared_folder = get_save_path

# Build request payload
payload = {
  model: default_grok_video_model,
  prompt: options[:prompt],
  duration: options[:duration],
  aspect_ratio: options[:aspect_ratio],
  resolution: options[:resolution]
}

# Handle image-to-video
if options[:image_path] && !options[:image_path].strip.empty?
  image_full_path = if File.absolute_path?(options[:image_path])
                      options[:image_path]
                    else
                      File.join(shared_folder, options[:image_path])
                    end

  unless File.exist?(image_full_path)
    puts JSON.generate({ success: false, error: "Image file not found: #{options[:image_path]}" })
    exit 1
  end

  # Read and encode image as base64
  require "base64"
  image_data = File.binread(image_full_path)
  image_ext = File.extname(image_full_path).downcase
  mime_type = case image_ext
              when ".jpg", ".jpeg" then "image/jpeg"
              when ".png" then "image/png"
              when ".webp" then "image/webp"
              else
                puts JSON.generate({ success: false, error: "Unsupported image format. Use JPEG, PNG, or WebP." })
                exit 1
              end

  payload[:image] = "data:#{mime_type};base64,#{Base64.strict_encode64(image_data)}"
end

begin
  # Step 1: Create video generation job
  url = "https://api.x.ai/v1/videos/generations"
  headers = {
    "Content-Type" => "application/json",
    "Authorization" => "Bearer #{api_key}"
  }

  response = HTTP.headers(headers).post(url, json: payload)

  if response.status.code >= 400
    error_body = JSON.parse(response.body.to_s) rescue { "error" => { "message" => response.body.to_s } }
    puts JSON.generate({
      success: false,
      error: error_body.dig("error", "message") || "API request failed with status #{response.status}"
    })
    exit 1
  end

  job = JSON.parse(response.body.to_s)
  request_id = job["request_id"] || job["id"]

  $stderr.puts "Video generation started: #{request_id}" if options[:verbose]

  # Step 2: Poll for completion
  max_attempts = options[:max_wait] / 10
  attempts = 0

  loop do
    sleep 10
    attempts += 1

    status_url = "https://api.x.ai/v1/videos/#{request_id}"
    status_response = HTTP.headers(headers).get(status_url)

    if status_response.status.code >= 400
      puts JSON.generate({ success: false, error: "Failed to check video status" })
      exit 1
    end

    status_job = JSON.parse(status_response.body.to_s)
    current_status = status_job["status"]

    $stderr.puts "Status: #{current_status}" if options[:verbose]

    case current_status
    when "done", "completed"
      # Step 3: Download video
      video_url = status_job.dig("video", "url") || status_job["url"]

      unless video_url
        puts JSON.generate({ success: false, error: "Video URL not found in response" })
        exit 1
      end

      video_response = HTTP.follow.get(video_url)

      if video_response.status.code >= 400
        puts JSON.generate({ success: false, error: "Failed to download video" })
        exit 1
      end

      # Save video to shared folder
      timestamp = Time.now.to_i
      filename = "grok_video_#{timestamp}.mp4"
      output_path = File.join(shared_folder, filename)

      File.binwrite(output_path, video_response.body.to_s)

      puts JSON.generate({
        success: true,
        request_id: request_id,
        filename: filename,
        path: output_path,
        duration: options[:duration],
        aspect_ratio: options[:aspect_ratio],
        resolution: options[:resolution]
      })
      exit 0

    when "failed", "error"
      error_message = status_job.dig("error", "message") || status_job["error"] || "Video generation failed"
      puts JSON.generate({ success: false, error: error_message })
      exit 1

    when "expired"
      puts JSON.generate({ success: false, error: "Video generation request expired" })
      exit 1

    else
      # queued, in_progress, processing, etc.
      if attempts >= max_attempts
        puts JSON.generate({
          success: false,
          error: "Video generation timeout after #{options[:max_wait]} seconds"
        })
        exit 1
      end
    end
  end

rescue => e
  puts JSON.generate({ success: false, error: "Unexpected error: #{e.message}" })
  $stderr.puts e.backtrace.join("\n") if options[:verbose]
  exit 1
end
