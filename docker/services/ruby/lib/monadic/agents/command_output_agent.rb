module MonadicAgent
  def command_output_agent(prompt, content)
    model = "gpt-4o"

    # Use string keys consistently for parameters
    body = {
      "model" => model,
      "temperature" => 0.0,
      "response_format" => {
        "type" => "json_schema",
        "json_schema" => {
          "name" => "examine_response",
          "schema" => {
            "type" => "object",
            "properties" => {
              "result" => {
                "type" => "string",
                "enum" => ["success", "error"]
              },
              "content" => {
                "type" => "string"
              }
            },
            "required" => ["result", "content"],
            "additionalProperties" => false
          },
          "strict" => true
        }
      }
    }

    body["messages"] = [
      { "role" => "system", "content" => prompt },
      { "role" => "user", "content" => content }
    ]
    
    # Debug logging
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
      puts "CommandOutputAgent: Using model #{model} for command output processing"
    end

    json = send_query(body, model: model)
    
    # Remove any markdown code block formatting if it's a string
    if json.is_a?(String)
      # Strip markdown code block syntax (```json, ```, etc.)
      cleaned_json = json.gsub(/```(?:json)?\s*\n?/, '').gsub(/\n```\s*$/, '').strip
      
      begin
        # Attempt to parse the cleaned JSON
        return JSON.parse(cleaned_json)
      rescue JSON::ParserError
        # If that fails, try the original JSON
        begin
          return JSON.parse(json)
        rescue JSON::ParserError
          # If all parsing fails, return error object
          return { "result" => "error", "content" => "Error parsing JSON response" }
        end
      end
    else
      # Return error if not a string
      return { "result" => "error", "content" => "Unexpected response type" }
    end
  end
end
