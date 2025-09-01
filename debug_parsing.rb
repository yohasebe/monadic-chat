#!/usr/bin/env ruby

spec_path = "./docker/services/ruby/public/js/monadic/model_spec.js"
js_content = File.read(spec_path)

puts "File size: #{js_content.size} bytes"
puts "=" * 50

# Try the regex
if js_content =~ /const\s+modelSpec\s*=\s*\{(.*)\};/m
  puts "Regex matched!"
  json_string = "{#{$1}}"
  puts "Extracted content size: #{json_string.size} bytes"
  puts "First 200 chars:"
  puts json_string[0..200]
else
  puts "Regex did NOT match"
  
  # Try alternate regex
  if js_content =~ /const\s+modelSpec\s*=\s*\{/
    puts "Found start of modelSpec"
    start_pos = js_content.index(/const\s+modelSpec\s*=\s*\{/)
    puts "Start position: #{start_pos}"
    
    # Look for the closing brace
    brace_count = 0
    in_object = false
    end_pos = nil
    
    js_content[start_pos..-1].each_char.with_index do |char, i|
      if char == '{'
        brace_count += 1
        in_object = true if brace_count == 1
      elsif char == '}'
        brace_count -= 1
        if brace_count == 0 && in_object
          end_pos = start_pos + i
          break
        end
      end
    end
    
    if end_pos
      puts "End position: #{end_pos}"
      object_content = js_content[start_pos..end_pos]
      puts "Object length: #{object_content.size}"
      puts "Last 100 chars:"
      puts object_content[-100..-1]
    else
      puts "Could not find matching closing brace"
    end
  end
end