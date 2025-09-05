# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Monadic Mode (context carry, API smoke)', :api do
  include ProviderMatrixHelper

  it 'maintains simple context across two turns' do
    require_run_api!
    providers_from_env.each do |prov|
      with_provider(prov) do |p|
        msgs = [
          { role: 'user', content: 'My name is Alex. Remember it.' },
          { role: 'user', content: 'What is my name? Answer with one word.' }
        ]
        res = p.chat_messages(msgs, app: 'Monadic Mode')
        expect(res[:text]).to be_a(String)
        expect(res[:text].length).to be > 0
      end
    end
  end
end
