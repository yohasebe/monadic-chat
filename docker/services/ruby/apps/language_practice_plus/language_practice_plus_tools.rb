# Facade methods for Language Practice Plus app
# Web search functionality is now provided by WebSearchTools shared module

class LanguagePracticePlusOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MonadicSharedTools::WebSearchTools
end