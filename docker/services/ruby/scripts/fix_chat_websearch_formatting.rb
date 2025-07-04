#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fix formatting issues in Chat apps after web search update

def fix_chat_app_formatting(file_path)
  puts "Fixing #{File.basename(file_path)}..."
  
  content = File.read(file_path)
  original_content = content.dup
  
  # Fix indentation issues in web search prompt
  content = content.gsub(/(\n)I have access to web search when needed/m, '\1  I have access to web search when needed')
  content = content.gsub(/\n- You ask about/m, '\n  - You ask about')
  content = content.gsub(/\n- You need facts/m, '\n  - You need facts')
  content = content.gsub(/\n- You want the latest/m, '\n  - You want the latest')
  content = content.gsub(/\n- The question would/m, '\n  - The question would')
  content = content.gsub(/\nI'll search efficiently/m, '\n  I\'ll search efficiently')
  
  # Remove extra blank lines before 'end'
  content = content.gsub(/\n\n+end\s*\Z/m, "\nend\n")
  
  # Special handling for Ollama - add web search prompt if missing
  if file_path.include?("chat_ollama") && !content.include?("I have access to web search")
    content = content.gsub(/(at the beginning of your response\.)\s*(\n\s*PROMPT)/m) do
      "#{$1}\n  \n  I have access to web search when needed. I'll use it when:\n  - You ask about current events or recent information\n  - You need facts about specific people, companies, or organizations  \n  - You want the latest information on any topic\n  - The question would benefit from up-to-date sources\n  \n  I'll search efficiently and provide relevant information with sources when available.#{$2}"
    end
  end
  
  # Write back only if changed
  if content != original_content
    File.write(file_path, content)
    puts "  ✓ Fixed formatting"
  else
    puts "  ✓ No changes needed"
  end
rescue => e
  puts "  ✗ Error: #{e.message}"
end

# Find all Chat app files
chat_apps = Dir.glob(File.join(__dir__, "../apps/chat/chat_*.mdsl"))

puts "Checking #{chat_apps.length} Chat apps for formatting issues\n\n"

chat_apps.each do |app_file|
  fix_chat_app_formatting(app_file)
end

puts "\nFormatting fixes complete!"