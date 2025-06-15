require_relative "visual_web_explorer_tools"
require "base64"

class VisualWebExplorerClaude < MonadicApp
  include ClaudeHelper
  include VisualWebExplorerTools
end