# frozen_string_literal: true

require_relative "../../../spec_helper"
require "monadic/substitution/providers/privacy_filter"
require "monadic/substitution/pipeline"
require "monadic/substitution/context"
require "monadic/utils/privacy/types"

# Interface tests for the Privacy Filter recast as a Substitution::Provider
# (Phase 2.2). The behaviour-equivalence with the legacy Privacy::Pipeline is
# covered by spec/unit/utils/privacy/ and spec/golden/privacy/ (which run
# against the same class via the alias); these tests pin the *provider*
# contract: the generic hooks, the failure policy, the state neutralization,
# and that the legacy rich methods still return their structured types from the
# same shared core.
RSpec.describe Monadic::Substitution::Providers::PrivacyFilter do
  let(:masked_response) do
    { masked_text: "Hi <<PERSON_1>>", registry: { "<<PERSON_1>>" => "Alice" }, entities: [{ "placeholder" => "<<PERSON_1>>" }], stats: {} }
  end

  let(:ok_backend) do
    double("Backend").tap { |b| allow(b).to receive(:anonymize).and_return(masked_response) }
  end

  let(:failing_backend) do
    double("Backend").tap do |b|
      allow(b).to receive(:anonymize).and_raise(Monadic::Utils::Privacy::BackendError, "boom")
    end
  end

  let(:session) { { parameters: { "conversation_language" => "en" } } }

  def build(backend: ok_backend, config: { enabled: true })
    described_class.new(backend: backend, config: config, session: session)
  end

  let(:context) { Monadic::Substitution::Context.new(session: session) }

  describe "provider identity & policy" do
    it "is a Substitution::Provider" do
      expect(build).to be_a(Monadic::Substitution::Provider)
    end

    it "registers on a Substitution::Pipeline without error" do
      pipeline = Monadic::Substitution::Pipeline.new(session: session)
      expect { pipeline.register(build) }.not_to raise_error
      expect(pipeline.providers.length).to eq(1)
    end

    it "names itself PrivacyFilter" do
      expect(build.name).to eq("PrivacyFilter")
    end

    it "declares a :closed failure mode (PII-leak prevention)" do
      expect(build.failure_mode).to eq(:closed)
    end

    it "owns no tokens yet (deferred to Phase 4)" do
      expect(build.owns_token?("PERSON_1")).to be(false)
      expect(build.resolve("PERSON_1", context)).to be_nil
    end
  end

  describe "#state neutralization (no orphan substitution_state slot)" do
    it "raises rather than creating session[:substitution_state]" do
      expect { build.state(context) }.to raise_error(NotImplementedError)
      expect(session).not_to have_key(:substitution_state)
    end
  end

  describe "#on_input (generic hook, String in/out)" do
    it "returns masked text as a String" do
      expect(build.on_input("Hi Alice", context)).to eq("Hi <<PERSON_1>>")
    end

    it "passes the message through unchanged when disabled" do
      provider = build(config: { enabled: false })
      expect(provider.on_input("Hi Alice", context)).to eq("Hi Alice")
    end

    it "propagates BackendError (does NOT swallow it — failure_mode governs)" do
      provider = build(backend: failing_backend)
      expect { provider.on_input("Hi Alice", context) }.to raise_error(Monadic::Utils::Privacy::BackendError)
    end

    it "writes the registry to monadic_state[:privacy], not substitution_state" do
      build.on_input("Hi Alice", context)
      expect(session.dig(:monadic_state, :privacy, :registry)).to eq("<<PERSON_1>>" => "Alice")
      expect(session).not_to have_key(:substitution_state)
    end
  end

  describe "#on_output_render (generic hook, String in/out)" do
    let(:session) do
      { parameters: { "conversation_language" => "en" },
        monadic_state: { privacy: { registry: { "<<PERSON_1>>" => "Alice" }, audit: [] } } }
    end

    it "restores placeholders and returns a String" do
      expect(build.on_output_render("Bye <<PERSON_1>>", context)).to eq("Bye Alice")
    end

    it "passes the text through unchanged when disabled" do
      provider = build(config: { enabled: false })
      expect(provider.on_output_render("Bye <<PERSON_1>>", context)).to eq("Bye <<PERSON_1>>")
    end
  end

  describe "legacy rich methods keep their structured return types" do
    it "before_send_to_llm returns a MaskedMessage with .text" do
      raw = Monadic::Utils::Privacy::RawMessage.new("Hi Alice", "user", {})
      masked = build.before_send_to_llm(raw)
      expect(masked).to be_a(Monadic::Utils::Privacy::MaskedMessage)
      expect(masked.text).to eq("Hi <<PERSON_1>>")
      expect(masked.safe_for_llm?).to be(true)
    end

    it "after_receive_from_llm returns a RestoredResponse with .text and .meta" do
      session_with_reg = { monadic_state: { privacy: { registry: { "<<PERSON_1>>" => "Alice" }, audit: [] } } }
      provider = described_class.new(backend: ok_backend, config: { enabled: true }, session: session_with_reg)
      restored = provider.after_receive_from_llm("Bye <<PERSON_1>>")
      expect(restored).to be_a(Monadic::Utils::Privacy::RestoredResponse)
      expect(restored.text).to eq("Bye Alice")
      expect(restored.meta[:restored_spans]).to contain_exactly(
        { placeholder: "<<PERSON_1>>", entity_type: "PERSON", original: "Alice" }
      )
    end
  end

  describe "tolerant restoration of LLM-corrupted placeholders" do
    let(:corrupt_session) do
      { monadic_state: { privacy: { registry: { "<<EMAIL_ADDRESS_2>>" => "robert.chen@example.com",
                                                "<<PERSON_1>>" => "Alice Johnson" }, audit: [] } } }
    end

    def corrupt_provider
      described_class.new(backend: ok_backend, config: { enabled: true }, session: corrupt_session)
    end

    it "restores a token the model wrapped in stray '?' (the reported case)" do
      result = corrupt_provider.after_receive_from_llm("CC: <<?EMAIL_ADDRESS_2?>> please")
      expect(result.text).to eq("CC: robert.chen@example.com please")
      expect(result.meta[:missing_placeholders]).to eq([])
    end

    it "restores a token padded with whitespace" do
      expect(corrupt_provider.after_receive_from_llm("Hi << PERSON_1 >>").text).to eq("Hi Alice Johnson")
    end

    it "normalizes the span placeholder to the clean canonical key" do
      spans = corrupt_provider.after_receive_from_llm("<<?PERSON_1?>>").meta[:restored_spans]
      expect(spans).to contain_exactly(
        { placeholder: "<<PERSON_1>>", entity_type: "PERSON", original: "Alice Johnson" }
      )
    end

    it "still restores perfectly clean tokens unchanged" do
      expect(corrupt_provider.after_receive_from_llm("<<PERSON_1>>").text).to eq("Alice Johnson")
    end

    it "sanitize_for_tts also tolerates the corruption" do
      expect(corrupt_provider.sanitize_for_tts("call <<?PERSON_1?>> now")).to eq("call PERSON 1 now")
    end
  end

  describe "shared masking core: on_input and before_send_to_llm agree" do
    it "produces the same masked text from the same input" do
      hook_out = build.on_input("Hi Alice", context)
      raw = Monadic::Utils::Privacy::RawMessage.new("Hi Alice", "user", {})
      legacy_out = build.before_send_to_llm(raw).text
      expect(hook_out).to eq(legacy_out)
    end
  end

  describe "before_send_to_llm failure policy (independent of failure_mode)" do
    it "raises BackendError when on_failure is :block" do
      provider = build(backend: failing_backend, config: { enabled: true, on_failure: :block })
      raw = Monadic::Utils::Privacy::RawMessage.new("Hi Alice", "user", {})
      expect { provider.before_send_to_llm(raw) }.to raise_error(Monadic::Utils::Privacy::BackendError)
    end

    it "returns the raw message when on_failure is :pass" do
      provider = build(backend: failing_backend, config: { enabled: true, on_failure: :pass })
      raw = Monadic::Utils::Privacy::RawMessage.new("Hi Alice", "user", {})
      result = provider.before_send_to_llm(raw)
      expect(result).to equal(raw)
    end
  end
end
