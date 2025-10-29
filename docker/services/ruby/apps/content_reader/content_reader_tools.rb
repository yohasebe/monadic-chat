# Content Reader application class definitions

class ContentReaderOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end
