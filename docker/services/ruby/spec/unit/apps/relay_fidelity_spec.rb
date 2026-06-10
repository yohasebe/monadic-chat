# frozen_string_literal: true

require 'spec_helper'

# Guards the relay-fidelity guardrails added after the Music Analyst incident:
# orchestrator LLMs were found embellishing or reinterpreting authoritative
# tool/subagent results (another model's verdict, measured audio features, web
# sources, video analysis) when synthesizing the final answer. Each app below
# now carries an explicit faithful-relay section in its system prompt; these
# examples pin the load-bearing phrases across ALL provider variants so a
# future prompt edit can't silently drop the guardrail in one variant.
#
# Music Analyst's own pins live in music_analyst_tools_spec.rb.
RSpec.describe 'Relay-fidelity prompt guardrails' do
  apps_root = File.expand_path('../../../apps', __dir__)

  def self.variants(apps_root, dir, glob)
    Dir.glob(File.join(apps_root, dir, glob)).sort
  end

  describe 'Second Opinion (all variants)' do
    variants(apps_root, 'second_opinion', 'second_opinion_*.mdsl').each do |path|
      context File.basename(path) do
        let(:content) { File.read(path) }

        it 'relays the evaluator verdict unaltered' do
          expect(content).to match(/Relay the second opinion faithfully/i)
          expect(content).to match(/do NOT soften, strengthen, condense away, or reword/i)
          expect(content).to match(/validity score exactly as returned/i)
        end

        it 'keeps the orchestrator opinion separate and labeled' do
          expect(content).to match(/AFTER the relayed opinion, clearly labeled as yours/i)
        end

        # Dogfood (2026-06-10): the orchestrator re-typed the evaluator model
        # name from memory and fabricated an outdated one. The agent now embeds
        # the identity inside the comments; the prompt must forbid re-typing.
        it 'forbids re-typing the evaluator model name' do
          expect(content).to match(/NEVER write a model name from memory/i)
          expect(content).to match(/"Evaluator model:" line/i)
        end
      end
    end
  end

  describe 'Music Lab (all variants)' do
    variants(apps_root, 'music_lab', 'music_lab_*.mdsl').each do |path|
      context File.basename(path) do
        let(:content) { File.read(path) }

        it 'presents measured results exactly as the tool returned them' do
          expect(content).to match(/MEASURED results first, exactly as the tool returned them/i)
          expect(content).to match(/Do not round, alter, or "correct" these values/i)
        end

        it 'keeps theory commentary separate from measurements' do
          expect(content).to match(/clearly separate section/i)
          expect(content).to match(/must not restate them with different numbers/i)
        end
      end
    end
  end

  describe 'Research Assistant (all variants)' do
    variants(apps_root, 'research_assistant', 'research_assistant_*.mdsl').each do |path|
      context File.basename(path) do
        let(:content) { File.read(path) }

        it 'pins the Source Fidelity section' do
          expect(content).to match(/## Source Fidelity/i)
          expect(content).to match(/Do NOT upgrade a source's speculation into fact/i)
          expect(content).to match(/quoted must be quoted exactly/i)
        end
      end
    end
  end

  describe 'Video Describer' do
    let(:content) do
      File.read(File.join(apps_root, 'video_describer/video_describer_app.mdsl'))
    end

    it 'relays tool analysis without invented detail' do
      expect(content).to match(/Present the analysis faithfully/i)
      expect(content).to match(/do not add scenes, actions, or details it did not mention/i)
      expect(content).to match(/never paraphrase, "clean up", or fill gaps/i)
    end
  end
end
