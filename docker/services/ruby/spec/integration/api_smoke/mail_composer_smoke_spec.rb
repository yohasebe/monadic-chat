# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Mail Composer (API smoke)', :api do
  include ProviderMatrixHelper

  it 'drafts a one-sentence professional email' do
    require_run_api!
    prompt = 'Draft a single-sentence professional email to thank for a meeting.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Mail Composer')
        expect(res[:text]).to be_a(String)
        expect(res[:text].length).to be > 10
      end
    end
  end
end
