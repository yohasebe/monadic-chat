require_relative "visual_web_explorer_tools"
require "base64"

class VisualWebExplorerOpenAI < MonadicApp
  include OpenAIHelper
  include VisualWebExplorerTools
end