# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../lib/monadic/utils/tts_utils"
require_relative "../../../lib/monadic/utils/tts_provider"
require_relative "../../../lib/monadic/utils/model_spec"
require_relative "../../../lib/monadic/utils/tts_text_processors"

# ttsChoices (model_spec.js) maps each TTS provider selector value to the
# provider that speaks it and the model it sends. The expectations are shared
# with test/frontend/tts-choices.test.js, so Ruby and the browser resolve the
# same value the same way.
RSpec.describe "TTS choices" do
  let(:expected) { JSON.parse(File.read(File.expand_path("../../fixtures/tts/choices_expected.json", __dir__))) }
  let(:choices) { Monadic::Utils::ModelSpec.load_tts_choices }
  let(:tp) { Monadic::Utils::TtsProvider }

  it "resolves every value, saved aliases included, as expected" do
    expect(choices.keys).to match_array(expected.keys)
    expected.each do |label, want|
      got = tp.choice(label)
      expect(got).to include(requested_id: label, id: want["id"], provider: want["provider"], model: want["model"]),
                     "#{label}: #{got.inspect}"
      expect(got[:execution]).to eq(want["execution"] || "server")
    end
  end

  # The table is a statement of today's behaviour: each value names the
  # model the request path sends now (asked of resolve_tts_model itself).
  it "names the model the current request path sends for each value" do
    host = Class.new { include InteractionUtils; public :resolve_tts_model }.new
    expected.each do |label, want|
      next if want["provider"] == "webspeech"

      expect(host.resolve_tts_model(label)).to eq(want["model"]), label
    end
  end

  it "names only registered TTS models, and aliases that reach a choice" do
    choices.each do |label, entry|
      if entry["alias"]
        expect(choices[entry["alias"]]).to include("provider"), "#{label} -> #{entry['alias']}"
        expect(choices[entry["alias"]]).not_to include("alias")
      elsif entry["execution"] == "browser"
        expect(entry["model"]).to be_nil
      else
        expect(Monadic::Utils::ModelSpec.get_model_property(entry["model"], "tts_capability")).to be(true), label
      end
    end
  end

  it "sends no deprecated model, and moves a retired choice to an offered one" do
    choices.each do |label, entry|
      next if entry["alias"] || entry["model"].nil?

      expect(Monadic::Utils::ModelSpec.deprecated?(entry["model"])).to be(false), label
    end
    choices.select { |_, e| e["retired"] }.each do |label, entry|
      expect(entry["alias"]).not_to be_nil, label
    end
  end

  it "resolves nothing for an empty, unknown or circular value" do
    expect(tp.choice(nil)).to be_nil
    expect(tp.choice(" ")).to be_nil
    expect(tp.choice("no-such-voice")).to be_nil
    allow(Monadic::Utils::ModelSpec).to receive(:load_tts_choices).and_return({ "a" => { "alias" => "b" }, "b" => { "alias" => "a" } })
    expect(tp.choice("a")).to be_nil
  end

  it "offers in the page exactly the choices that are not aliases" do
    erb = File.read(File.expand_path("../../../views/index.erb", __dir__))
    block = erb[/<select[^>]*id="tts-provider".*?<\/select>/m]
    offered = block.scan(/<option[^>]*value="([^"]+)"/).flatten
    expect(offered).to match_array(choices.reject { |_, e| e["alias"] }.keys)
  end

  # The family that decides how a value's text is prepared (markers,
  # instructions); shared with tts-tag-sanitizer.js.
  it "gives every value and TTS model the expected text family" do
    families = JSON.parse(File.read(File.expand_path("../../fixtures/tts/families_expected.json", __dir__)))
    families.each do |key, family|
      expect(Monadic::Utils::TtsTextProcessors.family_for(key)).to eq(family), key
    end
  end

  it "is read again after ModelSpec.reload!" do
    first = Monadic::Utils::ModelSpec.load_tts_choices
    Monadic::Utils::ModelSpec.reload!
    expect(Monadic::Utils::ModelSpec.load_tts_choices).not_to equal(first)
    expect(Monadic::Utils::ModelSpec.load_tts_choices).to eq(first)
  end
end
