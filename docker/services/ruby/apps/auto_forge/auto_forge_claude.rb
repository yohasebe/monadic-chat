# frozen_string_literal: true

require_relative 'auto_forge'
require_relative 'auto_forge_tools'
require_relative '../../lib/monadic/adapters/vendors/claude_helper'
require_relative '../../lib/monadic/agents/claude_opus_agent'

class AutoForgeClaude < MonadicApp
  include ClaudeHelper
  include AutoForge
  include AutoForgeTools

  def generate_application(spec:)
    super(spec: spec, agent: :claude)
  end
end
