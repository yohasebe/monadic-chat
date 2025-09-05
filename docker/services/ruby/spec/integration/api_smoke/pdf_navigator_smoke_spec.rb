# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'PDF Navigator (API smoke)', :api do
  include ProviderMatrixHelper

  it 'summarizes short text as if extracted from a PDF' do
    require_run_api!
    text = 'Monadic Chat provides a local AI framework with Docker-backed tools.'
    prompt = "Summarize in one short sentence: #{text}"
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'PDF Navigator')
        expect(res[:text]).to be_a(String)
        expect(res[:text]).not_to be_empty
      end
    end
  end
end
