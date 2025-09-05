require "json"

module Monadic
  module Utils
    class ModelSpec
      class << self
        def load_spec
          @spec ||= begin
            # First, load the default model_spec.js
            spec_path = File.join(
              File.dirname(__FILE__), 
              "..", "..", "..", 
              "public", "js", "monadic", "model_spec.js"
            )
            
            base_spec = if File.exist?(spec_path)
              # Read the JavaScript file
              js_content = File.read(spec_path)
              
              # Find the modelSpec object using brace matching
              if js_content =~ /const\s+modelSpec\s*=\s*\{/
                start_pos = js_content.index(/const\s+modelSpec\s*=\s*\{/)
                start_pos = js_content.index("{", start_pos)
                
                # Find matching closing brace
                brace_count = 0
                end_pos = nil
                
                js_content[start_pos..-1].each_char.with_index do |char, i|
                  if char == '{'
                    brace_count += 1
                  elsif char == '}'
                    brace_count -= 1
                    if brace_count == 0
                      end_pos = start_pos + i
                      break
                    end
                  end
                end
                
                if end_pos
                  json_string = js_content[start_pos..end_pos]
                  
                  # Clean up JavaScript syntax to make it valid JSON
                  # Remove single-line comments
                  json_string = json_string.gsub(%r{//.*$}, "")
                  # Remove multi-line comments
                  json_string = json_string.gsub(%r{/\*.*?\*/}m, "")
                  
                  # Handle trailing commas
                  json_string = json_string.gsub(/,(\s*[}\]])/, '\1')
                  
                  # Parse the JSON
                  JSON.parse(json_string)
                else
                  {}
                end
              else
                {}
              end
            else
              {}
            end
            
            # Then, apply overrides from models.json if it exists
            override_path = File.expand_path("~/monadic/config/models.json")
            if File.exist?(override_path)
              begin
                override_spec = JSON.parse(File.read(override_path))
                # Deep merge the override spec into base spec
                deep_merge_specs(base_spec, override_spec)
              rescue JSON::ParserError => e
                puts "Warning: Failed to parse models.json: #{e.message}"
                base_spec
              end
            else
              base_spec
            end
          rescue JSON::ParserError => e
            puts "Warning: Failed to parse model_spec.js: #{e.message}"
            {}
          end
        end
        
        def deep_merge_specs(base, override)
          override.each do |model_name, model_override|
            if base.key?(model_name)
              # Model exists, merge properties
              model_override.each do |prop, value|
                base[model_name][prop] = value
              end
            else
              # New model, add it
              base[model_name] = model_override
            end
          end
          base
        end
        
        def get_model_spec(model_name)
          load_spec[model_name] || {}
        end
        
        def model_has_property?(model_name, property)
          spec = get_model_spec(model_name)
          spec.key?(property.to_s)
        end
        
        def get_model_property(model_name, property)
          spec = get_model_spec(model_name)
          spec[property.to_s]
        end
        
        def supports_verbosity?(model_name)
          get_model_property(model_name, "supports_verbosity") == true
        end
        
        def skip_in_progress_events?(model_name)
          get_model_property(model_name, "skip_in_progress_events") == true
        end
        
        def get_reasoning_effort_options(model_name)
          reasoning_effort = get_model_property(model_name, "reasoning_effort")
          return nil unless reasoning_effort.is_a?(Array) && reasoning_effort.length == 2
          
          options = reasoning_effort[0]
          default = reasoning_effort[1]
          
          { options: options, default: default }
        end
        
        def supports_reasoning_effort_minimal?(model_name)
          effort_config = get_reasoning_effort_options(model_name)
          return false unless effort_config
          
          effort_config[:options].include?("minimal")
        end
        
        def supports_thinking?(model_name)
          get_model_property(model_name, "supports_thinking") == true
        end
        
        def supports_web_search?(model_name)
          get_model_property(model_name, "supports_web_search") == true
        end

        def responses_api?(model_name)
          get_model_property(model_name, "api_type") == "responses"
        end
        
        def supports_parallel_function_calling?(model_name)
          get_model_property(model_name, "supports_parallel_function_calling") == true
        end
        
        def get_websearch_fallback(model_name)
          get_model_property(model_name, "fallback_for_websearch")
        end
        
        def get_thinking_constraints(model_name)
          get_model_property(model_name, "thinking_constraints")
        end
        
        def get_thinking_budget(model_name)
          get_model_property(model_name, "thinking_budget")
        end
        
        def supports_reasoning_content?(model_name)
          get_model_property(model_name, "supports_reasoning_content") == true
        end
        
        def is_reasoning_model?(model_name)
          get_model_property(model_name, "is_reasoning_model") == true
        end
        
        def reload!
          @spec = nil
          load_spec
        end
      end
    end
  end
end
