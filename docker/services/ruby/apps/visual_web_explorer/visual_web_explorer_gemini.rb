require_relative "visual_web_explorer_tools"
require "base64"

class VisualWebExplorerGemini < MonadicApp
  include GeminiHelper
  include VisualWebExplorerTools
end