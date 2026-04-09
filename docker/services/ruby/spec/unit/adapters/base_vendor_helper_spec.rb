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

  describe '#retry_with_backoff' do
    subject(:helper) do
      Class.new do
        include BaseVendorHelper
      end.new
    end

    it 'returns the block result on success' do
      result = helper.retry_with_backoff { 42 }
      expect(result).to eq(42)
    end

    it 'retries on HTTP::Error up to max_retries' do
      call_count = 0
      result = helper.retry_with_backoff(max_retries: 3, delay: 0) do
        call_count += 1
        raise HTTP::Error, "timeout" if call_count < 3
        "success"
      end
      expect(result).to eq("success")
      expect(call_count).to eq(3)
    end

    it 'raises after exceeding max_retries' do
      expect {
        helper.retry_with_backoff(max_retries: 2, delay: 0) do
          raise HTTP::Error, "always fails"
        end
      }.to raise_error(HTTP::Error)
    end

    it 'raises non-network errors immediately without retry' do
      call_count = 0
      expect {
        helper.retry_with_backoff(max_retries: 5, delay: 0) do
          call_count += 1
          raise ArgumentError, "bad input"
        end
      }.to raise_error(ArgumentError)
      expect(call_count).to eq(1)
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
end
