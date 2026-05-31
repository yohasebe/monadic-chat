# frozen_string_literal: true

require_relative "../../../spec_helper"
require "monadic/substitution/providers/vocabulary"
require "monadic/substitution/pipeline"
require "monadic/substitution/context"
require "monadic/utils/environment"

RSpec.describe Monadic::Substitution::Providers::Vocabulary do
  let(:session) { {} }
  let(:context) { Monadic::Substitution::Context.new(session: session) }

  before do
    # Deterministic resolution regardless of container/dev mode.
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return("/monadic/data")
  end

  def provider(tokens: [:shared])
    described_class.new(tokens: tokens)
  end

  describe "provider identity & policy" do
    it "is a Substitution::Provider" do
      expect(provider).to be_a(Monadic::Substitution::Provider)
    end

    it "names itself Vocabulary" do
      expect(provider.name).to eq("Vocabulary")
    end

    it "declares an :open failure mode (a miss must not break the turn)" do
      expect(provider.failure_mode).to eq(:open)
    end

    it "registers on a Substitution::Pipeline" do
      pipeline = Monadic::Substitution::Pipeline.new(session: session)
      expect { pipeline.register(provider) }.not_to raise_error
    end
  end

  describe "#owns_token? / #resolve" do
    it "owns an enabled token by its bare name" do
      expect(provider.owns_token?("SHARED")).to be(true)
    end

    it "does not own a token the app did not opt into" do
      expect(provider(tokens: []).owns_token?("SHARED")).to be(false)
    end

    it "does not own an unknown token" do
      expect(provider.owns_token?("NOPE")).to be(false)
    end

    it "resolves an enabled token to its value" do
      expect(provider.resolve("SHARED", context)).to eq("/monadic/data")
    end

    it "returns nil resolving a non-enabled token" do
      expect(provider(tokens: []).resolve("SHARED", context)).to be_nil
    end

    it "returns nil resolving an unknown token" do
      expect(provider.resolve("NOPE", context)).to be_nil
    end
  end

  describe "#on_tool_invoke (expansion)" do
    it "expands a bare ${SHARED} in a string arg" do
      out = provider.on_tool_invoke("t", { "path" => "${SHARED}" }, context)
      expect(out).to eq("path" => "/monadic/data")
    end

    it "expands the prefix of ${SHARED}/sub/path" do
      out = provider.on_tool_invoke("t", { "path" => "${SHARED}/reports/q1.csv" }, context)
      expect(out).to eq("path" => "/monadic/data/reports/q1.csv")
    end

    it "expands across nested hashes and arrays" do
      args = { "files" => ["${SHARED}/a.txt", { "dst" => "${SHARED}/b.txt" }] }
      out = provider.on_tool_invoke("t", args, context)
      expect(out).to eq("files" => ["/monadic/data/a.txt", { "dst" => "/monadic/data/b.txt" }])
    end

    it "expands multiple tokens in one string" do
      out = provider.on_tool_invoke("t", { "cmd" => "cp ${SHARED}/a ${SHARED}/b" }, context)
      expect(out).to eq("cmd" => "cp /monadic/data/a /monadic/data/b")
    end

    it "leaves an unowned ${TOKEN} literal" do
      out = provider.on_tool_invoke("t", { "path" => "${OTHER}/x" }, context)
      expect(out).to eq("path" => "${OTHER}/x")
    end

    it "leaves ${SHARED} literal when the app did not opt in" do
      out = provider(tokens: []).on_tool_invoke("t", { "path" => "${SHARED}/x" }, context)
      expect(out).to eq("path" => "${SHARED}/x")
    end

    it "passes non-string scalars through untouched" do
      args = { "n" => 3, "flag" => true, "nothing" => nil }
      expect(provider.on_tool_invoke("t", args, context)).to eq(args)
    end

    it "does not expand hash keys, only values" do
      out = provider.on_tool_invoke("t", { "${SHARED}" => "v" }, context)
      expect(out).to eq("${SHARED}" => "v")
    end
  end

  describe "#on_output_render (decoration, no expansion)" do
    it "wraps an owned token in <code> with a hover title of the resolved value" do
      out = provider.on_output_render("see ${SHARED}", context)
      expect(out).to eq('see <code class="vocab-token" title="/monadic/data">${SHARED}</code>')
    end

    it "preserves the symbol and does NOT expand it" do
      out = provider.on_output_render("${SHARED}/x", context)
      expect(out).to include("${SHARED}")
      expect(out).not_to match(%r{/monadic/data/x})  # not expanded inline
      expect(out).to end_with("/x")                  # the path tail stays as text
    end

    it "decorates multiple occurrences" do
      out = provider.on_output_render("${SHARED} and ${SHARED}", context)
      expect(out.scan(/vocab-token/).length).to eq(2)
    end

    it "HTML-escapes the resolved value in the title attribute" do
      allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return('/d/"q"<x>')
      out = provider.on_output_render("${SHARED}", context)
      expect(out).to include('title="/d/&quot;q&quot;&lt;x&gt;"')
      expect(out).not_to include('<x>')
    end

    it "leaves an unowned token literal" do
      expect(provider.on_output_render("${OTHER}", context)).to eq("${OTHER}")
    end

    it "returns non-string input unchanged" do
      expect(provider.on_output_render(nil, context)).to be_nil
    end
  end

  describe "backtick escape (decision B)" do
    it "leaves a backtick-wrapped token literal during expansion" do
      out = provider.on_tool_invoke("t", { "doc" => "use `${SHARED}` here" }, context)
      expect(out).to eq("doc" => "use `${SHARED}` here")
    end

    it "leaves a backtick-wrapped token literal during decoration" do
      expect(provider.on_output_render("use `${SHARED}`", context)).to eq("use `${SHARED}`")
    end

    it "transforms only the unescaped occurrence in a mixed string (expand)" do
      out = provider.on_tool_invoke("t", { "doc" => "`${SHARED}` vs ${SHARED}/x" }, context)
      expect(out).to eq("doc" => "`${SHARED}` vs /monadic/data/x")
    end

    it "transforms only the unescaped occurrence in a mixed string (decorate)" do
      out = provider.on_output_render("`${SHARED}` vs ${SHARED}", context)
      expect(out).to start_with("`${SHARED}` vs ")
      expect(out.scan(/vocab-token/).length).to eq(1)
    end
  end

  describe "#system_prompt_addendum" do
    it "lists each enabled token with its description" do
      out = provider.system_prompt_addendum(context)
      expect(out).to include("${SHARED}")
      expect(out).to include("shared data folder")
    end

    it "returns nil when the app exposes no tokens" do
      expect(provider(tokens: []).system_prompt_addendum(context)).to be_nil
    end
  end
end
