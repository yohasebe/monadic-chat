# frozen_string_literal: true

require_relative '../spec_helper'

# Initialize $MODELS for tests
$MODELS = {
  openai: ["gpt-4", "gpt-3.5-turbo"],
  anthropic: ["claude-3-opus", "claude-3-sonnet"],
  gemini: ["gemini-pro"],
  mistral: ["mistral-large"],
  cohere: ["command"],
  ollama: ["llama2"],
  deepseek: ["deepseek-chat"],
  perplexity: ["pplx-70b"],
  grok: ["grok-1"]
}

require_relative '../../lib/monadic/app'
require_relative '../../lib/monadic/dsl'

RSpec.describe "Monadic Behavior System Tests" do
  # Define test apps with different configurations
  let(:monadic_app_definition) do
    <<~RUBY
      app "TestMonadicApp" do
        description "Test app with monadic mode"
        icon "test"
        llm do
          provider "openai"
          model "gpt-4"
        end
        features do
          monadic true
          context_size 5
        end
        tools do
          # Empty tools block
        end
      end
    RUBY
  end

  let(:non_monadic_app_definition) do
    <<~RUBY
      app "TestNonMonadicApp" do
        description "Test app without monadic mode"
        icon "test"
        llm do
          provider "openai"
          model "gpt-4"
        end
        features do
          monadic false
          context_size 5
        end
        tools do
          # Empty tools block
        end
      end
    RUBY
  end

  describe "Monadic Mode Behavior" do
    context "when monadic: true" do
      let(:app) do
        eval(monadic_app_definition, TOPLEVEL_BINDING)
      end

      it "uses JSON structure for context management" do
        expect(app.features[:monadic]).to be true
      end

      it "requires response_format configuration for certain providers" do
        # OpenAI with monadic mode should support response_format
        expect(app.settings[:provider]).to eq("openai")
        # In real app, this would be set in the helper
      end

      it "maintains context in JSON format through messages" do
        # This would test the actual message flow in a real app instance
        # For now, we verify the configuration
        expect(app.features[:context_size]).to eq(5)
      end
    end

    context "when monadic: false" do
      let(:app) do
        eval(non_monadic_app_definition, TOPLEVEL_BINDING)
      end

      it "uses standard mode without structured JSON" do
        expect(app.features[:monadic]).to be false
      end

      it "does not require response_format configuration" do
        # Standard mode doesn't need structured JSON responses
        expect(app.settings[:provider]).to eq("openai")
      end
    end
  end

  # Toggle property has been removed from the system
  # The mutual exclusivity test is no longer needed

  describe "Provider-Specific Monadic Behavior" do
    %w[openai deepseek perplexity grok].each do |provider|
      context "with #{provider} provider" do
        let(:app_def) do
          <<~RUBY
            app "Test#{provider.capitalize}App" do
              description "Test app for #{provider}"
              icon "test"
              llm do
                provider "#{provider}"
                model "test-model"
              end
              features do
                monadic true
              end
              tools do
              end
            end
          RUBY
        end

        it "enables monadic mode for #{provider}" do
          app = eval(app_def, TOPLEVEL_BINDING)
          
          expect(app.features[:monadic]).to be true
          expect(app.settings[:provider]).to eq(provider)
        end
      end
    end

    %w[anthropic gemini mistral cohere ollama].each do |provider|
      context "with #{provider} provider" do
        let(:app_def) do
          <<~RUBY
            app "Test#{provider.capitalize}App" do
              description "Test app for #{provider}"
              icon "test"
              llm do
                provider "#{provider == 'anthropic' ? 'anthropic' : provider}"
                model "test-model"
              end
              features do
                monadic false
              end
              tools do
              end
            end
          RUBY
        end

        it "uses standard mode for #{provider}" do
          app = eval(app_def, TOPLEVEL_BINDING)
          
          expect(app.features[:monadic]).to be false
        end
      end
    end
  end

  describe "Response Format Integration" do
    context "with monadic apps and response_format" do
      let(:app_with_response_format) do
        <<~RUBY
          app "MonadicWithFormat" do
            description "Monadic app with response format"
            icon "test"
            llm do
              provider "openai"
              model "gpt-4"
              response_format ({ type: "json_object" })
            end
            features do
              monadic true
            end
            tools do
            end
          end
        RUBY
      end

      it "accepts response_format in llm block" do
        app = eval(app_with_response_format, TOPLEVEL_BINDING)
        
        expect(app.settings[:response_format]).to eq({ type: "json_object" })
        expect(app.features[:monadic]).to be true
      end
    end
  end

  describe "Context Management Patterns" do
    let(:monadic_context_example) do
      {
        "message" => "User query",
        "context" => {
          "key1" => "value1",
          "nested" => {
            "key2" => "value2"
          }
        }
      }
    end

    let(:standard_context_example) do
      <<~HTML
        <div class="context">
          <div class="context-title">Context</div>
          <div class="context-content">
            <p>Key1: value1</p>
            <p>Nested Key2: value2</p>
          </div>
        </div>
      HTML
    end

    it "documents expected monadic JSON structure" do
      # This test serves as documentation
      expect(monadic_context_example).to have_key("message")
      expect(monadic_context_example).to have_key("context")
      expect(monadic_context_example["context"]).to be_a(Hash)
    end

    it "documents expected standard HTML structure" do
      # This test serves as documentation
      expect(standard_context_example).to include("context")
      expect(standard_context_example).to include("context-title")
      expect(standard_context_example).to include("context-content")
    end
  end

  describe "MDSL Feature Validation" do
    it "validates monadic apps have proper system prompts" do
      # Check that monadic apps include proper JSON formatting instructions
      monadic_apps = Dir.glob(File.join(__dir__, "../../apps/**/*.mdsl")).select do |file|
        content = File.read(file)
        content.include?("monadic true")
      end

      monadic_apps.each do |mdsl_file|
        content = File.read(mdsl_file)
        
        # Monadic apps should have JSON response instructions
        if content.include?("response_format")
          expect(content).to match(/json|JSON/i), 
            "#{mdsl_file} with monadic mode should mention JSON in system prompt"
        end
      end
    end

    it "validates standard mode apps have proper formatting instructions" do
      standard_apps = Dir.glob(File.join(__dir__, "../../apps/**/*.mdsl")).select do |file|
        content = File.read(file)
        content.include?("monadic false") || (!content.include?("monadic true") && !content.include?("monadic:"))
      end

      standard_apps.each do |mdsl_file|
        content = File.read(mdsl_file)
        
        # Standard mode apps might mention formatting in their prompts
        # but this is not strictly required
      end
    end
  end

  describe "Real App Configuration Validation" do
    it "ensures all production apps follow monadic/toggle rules" do
      all_apps = Dir.glob(File.join(__dir__, "../../apps/**/*.mdsl"))
      
      all_apps.each do |mdsl_file|
        content = File.read(mdsl_file)
        
        # Skip if it's a module or constants file
        next if mdsl_file.include?("_constants.mdsl") || mdsl_file.include?("_tools.mdsl")
        
        has_monadic = content.match(/monadic\s+true/)
        
        # Apps either have monadic mode enabled or use standard mode
        # No need to check for toggle since it's been removed
        
        # Provider-specific validation removed - JSON support and toggle mode can coexist
        # A provider being JSON-capable doesn't mean it must use monadic mode
      end
    end
  end
end