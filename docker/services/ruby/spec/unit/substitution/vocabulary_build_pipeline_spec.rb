# frozen_string_literal: true

require_relative "../../../lib/monadic/substitution/vocabulary"
require_relative "../../../lib/monadic/substitution/pipeline"
require_relative "../../../lib/monadic/substitution/providers/vocabulary"

# Regression coverage for the build-if-absent seam shared by the vendor-helper
# tool-call path (BaseVendorHelper#substitution_pipeline_for) and the WebSocket
# streaming handler's display-decoration attach site. Previously the pipeline was
# only built inside the OpenAI tool-call path, so pure-text turns (and providers
# that did not invoke a tool) shipped an empty vocabulary_map and ${TOKEN}s stayed
# literal in the rendered card. Vocabulary.build_pipeline is now the single
# builder both sites call.
RSpec.describe Monadic::Substitution::Vocabulary do
  describe ".build_pipeline" do
    context "when the session has no pipeline yet (default-on app)" do
      let(:session) { {} }

      it "builds a pipeline and memoizes it into session[:_substitution_pipeline]" do
        expect(session[:_substitution_pipeline]).to be_nil

        pipeline = described_class.build_pipeline(session, nil)

        expect(pipeline).to be_a(Monadic::Substitution::Pipeline)
        expect(session[:_substitution_pipeline]).to equal(pipeline)
      end

      it "produces a non-empty vocabulary_map (default ${SHARED} present)" do
        pipeline = described_class.build_pipeline(session, nil)

        map = pipeline.vocabulary_map
        expect(map).not_to be_empty
        expect(map).to have_key("SHARED")
      end

      it "memoizes: a second call returns the same instance and does not rebuild" do
        first = described_class.build_pipeline(session, nil)
        second = described_class.build_pipeline(session, nil)

        expect(second).to equal(first)
      end
    end

    context "when the app opts out of vocabulary (vocabulary false)" do
      let(:session) { {} }
      let(:app_settings) { { vocabulary: { enabled: false } } }

      it "returns nil and leaves no pipeline on the session (opt-out stays off)" do
        result = described_class.build_pipeline(session, app_settings)

        expect(result).to be_nil
        expect(session).not_to have_key(:_substitution_pipeline)
      end

      it "also honors string-keyed opt-out settings" do
        result = described_class.build_pipeline(session, { "vocabulary" => { "enabled" => false } })

        expect(result).to be_nil
        expect(session).not_to have_key(:_substitution_pipeline)
      end
    end

    context "when a pipeline already exists on the session" do
      it "returns the existing pipeline without rebuilding" do
        existing = Monadic::Substitution::Pipeline.new(session: {}, app: nil)
        session = { _substitution_pipeline: existing }

        result = described_class.build_pipeline(session, nil)

        expect(result).to equal(existing)
      end
    end

    context "when given a session that does not respond to []" do
      it "returns nil defensively" do
        expect(described_class.build_pipeline(nil, nil)).to be_nil
      end
    end
  end
end
