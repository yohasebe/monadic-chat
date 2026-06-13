# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/adapters/base_vendor_helper'

RSpec.describe BaseVendorHelper do
  describe 'constants' do
    it 'defines DEFAULT_MAX_RETRIES' do
      expect(BaseVendorHelper::DEFAULT_MAX_RETRIES).to eq(5)
    end

    it 'defines DEFAULT_RETRY_DELAY' do
      expect(BaseVendorHelper::DEFAULT_RETRY_DELAY).to eq(1)
    end
  end

  describe '#post_json_with_retries' do
    subject(:helper) do
      mod = Module.new do
        include BaseVendorHelper
        define_timeouts "RETRYTEST", open: 1, read: 1, write: 1
      end
      Class.new { include mod }.new
    end

    let(:success_response) { double('Response', status: double('Status', success?: true)) }
    let(:failure_response) { double('Response', status: double('Status', success?: false)) }

    # Builds an http double whose post yields the given outcomes in order
    # (an Exception class is raised; anything else is returned). The last
    # outcome repeats if the loop asks for more.
    def http_yielding(*outcomes)
      http = double('HTTP')
      chain = double('HTTPWithTimeout')
      allow(http).to receive(:timeout).and_return(chain)
      calls = 0
      allow(chain).to receive(:post) do
        outcome = outcomes[[calls, outcomes.length - 1].min]
        calls += 1
        outcome.is_a?(Class) ? raise(outcome, "boom") : outcome
      end
      [http, -> { calls }]
    end

    it 'returns the first successful response without further attempts' do
      http, calls = http_yielding(success_response)
      result = helper.post_json_with_retries(http, "http://x", {}, max_retries: 3, retry_delay: 0)
      expect(result).to equal(success_response)
      expect(calls.call).to eq(1)
    end

    it 'retries on non-success status and returns the successful response' do
      http, calls = http_yielding(failure_response, success_response)
      result = helper.post_json_with_retries(http, "http://x", {}, max_retries: 3, retry_delay: 0)
      expect(result).to equal(success_response)
      expect(calls.call).to eq(2)
    end

    it 'returns the last response after exhausting retries on non-success status' do
      http, calls = http_yielding(failure_response)
      result = helper.post_json_with_retries(http, "http://x", {}, max_retries: 3, retry_delay: 0)
      expect(result).to equal(failure_response)
      expect(calls.call).to eq(3)
    end

    it 'swallows and retries exceptions listed in rescue_errors' do
      http, calls = http_yielding(HTTP::Error, success_response)
      result = helper.post_json_with_retries(http, "http://x", {},
                                             max_retries: 3, retry_delay: 0,
                                             rescue_errors: [HTTP::Error, HTTP::TimeoutError])
      expect(result).to equal(success_response)
      expect(calls.call).to eq(2)
    end

    it 'returns nil when every attempt raises a rescued error' do
      http, calls = http_yielding(HTTP::Error)
      result = helper.post_json_with_retries(http, "http://x", {},
                                             max_retries: 2, retry_delay: 0,
                                             rescue_errors: [HTTP::Error])
      expect(result).to be_nil
      expect(calls.call).to eq(2)
    end

    it 'propagates exceptions by default (no rescue_errors)' do
      http, calls = http_yielding(HTTP::Error)
      expect {
        helper.post_json_with_retries(http, "http://x", {}, max_retries: 3, retry_delay: 0)
      }.to raise_error(HTTP::Error)
      expect(calls.call).to eq(1)
    end
  end

  describe '.define_timeouts' do
    context 'when defining timeouts on a vendor module' do
      let(:vendor_module) do
        Module.new do
          include BaseVendorHelper
          define_timeouts "TEST_VENDOR", open: 15, read: 300, write: 90
        end
      end

      let(:helper_instance) do
        mod = vendor_module
        Class.new { include mod }.new
      end

      it 'creates class-level open_timeout method' do
        expect(vendor_module.open_timeout).to eq(15)
      end

      it 'creates class-level read_timeout method' do
        expect(vendor_module.read_timeout).to eq(300)
      end

      it 'creates class-level write_timeout method' do
        expect(vendor_module.write_timeout).to eq(90)
      end

      it 'creates instance-level open_timeout delegating to module' do
        expect(helper_instance.open_timeout).to eq(15)
      end

      it 'creates instance-level read_timeout delegating to module' do
        expect(helper_instance.read_timeout).to eq(300)
      end

      it 'creates instance-level write_timeout delegating to module' do
        expect(helper_instance.write_timeout).to eq(90)
      end
    end

    context 'with CONFIG override' do
      let(:vendor_module) do
        Module.new do
          include BaseVendorHelper
          define_timeouts "CONFIGTEST", open: 10, read: 600, write: 120
        end
      end

      around(:each) do |example|
        # Temporarily set CONFIG values
        original = CONFIG.dup
        CONFIG["CONFIGTEST_OPEN_TIMEOUT"] = "25"
        CONFIG["CONFIGTEST_READ_TIMEOUT"] = "900"
        CONFIG["CONFIGTEST_WRITE_TIMEOUT"] = "180"
        example.run
        CONFIG.replace(original)
      end

      it 'reads open_timeout from CONFIG when available' do
        expect(vendor_module.open_timeout).to eq(25)
      end

      it 'reads read_timeout from CONFIG when available' do
        expect(vendor_module.read_timeout).to eq(900)
      end

      it 'reads write_timeout from CONFIG when available' do
        expect(vendor_module.write_timeout).to eq(180)
      end
    end

    context 'with default parameter values' do
      let(:vendor_module) do
        Module.new do
          include BaseVendorHelper
          define_timeouts "DEFAULTS"
        end
      end

      it 'uses open: 10 as default' do
        expect(vendor_module.open_timeout).to eq(10)
      end

      it 'uses read: 600 as default' do
        expect(vendor_module.read_timeout).to eq(600)
      end

      it 'uses write: 120 as default' do
        expect(vendor_module.write_timeout).to eq(120)
      end
    end
  end

  describe '#strip_inactive_image_data' do
    subject(:helper) do
      Class.new do
        include BaseVendorHelper
      end.new
    end

    it 'strips base64 data from inactive messages with images array' do
      session = {
        messages: [
          { "role" => "user", "active" => false, "images" => [
            { "title" => "cat.png", "data" => "data:image/png;base64,iVBOR..." }
          ] },
          { "role" => "user", "active" => true, "images" => [
            { "title" => "dog.png", "data" => "data:image/png;base64,ABCDE..." }
          ] }
        ]
      }

      helper.strip_inactive_image_data(session)

      # Inactive message stripped
      expect(session[:messages][0]["images"][0]["data"]).to eq("[stripped]")
      expect(session[:messages][0]["images"][0]["title"]).to eq("cat.png")
      # Active message untouched
      expect(session[:messages][1]["images"][0]["data"]).to start_with("data:")
    end

    it 'strips base64 data from inactive messages with OpenAI multimodal content' do
      session = {
        messages: [
          { "role" => "user", "active" => false, "content" => [
            { "type" => "text", "text" => "Describe this" },
            { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,iVBOR..." } }
          ] }
        ]
      }

      helper.strip_inactive_image_data(session)

      expect(session[:messages][0]["content"][0]["text"]).to eq("Describe this")
      expect(session[:messages][0]["content"][1]["image_url"]["url"]).to eq("[stripped]")
    end

    it 'preserves non-data URLs (e.g., https)' do
      session = {
        messages: [
          { "role" => "user", "active" => false, "content" => [
            { "type" => "image_url", "image_url" => { "url" => "https://example.com/img.png" } }
          ] }
        ]
      }

      helper.strip_inactive_image_data(session)

      expect(session[:messages][0]["content"][0]["image_url"]["url"]).to eq("https://example.com/img.png")
    end

    it 'handles nil messages gracefully' do
      expect { helper.strip_inactive_image_data({}) }.not_to raise_error
      expect { helper.strip_inactive_image_data({ messages: nil }) }.not_to raise_error
      expect { helper.strip_inactive_image_data({ messages: [nil] }) }.not_to raise_error
    end

    it 'is idempotent' do
      session = {
        messages: [
          { "role" => "user", "active" => false, "images" => [
            { "title" => "img.png", "data" => "[stripped]" }
          ] }
        ]
      }

      helper.strip_inactive_image_data(session)
      expect(session[:messages][0]["images"][0]["data"]).to eq("[stripped]")
    end
  end

  describe '.define_models_cache' do
    let(:vendor_module) do
      Module.new do
        include BaseVendorHelper
        define_models_cache :test_vendor
      end
    end

    let(:helper_instance) do
      mod = vendor_module
      Class.new { include mod }.new
    end

    before do
      $MODELS[:test_vendor] = ["model-a", "model-b"]
    end

    after do
      $MODELS.delete(:test_vendor)
    end

    it 'creates clear_models_cache method' do
      expect(helper_instance).to respond_to(:clear_models_cache)
    end

    it 'clears the models cache for the vendor' do
      expect($MODELS[:test_vendor]).not_to be_nil
      helper_instance.clear_models_cache
      expect($MODELS[:test_vendor]).to be_nil
    end
  end

  describe '#privacy_enabled_for? two-gate activation' do
    subject(:helper) do
      Class.new { include BaseVendorHelper }.new
    end

    let(:enabled_settings) { { privacy: { enabled: true } } }
    let(:disabled_settings) { { privacy: { enabled: false } } }

    it 'returns false when app_settings is nil' do
      session = { _privacy_session_enabled: true }
      expect(helper.privacy_enabled_for?(nil, session)).to be false
    end

    it 'returns false when MDSL privacy is disabled, even if session opts in' do
      session = { _privacy_session_enabled: true }
      expect(helper.privacy_enabled_for?(disabled_settings, session)).to be false
    end

    it 'returns false when MDSL enables but session does not opt in' do
      session = { _privacy_session_enabled: false }
      expect(helper.privacy_enabled_for?(enabled_settings, session)).to be false
    end

    it 'returns false when session is nil' do
      expect(helper.privacy_enabled_for?(enabled_settings, nil)).to be false
    end

    it 'returns false when session SSOT key is absent (user never opted in)' do
      expect(helper.privacy_enabled_for?(enabled_settings, {})).to be false
    end

    it 'returns true only when both MDSL and session opt in' do
      session = { _privacy_session_enabled: true }
      expect(helper.privacy_enabled_for?(enabled_settings, session)).to be true
    end

    it 'ignores any leftover privacy_session_enabled in params (params is not authoritative)' do
      # Stale clients could still write the legacy field. The contract is
      # "PRIVACY_TOGGLE is the only path", so a params-only declaration
      # must NOT activate masking.
      session = { parameters: { 'privacy_session_enabled' => true } }
      expect(helper.privacy_enabled_for?(enabled_settings, session)).to be false
    end

    it 'works with non-Hash session-like objects (e.g., Rack SecureSessionHash)' do
      # Production Rack sessions are
      # Rack::Session::Abstract::PersistedSecure::SecureSessionHash, which
      # supports `[]` but is NOT a Hash subclass. Tightening the gate to
      # `is_a?(Hash)` would silently disable masking in production while
      # passing plain-Hash unit fixtures.
      rack_session = Class.new do
        def initialize(data); @data = data; end
        def [](key); @data[key] || @data[key.to_s]; end
      end.new(_privacy_session_enabled: true)

      expect(rack_session.is_a?(Hash)).to be false
      expect(helper.privacy_enabled_for?(enabled_settings, rack_session)).to be true
    end
  end

  describe '#apply_privacy_to_messages with Claude-shape content' do
    subject(:helper) do
      Class.new do
        include BaseVendorHelper
      end.new
    end

    let(:fake_pipeline) do
      double('Pipeline').tap do |p|
        allow(p).to receive(:before_send_to_llm) do |raw|
          masked_text = raw.text.gsub(/Alice/, '<<PERSON_1>>')
          double('MaskedMessage', text: masked_text)
        end
      end
    end

    before do
      require_relative '../../../lib/monadic/utils/privacy/types'
      allow(helper).to receive(:privacy_pipeline_for).and_return(fake_pipeline)
    end

    it 'masks user-message text in Anthropic-style content array' do
      messages = [
        { "role" => "user", "content" => [{ "type" => "text", "text" => "Email Alice" }] }
      ]
      result = helper.apply_privacy_to_messages(messages, {}, { privacy: { enabled: true } })
      expect(result[0]["content"][0]["text"]).to eq("Email <<PERSON_1>>")
    end

    it 'leaves image and document blocks untouched while masking text blocks' do
      messages = [{
        "role" => "user",
        "content" => [
          { "type" => "image", "source" => { "type" => "base64", "data" => "abc" } },
          { "type" => "text", "text" => "What does Alice think?" },
          { "type" => "document", "source" => { "type" => "base64", "data" => "pdf" } }
        ]
      }]
      result = helper.apply_privacy_to_messages(messages, {}, { privacy: { enabled: true } })
      expect(result[0]["content"][0]["type"]).to eq("image")
      expect(result[0]["content"][0]["source"]["data"]).to eq("abc")
      expect(result[0]["content"][1]["text"]).to eq("What does <<PERSON_1>> think?")
      expect(result[0]["content"][2]["type"]).to eq("document")
    end

    it 'masks assistant-role messages too (multi-turn context replay)' do
      # session[:messages] stores the restored text for past assistant
      # turns; on the next round-trip it must be re-masked using the same
      # registry so PII does not leak back to the LLM via context history.
      messages = [
        { "role" => "user", "content" => [{ "type" => "text", "text" => "Hi Alice" }] },
        { "role" => "assistant", "content" => [{ "type" => "text", "text" => "Hello Alice" }] }
      ]
      result = helper.apply_privacy_to_messages(messages, {}, { privacy: { enabled: true } })
      expect(result[0]["content"][0]["text"]).to eq("Hi <<PERSON_1>>")
      expect(result[1]["content"][0]["text"]).to eq("Hello <<PERSON_1>>")
    end

    it 'leaves system / tool / developer roles untouched' do
      messages = [
        { "role" => "system", "content" => "You are a helpful assistant about Alice." },
        { "role" => "tool", "content" => [{ "type" => "text", "text" => "tool output mentioning Alice" }] },
        { "role" => "user", "content" => "Hi Alice" }
      ]
      result = helper.apply_privacy_to_messages(messages, {}, { privacy: { enabled: true } })
      expect(result[0]["content"]).to eq("You are a helpful assistant about Alice.")
      expect(result[1]["content"][0]["text"]).to eq("tool output mentioning Alice")
      expect(result[2]["content"]).to eq("Hi <<PERSON_1>>")
    end

    it 'returns messages unchanged when pipeline is nil (privacy disabled)' do
      allow(helper).to receive(:privacy_pipeline_for).and_return(nil)
      messages = [{ "role" => "user", "content" => [{ "type" => "text", "text" => "Hi Alice" }] }]
      result = helper.apply_privacy_to_messages(messages, {}, nil)
      expect(result).to eq(messages)
    end
  end

  # End-to-end gating: privacy_pipeline_for must honor both gates
  # (MDSL `privacy.enabled` + session opt-in via PRIVACY_TOGGLE) and
  # only build a Pipeline when both are true.
  describe '#privacy_pipeline_for end-to-end gating' do
    subject(:helper) do
      Class.new { include BaseVendorHelper }.new
    end

    let(:enabled_settings) { { privacy: { enabled: true, languages: ["en"], score_threshold: 0.4, honorific_trim: true } } }

    before do
      require_relative '../../../lib/monadic/utils/privacy/presidio_backend'
      require_relative '../../../lib/monadic/utils/privacy/pipeline'
      # Stub the network-bound backend so the test does not require the
      # privacy container to be running.
      fake_backend = instance_double(Monadic::Utils::Privacy::PresidioBackend)
      allow(Monadic::Utils::Privacy::PresidioBackend).to receive(:new).and_return(fake_backend)
      allow(fake_backend).to receive(:anonymize) do |args|
        masked = args[:text].gsub(/Alice/, '<<PERSON_1>>')
        { masked_text: masked, registry: { '<<PERSON_1>>' => 'Alice' }, entities: [], stats: {} }
      end
    end

    it 'creates a real Pipeline that masks input text when both gates pass' do
      session = { _privacy_session_enabled: true }
      messages = [{ "role" => "user", "content" => "Email Alice today" }]

      result = helper.apply_privacy_to_messages(messages, session, enabled_settings)
      expect(result[0]["content"]).to eq("Email <<PERSON_1>> today")
    end

    it 'returns no pipeline when session SSOT key is missing' do
      # No PRIVACY_TOGGLE was sent, so the toggle key is absent and the
      # gate must refuse to build a pipeline.
      session = { parameters: { 'message' => 'Hi Alice' } }
      messages = [{ "role" => "user", "content" => "Email Alice today" }]

      expect(helper.privacy_pipeline_for(session, enabled_settings)).to be_nil
      result = helper.apply_privacy_to_messages(messages, session, enabled_settings)
      expect(result[0]["content"]).to eq("Email Alice today")
    end

    it 'returns no pipeline when MDSL declares privacy but session opts out' do
      session = { _privacy_session_enabled: false }
      expect(helper.privacy_pipeline_for(session, enabled_settings)).to be_nil
    end
  end

  describe 'Vocabulary substitution helpers' do
    subject(:helper) { Class.new { include BaseVendorHelper }.new }

    let(:vocab_settings) { { vocabulary: { tokens: [:shared] } } }

    before do
      require 'monadic/utils/environment'
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return('/monadic/data')
    end

    describe '#substitution_pipeline_for' do
      it 'builds a pipeline by default (${SHARED} on) even with no vocabulary block' do
        expect(helper.substitution_pipeline_for({}, {})).to be_a(Monadic::Substitution::Pipeline)
      end

      it 'returns nil only when the app opts out (vocabulary false)' do
        expect(helper.substitution_pipeline_for({}, { vocabulary: { tokens: [], enabled: false } })).to be_nil
      end

      it 'builds and caches a Vocabulary-only pipeline' do
        session = {}
        pipeline = helper.substitution_pipeline_for(session, vocab_settings)
        expect(pipeline).to be_a(Monadic::Substitution::Pipeline)
        expect(session[:_substitution_pipeline]).to equal(pipeline)
        # cached: second call returns the same instance
        expect(helper.substitution_pipeline_for(session, vocab_settings)).to equal(pipeline)
      end

      it 'works with a non-Hash session that only duck-types [] (SecureSessionHash)' do
        store = {}
        session = Object.new
        session.define_singleton_method(:[]) { |k| store[k] }
        session.define_singleton_method(:[]=) { |k, v| store[k] = v }
        expect(helper.substitution_pipeline_for(session, vocab_settings)).to be_a(Monadic::Substitution::Pipeline)
      end
    end

    describe '#expand_tool_args_for_vocabulary' do
      it 'expands ${SHARED} prefixes deeply across the arg structure' do
        args = { 'path' => '${SHARED}/a.txt', 'nested' => ['${SHARED}/b'] }
        out = helper.expand_tool_args_for_vocabulary(args, {}, vocab_settings)
        expect(out).to eq('path' => '/monadic/data/a.txt', 'nested' => ['/monadic/data/b'])
      end

      it 'returns args unchanged when the app opted out (vocabulary false)' do
        args = { 'path' => '${SHARED}/a.txt' }
        opted_out = { vocabulary: { tokens: [], enabled: false } }
        expect(helper.expand_tool_args_for_vocabulary(args, {}, opted_out)).to eq(args)
      end

      it 'leaves a backtick-escaped token literal' do
        out = helper.expand_tool_args_for_vocabulary({ 'doc' => 'see `${SHARED}`' }, {}, vocab_settings)
        expect(out).to eq('doc' => 'see `${SHARED}`')
      end
    end

    describe '#decorate_response_text' do
      it 'wraps ${SHARED} in <code> with a resolved-path title' do
        out = helper.decorate_response_text('see ${SHARED}', {}, vocab_settings)
        expect(out).to eq('see <code class="vocab-token" title="/monadic/data">${SHARED}</code>')
      end

      it 'returns the text unchanged when the app opted out (vocabulary false)' do
        opted_out = { vocabulary: { tokens: [], enabled: false } }
        expect(helper.decorate_response_text('see ${SHARED}', {}, opted_out)).to eq('see ${SHARED}')
      end

      it 'returns non-string input unchanged' do
        expect(helper.decorate_response_text(nil, {}, vocab_settings)).to be_nil
      end
    end
  end
end
