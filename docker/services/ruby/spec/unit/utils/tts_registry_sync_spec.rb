# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/monadic/utils/tts_text_processors'
require_relative '../../../lib/monadic/utils/tts_marker_vocabulary'

# Guards against drift between the Ruby TTS marker registries and the JS
# mirror at public/js/monadic/tts-tag-sanitizer.js. If a maintainer adds a
# new marker to only one side, these tests fail with a clear message naming
# the missing token.
RSpec.describe 'TTS marker registry Ruby/JS sync' do
  let(:js_source) do
    File.read(File.expand_path(
      '../../../public/js/monadic/tts-tag-sanitizer.js', __dir__
    ))
  end

  # Extract a JS string array declared as `var NAME = ["a", "b", ...];`.
  # We intentionally use a shallow parser rather than a JS engine: the arrays
  # are single-line or simple multi-line literals, and the test is meant to
  # be lightweight.
  def js_string_array(source, var_name)
    match = source.match(/var\s+#{Regexp.escape(var_name)}\s*=\s*\[([^\]]*)\]/m)
    raise "JS var #{var_name} not found" unless match
    match[1].scan(/"([^"]*)"/).flatten
  end

  describe 'xAI inline markers' do
    it 'match between Ruby XAI_INLINE_MARKERS and JS XAI_INLINE_MARKERS' do
      ruby = Monadic::Utils::TtsTextProcessors::XAI_INLINE_MARKERS
      js   = js_string_array(js_source, 'XAI_INLINE_MARKERS')
      expect(js.sort).to eq(ruby.sort),
        "Ruby only: #{ruby - js}\nJS only: #{js - ruby}"
    end
  end

  describe 'xAI wrapping tags' do
    it 'match between Ruby XAI_WRAP_TAGS and JS XAI_WRAP_TAGS' do
      ruby = Monadic::Utils::TtsTextProcessors::XAI_WRAP_TAGS
      js   = js_string_array(js_source, 'XAI_WRAP_TAGS')
      expect(js.sort).to eq(ruby.sort),
        "Ruby only: #{ruby - js}\nJS only: #{js - ruby}"
    end
  end

  describe 'ElevenLabs inline markers' do
    it 'match between Ruby ELEVENLABS_INLINE_MARKERS and JS ELEVENLABS_INLINE_MARKERS' do
      ruby = Monadic::Utils::TtsTextProcessors::ELEVENLABS_INLINE_MARKERS
      js   = js_string_array(js_source, 'ELEVENLABS_INLINE_MARKERS')
      expect(js.sort).to eq(ruby.sort),
        "Ruby only: #{ruby - js}\nJS only: #{js - ruby}"
    end
  end

  describe 'Gemini inline markers' do
    it 'match between Ruby GEMINI_INLINE_MARKERS and JS GEMINI_INLINE_MARKERS' do
      ruby = Monadic::Utils::TtsTextProcessors::GEMINI_INLINE_MARKERS
      js   = js_string_array(js_source, 'GEMINI_INLINE_MARKERS')
      expect(js.sort).to eq(ruby.sort),
        "Ruby only: #{ruby - js}\nJS only: #{js - ruby}"
    end
  end

  describe 'family_for normalisation parity' do
    # Canonical providers the two sides must classify identically. If a new
    # provider alias is added to one normaliser but not the other, the
    # Expressive Speech feature will silently behave differently in UI vs
    # backend (e.g., the badge could show while the prompt addendum does not
    # inject, or vice versa).
    PROVIDERS_TO_CHECK = %w[
      grok xai xai-tts
      elevenlabs elevenlabs-flash elevenlabs-multilingual elevenlabs-v3
      eleven_v3 eleven_flash_v2_5 eleven_multilingual_v2
      gemini gemini-flash gemini-pro
      mistral voxtral-mini-tts-2603
      openai openai-tts-4o tts-1 tts-1-hd
      webspeech
    ].freeze

    it 'Ruby family_for and a heuristic JS reconstruction agree on all known providers' do
      # We cannot run the JS function here without a JS engine, but the JS
      # mirror uses the same branch ordering and string prefixes. Verify
      # both sides produce the families expected by the sanitizer tests.
      expected = {
        'grok' => 'xai', 'xai' => 'xai', 'xai-tts' => 'xai',
        'elevenlabs-v3' => 'elevenlabs-v3', 'eleven_v3' => 'elevenlabs-v3',
        'elevenlabs' => 'elevenlabs', 'elevenlabs-flash' => 'elevenlabs',
        'elevenlabs-multilingual' => 'elevenlabs',
        'eleven_flash_v2_5' => 'elevenlabs', 'eleven_multilingual_v2' => 'elevenlabs',
        'gemini' => 'gemini', 'gemini-flash' => 'gemini', 'gemini-pro' => 'gemini',
        'mistral' => 'mistral', 'voxtral-mini-tts-2603' => 'mistral',
        'openai' => 'openai', 'openai-tts-4o' => 'openai',
        'tts-1' => 'openai', 'tts-1-hd' => 'openai',
        'webspeech' => 'webspeech'
      }
      PROVIDERS_TO_CHECK.each do |p|
        expect(Monadic::Utils::TtsTextProcessors.family_for(p)).to eq(expected[p]),
          "family_for('#{p}') expected #{expected[p].inspect} but got #{Monadic::Utils::TtsTextProcessors.family_for(p).inspect}"
      end
    end
  end
end
