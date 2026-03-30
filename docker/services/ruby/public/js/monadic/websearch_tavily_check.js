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
  const websearchEl = document.getElementById("websearch");
  const websearchBadge = document.getElementById("websearch-badge");
  const modelEl = document.getElementById("model");
  const model = modelEl ? modelEl.value : '';

  if (!websearchEl || !websearchBadge) return;

  // First check if model has tool capability
  const supportsWeb = modelSpec[model] && (modelSpec[model]["supports_web_search"] === true || modelSpec[model]["tool_capability"] === true);
  if (!supportsWeb) {
    // Model doesn't support tools at all
    websearchEl.disabled = true;
    websearchBadge.style.display = "none";
    const tt = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchModelDisabled') : 'Model does not support Web Search';
    websearchEl.title = tt;
    return;
  }

  // Model supports tools, now check Tavily requirement
  if (requiresTavilyAPI(provider) && !hasTavilyKey) {
    // Provider needs Tavily but key is missing
    websearchEl.checked = false;
    websearchEl.disabled = true;
    websearchBadge.style.display = "none";
    const tt = (typeof webUIi18n !== 'undefined') ? webUIi18n.t('ui.webSearchNeedsTavily') : 'Web Search requires a Tavily API key';
    websearchEl.title = tt;
  } else {
    // Either doesn't need Tavily or has the key
    websearchEl.disabled = false;
    websearchEl.removeAttribute("title");

    // Update badge visibility based on checked state
    websearchBadge.style.display = websearchEl.checked ? "" : "none";
  }
}

// Export for use in other modules
window.websearchTavilyCheck = {
  requiresTavilyAPI,
  updateWebSearchState
};
