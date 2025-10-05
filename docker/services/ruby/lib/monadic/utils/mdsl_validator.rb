# frozen_string_literal: true

module Monadic
  module Utils
    class MDSLValidator
      # Validate MDSL configuration against model specifications
      class << self
        def validate_reasoning_parameters(app_config, provider, model)
          errors = []
          warnings = []
          
          # Get model spec from ModelSpec
          model_spec = ModelSpec.get_model_spec(model)
          return { errors: ["Model '#{model}' not found in specifications"], warnings: [] } unless model_spec
          
          # Check reasoning/thinking parameters based on provider
          case provider
          when 'OpenAI'
            validate_openai_reasoning(app_config, model_spec, errors, warnings)
          when 'Anthropic'
            validate_anthropic_thinking(app_config, model_spec, errors, warnings)
          when 'Google'
            validate_gemini_thinking(app_config, model_spec, errors, warnings)
          when 'xAI'
            validate_grok_reasoning(app_config, model_spec, errors, warnings)
          when 'DeepSeek'
            validate_deepseek_reasoning(app_config, model_spec, errors, warnings)
          when 'Perplexity'
            validate_perplexity_reasoning(app_config, model_spec, errors, warnings)
          when 'Mistral', 'Cohere'
            validate_no_reasoning(app_config, provider, errors, warnings)
          end
          
          { errors: errors, warnings: warnings }
        end
        
        private
        
        def validate_openai_reasoning(config, spec, errors, warnings)
          if config[:reasoning_effort]
            if spec[:reasoning_effort]
              valid_values = spec[:reasoning_effort].first if spec[:reasoning_effort].is_a?(Array)
              unless valid_values&.include?(config[:reasoning_effort])
                errors << "Invalid reasoning_effort '#{config[:reasoning_effort]}' for OpenAI model. Valid values: #{valid_values&.join(', ')}"
              end
            else
              warnings << "Model doesn't support reasoning_effort parameter, it will be ignored"
            end
          end
          
          # Check for incorrect parameters
          if config[:thinking_budget]
            errors << "OpenAI models use 'reasoning_effort', not 'thinking_budget'"
          end
          if config[:reasoning_content]
            errors << "OpenAI models use 'reasoning_effort', not 'reasoning_content'"
          end
        end
        
        def validate_anthropic_thinking(config, spec, errors, warnings)
          # Anthropic doesn't use explicit thinking parameters in MDSL
          # It's handled internally based on model capabilities
          if config[:reasoning_effort]
            errors << "Anthropic models don't use 'reasoning_effort' in MDSL configuration"
          end
          if config[:thinking_budget]
            warnings << "thinking_budget is automatically managed for Anthropic models"
          end
        end
        
        def validate_gemini_thinking(config, spec, errors, warnings)
          # Gemini uses internal thinking_budget but not in MDSL
          if config[:reasoning_effort]
            errors << "Gemini models don't use 'reasoning_effort' in MDSL configuration"
          end
          if config[:thinking_budget]
            warnings << "thinking_budget is automatically managed for Gemini models"
          end
        end
        
        def validate_grok_reasoning(config, spec, errors, warnings)
          if config[:reasoning_effort]
            if spec[:reasoning_effort]
              valid_values = spec[:reasoning_effort].first if spec[:reasoning_effort].is_a?(Array)
              unless valid_values&.include?(config[:reasoning_effort])
                errors << "Invalid reasoning_effort '#{config[:reasoning_effort]}' for xAI model. Valid values: #{valid_values&.join(', ')}"
              end
            else
              warnings << "Model doesn't support reasoning_effort parameter, it will be ignored"
            end
          end
        end
        
        def validate_deepseek_reasoning(config, spec, errors, warnings)
          # DeepSeek uses reasoning_content internally but not in MDSL
          if config[:reasoning_effort]
            errors << "DeepSeek models don't use 'reasoning_effort' in MDSL configuration"
          end
          if config[:reasoning_content]
            warnings << "reasoning_content is automatically managed for DeepSeek models"
          end
        end
        
        def validate_perplexity_reasoning(config, spec, errors, warnings)
          if config[:reasoning_effort]
            if spec[:reasoning_effort]
              valid_values = spec[:reasoning_effort].first if spec[:reasoning_effort].is_a?(Array)
              unless valid_values&.include?(config[:reasoning_effort])
                errors << "Invalid reasoning_effort '#{config[:reasoning_effort]}' for Perplexity model. Valid values: #{valid_values&.join(', ')}"
              end
            else
              warnings << "Model doesn't support reasoning_effort parameter, it will be ignored"
            end
          end
        end
        
        def validate_no_reasoning(config, provider, errors, warnings)
          if config[:reasoning_effort]
            errors << "#{provider} models don't support reasoning_effort parameter"
          end
          if config[:thinking_budget]
            errors << "#{provider} models don't support thinking_budget parameter"
          end
          if config[:reasoning_content]
            errors << "#{provider} models don't support reasoning_content parameter"
          end
        end
      end
    end
  end
end