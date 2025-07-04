#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to update Chat apps with web search capability

require 'fileutils'

WEB_SEARCH_PROMPT = <<~PROMPT
  
  I have access to web search when needed. I'll use it when:
  - You ask about current events or recent information
  - You need facts about specific people, companies, or organizations  
  - You want the latest information on any topic
  - The question would benefit from up-to-date sources
  
  I'll search efficiently and provide relevant information with sources when available.
PROMPT

def update_chat_app(file_path)
  puts "Updating #{File.basename(file_path)}..."
  
  content = File.read(file_path)
  
  # Check if already has tools block
  has_tools_block = content.match(/tools\s+do/)
  
  # Update system prompt - find the end of the prompt and insert before PROMPT marker
  content = content.gsub(/(If the response is too long.*?when viewed as HTML\.)\s*(\n\s*PROMPT)/m) do
    "#{$1}#{WEB_SEARCH_PROMPT.chomp}#{$2}"
  end
  
  # For files that have different prompt endings, try another pattern
  if !content.include?("I have access to web search")
    content = content.gsub(/(\.\s*)\n(\s*PROMPT)/m) do |match|
      if match.include?("HTML") || match.include?("response") || match.include?("emoji")
        "#{$1}#{WEB_SEARCH_PROMPT}#{$2}"
      else
        match
      end
    end
  end
  
  # Update websearch setting
  content = content.gsub(/websearch\s+false/, "websearch true")
  
  # Add websearch true if not present
  if !content.match(/websearch\s+(true|false)/)
    content = content.gsub(/(features\s+do\s*\n.*?)(  end)/m) do
      features_content = $1
      end_marker = $2
      "#{features_content}    websearch true\n#{end_marker}"
    end
  end
  
  # Add tools block if missing
  if !has_tools_block
    content = content.gsub(/(\s*end\s*\Z)/m, "\n  \n  tools do\n  end\n\\1")
  end
  
  # Write back
  File.write(file_path, content)
  puts "  ✓ Updated successfully"
rescue => e
  puts "  ✗ Error: #{e.message}"
end

# Find all Chat app files
chat_apps = Dir.glob(File.join(__dir__, "../apps/chat/chat_*.mdsl"))

puts "Found #{chat_apps.length} Chat apps to update\n\n"

chat_apps.each do |app_file|
  # Skip if already has web search enabled and proper structure
  content = File.read(app_file)
  if content.include?("websearch true") && content.include?("I have access to web search")
    puts "Skipping #{File.basename(app_file)} - already updated"
    next
  end
  
  update_chat_app(app_file)
end

puts "\nUpdate complete!"
puts "\nTo verify changes, run:"
puts "  bundle exec rspec spec/system/chat_websearch_system_spec.rb"