#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a video with Gemini Omni (gemini-omni-1.1-flash) and saves it in
# the shared folder. The request itself is Monadic::Utils::GeminiOmniVideo;
# this script reads the arguments, checks the image path, and prints one JSON
# line on stdout (messages go to stderr).
#
#   video_generator_gemini.rb -p PROMPT [-i IMAGE] [-a 16:9|9:16] [-d SECONDS] [--negative-prompt TEXT]

require "base64"
require "json"
require "optparse"
require "fileutils"
require_relative "../../lib/monadic/utils/shared_path_guard"
require_relative "../../lib/monadic/utils/ssl_configuration"
require_relative "../../lib/monadic/utils/secret_references"
require_relative "../../lib/monadic/utils/gemini_omni_video"

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

begin
  require_relative "../../lib/monadic/utils/model_spec"
rescue LoadError
  # ModelSpec not available in this environment
end

DATA_PATHS = ["/monadic/data/", "#{Dir.home}/monadic/data/"].freeze
VALID_ASPECT_RATIOS = Monadic::Utils::GeminiOmniVideo::ASPECT_RATIOS
VALID_DURATION_SECONDS = Monadic::Utils::GeminiOmniVideo::DURATIONS.to_a
FALLBACK_VIDEO_MODEL = "gemini-omni-1.1-flash"

DEFAULT_OPTIONS = {
  aspect_ratio: "16:9",
  duration_seconds: Monadic::Utils::GeminiOmniVideo::DEFAULT_DURATION,
  negative_prompt: nil
}.freeze

def video_model
  models = defined?(Monadic::Utils::ModelSpec) ? Monadic::Utils::ModelSpec.get_provider_models("gemini", "video") : nil
  Array(models).first || FALLBACK_VIDEO_MODEL
end

def get_api_key
  # Through config_value: config/env may hold an op:// reference, which only
  # the delivered secrets resolve.
  api_key = Monadic::Utils::SecretReferences.config_value("GEMINI_API_KEY")
  return api_key if api_key

  raise "ERROR: GEMINI_API_KEY is not set, or its 1Password reference could not be read. Set it in ~/monadic/config/env, then restart Monadic Chat."
end

def get_save_path
  DATA_PATHS.each do |path|
    return path if Dir.exist?(path)

    begin
      FileUtils.mkdir_p(path)
      return path
    rescue StandardError
      next
    end
  end
  raise "ERROR: the shared folder could not be found or created."
end

# An image path inside the shared folder (relative paths are relative to it,
# never to the current directory), or nil.
def resolve_image_path(image_path)
  Monadic::Utils::SharedPathGuard.resolve_in_shared(
    image_path, extensions: Monadic::Utils::SharedPathGuard::IMAGE_EXTENSIONS
  )
end

# { data:, mime_type: } for a PNG, JPEG or WebP image in the shared folder,
# or nil (outside the shared folder, another type, too large, unreadable).
def read_image(image_path)
  path = resolve_image_path(image_path)
  return nil unless path

  mime_type = Monadic::Utils::GeminiOmniVideo::IMAGE_TYPES[File.extname(path).downcase]
  return nil unless mime_type
  return nil if File.size(path) > Monadic::Utils::GeminiOmniVideo::MAX_IMAGE_BYTES

  { data: File.binread(path), mime_type: mime_type }
rescue SystemCallError
  nil
end

def encode_image_to_data_url(image_path)
  image = read_image(image_path)
  image && "data:#{image[:mime_type]};base64,#{Base64.strict_encode64(image[:data])}"
end

def generate_video(prompt, image_path = nil, aspect_ratio: DEFAULT_OPTIONS[:aspect_ratio],
                   duration: DEFAULT_OPTIONS[:duration_seconds], negative_prompt: nil)
  image = nil
  if image_path && !image_path.to_s.strip.empty?
    image = read_image(image_path)
    unless image
      return { success: false, error: "invalid_input",
               message: "Invalid shared image path or unsupported format (PNG, JPEG or WebP in the shared folder, up to 10 MB)" }
    end
  end

  generator = Monadic::Utils::GeminiOmniVideo.new(api_key: get_api_key, model: video_model, save_dir: get_save_path)
  result = generator.generate(prompt: prompt, image: image, aspect_ratio: aspect_ratio,
                              duration: duration, negative_prompt: negative_prompt)
  result[:original_prompt] = prompt
  # The shape the chat helpers read: a list of saved videos.
  result[:videos] = [{ filename: result[:filename], aspect_ratio: aspect_ratio, duration: result[:duration] }] if result[:success]
  result
rescue RuntimeError => e
  { success: false, error: "configuration", message: e.message.delete_prefix("ERROR: "), original_prompt: prompt }
end

def parse_options(argv = ARGV)
  options = DEFAULT_OPTIONS.dup
  OptionParser.new do |opts|
    opts.banner = "Usage: video_generator_gemini.rb [options]"
    opts.on("-p", "--prompt PROMPT", "What the video shows") { |v| options[:prompt] = v }
    opts.on("-i", "--image PATH", "An image in the shared folder to start the video from") { |v| options[:image_path] = v }
    opts.on("-a", "--aspect-ratio RATIO", VALID_ASPECT_RATIOS.join(" or ")) { |v| options[:aspect_ratio] = v }
    opts.on("-d", "--duration SECONDS", "#{VALID_DURATION_SECONDS.first} to #{VALID_DURATION_SECONDS.last} seconds") { |v| options[:duration_seconds] = v }
    opts.on("--negative-prompt TEXT", "What to keep out of the video") { |v| options[:negative_prompt] = v }
    # Accepted from callers written for Veo; Omni makes one video at one speed.
    opts.on("-n", "--number NUMBER", "Ignored: one video is made") { |_v| nil }
    opts.on("--fast", "Ignored") { nil }
    opts.on("--quality", "Ignored") { nil }
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!(argv)
  options
end

if __FILE__ == $PROGRAM_NAME
  options = begin
    parse_options
  rescue OptionParser::ParseError => e
    puts JSON.generate(success: false, error: "invalid_input", message: e.message)
    exit 1
  end
  if options[:prompt].to_s.strip.empty?
    puts JSON.generate(success: false, error: "invalid_input", message: "A prompt is required (-p).")
    exit 1
  end

  result = generate_video(options[:prompt], options[:image_path], aspect_ratio: options[:aspect_ratio],
                          duration: options[:duration_seconds], negative_prompt: options[:negative_prompt])
  STDERR.puts(result[:success] ? "Saved video: #{result[:filename]}" : "Video generation failed: #{result[:message]}")
  puts JSON.generate(result)
  exit(result[:success] ? 0 : 1)
end
