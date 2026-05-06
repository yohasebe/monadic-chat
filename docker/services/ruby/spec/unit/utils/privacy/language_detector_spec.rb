# frozen_string_literal: true

require 'spec_helper'
require 'monadic/utils/privacy/language_detector'

RSpec.describe Monadic::Utils::Privacy::LanguageDetector do
  let(:session) do
    { parameters: { 'conversation_language' => 'auto' } }
  end

  around do |example|
    original_env = ENV['PRIVACY_LANGS']
    config_present = defined?(CONFIG) && CONFIG.is_a?(Hash)
    had_key = config_present && CONFIG.key?('PRIVACY_LANGS')
    saved_config = config_present ? CONFIG['PRIVACY_LANGS'] : nil
    # Detector reads CONFIG first; clear it so ENV-driven tests are not
    # masked by a pre-loaded CONFIG entry.
    CONFIG.delete('PRIVACY_LANGS') if config_present
    example.run
  ensure
    ENV['PRIVACY_LANGS'] = original_env
    if config_present
      if had_key
        CONFIG['PRIVACY_LANGS'] = saved_config
      else
        CONFIG.delete('PRIVACY_LANGS')
      end
    end
  end

  describe '.installed_languages' do
    it 'reads from PRIVACY_LANGS env and intersects with PRESIDIO_LANGS' do
      ENV['PRIVACY_LANGS'] = 'en, ja , zh '
      expect(described_class.installed_languages).to eq(%w[en ja zh])
    end

    it 'drops unknown codes that are not in PRESIDIO_LANGS' do
      ENV['PRIVACY_LANGS'] = 'en,ko,ja' # ko is not Presidio-supported
      expect(described_class.installed_languages).to eq(%w[en ja])
    end

    it 'falls back to ["en"] when env is empty or unset' do
      ENV['PRIVACY_LANGS'] = ''
      expect(described_class.installed_languages).to eq(['en'])
      ENV.delete('PRIVACY_LANGS')
      expect(described_class.installed_languages).to eq(['en'])
    end

    it 'reads from CONFIG hash when set (dev mode where ENV is not populated)' do
      ENV.delete('PRIVACY_LANGS')
      CONFIG['PRIVACY_LANGS'] = 'en,ja'
      expect(described_class.installed_languages).to eq(%w[en ja])
    end

    it 'prefers CONFIG over ENV when both are set' do
      ENV['PRIVACY_LANGS'] = 'en'
      CONFIG['PRIVACY_LANGS'] = 'en,ja,zh'
      expect(described_class.installed_languages).to eq(%w[en ja zh])
    end
  end

  describe '.auto_mode?' do
    it 'is true when conversation_language is "auto"' do
      expect(described_class.auto_mode?(parameters: { 'conversation_language' => 'auto' })).to be(true)
    end

    it 'is true when conversation_language is unset/empty' do
      expect(described_class.auto_mode?(parameters: {})).to be(true)
      expect(described_class.auto_mode?(parameters: { 'conversation_language' => '' })).to be(true)
      expect(described_class.auto_mode?({})).to be(true) # no parameters at all
    end

    it 'is false when conversation_language is an explicit value' do
      expect(described_class.auto_mode?(parameters: { 'conversation_language' => 'ja' })).to be(false)
      expect(described_class.auto_mode?(parameters: { 'conversation_language' => 'en' })).to be(false)
    end

    it 'reads symbol- or string-keyed parameters' do
      expect(described_class.auto_mode?(parameters: { conversation_language: 'auto' })).to be(true)
      expect(described_class.auto_mode?('parameters' => { 'conversation_language' => 'ja' })).to be(false)
    end

    it 'is false for nil/empty session' do
      expect(described_class.auto_mode?(nil)).to be(false)
    end
  end

  describe '.detect_and_lock!' do
    before { ENV['PRIVACY_LANGS'] = 'en,ja,fr,de,es,it,nl,pt,zh' }

    it 'locks to detected language on a reliable Japanese text' do
      state = described_class.detect_and_lock!(
        'こんにちは世界。これは日本語のテキストです。意味のある長さの文章。',
        session
      )
      expect(state[:locked]).to be(true)
      expect(state[:language]).to eq('ja')
      expect(state[:reliable]).to be(true)
      expect(state[:attempts]).to eq(1)
    end

    it 'locks to detected language on reliable English text' do
      described_class.detect_and_lock!(
        'This is a sufficiently long English sentence to be reliable.',
        session
      )
      expect(described_class.locked_language(session)).to eq('en')
    end

    it 'does not lock when CLD reports reliable: false (very short input)' do
      # CLD 0.13 returns reliable: false for "hi" (guesses Catalan).
      described_class.detect_and_lock!('hi', session)
      state = described_class.detection_state(session)
      expect(state[:locked]).to be(false)
      expect(state[:language]).to be_nil
      expect(state[:attempts]).to eq(1)
    end

    it 'is idempotent once locked (subsequent calls do not flip the lock)' do
      described_class.detect_and_lock!(
        'こんにちは世界。日本語の長文を送ります。これはテストです。',
        session
      )
      first_lang = described_class.locked_language(session)

      described_class.detect_and_lock!(
        'Now I switch to a fairly long English sentence intentionally.',
        session
      )
      expect(described_class.locked_language(session)).to eq(first_lang)
    end

    it 'is a no-op when conversation_language is an explicit value (not "auto")' do
      explicit_session = { parameters: { 'conversation_language' => 'en' } }
      described_class.detect_and_lock!(
        'こんにちは世界。日本語のテキストです。十分な長さの文章。',
        explicit_session
      )
      state = described_class.detection_state(explicit_session)
      expect(state[:locked]).to be(false)
      expect(state[:language]).to be_nil
      expect(state[:attempts]).to eq(0)
    end

    it 'is a no-op for nil/empty text' do
      described_class.detect_and_lock!(nil, session)
      described_class.detect_and_lock!('', session)
      described_class.detect_and_lock!('   ', session)
      state = described_class.detection_state(session)
      expect(state[:locked]).to be(false)
      expect(state[:attempts]).to eq(0)
    end

    it 'does not lock to a detected language that is not installed' do
      ENV['PRIVACY_LANGS'] = 'en,ja' # French not installed
      described_class.detect_and_lock!(
        "Bonjour à tous, j'espère que vous allez bien aujourd'hui. " \
        "C'est un message en français pour tester la détection.",
        session
      )
      expect(described_class.locked_language(session)).to be_nil
      expect(described_class.detection_state(session)[:language]).not_to eq('fr')
    end
  end

  describe '.locked_language / .locked_reliable / .attempt_count' do
    it 'returns nil/0 when no detection has been performed' do
      expect(described_class.locked_language(session)).to be_nil
      expect(described_class.locked_reliable(session)).to be_nil
      expect(described_class.attempt_count(session)).to eq(0)
    end

    it 'returns the locked language and reliable flag once locked' do
      ENV['PRIVACY_LANGS'] = 'en,ja'
      described_class.detect_and_lock!(
        'こんにちは世界。日本語の長文を送ります。これはテストです。',
        session
      )
      expect(described_class.locked_language(session)).to eq('ja')
      expect(described_class.locked_reliable(session)).to be(true)
      expect(described_class.attempt_count(session)).to eq(1)
    end
  end

  describe '.reset!' do
    it 'clears the lock so detection can run again' do
      ENV['PRIVACY_LANGS'] = 'en,ja'
      described_class.detect_and_lock!(
        'こんにちは世界。日本語の長文を送ります。これはテストです。',
        session
      )
      expect(described_class.locked?(session)).to be(true)
      described_class.reset!(session)
      expect(described_class.locked?(session)).to be(false)
      expect(described_class.detection_state(session)[:language]).to be_nil
    end
  end
end
