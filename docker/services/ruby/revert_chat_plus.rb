#!/usr/bin/env ruby

# Revert Chat Plus apps to monadic true and remove tools
# (Except OpenAI which works with both)

providers = ["claude", "gemini", "grok", "mistral", "deepseek", "cohere"]

providers.each do |provider|
  file_path = "apps/chat_plus/chat_plus_#{provider}.mdsl"
  
  if File.exist?(file_path)
    puts "Reverting #{provider}..."
    content = File.read(file_path)
    
    # 1. Change monadic false back to monadic true
    content.gsub!(/monadic false.*$/, 'monadic true')
    puts "  - Changed monadic to true"
    
    # 2. Remove the tools section
    content.gsub!(/\n\s*tools do.*?\n\s*end\s*$/m, '')
    puts "  - Removed tools section"
    
    # 3. Remove file operations section from system prompt
    content.gsub!(/## File Operations.*?Only use file operation tools when explicitly requested or clearly necessary for the task\.\s*/m, '')
    puts "  - Removed file operations section"
    
    # 4. Remove tool usage instructions and context tracking
    content.gsub!(/When you use tools:.*?This mental tracking ensures continuity.*?when relevant\./m, '')
    puts "  - Removed tool usage instructions"
    
    # 5. Restore JSON structure instructions for monadic mode
    if provider == "claude"
      # Claude needs explicit JSON instructions
      unless content.include?("IMPORTANT: You MUST structure your ENTIRE response")
        json_instructions = <<~'TEXT'
    IMPORTANT: You MUST structure your ENTIRE response as a valid JSON object with the following structure:
    {
      "message": "Your response to the user",
      "context": {
        "reasoning": "The reasoning and thought process behind your response",
        "topics": ["topic1", "topic2", ...],
        "people": ["person1 and their relationship", "person2 and their relationship", ...],
        "notes": ["user preference 1", "important date/location/event", ...]
      }
    }

    Requirements:
    - The response MUST be valid JSON - no text before or after the JSON object
    - "message": Your response to the user (can include markdown formatting)
    - "reasoning": Explain your thought process for this response
    - "topics": Array of ALL topics discussed in the entire conversation (accumulated)
    - "people": Array of ALL people and their relationships mentioned (accumulated)
    - "notes": Array of ALL user preferences, important dates, locations, and events (accumulated)

    Remember: The lists in the context object should be ACCUMULATED - do not remove any items unless the user explicitly asks you to do so. Each response should include all previously mentioned items plus any new ones.
TEXT
        content.sub!(/While keeping the conversation going.*?update these notes as the conversation progresses\.\s*/m,
                    "While keeping the conversation going, you take notes on various aspects of the conversation, such as the topics discussed, the people mentioned, and other important information provided by the user. You should update these notes as the conversation progresses.\n\n#{json_instructions}")
        puts "  - Restored JSON instructions for Claude"
      end
    else
      # For other providers, restore standard JSON format instructions
      unless content.include?("Your response should")
        json_instructions = <<~'TEXT'
    Your response should be contained in a JSON object with the following structure:
    - "message": Your response to the user
    - "context": An object containing the following properties:
      - "reasoning": The reasoning and thought process behind your response
      - "topics": A list of topics ever discussed in the whole conversation
      - "people": A list of people and their relationships ever mentioned in the whole conversation
      - "notes": A list of the user's preferences and other important information including important dates, locations, and events ever mentioned in the whole conversation and should be remembered throughout the conversation

    You should update the "reasoning", "topics", "people", and "notes" properties of the "context" object as the conversation progresses. Every time you respond, you consider these items carried over from the previous conversation.

    Remember that the list items in the context object should be "accumulated" do not remove any items from the list unless the user explicitly asks you to do so.
TEXT
        content.sub!(/While keeping the conversation going.*?update these notes as the conversation progresses\.\s*/m,
                    "While keeping the conversation going, you take notes on various aspects of the conversation, such as the topics discussed, the people mentioned, and other important information provided by the user. You should update these notes as the conversation progresses.\n\n#{json_instructions}")
        puts "  - Restored JSON instructions"
      end
    end
    
    # Add response_format for specific providers if needed
    if provider == "grok" && !content.include?("response_format")
      content.sub!(/model "grok-.*?"/, "model \"grok-4-fast-reasoning\"\n    response_format({ type: \"json_object\" })")
      puts "  - Added response_format for Grok"
    end
    
    File.write(file_path, content)
    puts "  - Saved #{file_path}"
  else
    puts "File not found: #{file_path}"
  end
  puts
end

puts "Revert complete!"
puts "\nNote: OpenAI Chat Plus remains unchanged (supports both monadic and tools)"
