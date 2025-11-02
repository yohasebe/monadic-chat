# frozen_string_literal: true

require_relative 'auto_forge'
require_relative 'auto_forge_tools'
require_relative '../../lib/monadic/adapters/vendors/openai_helper'
require_relative '../../lib/monadic/agents/openai_code_agent'

class AutoForgeOpenAI < MonadicApp
  include OpenAIHelper
  include AutoForge
  include AutoForgeTools
  include Monadic::Agents::OpenAICodeAgent

  def generate_application(spec:)
    super(spec: spec, agent: :openai)
  end
end
