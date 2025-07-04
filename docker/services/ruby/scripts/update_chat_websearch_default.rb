#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to update websearch default to false for all Chat apps

require 'fileutils'

# Define the directory containing chat apps
apps_dir = File.expand_path('../apps/chat', __dir__)

# Find all chat MDSL files
chat_files = Dir.glob(File.join(apps_dir, 'chat_*.mdsl'))

puts "Found #{chat_files.length} Chat app files to update"

chat_files.each do |file|
  content = File.read(file)
  original_content = content.dup
  
  # Replace websearch true with websearch false
  content.gsub!(/^\s*websearch\s+true\s*$/, '    websearch false')
  
  if content != original_content
    File.write(file, content)
    puts "Updated: #{File.basename(file)}"
  else
    puts "No changes needed: #{File.basename(file)}"
  end
end

puts "\nDone! Chat apps now have websearch defaulted to false."
puts "Users can enable web search manually when needed."