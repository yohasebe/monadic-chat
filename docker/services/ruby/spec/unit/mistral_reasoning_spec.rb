# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/monadic/utils/model_spec"

# Magistral reasoning handling. Two regressions are locked here:
#
# 1. WIRE FORMAT — Magistral streams its reasoning INSIDE the content array
#    (verified against the live Mistral API 2026-07-09):
#      delta.content = [{ "type" => "thinking",
#                         "thinking" => [{"type"=>"text","text"=>...}] }]
#    while the answer arrives as plain-string content deltas. The generic
#    Array flattening used to read c["text"]/c["content"] (both nil for
#    thinking items) and silently discarded the entire trace, so Magistral
#    never showed a Thinking panel in Monadic.
#
# 2. reasoning_effort GATING — the Mistral API rejects reasoning_effort for
#    Magistral models outright ("reasoning_effort is not enabled for this
#    model", HTTP 400, verified live 2026-07-09); Magistral reasons by
#    default. The parameter must be sent ONLY for models whose spec declares
#    a reasoning_effort property (SSOT gate), never merely because
#    supports_thinking is true.
RSpec.describe "Mistral Magistral Reasoning" do
  describe "content-array thinking extraction (live wire format)" do
    # Mirrors the extraction in mistral_helper's streaming loop.
    def extract(delta)
      thinking = []
      if delta["content"].is_a?(Array)
        text = delta["content"].filter_map do |item|
          next unless item.is_a?(Hash) && item["type"] == "thinking"

          Array(item["thinking"]).filter_map do |chunk|
            chunk["text"] if chunk.is_a?(Hash) && chunk["type"] == "text"
          end.join
        end.join
        thinking << text unless text.empty?
      end
      content = delta["content"]
      if content.is_a?(Array)
        content = content.filter_map do |c|
          next if c.is_a?(Hash) && c["type"] == "thinking"

          c.is_a?(Hash) ? (c["text"] || c["content"] || "") : c.to_s
        end.join
      end
      [thinking, content.to_s]
    end

    it "captures thinking from the content array and keeps it out of the answer" do
      delta = {
        "content" => [
          { "type" => "thinking",
            "thinking" => [{ "type" => "text", "text" => "Okay" },
                           { "type" => "text", "text" => ", let's see." }] }
        ]
      }
      thinking, content = extract(delta)
      expect(thinking).to eq(["Okay, let's see."])
      expect(content).to eq("")
    end

    it "passes plain-string answer deltas through untouched" do
      thinking, content = extract({ "content" => "Yes, 17 is prime." })
      expect(thinking).to be_empty
      expect(content).to eq("Yes, 17 is prime.")
    end

    it "keeps non-thinking array items as answer text" do
      delta = { "content" => [{ "type" => "text", "text" => "Answer." }] }
      thinking, content = extract(delta)
      expect(thinking).to be_empty
      expect(content).to eq("Answer.")
    end
  end

  describe "reasoning_effort SSOT gating" do
    it "Magistral models do NOT declare reasoning_effort (API rejects the param)" do
      %w[magistral-medium-latest magistral-small-latest].each do |m|
        expect(Monadic::Utils::ModelSpec.model_has_property?(m, "reasoning_effort"))
          .to be(false), "#{m} must not declare reasoning_effort"
        expect(Monadic::Utils::ModelSpec.supports_thinking?(m))
          .to be(true), "#{m} should remain supports_thinking"
      end
    end

    it "reasoning-effort-capable Mistral models still declare it" do
      expect(Monadic::Utils::ModelSpec.model_has_property?("mistral-medium-3-5", "reasoning_effort")).to be(true)
    end
  end

  describe "reasoning persistence across tool-call rounds" do
    # Mirrors the session accumulator added around the api_request("tool")
    # recursion and the prepend-merge in build_mistral_text_response.
    it "prepends pre-tool reasoning to the final round's thinking" do
      session = {}
      round1_thinking = ["Deciding to run code"]
      (session[:mistral_reasoning] ||= []).concat(round1_thinking)

      final_thinking = ["Final check"]
      if session[:mistral_reasoning].is_a?(Array) && !session[:mistral_reasoning].empty?
        final_thinking = session[:mistral_reasoning] + final_thinking
        session.delete(:mistral_reasoning)
      end

      expect(final_thinking).to eq(["Deciding to run code", "Final check"])
      expect(session).not_to have_key(:mistral_reasoning)
    end
  end
end
