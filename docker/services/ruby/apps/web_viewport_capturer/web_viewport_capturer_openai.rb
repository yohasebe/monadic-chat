require_relative "web_viewport_capturer_tools"

class WebViewportCapturerOpenAI < MonadicApp
  include OpenAIHelper
  include WebViewportCapturerTools
end