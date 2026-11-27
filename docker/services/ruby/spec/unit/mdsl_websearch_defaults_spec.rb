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

    it 'lets Chat search with the other providers too (DeepSeek and Mistral through their own search, Cohere and Ollama when Tavily has its key)' do
      apps_dir = File.join(__dir__, '../../apps/chat')
      %w[chat_cohere.mdsl chat_deepseek.mdsl chat_mistral.mdsl chat_ollama.mdsl].each do |app_file|
        expect(parse_mdsl_websearch(File.join(apps_dir, app_file))).to eq(true), "#{app_file} should have websearch true"
      end
    end

    # Built-in apps search when it helps; these three do not: Monadic Help
    # answers from its own documentation, Wikipedia has a search of its own,
    # and Voice Interpreter only translates what is said.
    NOT_SEARCHING = %w[monadic_help wikipedia voice_interpreter].freeze

    it 'lets every built-in app search except those whose task a web search would get in the way of' do
      Dir.glob(File.join(__dir__, '../../apps/*/*.mdsl')).each do |file|
        app = File.basename(File.dirname(file))
        next if app == 'live_conversation' # Live searches through its Live Tools switch

        expected = !NOT_SEARCHING.include?(app)
        expect(parse_mdsl_websearch(file)).to eq(expected), "#{File.basename(file)} should have websearch #{expected}"
      end
    end
  end

  # Apps whose conversations may search the web (MDSL `websearch true`) with
  # every provider: whether a search is made is the model's choice, and
  # whether it can be is the provider's (a search of its own, or Tavily
  # with its key). An app that does not say `websearch true` does not search.
  CHAT_STYLE_APPS_AND_PROVIDERS = {
    'voice_chat' => %w[claude cohere deepseek gemini grok mistral ollama openai],
    'second_opinion' => %w[claude cohere deepseek gemini grok mistral openai],
    'mail_composer' => %w[claude cohere deepseek gemini grok mistral ollama openai]
  }.freeze

  CHAT_STYLE_APPS_AND_PROVIDERS.each do |app_name, providers|
    describe "Chat-style default convention for #{app_name}" do
      providers.each do |provider|
        it "sets websearch true for #{app_name}_#{provider}" do
          mdsl_file = File.join(__dir__, "../../apps/#{app_name}/#{app_name}_#{provider}.mdsl")
          expect(parse_mdsl_websearch(mdsl_file)).to eq(true), "#{app_name}_#{provider}.mdsl should have websearch true"
        end

        # The MDSL `websearch true` lets the app's chats search, but without
        # a system prompt nudge
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
