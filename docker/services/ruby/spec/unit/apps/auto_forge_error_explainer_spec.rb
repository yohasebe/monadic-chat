# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/auto_forge/agents/error_explainer'

RSpec.describe AutoForge::Agents::ErrorExplainer do
  subject(:explainer) { described_class.new }

  describe '#explain_errors' do
    it 'returns a user-friendly explanation for known errors' do
      debug_result = {
        javascript_errors: [{ 'message' => 'undefined is not a function' }]
      }

      explanations = explainer.explain_errors(debug_result)

      expect(explanations.length).to eq(1)
      expect(explanations.first[:title]).to eq('Function not found')
      expect(explanations.first[:severity]).to eq(:high)
    end

    it 'falls back to a default explanation for unknown errors' do
      debug_result = {
        javascript_errors: [{ 'message' => 'Unexpected custom error' }]
      }

      explanations = explainer.explain_errors(debug_result)

      expect(explanations.length).to eq(1)
      expect(explanations.first[:title]).to eq('Technical error')
      expect(explanations.first[:severity]).to eq(:medium)
    end
  end
end
