# frozen_string_literal: true

require_relative 'auto_forge'
require_relative 'auto_forge_tools'
require_relative '../../lib/monadic/adapters/vendors/grok_helper'
require_relative '../../lib/monadic/agents/grok_code_agent'

class AutoForgeGrok < MonadicApp
  include GrokHelper
  include AutoForge
  include AutoForgeTools
  include Monadic::Agents::GrokCodeAgent

  def generate_application(spec:)
    super(spec: spec, agent: :grok)
  end
end
