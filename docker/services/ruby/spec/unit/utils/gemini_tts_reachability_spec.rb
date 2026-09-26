# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/tts_utils"
require_relative "../../../lib/monadic/utils/model_spec"

RSpec.describe "Gemini TTS selector reachability" do
  let(:host) { Class.new { include InteractionUtils }.new }
  let(:script) do
    path = File.expand_path("../../../scripts/cli_tools/tts_query.rb", __dir__)
    Object.new.tap { |receiver| receiver.instance_eval(File.read(path).split("# Usage:", 2).first, path) }
  end
  let(:models) { Monadic::Utils::ModelSpec.get_provider_models("gemini", "tts") }
  let(:options) do
    html = File.read(File.expand_path("../../../views/index.erb", __dir__))
    select = html[/<select\b[^>]*id="tts-provider".*?<\/select>/m]
    select.scan(/<option\b[^>]*value="(gemini[^"]*)"/).flatten
  end

  %w[gemini gemini-flash gemini-flash-lite gemini-pro].each do |label|
    it("recognizes #{label}") { expect(Monadic::Utils::TtsProvider.gemini?(label)).to be(true) }
  end

  [nil, "", "openai-tts", "elevenlabs", "mistral", "grok", "webspeech", "gemini-unknown", "gemini-3.8-flash-tts"].each do |label|
    it("rejects #{label.inspect}") { expect(Monadic::Utils::TtsProvider.gemini?(label)).to be(false) }
  end

  [:host, :script].each do |route|
    context route.to_s do
      it "resolves every actual UI option to a distinct, existing SSOT TTS model" do
        expect(options).not_to be_empty
        resolved = options.map { |label| public_send(route).send(:resolve_tts_model, label) }
        expect(resolved.uniq.size).to eq(options.size)
        resolved.each do |model|
          expect(models).to include(model)
          expect(Monadic::Utils::ModelSpec.get_model_property(model, "tts_capability")).to be(true)
        end
      end

      it "reaches the first SSOT model of every available variant from the UI" do
        # Older generations within the same variant remain fallback entries.
        # Check coverage separately: uniqueness alone cannot detect a missing option.
        representatives = models.group_by do |model|
          model.include?("flash-lite") ? :lite : (model.include?("-pro-") ? :pro : :flash)
        end.values.map(&:first)
        resolved = options.map { |label| public_send(route).send(:resolve_tts_model, label) }
        expect(resolved).to match_array(representatives)
      end

      it "resolves explicit variants by name while preserving the unsuffixed default" do
        reordered = %w[gemini-2.5-pro-preview-tts gemini-3.8-flash-lite-tts gemini-3.8-flash-tts]
        allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models).with("gemini", "tts").and_return(reordered)
        receiver = public_send(route)
        expect(receiver.send(:resolve_tts_model, "gemini-flash")).to eq(reordered[2])
        expect(receiver.send(:resolve_tts_model, "gemini-flash-lite")).to eq(reordered[1])
        expect(receiver.send(:resolve_tts_model, "gemini-pro")).to eq(reordered[0])
        expect(receiver.send(:resolve_tts_model, "gemini")).to eq(reordered.first)
      end

      [nil, [], ["gemini-2.5-pro-preview-tts"]].each do |available|
        it "does not substitute another variant when Flash/Lite are absent from #{available.inspect}" do
          allow(Monadic::Utils::ModelSpec).to receive(:get_provider_models).with("gemini", "tts").and_return(available)
          %w[gemini-flash gemini-flash-lite].each do |label|
            expect(public_send(route).send(:resolve_tts_model, label)).to be_nil
          end
        end
      end
    end
  end
end
