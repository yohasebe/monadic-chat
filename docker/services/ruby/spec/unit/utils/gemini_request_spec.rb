# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/gemini_request'

RSpec.describe Monadic::Utils::GeminiRequest do
  it 'disables storage at the top level without changing content or generation settings' do
    body = { 'contents' => [{ 'parts' => [{ 'text' => 'Hello' }] }],
             'generationConfig' => { 'temperature' => 0.3 } }
    expect(described_class.without_storage(body)).to eq(body.merge('store' => false))
    expect(body).not_to have_key('store')
    expect(body['generationConfig']).not_to have_key('store')
  end

  it 'overrides an explicit request to store content' do
    expect(described_class.without_storage('store' => true, contents: []))
      .to eq('store' => false, contents: [])
  end
end
