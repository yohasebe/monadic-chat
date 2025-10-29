# Mail Composer application class definitions

class MailComposerClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

class MailComposerPerplexity < MonadicApp
  include PerplexityHelper if defined?(PerplexityHelper)
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end
