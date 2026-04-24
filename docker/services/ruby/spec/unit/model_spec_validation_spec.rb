require "spec_helper"
require "json"
require "http"

# Require the vendor helpers directly
require_relative "../../lib/monadic/adapters/vendors/openai_helper"
require_relative "../../lib/monadic/adapters/vendors/claude_helper"
require_relative "../../lib/monadic/adapters/vendors/cohere_helper"
require_relative "../../lib/monadic/adapters/vendors/mistral_helper"
require_relative "../../lib/monadic/adapters/vendors/grok_helper"
require_relative "../../lib/monadic/adapters/vendors/deepseek_helper"
require_relative "../../lib/monadic/adapters/vendors/perplexity_helper"

# Define PROJECT_ROOT if not already defined
PROJECT_ROOT ||= File.expand_path("../..", __dir__)

# Normalize model name by removing date suffixes
# e.g., "gpt-5.5-2026-04-23" → "gpt-5.5"
def normalize_model_name(model)
  model.sub(/-\d{4}-\d{2}-\d{2}$/, '')
end

# Check if model should be excluded from model_spec.js
# Excludes audio, realtime, TTS, STT, transcription, image/video generation, embedding, and code-only models
# Policy: model_spec.js only contains chat/reasoning models, not TTS/STT/transcription models
def should_exclude_from_model_spec?(model)
  # Audio and realtime models
  return true if model.include?('audio-preview') || model.include?('audio')
  return true if model.include?('realtime')
  # TTS (Text-to-Speech) models
  return true if model.match?(/^tts-/)
  # STT (Speech-to-Text) / Transcription models
  return true if model.match?(/^whisper-/)
  return true if model.include?('transcribe')  # gpt-4o-transcribe, gpt-4o-mini-transcribe, etc.
  # Image/Video generation models
  return true if model.match?(/^dall-e/)
  return true if model.match?(/^gpt-image/)
  return true if model.match?(/^chatgpt-image/)
  return true if model.match?(/^sora/)
  # Embedding models
  return true if model.match?(/^text-embedding/)
  # Voice models (Mistral voxtral series)
  return true if model.match?(/^voxtral/)
  # Code-only models that are not general chat models (devstral is code-only)
  return true if model.match?(/^devstral/)
  # CLI-only models (not usable via standard chat API)
  return true if model.include?('vibe-cli')
  false
end

# Initialize global models cache
$MODELS ||= {}

RSpec.describe "Model Specification Validation" do
  let(:model_spec_path) { File.join(PROJECT_ROOT, "public/js/monadic/model_spec.js") }
  let(:model_spec) do
    content = File.read(model_spec_path)

    # Simple and robust extraction using regex
    begin
      # Extract all model names (quoted strings followed by a colon and opening brace)
      # This will match lines like:   "gpt-4.5-preview-2025-02-27": {
      model_names = content.scan(/^\s*"([^"]+)"\s*:\s*\{/)

      # Convert to hash with empty values (we only need the keys)
      model_names.flatten.each_with_object({}) { |key, hash| hash[key] = {} }
    rescue => e
      puts "Error extracting model_spec: #{e.message}"
      {}
    end
  end

  # Helper to check deprecated flag for a specific model
  def model_deprecated?(model_name)
    content = File.read(model_spec_path)
    # Find the model's configuration block
    if content =~ /"#{Regexp.escape(model_name)}"\s*:\s*\{([^}]*"deprecated"\s*:\s*(true|false))/m
      $2 == 'true'
    else
      false  # If no deprecated flag found, assume not deprecated
    end
  end

  # Provider Model Synchronization
  # model_spec.js is the SSOT — discrepancies with provider APIs are
  # reported for informational purposes only, not as test failures.
  # Use the report output below to identify models that may need attention.

  describe "Model Specification Report" do
    it "generates a comprehensive report of model status" do
      puts "\n" + "=" * 80
      puts "MODEL SPECIFICATION VALIDATION REPORT"
      puts "=" * 80
      
      providers = {
        "OpenAI" => { helper: OpenAIHelper, key: "OPENAI_API_KEY", pattern: /^(gpt|o[1-9]|chatgpt|codex)/ },
        "Claude" => { helper: ClaudeHelper, key: "ANTHROPIC_API_KEY", pattern: /^claude/ },
        "Cohere" => { helper: CohereHelper, key: "COHERE_API_KEY", pattern: /^(command|embed|rerank|c4ai)/ },
        "Mistral" => { helper: MistralHelper, key: "MISTRAL_API_KEY", pattern: /^(mistral|open-|codestral|pixtral|ministral|magistral|devstral|voxtral)/ },
        "Grok (xAI)" => { helper: GrokHelper, key: "XAI_API_KEY", pattern: /^grok/ },
        "DeepSeek" => { helper: DeepSeekHelper, key: "DEEPSEEK_API_KEY", pattern: /^deepseek/ },
        "Perplexity" => { helper: PerplexityHelper, key: nil, pattern: /^(sonar|r1)/ }  # No API key needed for hardcoded list
      }
      
      providers.each do |provider_name, config|
        # Perplexity doesn't need an API key (hardcoded list)
        if config[:key].nil? || ENV[config[:key]] || CONFIG[config[:key]]
          begin
            available_models = config[:helper].list_models

            # Exclude TTS/STT/transcription/voice/code-only models from comparison
            available_models = available_models.reject { |m| should_exclude_from_model_spec?(m) }

            models_in_spec = model_spec.keys.select { |k| k.match?(config[:pattern]) }

            missing = available_models - model_spec.keys
            deprecated = models_in_spec - available_models
            
            puts "\n#{provider_name}:"
            puts "  ✓ Models in API: #{available_models.size}"
            puts "  ✓ Models in spec: #{models_in_spec.size}"
            
            if missing.any?
              puts "  ⚠️  Missing in spec: #{missing.join(', ')}"
            end
            
            if deprecated.any?
              puts "  ⚠️  Potentially deprecated: #{deprecated.join(', ')}"
            end
            
            if missing.empty? && deprecated.empty?
              puts "  ✅ All models are in sync!"
            end
          rescue => e
            puts "\n#{provider_name}: ❌ Error - #{e.message}"
          end
        else
          puts "\n#{provider_name}: ⏭️  Skipped (no API key)"
        end
      end
      
      puts "\n" + "=" * 80
    end
  end
end
