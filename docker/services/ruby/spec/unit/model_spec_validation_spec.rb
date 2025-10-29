require "spec_helper"
require "json"
require "http"
require "yaml"

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
REPO_ROOT ||= File.expand_path("../../..", PROJECT_ROOT)

MISSING_MODELS_MEMO = File.join(REPO_ROOT, "tmp/memo/model_spec_missing_models.md")

def load_missing_model_allowlist
  allowlist = {}
  return allowlist unless File.exist?(MISSING_MODELS_MEMO)

  content = File.read(MISSING_MODELS_MEMO)
  data_section = content.lines.drop_while { |line| !line.lstrip.start_with?('- provider') }.join
  return allowlist if data_section.strip.empty?

  begin
    entries = YAML.safe_load(data_section, permitted_classes: [], permitted_symbols: [], aliases: true)
  rescue Psych::SyntaxError => e
    warn "Failed to parse #{MISSING_MODELS_MEMO}: #{e.message}"
    return allowlist
  end

  Array(entries).each do |entry|
    provider = entry['provider']
    next unless provider
    models = Array(entry['models'])
    allowlist[provider] ||= []
    allowlist[provider].concat(models)
  end

  allowlist.transform_values! { |arr| arr.uniq.freeze }
  allowlist.freeze
  allowlist
end

MISSING_MODEL_ALLOWLIST = load_missing_model_allowlist.freeze

# Normalize model name by removing date suffixes
# e.g., "gpt-5-pro-2025-10-06" → "gpt-5-pro"
def normalize_model_name(model)
  model.sub(/-\d{4}-\d{2}-\d{2}$/, '')
end

# Check if model should be excluded from model_spec.js
# Excludes audio, realtime, TTS, STT, image/video generation, and embedding models
def should_exclude_from_model_spec?(model)
  return true if model.include?('audio-preview') || model.include?('audio')
  return true if model.include?('realtime')
  return true if model.match?(/^tts-/)
  return true if model.match?(/^whisper-/)
  return true if model.match?(/^dall-e/)
  return true if model.match?(/^sora/)
  return true if model.match?(/^text-embedding/)
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

  describe "Provider Model Synchronization" do
    context "OpenAI Models" do
      it "contains all available OpenAI models from the helper" do
        skip "Requires API key" unless ENV["OPENAI_API_KEY"] || CONFIG["OPENAI_API_KEY"]

        available_models = OpenAIHelper.list_models
        skip "No OpenAI models returned; skipping sync check" if available_models.nil? || available_models.empty?

        # Filter for GPT models that should be in model_spec
        gpt_models = available_models.select { |m| m.match?(/^(gpt|o1|chatgpt)/) }

        # Exclude models that don't belong in model_spec (audio, realtime, generation, embeddings)
        gpt_models = gpt_models.reject { |m| should_exclude_from_model_spec?(m) }

        # Normalize model names (remove date suffixes like -2025-10-06)
        normalized_gpt_models = gpt_models.map { |m| normalize_model_name(m) }.uniq

        model_spec_keys = model_spec.keys
        missing_models = normalized_gpt_models - model_spec_keys
        missing_models -= Array(MISSING_MODEL_ALLOWLIST['openai'])

        if missing_models.any?
          puts "\n⚠️  Missing OpenAI models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end

        expect(missing_models).to be_empty,
          "model_spec.js is missing these OpenAI models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated OpenAI models" do
        skip "Requires API key" unless ENV["OPENAI_API_KEY"] || CONFIG["OPENAI_API_KEY"]

        available_models = OpenAIHelper.list_models
        skip "No OpenAI models returned; skipping deprecated check" if available_models.nil? || available_models.empty?

        # Find OpenAI models in model_spec that are not in the API response
        openai_models_in_spec = model_spec.keys.select { |k| k.match?(/^(gpt|o1|chatgpt)/) }

        # Exclude audio/realtime/generation models from deprecated check (they don't belong in model_spec)
        openai_models_in_spec = openai_models_in_spec.reject { |m| should_exclude_from_model_spec?(m) }

        # Filter out models that have explicit deprecated: false flag
        deprecated_models = openai_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Normalize model name before checking
          normalized_model = normalize_model_name(model)
          # Check if normalized model is not in available models
          !available_models.any? { |m| normalize_model_name(m) == normalized_model }
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['openai'])

        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated OpenAI models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end

        # This is a warning, not a failure, as some models might be intentionally kept
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated OpenAI models: #{deprecated_models.join(', ')}"
      end
    end

    context "Anthropic/Claude Models" do
      it "contains all available Claude models from the helper" do
        skip "Requires API key" unless ENV["ANTHROPIC_API_KEY"] || CONFIG["ANTHROPIC_API_KEY"]

        available_models = ClaudeHelper.list_models
        skip "No Claude models returned; skipping sync check" if available_models.nil? || available_models.empty?
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        missing_models -= Array(MISSING_MODEL_ALLOWLIST['anthropic'])
        
        if missing_models.any?
          puts "\n⚠️  Missing Claude models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these Claude models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated Claude models" do
        skip "Requires API key" unless ENV["ANTHROPIC_API_KEY"] || CONFIG["ANTHROPIC_API_KEY"]
        
        available_models = ClaudeHelper.list_models
        skip "No Claude models returned; skipping deprecated check" if available_models.nil? || available_models.empty?
        
        claude_models_in_spec = model_spec.keys.select { |k| k.match?(/^claude/) }
        
        # Filter out models that have explicit deprecated: true flag or are in available models
        deprecated_models = claude_models_in_spec.select do |model|
          # Skip if model is in available models list
          next false if available_models.include?(model)
          # Skip if model has deprecated: true (these are intentionally kept for backward compatibility)
          next false if model_deprecated?(model)
          # Otherwise, it's potentially deprecated (missing from API, no deprecated flag)
          true
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['anthropic'])
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated Claude models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated Claude models: #{deprecated_models.join(', ')}"
      end
    end

    context "Cohere Models" do
      it "contains all available Cohere models from the helper" do
        skip "Requires API key" unless ENV["COHERE_API_KEY"] || CONFIG["COHERE_API_KEY"]

        available_models = CohereHelper.list_models
        skip "No Cohere models returned; skipping sync check" if available_models.nil? || available_models.empty?
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        missing_models -= Array(MISSING_MODEL_ALLOWLIST['cohere'])
        
        if missing_models.any?
          puts "\n⚠️  Missing Cohere models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these Cohere models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated Cohere models" do
        skip "Requires API key" unless ENV["COHERE_API_KEY"] || CONFIG["COHERE_API_KEY"]
        
        available_models = CohereHelper.list_models
        skip "No Cohere models returned; skipping deprecated check" if available_models.nil? || available_models.empty?
        
        cohere_models_in_spec = model_spec.keys.select { |k| k.match?(/^(command|embed|rerank)/) }
        
        # Filter out models that have explicit deprecated: false flag
        deprecated_models = cohere_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Otherwise, check if it's not in available models
          !available_models.include?(model)
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['cohere'])
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated Cohere models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated Cohere models: #{deprecated_models.join(', ')}"
      end
    end

    context "Mistral Models" do
      it "contains all available Mistral models from the helper" do
        skip "Requires API key" unless ENV["MISTRAL_API_KEY"] || CONFIG["MISTRAL_API_KEY"]

        available_models = MistralHelper.list_models
        skip "No Mistral models returned; skipping sync check" if available_models.nil? || available_models.empty?
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        missing_models -= Array(MISSING_MODEL_ALLOWLIST['mistral'])
        
        if missing_models.any?
          puts "\n⚠️  Missing Mistral models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these Mistral models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated Mistral models" do
        skip "Requires API key" unless ENV["MISTRAL_API_KEY"] || CONFIG["MISTRAL_API_KEY"]
        
        available_models = MistralHelper.list_models
        skip "No Mistral models returned; skipping deprecated check" if available_models.nil? || available_models.empty?
        
        mistral_models_in_spec = model_spec.keys.select { |k| k.match?(/^(mistral|open-mistral|codestral|pixtral)/) }
        
        # Filter out models that have explicit deprecated: false flag
        deprecated_models = mistral_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Otherwise, check if it's not in available models
          !available_models.include?(model)
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['mistral'])
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated Mistral models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated Mistral models: #{deprecated_models.join(', ')}"
      end
    end

    context "Grok Models" do
      it "contains all available Grok models from the helper" do
        skip "Requires API key" unless ENV["XAI_API_KEY"] || CONFIG["XAI_API_KEY"]

        available_models = GrokHelper.list_models
        skip "No Grok models returned; skipping sync check" if available_models.nil? || available_models.empty?
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        missing_models -= Array(MISSING_MODEL_ALLOWLIST['grok'])
        
        if missing_models.any?
          puts "\n⚠️  Missing Grok models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these Grok models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated Grok models" do
        skip "Requires API key" unless ENV["XAI_API_KEY"] || CONFIG["XAI_API_KEY"]
        
        available_models = GrokHelper.list_models
        skip "No Grok models returned; skipping deprecated check" if available_models.nil? || available_models.empty?
        
        grok_models_in_spec = model_spec.keys.select { |k| k.match?(/^grok/) }
        
        # Filter out models that have explicit deprecated: false flag
        deprecated_models = grok_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Otherwise, check if it's not in available models
          !available_models.include?(model)
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['grok'])
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated Grok models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated Grok models: #{deprecated_models.join(', ')}"
      end
    end
    
    context "DeepSeek Models" do
      it "contains all available DeepSeek models from the helper" do
        skip "Requires API key" unless ENV["DEEPSEEK_API_KEY"] || CONFIG["DEEPSEEK_API_KEY"]

        available_models = DeepSeekHelper.list_models
        skip "No DeepSeek models returned; skipping deprecated check" if available_models.nil? || available_models.empty?
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        
        if missing_models.any?
          puts "\n⚠️  Missing DeepSeek models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these DeepSeek models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated DeepSeek models" do
        skip "Requires API key" unless ENV["DEEPSEEK_API_KEY"] || CONFIG["DEEPSEEK_API_KEY"]
        
        available_models = DeepSeekHelper.list_models
        
        deepseek_models_in_spec = model_spec.keys.select { |k| k.match?(/^deepseek/) }
        
        # Filter out models that have explicit deprecated: false flag
        deprecated_models = deepseek_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Otherwise, check if it's not in available models
          !available_models.include?(model)
        end
        deprecated_models -= Array(MISSING_MODEL_ALLOWLIST['deepseek'])
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated DeepSeek models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated DeepSeek models: #{deprecated_models.join(', ')}"
      end
    end
    
    context "Perplexity Models" do
      it "contains all available Perplexity models from the helper" do
        # Perplexity models are hardcoded, so we always check
        available_models = PerplexityHelper.list_models
        
        model_spec_keys = model_spec.keys
        missing_models = available_models - model_spec_keys
        
        if missing_models.any?
          puts "\n⚠️  Missing Perplexity models in model_spec.js:"
          missing_models.each { |m| puts "   - #{m}" }
        end
        
        expect(missing_models).to be_empty,
          "model_spec.js is missing these Perplexity models: #{missing_models.join(', ')}"
      end
      
      it "doesn't contain deprecated Perplexity models" do
        # Check for Perplexity models in spec that aren't in the helper's list
        available_models = PerplexityHelper.list_models
        
        perplexity_models_in_spec = model_spec.keys.select { |k| k.match?(/^(sonar|r1)/) }
        
        # Filter out models that have explicit deprecated: false flag
        deprecated_models = perplexity_models_in_spec.select do |model|
          # Skip if model has deprecated: false explicitly set
          next false if model_spec[model] && model_spec[model]["deprecated"] == false
          # Otherwise, check if it's not in available models
          !available_models.include?(model)
        end
        
        if deprecated_models.any?
          puts "\n⚠️  Potentially deprecated Perplexity models in model_spec.js:"
          deprecated_models.each { |m| puts "   - #{m}" }
        end
        
        expect(deprecated_models.size).to eq(0),
          "model_spec.js contains potentially deprecated Perplexity models: #{deprecated_models.join(', ')}"
      end
    end
  end
  
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
require 'yaml'
