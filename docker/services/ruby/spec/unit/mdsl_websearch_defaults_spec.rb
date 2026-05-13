# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MDSL Web Search Default Settings' do
  # Helper to parse MDSL files and extract websearch setting
  def parse_mdsl_websearch(file_path)
    return nil unless File.exist?(file_path)

    content = File.read(file_path)

    # Look for websearch setting in features block
    # Pattern: features do ... websearch true/false ... end
    if content =~ /features\s+do(.*?)end/m
      features_block = $1

      # Extract websearch value
      if features_block =~ /websearch\s+(true|false)/
        return $1 == "true"
      end
    end

    nil
  end

  describe 'Native web search providers' do
    let(:apps_dir) { File.join(__dir__, '../../apps/chat') }

    it 'enables websearch by default for OpenAI Chat' do
      mdsl_file = File.join(apps_dir, 'chat_openai.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      expect(websearch_enabled).to eq(true),
        "chat_openai.mdsl should have websearch true (native support via OpenAI API)"
    end

    it 'enables websearch by default for Claude Chat' do
      mdsl_file = File.join(apps_dir, 'chat_claude.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      expect(websearch_enabled).to eq(true),
        "chat_claude.mdsl should have websearch true (native support via web_search_20250305 tool)"
    end

    it 'enables websearch by default for Gemini Chat' do
      mdsl_file = File.join(apps_dir, 'chat_gemini.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      expect(websearch_enabled).to eq(true),
        "chat_gemini.mdsl should have websearch true (native support via google_search grounding)"
    end

    it 'enables websearch by default for Grok Chat' do
      mdsl_file = File.join(apps_dir, 'chat_grok.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      expect(websearch_enabled).to eq(true),
        "chat_grok.mdsl should have websearch true (native support via Responses API web_search/x_search tools)"
    end

  end

  describe 'Tavily-based web search providers' do
    let(:apps_dir) { File.join(__dir__, '../../apps/chat') }

    it 'keeps websearch disabled by default for Cohere Chat (requires TAVILY_API_KEY)' do
      mdsl_file = File.join(apps_dir, 'chat_cohere.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      # Cohere uses Tavily, so it should remain false (requires separate API key)
      expect(websearch_enabled).to eq(false),
        "chat_cohere.mdsl should have websearch false (requires TAVILY_API_KEY)"
    end

    it 'keeps websearch disabled by default for DeepSeek Chat (requires TAVILY_API_KEY)' do
      mdsl_file = File.join(apps_dir, 'chat_deepseek.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      # DeepSeek uses Tavily, so it should remain false
      expect(websearch_enabled).to eq(false),
        "chat_deepseek.mdsl should have websearch false (requires TAVILY_API_KEY)"
    end

    it 'keeps websearch disabled by default for Mistral Chat (requires TAVILY_API_KEY)' do
      mdsl_file = File.join(apps_dir, 'chat_mistral.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      # Mistral uses Tavily, so it should remain false
      expect(websearch_enabled).to eq(false),
        "chat_mistral.mdsl should have websearch false (requires TAVILY_API_KEY)"
    end
  end

  describe 'System prompt verification for web search' do
    let(:apps_dir) { File.join(__dir__, '../../apps/chat') }

    it 'includes web search description in Gemini system prompt' do
      mdsl_file = File.join(apps_dir, 'chat_gemini.mdsl')
      content = File.read(mdsl_file)

      # Gemini's system prompt should mention web search when needed
      expect(content).to match(/web search|current information|up-to-date sources/i),
        "Gemini system prompt should mention web search capability"
    end

    it 'includes web search description in Grok system prompt' do
      mdsl_file = File.join(apps_dir, 'chat_grok.mdsl')
      content = File.read(mdsl_file)

      # Grok's system prompt should mention web search capability
      expect(content).to match(/web search|current events|recent information/i),
        "Grok system prompt should mention web search capability"
    end
  end

  describe 'Configuration consistency' do
    it 'matches native-search apps having websearch true' do
      apps_dir = File.join(__dir__, '../../apps/chat')

      native_search_apps = [
        'chat_openai.mdsl',
        'chat_claude.mdsl',
        'chat_gemini.mdsl',
        'chat_grok.mdsl'
      ]

      native_search_apps.each do |app_file|
        mdsl_file = File.join(apps_dir, app_file)
        websearch_enabled = parse_mdsl_websearch(mdsl_file)

        expect(websearch_enabled).to eq(true),
          "#{app_file} should have websearch enabled (native search provider)"
      end
    end

    it 'keeps Tavily-based apps with websearch false' do
      apps_dir = File.join(__dir__, '../../apps/chat')

      # These apps use Tavily and should remain false
      tavily_apps = [
        'chat_cohere.mdsl',
        'chat_deepseek.mdsl',
        'chat_mistral.mdsl'
      ]

      tavily_apps.each do |app_file|
        mdsl_file = File.join(apps_dir, app_file)
        next unless File.exist?(mdsl_file)

        websearch_enabled = parse_mdsl_websearch(mdsl_file)

        expect(websearch_enabled).to eq(false),
          "#{app_file} should keep websearch disabled (requires TAVILY_API_KEY)"
      end
    end
  end

  # Apps that follow the same "native → true, Tavily fallback → false"
  # convention as the Chat app. Added 2026-05-13 when these apps were
  # promoted to default-on web search where the provider supports it.
  #
  # The convention is *not* universal — purpose-specific apps (Image
  # Generator, Translate, Math Tutor, etc.) keep websearch absent /
  # false even on native providers because their core task does not
  # benefit from web search and the toggle would just add noise. The
  # parameterised group below pins which apps consciously opted into
  # the chat-style default; adding a new app here means: "for this
  # app, the conversational use case dominates and current-events
  # context is worth the extra latency on native providers."
  CHAT_STYLE_APPS_AND_PROVIDERS = {
    'voice_chat' => %w[claude cohere deepseek gemini grok mistral ollama openai],
    'chat_plus' => %w[claude cohere deepseek gemini grok mistral openai],
    'second_opinion' => %w[claude cohere deepseek gemini grok mistral openai],
    'mail_composer' => %w[claude cohere deepseek gemini grok mistral ollama openai]
  }.freeze

  CHAT_NATIVE_PROVIDERS = %w[openai claude gemini grok].freeze

  CHAT_STYLE_APPS_AND_PROVIDERS.each do |app_name, providers|
    describe "Chat-style default convention for #{app_name}" do
      providers.each do |provider|
        expected = CHAT_NATIVE_PROVIDERS.include?(provider)

        it "sets websearch #{expected} for #{app_name}_#{provider}" do
          mdsl_file = File.join(__dir__, "../../apps/#{app_name}/#{app_name}_#{provider}.mdsl")
          actual = parse_mdsl_websearch(mdsl_file)

          expect(actual).to eq(expected),
            "#{app_name}_#{provider}.mdsl should have websearch #{expected} " \
            "(#{CHAT_NATIVE_PROVIDERS.include?(provider) ? 'native search provider' : 'Tavily fallback — toggle stays opt-in'})"
        end

        # The MDSL `websearch <bool>` directive controls UI default
        # and tool registration, but without a system prompt nudge
        # the LLM (especially native-search providers like Claude /
        # Gemini) often won't actually USE the tool. Each chat-style
        # app must therefore advertise web search in its prompt the
        # same way the Chat app does.
        it "mentions web search in the system prompt of #{app_name}_#{provider}" do
          mdsl_file = File.join(__dir__, "../../apps/#{app_name}/#{app_name}_#{provider}.mdsl")
          content = File.read(mdsl_file)
          expect(content).to match(/web search|search the web/i),
            "#{app_name}_#{provider}.mdsl should mention web search in system_prompt " \
            "so the model knows the tool is available"
        end
      end
    end
  end
end
