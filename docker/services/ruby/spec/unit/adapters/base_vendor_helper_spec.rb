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
