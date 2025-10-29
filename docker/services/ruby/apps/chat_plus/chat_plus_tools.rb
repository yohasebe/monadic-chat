# Chat Plus application tools for shared folder operations

# Module containing the shared folder operation tools
# Now uses shared implementation from MonadicSharedTools::FileOperations
module ChatPlusTools
  include MonadicHelper
  include MonadicSharedTools::FileOperations
end

# Class definitions for Chat Plus apps
# These must come AFTER the module definition

# Chat Plus apps with file operations
class ChatPlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include ChatPlusTools
end

class ChatPlusClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include ChatPlusTools
end

class ChatPlusGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include ChatPlusTools
end

class ChatPlusGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include ChatPlusTools
end

class ChatPlusMistral < MonadicApp
  include MistralHelper if defined?(MistralHelper)
  include ChatPlusTools
end

class ChatPlusDeepSeek < MonadicApp
  include DeepSeekHelper if defined?(DeepSeekHelper)
  include ChatPlusTools
end

class ChatPlusCohere < MonadicApp
  include CohereHelper if defined?(CohereHelper)
  include ChatPlusTools
end

class ChatPlusPerplexity < MonadicApp
  include PerplexityHelper if defined?(PerplexityHelper)
  include ChatPlusTools
end

class ChatPlusOllama < MonadicApp
  include OllamaHelper if defined?(OllamaHelper)
  include ChatPlusTools
end