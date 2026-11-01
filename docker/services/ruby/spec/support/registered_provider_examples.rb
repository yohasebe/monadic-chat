# frozen_string_literal: true

require_relative '../../lib/monadic/dsl/provider_config'

module RegisteredChatProviders
  def self.helpers
    MonadicDSL::ProviderConfig::PROVIDER_INFO.values.map { |config| config.fetch(:helper_module) }
  end
end

RSpec.shared_examples 'coverage of registered chat providers' do |helpers|
  it 'covers exactly the registered chat providers' do
    expect(helpers).to match_array(RegisteredChatProviders.helpers)
  end
end
