/**
 * Fix for app selector and model-selected synchronization issues
 * 
 * Problem:
 * 1. When switching apps, #model-selected in menu panel doesn't update
 * 2. App selector with custom dropdown overlay doesn't reflect the change properly
 * 
 * Solution:
 * - Update app icon when app changes
 * - Trigger model change event to update model-selected display
 */

// File: docker/services/ruby/public/js/monadic/utilities.js
// Function: loadParams
// Section to modify: calledFor === "changeApp" condition

// ORIGINAL CODE (around line 666-671):
/*
} else if (calledFor === "changeApp") {
  let app_name = params["app_name"];
  $("#apps").val(app_name);
  $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
  $("#model").val(params["model"]);
}
*/

// PROPOSED FIX:
/*
} else if (calledFor === "changeApp") {
  let app_name = params["app_name"];
  $("#apps").val(app_name);
  $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
  $("#model").val(params["model"]);
  
  // Update the app icon for custom dropdown
  updateAppSelectIcon(app_name);
  
  // Trigger model change event to update model-selected display
  // Use setTimeout to ensure DOM is updated first
  setTimeout(function() {
    $("#model").trigger('change');
  }, 50);
}
*/

// Additional considerations:
// 1. The app uses a custom dropdown overlay (#app-select-overlay) with icon display (#app-select-icon)
// 2. The updateAppSelectIcon() function is already defined and handles icon updates
// 3. The #model change event handler (in monadic.js around line 360-394) already updates #model-selected
// 4. Using setTimeout ensures DOM updates complete before triggering the change event

// Testing checklist:
// [ ] Switch between different apps and verify #apps selector shows correct app
// [ ] Verify app icon updates in the custom dropdown
// [ ] Verify #model-selected in menu panel shows correct model
// [ ] Test with apps that have reasoning_effort parameter
// [ ] Test with apps that don't have reasoning_effort parameter
// [ ] Verify no JavaScript errors in console

// Alternative approach if the above doesn't work:
// Instead of triggering change event, directly update #model-selected:
/*
} else if (calledFor === "changeApp") {
  let app_name = params["app_name"];
  $("#apps").val(app_name);
  $(`#apps option[value="${params['app_name']}"]`).attr('selected', 'selected');
  $("#model").val(params["model"]);
  
  // Update the app icon for custom dropdown
  updateAppSelectIcon(app_name);
  
  // Directly update model-selected display
  const model = params["model"];
  const provider = params["llm_provider"];
  
  if (provider && model) {
    // Check if model has reasoning_effort
    if (window.modelSpec && window.modelSpec[model] && 
        window.modelSpec[model].hasOwnProperty("reasoning_effort")) {
      const reasoningEffort = $("#reasoning-effort").val() || 
                              params["reasoning_effort"] || 
                              "minimal";
      $("#model-selected").text(`${provider} (${model} - ${reasoningEffort})`);
    } else {
      $("#model-selected").text(`${provider} (${model})`);
    }
  }
}
*/

// Note: The direct update approach is more explicit but duplicates logic from
// the #model change handler. The trigger approach is cleaner but depends on
// the change event handler working correctly.