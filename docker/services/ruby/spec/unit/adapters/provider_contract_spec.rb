# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/provider_contract_examples'

# Contract tests pinning invariants that already hold across all 8 chat
# provider helpers. These guard the shared surface (constants, entry-point
# signatures, module identity) without imposing any unified abstraction —
# provider-specific behavior stays in each vendor's own spec under
# spec/unit/adapters/vendors/.
#
# No HTTP/API calls are made: the assertions are structural (constants,
# method signatures, respond_to), so this spec runs without API keys.
RSpec.describe "Chat provider contracts" do
  [
    [OpenAIHelper,   "OpenAI",    1, "https://"],
    [ClaudeHelper,   "Anthropic", 2, "https://"],
    [GeminiHelper,   "Google",    1, "https://"],
    [GrokHelper,     "xAI",       1, "https://"],
    [CohereHelper,   "Cohere",    1, "https://"],
    [DeepSeekHelper, "DeepSeek",  1, "https://"],
    [MistralHelper,  "Mistral",   1, "https://"],
    [OllamaHelper,   "Ollama",    2, "http://"]
  ].each do |mod, name, delay, prefix|
    context name do
      let(:vendor_module) { mod }
      let(:vendor_name) { name }
      let(:retry_delay) { delay }
      let(:endpoint_prefix) { prefix }

      it_behaves_like "a chat provider helper"
    end
  end
end
