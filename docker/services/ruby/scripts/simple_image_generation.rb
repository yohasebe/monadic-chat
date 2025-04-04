#!/usr/bin/env ruby

require "base64"
require "http"
require "json"
require "optparse"

# Parse command line arguments for the prompt and size
options = { size: "1024x1024" } # Default size
OptionParser.new do |opts|
  opts.banner = "Usage: simple_image_generation.rb [options]"

  opts.on("-p", "--prompt PROMPT", "The prompt to generate an image for") do |prompt|
    options[:prompt] = prompt
  end

  opts.on("-s", "--size SIZE", "The size of the generated image (1024x1024, 1024x1792, 1792x1024)") do |size|
    unless %w[1024x1024 1024x1792 1792x1024].include?(size)
      puts "ERROR: Invalid size. Allowed sizes are 1024x1024, 1024x1792, 1792x1024."
      exit
    end
    options[:size] = size
  end
end.parse!

# Exit if no prompt is provided
unless options[:prompt]
  puts "ERROR: A prompt is required. Use -p or --prompt to specify the prompt."
  exit
end

def generate_image(prompt, size, num_retrials: 3)
  revised_prompt = nil # Initialize to avoid undefined variable
  
  begin
    api_key = File.read("/monadic/config/env").split("\n").find do |line|
      line.start_with?("OPENAI_API_KEY")
    end.split("=").last
  rescue Errno::ENOENT
    api_key ||= File.read("#{Dir.home}/monadic/config/env").split("\n").find do |line|
      line.start_with?("OPENAI_API_KEY")
    end.split("=").last
  end

  url = "https://api.openai.com/v1/images/generations"
  res = nil

  begin
    headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer #{api_key}"
    }

    body = {
      model: "dall-e-3",
      prompt: prompt,
      n: 1,
      size: size,
      response_format: "b64_json"
    }

    res = HTTP.headers(headers).post(url, json: body)
  rescue HTTP::Error, HTTP::TimeoutError => e
    error_msg = "ERROR: #{e.message}"
    return { original_prompt: prompt, success: false, message: error_msg }
  end

  if res.status.success?
    json = JSON.parse(res.body)
    data = json["data"].first
    base64_data = data["b64_json"]
    revised_prompt = data["revised_prompt"]

    if base64_data.nil?
      error_msg = "Error: No image data received from the API."
      return { original_prompt: prompt, success: false, message: error_msg }
    else
      image_data = Base64.decode64(base64_data)
    end

    primary_save_path = "/monadic/data/"
    secondary_save_path = File.expand_path("~/monadic/data/")

    # check if the directory exists
    save_path = Dir.exist?(primary_save_path) ? primary_save_path : secondary_save_path
    filename = "#{Time.now.to_i}.png"
    file_path = File.join(save_path, filename)

    File.open(file_path, "wb") do |f|
      f.write(image_data)
    end

    { original_prompt: prompt, revised_prompt: revised_prompt, success: true, filename: filename }
  else
    begin
      error_response = JSON.parse(res.body)
      error_msg = error_response.dig('error', 'message') || "Error with API response"
      return { original_prompt: prompt, success: false, message: error_msg }
    rescue JSON::ParserError
      return { original_prompt: prompt, success: false, message: "Error parsing API response" }
    end
  end
rescue StandardError => e
  error_msg = "Error: #{e.message}"
  puts error_msg
  puts e.backtrace
  
  num_retrials -= 1
  if num_retrials.positive?
    sleep 1
    # Fixed: Pass the size parameter in recursive call
    return generate_image(prompt, size, num_retrials: num_retrials)
  else
    return { original_prompt: prompt, success: false, message: "Error: Image generation failed after multiple attempts." }
  end
end

res = generate_image(options[:prompt], options[:size])
puts JSON.pretty_generate(res)
