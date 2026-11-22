# frozen_string_literal: true

require_relative 'auto_forge'
require_relative 'auto_forge_tools'
require_relative '../../lib/monadic/adapters/vendors/claude_helper'
require_relative '../../lib/monadic/agents/claude_code_agent'

class AutoForgeClaude < MonadicApp
  include ClaudeHelper
  include AutoForge
  include AutoForgeTools
  include Monadic::Agents::ClaudeCodeAgent

  # The code agent of this app's provider, for everything it generates.
  def forge_agent
    :claude
  end

  def generate_application(spec:)
    super(spec: spec, agent: forge_agent)
  end
end
