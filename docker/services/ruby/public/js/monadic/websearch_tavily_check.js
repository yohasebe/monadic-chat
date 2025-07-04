// Check if Tavily API is required for web search based on provider
// This module handles disabling websearch for providers that need Tavily API when it's not available

const tavilyRequiredProviders = ['deepseek', 'mistral', 'cohere', 'ollama'];

// Providers with native web search (don't need Tavily)
const nativeWebSearchProviders = ['openai', 'perplexity', 'grok', 'xai', 'gemini', 'google', 'claude', 'anthropic'];

// Check if current provider requires Tavily API
function requiresTavilyAPI(provider) {
  if (!provider) return false;
  const providerLower = provider.toLowerCase();
  
  // Check if it's a native web search provider
  for (const nativeProvider of nativeWebSearchProviders) {
    if (providerLower.includes(nativeProvider)) {
      return false;
    }
  }
  
  // Check if it requires Tavily
  for (const tavilyProvider of tavilyRequiredProviders) {
    if (providerLower.includes(tavilyProvider)) {
      return true;
    }
  }
  
  // Default to not requiring Tavily (OpenAI default)
  return false;
}

// Update websearch UI state based on provider and Tavily API availability
function updateWebSearchState(provider, hasTavilyKey) {
  const websearchElement = $("#websearch");
  const websearchBadge = $("#websearch-badge");
  const model = $("#model").val();
  
  // First check if model has tool capability
  if (!modelSpec[model] || !modelSpec[model].hasOwnProperty("tool_capability") || !modelSpec[model]["tool_capability"]) {
    // Model doesn't support tools at all
    websearchElement.prop("disabled", true);
    websearchBadge.hide();
    return;
  }
  
  // Model supports tools, now check Tavily requirement
  if (requiresTavilyAPI(provider) && !hasTavilyKey) {
    // Provider needs Tavily but key is missing
    websearchElement.prop("checked", false);  // Turn off
    websearchElement.prop("disabled", true);   // Disable
    websearchBadge.hide();
    
    // Add tooltip to explain why it's disabled
    websearchElement.attr("title", "Web search requires Tavily API key for " + provider);
  } else {
    // Either doesn't need Tavily or has the key
    websearchElement.prop("disabled", false);
    websearchElement.removeAttr("title");
    
    // Update badge visibility based on checked state
    if (websearchElement.is(":checked")) {
      websearchBadge.show();
    } else {
      websearchBadge.hide();
    }
  }
}

// Export for use in other modules
window.websearchTavilyCheck = {
  requiresTavilyAPI,
  updateWebSearchState
};