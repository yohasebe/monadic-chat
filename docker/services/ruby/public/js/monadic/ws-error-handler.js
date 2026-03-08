/**
 * WebSocket Error Handler for Monadic Chat
 *
 * Handles error and cancellation WebSocket messages:
 * - error: Process error messages, reset UI state, handle AI User errors
 * - cancel: Handle operation cancellation, clean up UI
 *
 * Extracted from websocket.js to reduce the size of connect_websocket().
 */
(function() {
'use strict';

/**
 * Handle "error" WebSocket message.
 * Resets all streaming state, translates error messages, and restores UI.
 * @param {Object} data - Message data with content (string or object with key/details)
 */
function handleError(data) {
  // Clear any pending spinner check interval on error
  if (window.spinnerCheckInterval) {
    clearInterval(window.spinnerCheckInterval);
    window.spinnerCheckInterval = null;
  }

  // Reset streaming flags
  window.streamingResponse = false;
  if (window.UIState) {
    window.UIState.set('streamingResponse', false);
    window.UIState.set('isStreaming', false);
  }
  window.responseStarted = false;
  window.callingFunction = false;

  // Check if content is a translation key or an object with key and details
  let errorContent = data.content;

  // Handle various error message formats
  if (typeof errorContent === 'object' && errorContent.key) {
    // Handle structured error with key and details
    if (errorContent.key === 'ai_user_error') {
      errorContent = `${getTranslation('ui.messages.aiUserError', 'AI User error')}: ${errorContent.details}`;
    }
  } else if (typeof errorContent === 'string') {
    // Map translation keys to translated messages
    const errorTranslations = {
      'ai_user_requires_conversation': 'ui.messages.aiUserRequiresConversation',
      'message_not_found_for_editing': 'ui.messages.messageNotFoundForEditing',
      'voice_input_empty': 'ui.messages.voiceInputEmpty',
      'text_input_empty': 'ui.messages.textInputEmpty',
      'invalid_message_format': 'ui.messages.invalidMessageFormat',
      'api_stopped_safety': 'ui.messages.apiStoppedSafety',
      'something_went_wrong': 'ui.messages.somethingWentWrong',
      'error_processing_sample': 'ui.messages.errorProcessingSample',
      'content_not_found': 'ui.messages.contentNotFound',
      'empty_response': 'ui.messages.emptyResponse'
    };

    if (errorTranslations[errorContent]) {
      const fallbacks = {
        'ai_user_requires_conversation': 'AI User requires an existing conversation. Please start a conversation first.',
        'message_not_found_for_editing': 'Message not found for editing',
        'voice_input_empty': 'Voice input is empty',
        'text_input_empty': 'The text input is empty',
        'invalid_message_format': 'Invalid message format received',
        'api_stopped_safety': 'The API stopped responding because of safety reasons',
        'something_went_wrong': 'Something went wrong',
        'error_processing_sample': 'Error processing sample message',
        'content_not_found': 'Content not found in response',
        'empty_response': 'Empty response from API'
      };
      errorContent = getTranslation(errorTranslations[errorContent], fallbacks[errorContent] || errorContent);
    }
  }

  // Check if error during AI User generation
  const isAIUserError = errorContent && errorContent.toString().includes(getTranslation('ui.messages.aiUserError', 'AI User error'));

  // Use the handler if available, otherwise use inline code
  let handled = false;
  const wsHandlers = window.wsHandlers;
  if (wsHandlers && typeof wsHandlers.handleErrorMessage === 'function') {
    const translatedData = { ...data, content: errorContent };
    handled = wsHandlers.handleErrorMessage(translatedData);
  } else {
    // Fallback to inline handling
    $("#send, #clear, #image-file, #voice, #doc, #url, #pdf-import, #ai_user").prop("disabled", false);
    $("#message").show();
    $("#message").prop("disabled", false);
    $("#monadic-spinner").hide();
    setAlert(errorContent, 'error');
    handled = true;
  }

  // Additional UI operations
  if (handled) {
    $("#select-role").prop("disabled", false);

    // Only update status-message if system is not busy
    if (!isSystemBusy()) {
      $("#status-message").html(getTranslation('ui.messages.inputMessage', 'Input a message.'));
    }

    // Reset UI panels and indicators
    clearToolStatus();
    $("#temp-card").hide();
    $("#indicator").hide();
    $("#user-panel").show();
    document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');

    // For AI User errors, don't delete messages but re-enable the AI User button
    if (isAIUserError) {
      $("#ai_user").prop("disabled", false);
      updateAIUserButtonState(window.messages);
    } else {
      // For non-AI User errors, remove user message that caused error
      const lastCard = $("#discourse .card").last();
      if (lastCard.find(".user-color").length !== 0) {
        deleteMessage(lastCard.attr('id'));
      }

      // Restore the message content so user can edit and retry
      const params = window.params || {};
      $("#message").val(params["message"]);
    }

    // Notify Workflow Viewer of error state
    if (typeof WorkflowViewer !== 'undefined' && WorkflowViewer.setStage) {
      WorkflowViewer.setStage('error');
    }

    // Reset response tracking flags to ensure clean state
    window.responseStarted = false;
    window.callingFunction = false;
    window.streamingResponse = false;
    if (window.UIState) {
      window.UIState.set('streamingResponse', false);
      window.UIState.set('isStreaming', false);
    }

    // Set focus back to input field
    setInputFocus();
  }
}

/**
 * Handle "cancel" WebSocket message.
 * Cleans up temporary messages, re-enables UI elements, shows cancellation alert.
 * @param {Object} data - Message data (unused in inline handling)
 */
function handleCancel(data) {
  // Use the handler if available
  let handled = false;
  const wsHandlers = window.wsHandlers;
  if (wsHandlers && typeof wsHandlers.handleCancelMessage === 'function') {
    handled = wsHandlers.handleCancelMessage(data);
  }

  if (!handled) {
    const messages = window.messages || [];

    // Remove temporary message if it exists
    const tempMessageIndex = messages.findIndex(msg => msg.temp === true);
    if (tempMessageIndex !== -1) {
      window.SessionState.removeMessage(tempMessageIndex);
    }

    // Remove any UI cards that may have been created during initial message
    if (messages.length === 0) {
      $("#discourse").empty();
    }

    // Don't clear the message so users can edit and resubmit
    $("#message").attr("placeholder", typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : "Type your message...");
    $("#message").prop("disabled", false);

    // Re-enable all the UI elements
    $("#send").prop("disabled", false);
    $("#clear").prop("disabled", false);
    $("#image-file").prop("disabled", false);
    $("#voice").prop("disabled", false);
    $("#doc").prop("disabled", false);
    $("#url").prop("disabled", false);
    $("#ai_user").prop("disabled", false);
    $("#select-role").prop("disabled", false);

    $("#status-message").html(getTranslation('ui.messages.inputMessage', 'Input a message.'));
    document.getElementById('cancel_query').style.setProperty('display', 'none', 'important');

    // Hide loading indicators
    clearToolStatus();
    $("#temp-card").hide();
    $("#indicator").hide();

    // Show message input and hide spinner
    $("#message").show();
    $("#monadic-spinner").css("display", "none");

    // Update AI User button state
    updateAIUserButtonState(messages);

    // Show canceled message
    const operationCanceledText = getTranslation('ui.messages.operationCanceled', 'Operation canceled');
    setAlert(`<i class='fa-solid fa-ban' style='color: #FF7F07;'></i> ${operationCanceledText}`, "warning");

    setInputFocus();
  }
}

// Export for browser environment
window.WsErrorHandler = {
  handleError,
  handleCancel
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.WsErrorHandler;
}
})();
