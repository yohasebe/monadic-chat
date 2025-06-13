require_relative "web_viewport_capturer_tools"

class WebViewportCapturerGrok < MonadicApp
  include GrokHelper
  include WebViewportCapturerTools
end