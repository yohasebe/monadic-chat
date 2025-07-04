// Patch for utilities.js to support Tavily API check
// This file updates the doResetActions function to check Tavily API availability

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
window.doResetActions = function() {
  // Store the current app selection before reset
  const currentApp = $("#apps").val();

  $("#message").css("height", "96px").val("");

  ws.send(JSON.stringify({ "message": "RESET" }));
  ws.send(JSON.stringify({ "message": "LOAD" }));

  currentPdfData = null;
  resetParams();

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
        updateWebSearchBasic(model);
      });
  } else {
    // Fallback if websearchTavilyCheck is not available
    updateWebSearchBasic(model);
  }

  // Continue with the rest of the original function
  if (modelSpec[model] && modelSpec[model].hasOwnProperty("reasoning_effort")) {
    $("#model-selected").text(provider + " (" + model + " - " + $("#reasoning-effort").val() + ")");
  } else {
    $("#model-selected").text(provider + " (" + model + ")");
  }

  $("#resetConfirmation").modal("hide");
  $("#main-panel").hide();
  $("#discourse").html("").hide();
  $("#chat").html("")
  $("#temp-card").hide();
  $("#config").show();
  $("#back-to-settings").hide();
  $("#parameter-panel").hide();
  setAlert("<i class='fa-solid fa-circle-check'></i> Reset successful.", "success");
  
  // Set app selection back to current app instead of default
  $("#apps").val(currentApp);
  
  // Update lastApp to match the current app to prevent app change dialog from appearing
  lastApp = currentApp;
  
  $("#base-app-title").text(apps[currentApp]["display_name"] || apps[currentApp]["app_name"]);

  if (apps[currentApp]["monadic"]) {
    $("#monadic-badge").show();
  } else {
    $("#monadic-badge").hide();
  }

  if (apps[currentApp]["tools"]) {
    $("#tools-badge").show();
  } else {
    $("#tools-badge").hide();
  }

  if (apps[currentApp]["mathjax"]) {
    $("#math-badge").show();
  } else {
    $("#math-badge").hide();
  }

  $("#base-app-icon").html(apps[currentApp]["icon"]);
  $("#base-app-desc").html(apps[currentApp]["description"]);

  $("#model_and_file").show();
  $("#model_parameters").show();

  $("#image-file").show();

  $("#initial-prompt-toggle").prop("checked", false).trigger("change");
  $("#ai-user-initial-prompt-toggle").prop("checked", false).trigger("change");
};

// Basic websearch update without Tavily check
window.updateWebSearchBasic = function(model) {
  if (modelSpec[model] && modelSpec[model].hasOwnProperty("tool_capability") && modelSpec[model]["tool_capability"]) {
    $("#websearch").prop("disabled", false);
    if ($("#websearch").is(":checked")) {
      $("#websearch-badge").show();
    } else {
      $("#websearch-badge").hide();
    }
  } else {
    $("#websearch").prop("disabled", true);
    $("#websearch-badge").hide();
  }
};

// Also update when app changes
$(document).on('change', '#apps', function() {
  const currentApp = $(this).val();
  if (apps[currentApp]) {
    let provider = "OpenAI";
    if (apps[currentApp].group) {
      provider = window.getProviderFromGroup ? window.getProviderFromGroup(apps[currentApp].group) : window.getProviderFromGroupLocal(apps[currentApp].group);
    }
    
    // Check Tavily API when app changes
    if (window.websearchTavilyCheck) {
      fetch('/api/environment')
        .then(response => response.json())
        .then(data => {
          window.websearchTavilyCheck.updateWebSearchState(provider, data.has_tavily_key);
        })
        .catch(err => {
          console.error('Failed to fetch environment settings:', err);
        });
    }
  }
});