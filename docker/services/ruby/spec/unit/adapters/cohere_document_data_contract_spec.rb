# frozen_string_literal: true

require 'spec_helper'

# Cohere v2 requires the tool-result `document.data` to be a JSON STRING, not a
# raw Hash. Sending a Hash made the model fail to register tool results and
# re-call the same tool in a loop on multi-turn flows. This source-level guard
# pins the contract so the fix cannot silently regress.
RSpec.describe 'Cohere tool-result document.data contract' do
  let(:source) do
    File.read(File.join(__dir__, '../../../lib/monadic/adapters/vendors/cohere_helper.rb'))
  end

  it 'builds document.data via JSON.generate (a JSON string, per v2 spec)' do
    expect(source).to match(/"data"\s*=>\s*JSON\.generate\(/)
  end

  it 'does NOT pass a raw Hash as document.data (regression guard)' do
    expect(source).not_to match(/"data"\s*=>\s*\{\s*"results"/)
  end
end
