# frozen_string_literal: true

# Helper for accessing providerDefaults in tests.
# Usage: default_model_for("openai", "chat") => "gpt-5.4"
require_relative '../../lib/monadic/utils/model_spec'

module ProviderDefaultsHelper
  def default_model_for(provider, category = "chat")
    Monadic::Utils::ModelSpec.get_provider_default(provider, category)
  end

  def default_models_for(provider, category = "chat")
    Monadic::Utils::ModelSpec.get_provider_models(provider, category)
  end
end

RSpec.configure do |config|
  config.include ProviderDefaultsHelper
end
