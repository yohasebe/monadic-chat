require_relative "visual_web_explorer_tools"
require "base64"

class VisualWebExplorerGrok < MonadicApp
  include GrokHelper
  include VisualWebExplorerTools
end