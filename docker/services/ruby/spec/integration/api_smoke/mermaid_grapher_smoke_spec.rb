# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Mermaid Grapher (API smoke)', :api do
  include ProviderMatrixHelper

  it 'can produce a simple mermaid diagram text' do
    require_run_api!
    prompt = 'Output a mermaid graph code block for A->B as "graph TD; A-->B;". Do not add explanation.'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Mermaid Grapher')
        assert_valid_text_response(res)
      end
    end
  end
end
