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
        "chat_grok.mdsl should have websearch true (native support via search_parameters)"
    end

    it 'enables websearch by default for Perplexity Chat' do
      mdsl_file = File.join(apps_dir, 'chat_perplexity.mdsl')
      websearch_enabled = parse_mdsl_websearch(mdsl_file)

      expect(websearch_enabled).to eq(true),
        "chat_perplexity.mdsl should have websearch true (model inherent capability)"
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

    it 'includes web search description in Perplexity system prompt' do
      mdsl_file = File.join(apps_dir, 'chat_perplexity.mdsl')
      content = File.read(mdsl_file)

      # Perplexity's system prompt should mention web search capability
      expect(content).to match(/live web search|web search capabilities|current information from the web/i),
        "Perplexity system prompt should mention web search capability"
    end

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
    it 'matches commit 248dc9a1 changes (5 apps with websearch true)' do
      apps_dir = File.join(__dir__, '../../apps/chat')

      # These 5 apps were changed to websearch true in commit 248dc9a1
      native_search_apps = [
        'chat_openai.mdsl',
        'chat_claude.mdsl',
        'chat_gemini.mdsl',
        'chat_grok.mdsl',
        'chat_perplexity.mdsl'
      ]

      native_search_apps.each do |app_file|
        mdsl_file = File.join(apps_dir, app_file)
        websearch_enabled = parse_mdsl_websearch(mdsl_file)

        expect(websearch_enabled).to eq(true),
          "#{app_file} should have websearch enabled (commit 248dc9a1)"
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
end
