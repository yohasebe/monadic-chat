require "json"

module Monadic
  module Utils
    class ModelSpec
      class << self
        def load_spec
          return @spec if @spec
          begin
            js_content = read_model_spec_js
            base_spec = js_content ? extract_js_object(js_content, "modelSpec") : {}

            # Then, apply overrides from models.json if it exists
            override_path = File.expand_path("~/monadic/config/models.json")
            merged_spec = if File.exist?(override_path)
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
            # Return normalized spec for caching
            @spec = normalize_spec(merged_spec)
          rescue JSON::ParserError => e
            puts "Warning: Failed to parse model_spec.js: #{e.message}"
            @spec = {}
          end
          @spec
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
          resolved_name = resolve_model_alias(model_name)
          load_spec[resolved_name] || {}
        end

        # Normalize model name by removing date suffixes
        # Examples:
        #   gpt-5-2025-08-07 -> gpt-5
        #   claude-sonnet-4-5-20250929 -> claude-sonnet-4-5
        #   gemini-2.5-flash-002 -> gemini-2.5-flash
        #   command-a-vision-07-2025 -> command-a-vision
        def normalize_model_name(model_name)
          return model_name unless model_name.is_a?(String)

          # YYYY-MM-DD format (OpenAI, xAI)
          if model_name =~ /-\d{4}-\d{2}-\d{2}$/
            return model_name.sub(/-\d{4}-\d{2}-\d{2}$/, '')
          end

          # YYYYMMDD format (Claude) - validate it's a real date
          if model_name =~ /-(\d{8})$/
            date_str = $1
            year = date_str[0..3].to_i
            month = date_str[4..5].to_i
            day = date_str[6..7].to_i
            if year >= 2020 && year <= 2030 && month >= 1 && month <= 12 && day >= 1 && day <= 31
              return model_name.sub(/-\d{8}$/, '')
            end
          end

          # MM-YYYY format (Cohere)
          if model_name =~ /-(\d{2})-(\d{4})$/
            month = $1.to_i
            year = $2.to_i
            if year >= 2020 && year <= 2030 && month >= 1 && month <= 12
              return model_name.sub(/-\d{2}-\d{4}$/, '')
            end
          end

          # MM-DD format (Gemini) - heuristic check
          if model_name =~ /-(\d{2})-(\d{2})$/
            first = $1.to_i
            second = $2.to_i
            if first >= 1 && first <= 12 && second >= 1 && second <= 31
              return model_name.sub(/-\d{2}-\d{2}$/, '')
            end
          end

          # -exp-MMDD format (Gemini experimental)
          if model_name =~ /-exp-(\d{2})(\d{2})$/
            month = $1.to_i
            day = $2.to_i
            if month >= 1 && month <= 12 && day >= 1 && day <= 31
              return model_name.sub(/-exp-\d{4}$/, '')
            end
          end

          # YYMM format (Mistral) - 2509 means 2025-09
          if model_name =~ /-(\d{4})$/
            date_str = $1
            yy = date_str[0..1].to_i
            mm = date_str[2..3].to_i
            # Validate: year 20-30 (2020-2030), month 01-12
            if yy >= 20 && yy <= 30 && mm >= 1 && mm <= 12
              return model_name.sub(/-\d{4}$/, '')
            end
          end

          # -NNN format (Gemini version numbers like -001, -002)
          if model_name =~ /-\d{3}$/
            return model_name.sub(/-\d{3}$/, '')
          end

          model_name
        end

        # Resolve model name to handle aliases
        # If dated model doesn't exist in spec, try base model
        def resolve_model_alias(model_name)
          return model_name unless model_name.is_a?(String)

          spec = load_spec

          # If model exists directly, use it
          return model_name if spec.key?(model_name)

          # Try normalized (dateless) version
          base_name = normalize_model_name(model_name)
          return base_name if base_name != model_name && spec.key?(base_name)

          # Return original if no match found
          model_name
        end

        # Check if a model exists in model_spec.js
        # Handles both direct model names and dated versions that resolve to base models
        def model_exists?(model_name)
          return false unless model_name.is_a?(String)
          return false if model_name.strip.empty?

          spec = load_spec

          # Check if model exists directly
          return true if spec.key?(model_name)

          # Check if normalized (dateless) version exists
          base_name = normalize_model_name(model_name)
          return true if base_name != model_name && spec.key?(base_name)

          false
        end

        def model_has_property?(model_name, property)
          spec = get_model_spec(model_name)
          spec.key?(property.to_s)
        end
        
        def get_model_property(model_name, property)
          spec = get_model_spec(model_name)
          spec[property.to_s]
        end

        # Canonicalized accessors (prefer these over raw get_model_property going forward)
        def tool_capability?(model_name)
          get_model_property(model_name, "tool_capability") != false
        end

        def supports_streaming?(model_name)
          prop = get_model_property(model_name, "supports_streaming")
          prop.nil? ? true : !!prop
        end

        def vision_capability?(model_name)
          prop = get_model_property(model_name, "vision_capability")
          prop.nil? ? true : !!prop
        end

        def supports_pdf?(model_name)
          !!get_model_property(model_name, "supports_pdf")
        end

        def supports_pdf_upload?(model_name)
          !!get_model_property(model_name, "supports_pdf_upload")
        end

        def supports_web_search?(model_name)
          get_model_property(model_name, "supports_web_search") == true
        end
        
        def supports_verbosity?(model_name)
          # Support both old format (supports_verbosity: true) and new format (verbosity: [[options], default])
          return true if get_model_property(model_name, "supports_verbosity") == true
          verbosity = get_model_property(model_name, "verbosity")
          verbosity.is_a?(Array) && verbosity.length == 2
        end

        def get_verbosity_options(model_name)
          verbosity = get_model_property(model_name, "verbosity")
          return nil unless verbosity.is_a?(Array) && verbosity.length == 2

          options = verbosity[0]
          default = verbosity[1]

          { options: options, default: default }
        end
        
        def skip_in_progress_events?(model_name)
          get_model_property(model_name, "skip_in_progress_events") == true
        end

        def is_agent_model?(model_name)
          get_model_property(model_name, "is_agent_model") == true
        end

        def agent_type(model_name)
          get_model_property(model_name, "agent_type")
        end

        def adaptive_reasoning?(model_name)
          get_model_property(model_name, "adaptive_reasoning") == true
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

        def supports_adaptive_thinking?(model_name)
          get_model_property(model_name, "supports_adaptive_thinking") == true
        end

        # True when the provider's API returns 400 on any temperature/top_p/top_k
        # value. Callers must omit sampling params entirely for these models.
        # Currently applies to Claude Opus 4.7+.
        def rejects_sampling_params?(model_name)
          get_model_property(model_name, "rejects_sampling_params") == true
        end

        # True when the provider's default is to return an empty thinking block.
        # Callers who want visible reasoning must explicitly request display.
        # Currently applies to Claude Opus 4.7+.
        def thinking_display_default_omitted?(model_name)
          get_model_property(model_name, "thinking_display_default_omitted") == true
        end

        def supports_thinking_level?(model_name)
          get_model_property(model_name, "supports_thinking_level") == true
        end

        def get_thinking_level_options(model_name)
          levels = get_model_property(model_name, "thinking_level")
          return nil unless levels.is_a?(Array) && levels.length == 2
          options = levels[0]
          default = levels[1]
          { options: options, default: default }
        end

        def supports_context_management?(model_name)
          get_model_property(model_name, "supports_context_management") == true
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

        def supports_structured_outputs?(model_name)
          get_model_property(model_name, "structured_output") == true
        end

        def get_structured_output_mode(model_name)
          get_model_property(model_name, "structured_output_mode")
        end

        def get_structured_output_beta(model_name)
          get_model_property(model_name, "structured_output_beta")
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

        def supports_file_inputs?(model_name)
          !!get_model_property(model_name, "supports_file_inputs")
        end

        # --- TTS accessors ---

        # Canonical TTS family key (openai-instruction / openai / xai /
        # gemini / elevenlabs-v3 / elevenlabs / mistral). Nil when the model
        # has no TTS metadata.
        def tts_family(model_name)
          get_model_property(model_name, "tts_family")
        end

        # True when the model accepts the out-of-band `instructions`
        # parameter (OpenAI gpt-4o-mini-tts).
        def tts_instructions?(model_name)
          get_model_property(model_name, "tts_instructions_capability") == true
        end

        # Supported voice list for the TTS model, or nil when unknown.
        def tts_voices(model_name)
          get_model_property(model_name, "tts_voices")
        end

        # Preferred default voice for the TTS model, or nil when unknown.
        def tts_default_voice(model_name)
          get_model_property(model_name, "tts_default_voice")
        end

        def deprecated?(model_name)
          get_model_property(model_name, "deprecated") == true
        end

        def ui_hidden?(model_name)
          get_model_property(model_name, "ui_hidden") == true
        end

        # --- Provider Defaults accessors ---

        # Load and cache the providerDefaults object from model_spec.js
        def load_provider_defaults
          return @provider_defaults if @provider_defaults

          js_content = read_model_spec_js
          @provider_defaults = js_content ? extract_js_object(js_content, "providerDefaults") : {}
        rescue => e
          puts "Warning: Failed to load providerDefaults: #{e.message}"
          @provider_defaults = {}
        end

        # Get the default model (first in list) for a provider and category
        def get_provider_default(provider, category = "chat")
          models = get_provider_models(provider, category)
          models&.first
        end

        # Get the full model list for a provider and category
        def get_provider_models(provider, category = "chat")
          defaults = load_provider_defaults
          key = normalize_provider_key(provider)
          provider_entry = defaults[key]
          return nil unless provider_entry

          provider_entry[category.to_s]
        end

        # Convenience accessors
        def default_chat_model(provider)
          get_provider_default(provider, "chat")
        end

        def default_code_model(provider)
          get_provider_default(provider, "code")
        end

        def default_vision_model(provider)
          get_provider_default(provider, "vision")
        end

        def default_audio_model(provider)
          get_provider_default(provider, "audio_transcription")
        end

        def default_image_model(provider)
          get_provider_default(provider, "image")
        end

        def default_video_model(provider)
          get_provider_default(provider, "video")
        end

        def default_tts_model(provider)
          get_provider_default(provider, "tts")
        end

        def default_embedding_model(provider)
          get_provider_default(provider, "embedding")
        end

        def reload!
          @spec = nil
          @provider_defaults = nil
          remove_instance_variable(:@js_content) if defined?(@js_content)
          load_spec
        end

        private

        # Read and cache the model_spec.js file content (shared between load_spec and load_provider_defaults)
        def read_model_spec_js
          return @js_content if defined?(@js_content)

          spec_path = File.join(
            File.dirname(__FILE__),
            "..", "..", "..",
            "public", "js", "monadic", "model_spec.js"
          )
          @js_content = File.exist?(spec_path) ? File.read(spec_path) : nil
        end

        # Extract a JavaScript object assigned to `const <var_name> = { ... }` using brace matching.
        # Returns a Ruby Hash, or {} if not found.
        def extract_js_object(js_content, var_name)
          pattern = /const\s+#{Regexp.escape(var_name)}\s*=\s*\{/
          return {} unless js_content =~ pattern

          start_pos = js_content.index(pattern)
          start_pos = js_content.index("{", start_pos)

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

          return {} unless end_pos

          json_string = js_content[start_pos..end_pos]
          # Clean up JavaScript syntax to make it valid JSON
          json_string = json_string.gsub(%r{//.*$}, "")
          json_string = json_string.gsub(%r{/\*.*?\*/}m, "")
          json_string = json_string.gsub(/,(\s*[}\]])/, '\1')

          JSON.parse(json_string)
        rescue JSON::ParserError
          {}
        end

        # Normalize provider key aliases to canonical keys used in providerDefaults
        def normalize_provider_key(provider)
          key = provider.to_s.strip.downcase
          case key
          when "google"    then "gemini"
          when "claude"    then "anthropic"
          when "grok"      then "xai"
          else key
          end
        end

        # Normalize alias properties into canonical names without removing the originals.
        # This helps keep a single vocabulary across providers while staying backward compatible.
        def normalize_spec(spec)
          return spec unless spec.is_a?(Hash)

          spec.each do |model, props|
            next unless props.is_a?(Hash)

            # reasoning_model -> is_reasoning_model
            if props.key?("reasoning_model") && !props.key?("is_reasoning_model")
              props["is_reasoning_model"] = !!props["reasoning_model"]
            end

            # websearch_capability / websearch -> supports_web_search
            if !props.key?("supports_web_search")
              if props.key?("websearch_capability")
                props["supports_web_search"] = !!props["websearch_capability"]
              elsif props.key?("websearch")
                props["supports_web_search"] = !!props["websearch"]
              end
            end

            # is_slow_model -> latency_tier: "slow"
            if props["is_slow_model"] == true && !props.key?("latency_tier")
              props["latency_tier"] = "slow"
            end

            # responses_api (bool) -> api_type: "responses"
            if props["responses_api"] == true && !props.key?("api_type")
              props["api_type"] = "responses"
            end

            # For UI clarity: if supports_pdf is true but supports_pdf_upload is explicitly false for some providers,
            # keep as-is (Perplexity). Do not auto-populate supports_pdf_upload to avoid changing behavior.
          end

          spec
        end
      end
    end
  end
end
