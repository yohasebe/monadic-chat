# frozen_string_literal: true

require 'spec_helper'
require 'monadic/library'

RSpec.describe Monadic::Library::TitleSuggester do
  describe '.normalize' do
    it 'returns nil for nil/empty input' do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize('')).to be_nil
      expect(described_class.normalize('   ')).to be_nil
    end

    it 'strips surrounding quotes and a "Title:" prefix' do
      expect(described_class.normalize('"Discussion of LLM safety"')).to eq('Discussion of LLM safety')
      expect(described_class.normalize("Title: Quick chat about Ruby")).to eq('Quick chat about Ruby')
      expect(described_class.normalize('「LLM とコーディング」')).to eq('LLM とコーディング')
    end

    it 'truncates to MAX_LENGTH and rstrips trailing space' do
      raw = 'a' * 100
      out = described_class.normalize(raw)
      expect(out.length).to eq(described_class::MAX_LENGTH)
    end

    it 'keeps only the first non-empty line so chatty replies do not leak' do
      raw = "Quick chat about Ruby\n\n(Brief rationale follows...)"
      expect(described_class.normalize(raw)).to eq('Quick chat about Ruby')
    end
  end

  describe '.build_prompt' do
    it 'returns nil when there is no user/assistant content' do
      expect(described_class.build_prompt(nil)).to be_nil
      expect(described_class.build_prompt([])).to be_nil
      expect(described_class.build_prompt([{ 'role' => 'system', 'text' => 'You are a helper.' }])).to be_nil
    end

    it 'concatenates the first few user/assistant turns into the prompt' do
      messages = [
        { 'role' => 'system', 'text' => 'You are a helper.' },
        { 'role' => 'user', 'text' => 'Help me write Ruby.' },
        { 'role' => 'assistant', 'text' => 'Sure, what specifically?' },
        { 'role' => 'user', 'text' => 'Refactoring patterns.' }
      ]
      prompt = described_class.build_prompt(messages)
      expect(prompt).to include('Suggest a concise')
      expect(prompt).to include('user: Help me write Ruby.')
      expect(prompt).to include('assistant: Sure, what specifically?')
      expect(prompt).to include('user: Refactoring patterns.')
    end

    it 'caps how many turns are forwarded so the request stays small' do
      messages = (1..20).map { |i| { 'role' => 'user', 'text' => "Q#{i}" } }
      prompt = described_class.build_prompt(messages)
      # Anything past MAX_INPUT_TURNS should be cut.
      expect(prompt.scan(/^user: Q/).count).to eq(described_class::MAX_INPUT_TURNS)
    end
  end

  describe '.derive_provider' do
    before do
      stub_const('APPS', {
        'ChatOpenAI' => double('app', settings: { 'group' => 'OpenAI', 'display_name' => 'Chat' }),
        'ChatClaude' => double('app', settings: { 'group' => 'Anthropic Claude', 'display_name' => 'Chat' }),
        'ChatGrok'   => double('app', settings: { 'group' => 'xAI Grok', 'display_name' => 'Chat' })
      })
    end

    it 'maps app group strings onto canonical provider keys' do
      expect(described_class.derive_provider('ChatOpenAI')).to eq('openai')
      expect(described_class.derive_provider('ChatClaude')).to eq('anthropic')
      expect(described_class.derive_provider('ChatGrok')).to eq('xai')
    end

    it 'returns nil when app_name is unknown or empty' do
      expect(described_class.derive_provider(nil)).to be_nil
      expect(described_class.derive_provider('')).to be_nil
      expect(described_class.derive_provider('NoSuchApp')).to be_nil
    end
  end

  describe '.api_key_present?' do
    it 'returns false when no key is configured' do
      stub_const('CONFIG', { 'OPENAI_API_KEY' => '' })
      expect(described_class.api_key_present?('openai')).to eq(false)
    end

    it 'returns true when a non-empty key is configured' do
      stub_const('CONFIG', { 'OPENAI_API_KEY' => 'sk-test' })
      expect(described_class.api_key_present?('openai')).to eq(true)
    end

    it 'is true for providers without an API key requirement (Ollama)' do
      expect(described_class.api_key_present?('ollama')).to eq(true)
    end
  end

  describe '.suggest' do
    let(:app_instance) do
      Class.new do
        def settings; { 'group' => 'OpenAI', 'display_name' => 'Chat' }; end
        def send_query(_body, model:); 'Ruby refactor questions' end
      end.new
    end

    before do
      stub_const('APPS', { 'ChatOpenAI' => app_instance })
      stub_const('CONFIG', { 'OPENAI_API_KEY' => 'sk-test' })
      allow(::SystemDefaults).to receive(:get_default_model).with('openai').and_return('gpt-test')
    end

    it 'returns the normalized title when the LLM responds successfully' do
      messages = [
        { 'role' => 'user', 'text' => 'Help me refactor Ruby.' }
      ]
      expect(described_class.suggest(messages: messages, app_name: 'ChatOpenAI'))
        .to eq('Ruby refactor questions')
    end

    it 'returns nil when the API key is missing for the active provider' do
      stub_const('CONFIG', { 'OPENAI_API_KEY' => '' })
      messages = [{ 'role' => 'user', 'text' => 'Help me refactor Ruby.' }]
      expect(described_class.suggest(messages: messages, app_name: 'ChatOpenAI')).to be_nil
    end

    it 'returns nil when the LLM raises so the UI can fall back silently' do
      allow(app_instance).to receive(:send_query).and_raise(StandardError, 'boom')
      messages = [{ 'role' => 'user', 'text' => 'Help.' }]
      expect(described_class.suggest(messages: messages, app_name: 'ChatOpenAI')).to be_nil
    end

    it 'returns nil when there are no user/assistant turns to summarise' do
      messages = [{ 'role' => 'system', 'text' => 'You are a helper.' }]
      expect(described_class.suggest(messages: messages, app_name: 'ChatOpenAI')).to be_nil
    end

    # Phase 5: title-suggestion LLM call must not see raw PII when the
    # user has Privacy Filter on. The pipeline is passed by library_handler;
    # if absent (privacy off), behavior is unchanged from above.
    context 'with a privacy pipeline (Phase 5)' do
      let(:fake_pipeline) do
        double('Pipeline').tap do |p|
          allow(p).to receive(:before_send_to_llm) do |raw|
            masked = raw.text.gsub(/Alice/, '<<PERSON_1>>')
            double('MaskedMessage', text: masked)
          end
          allow(p).to receive(:sanitize_for_tts) do |text|
            text.gsub(/<<([A-Z_]+)_(\d+)>>/) { "#{Regexp.last_match(1).tr('_', ' ')} #{Regexp.last_match(2)}" }
          end
        end
      end

      it 'pre-masks message text before building the prompt' do
        sent = nil
        instance = Class.new do
          define_method(:settings) { { 'group' => 'OpenAI', 'display_name' => 'Chat' } }
          define_method(:send_query) { |body, model:| sent = body; 'Discussing PERSON 1' }
        end.new
        stub_const('APPS', { 'ChatOpenAI' => instance })

        messages = [{ 'role' => 'user', 'text' => 'Email Alice today.' }]
        described_class.suggest(
          messages: messages,
          app_name: 'ChatOpenAI',
          pipeline: fake_pipeline
        )

        prompt_text = sent['messages'].last['content'].to_s
        expect(prompt_text).to include('<<PERSON_1>>')
        expect(prompt_text).not_to include('Alice')
      end

      it 'humanises any placeholders the LLM echoes back' do
        instance = Class.new do
          define_method(:settings) { { 'group' => 'OpenAI', 'display_name' => 'Chat' } }
          define_method(:send_query) { |_body, model:| 'Discussion with <<PERSON_1>>' }
        end.new
        stub_const('APPS', { 'ChatOpenAI' => instance })

        messages = [{ 'role' => 'user', 'text' => 'Hi Alice.' }]
        title = described_class.suggest(
          messages: messages,
          app_name: 'ChatOpenAI',
          pipeline: fake_pipeline
        )
        expect(title).to eq('Discussion with PERSON 1')
      end

      it 'returns nil and skips the LLM call when masking raises (fail-closed)' do
        broken_pipeline = double('Pipeline')
        allow(broken_pipeline).to receive(:before_send_to_llm).and_raise('boom')

        instance = Class.new do
          define_method(:settings) { { 'group' => 'OpenAI', 'display_name' => 'Chat' } }
          define_method(:send_query) { |_body, model:| raise 'should not be called when masking failed' }
        end.new
        stub_const('APPS', { 'ChatOpenAI' => instance })

        messages = [{ 'role' => 'user', 'text' => 'Email Alice.' }]
        result = described_class.suggest(
          messages: messages,
          app_name: 'ChatOpenAI',
          pipeline: broken_pipeline
        )
        expect(result).to be_nil
      end
    end
  end
end
