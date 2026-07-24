# frozen_string_literal: true

# Shared examples that PIN existing invariants common to all 8 chat
# provider helpers (openai, claude, gemini, grok, cohere, deepseek,
# mistral, ollama). These assert only what is already true today —
# they intentionally do NOT introduce or assume any unified abstraction
# (see docs_dev/provider_specific_features.md: "Best-of-Breed, not
# unified abstraction"). If a provider legitimately diverges, extend
# that provider's own spec instead of weakening these contracts.
#
# Expected lets in the including scope:
#   vendor_module   - the helper module (e.g. OpenAIHelper)
#   vendor_name     - String returned by vendor_module.vendor_name
#   retry_delay     - Integer value of the module's RETRY_DELAY constant
#   endpoint_prefix - String prefix of API_ENDPOINT ("https://" or "http://")

RSpec.shared_examples "a chat provider helper" do
  describe "retry constants" do
    it "defines MAX_RETRIES as 5" do
      expect(vendor_module.const_defined?(:MAX_RETRIES)).to be(true)
      expect(vendor_module::MAX_RETRIES).to eq(5)
    end

    it "defines RETRY_DELAY with the provider-specific value" do
      expect(vendor_module.const_defined?(:RETRY_DELAY)).to be(true)
      expect(vendor_module::RETRY_DELAY).to eq(retry_delay)
    end
  end

  describe "module identity" do
    it "returns the expected vendor_name at module level" do
      expect(vendor_module.vendor_name).to eq(vendor_name)
    end

    it "defines API_ENDPOINT as a non-empty String with the expected scheme" do
      expect(vendor_module::API_ENDPOINT).to be_a(String)
      expect(vendor_module::API_ENDPOINT).to start_with(endpoint_prefix)
    end

    it "includes BaseVendorHelper for shared infrastructure" do
      expect(vendor_module.include?(BaseVendorHelper)).to be(true)
    end
  end

  describe "#api_request signature" do
    # Common subset across all 8 providers: (role, session, call_depth:, &block).
    # Grok adds an optional `disable_streaming:` keyword on top of this subset;
    # providers may add optional keywords but must not change the common core.
    it "accepts (role, session, call_depth:, &block)" do
      params = vendor_module.instance_method(:api_request).parameters

      expect(params).to include([:req, :role])
      expect(params).to include([:req, :session])
      expect(params).to include([:key, :call_depth])
      expect(params.last).to eq([:block, :block])
    end
  end

  describe "#send_query signature" do
    it "accepts (options, model:) uniformly across providers" do
      params = vendor_module.instance_method(:send_query).parameters

      expect(params).to include([:req, :options])
      expect(params).to include([:key, :model])
    end
  end

  describe "model listing" do
    # 7 providers expose list_models via BaseVendorHelper.define_model_lister
    # (which defines both instance and module-level methods); Ollama exposes
    # it via module_function. Either way the module itself must respond.
    it "responds to list_models at module level" do
      expect(vendor_module).to respond_to(:list_models)
    end
  end

  describe "includability" do
    it "can be included in a plain class and exposes the entry points" do
      mod = vendor_module
      instance = Class.new { include mod }.new

      expect(instance).to respond_to(:api_request)
      expect(instance).to respond_to(:send_query)
    end
  end
end
