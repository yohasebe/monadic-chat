# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/provider_matrix_helper'

RSpec.describe 'Image Generation (API media)', :api, :media do
  include ProviderMatrixHelper

  it 'generates a tiny image (provider-specific)' do
    require_run_media!
    prompt = 'a small yellow square icon'
    
    # Filter to only image-capable providers
    image_providers = providers_from_env.select do |prov|
      %w[openai gemini xai].include?(prov)
    end
    
    if image_providers.empty?
      skip "No image generation providers available in current configuration"
      return
    end
    
    image_providers.each do |prov|
      with_provider(prov) do |p|
        res = p.image_generate_api(prompt, size: '256x256')
        if res.is_a?(Hash) && res[:bytes]
          expect(res[:bytes].bytesize).to be > 0
        elsif res.is_a?(Hash) && res[:url]
          expect(res[:url]).to match(%r{^https?://})
        else
          raise "Unexpected response: #{res.inspect}"
        end
      end
    end
  end
end
