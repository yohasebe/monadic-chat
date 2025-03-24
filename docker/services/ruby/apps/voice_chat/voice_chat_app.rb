module VoiceChat
  # include WebSearchAgent
end

class VoiceChatOpenAI < MonadicApp
  include VoiceChat
end

class VoiceChatClaude < MonadicApp
  include VoiceChat
end

class VoiceChatGemini < MonadicApp
  include VoiceChat
end

class VoiceChatCohere < MonadicApp
  include VoiceChat
end

class VoiceChatMistral < MonadicApp
  include VoiceChat
end

class VoiceChatGrok < MonadicApp
  include VoiceChat
end

class VoiceChatDeepSeek < MonadicApp
  include VoiceChat
end

class VoiceChatPerplexity < MonadicApp
  include VoiceChat
end
