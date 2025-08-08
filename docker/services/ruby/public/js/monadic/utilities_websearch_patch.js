// Patch for utilities.js to support Tavily API check
// This file extends the doResetActions function to check Tavily API availability
// Uses minimal override approach - calls original function and adds extra functionality

// Store original doResetActions if it exists
if (typeof window.originalDoResetActions === 'undefined' && typeof doResetActions !== 'undefined') {
  window.originalDoResetActions = doResetActions;
}

// Helper function for provider detection (if not already defined)
if (typeof getProviderFromGroupLocal === 'undefined') {
  window.getProviderFromGroupLocal = function(group) {
    if (!group) return "OpenAI";
    
    const groupLower = group.toLowerCase();
    if (groupLower.includes("anthropic") || groupLower.includes("claude")) {
      return "Anthropic";
    } else if (groupLower.includes("gemini") || groupLower.includes("google")) {
      return "Google";
    } else if (groupLower.includes("cohere")) {
      return "Cohere";
    } else if (groupLower.includes("mistral")) {
      return "Mistral";
    } else if (groupLower.includes("perplexity")) {
      return "Perplexity";
    } else if (groupLower.includes("deepseek")) {
      return "DeepSeek";
    } else if (groupLower.includes("grok") || groupLower.includes("xai")) {
      return "xAI";
    } else if (groupLower.includes("ollama")) {
      return "Ollama";
    } else {
      return "OpenAI";
    }
  };
}

// Override doResetActions to include Tavily check
// This now calls the original function and adds extra functionality
window.doResetActions = function() {
  // Call the original function if it exists
  if (window.originalDoResetActions) {
    window.originalDoResetActions.call(this);
  }
  
  // Additional functionality: Check Tavily API availability
  const currentApp = $("#apps").val();
  const model = $("#model").val();
  
  // Extract provider from app_name parameter
  let provider = "OpenAI";
  if (apps[currentApp] && apps[currentApp].group) {
    provider = window.getProviderFromGroup ? window.getProviderFromGroup(apps[currentApp].group) : window.getProviderFromGroupLocal(apps[currentApp].group);
  }

  // Check Tavily API availability and update websearch state
  if (window.websearchTavilyCheck) {
    // Fetch environment settings to check Tavily key
    fetch('/api/environment')
      .then(response => response.json())
      .then(data => {
        window.websearchTavilyCheck.updateWebSearchState(provider, data.has_tavily_key);
      })
      .catch(err => {
        console.error('Failed to fetch environment settings:', err);
        // Fallback to basic check
        if (typeof updateWebSearchBasic === 'function') {
          updateWebSearchBasic(model);
        }
      });
  } else {
    // Fallback if websearchTavilyCheck is not available
    if (typeof updateWebSearchBasic === 'function') {
      updateWebSearchBasic(model);
    }
  }
  
  // Update model display with reasoning effort if applicable
  if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
    $("#model-selected").text(provider + " (" + model + " - " + $("#reasoning-effort").val() + ")");
  } else {
    $("#model-selected").text(provider + " (" + model + ")");
  }
  
  // Update base app title
  $("#base-app-title").text(apps[currentApp]["display_name"] || apps[currentApp]["app_name"]);
  
  // Show/hide monadic badge
  if (apps[currentApp]["monadic"]) {
    $("#monadic-badge").show();
  } else {
    $("#monadic-badge").hide();
  }
};