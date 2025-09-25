# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Mermaid Grapher (API smoke)', :api do
  include ProviderMatrixHelper

  it 'can produce a simple mermaid diagram text' do
    require_run_api!
    prompt = 'Create a simple mermaid flowchart with nodes A and B where A points to B. Output only the mermaid code starting with "graph TD".'
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        res = p.chat(prompt, app: 'Mermaid Grapher')
        assert_valid_text_response(res, min_len: 10)
        # Verify it contains some mermaid-like syntax
        text = res[:text] || res['text']
        expect(text).to match(/graph|flowchart|A|B|->|-->/i)
      end
    end
  end
end
