/**
 * WebSocket message handlers for Monadic Chat
 * 
 * This module contains extractable handler functions for different types of WebSocket messages.
 * These functions can be tested independently, making the codebase more maintainable.
 */

/**
 * Handles token verification messages
 * @param {Object} data - Parsed message data
 * @returns {boolean} - Whether the message was handled
 */
function handleTokenVerification(data) {
  if (data && data.type === 'token_verified') {
    $('#api-token').val(data.token);
    $('#ai-user-initial-prompt').val(data.ai_user_initial_prompt);
    return true;
  }
  return false;
}

/**
 * Handles error messages
 * @param {Object} data - Parsed message data
 * @returns {boolean} - Whether the message was handled
 */
function handleErrorMessage(data) {
  if (data && data.type === 'error') {
    $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
    $('#message').show();
    $('#message').prop('disabled', false);
    $('#monadic-spinner').hide();
    if (typeof setAlert === 'function') {
      setAlert(data.content, 'error');
    }
    return true;
  }
  return false;
}

/**
 * Handles audio messages
 * @param {Object} data - Parsed message data
 * @param {Function} processAudio - Function to process audio data
 * @returns {boolean} - Whether the message was handled
 */
function handleAudioMessage(data, processAudio) {
  if (data && data.type === 'audio') {
    $('#monadic-spinner').hide();
    
    try {
      // Check if content is a valid string
      if (typeof data.content !== 'string') {
        throw new Error('Invalid audio content format');
      }
      
      // Process audio data
      const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));
      
      // If a processing function is provided, call it
      if (typeof processAudio === 'function') {
        processAudio(audioData);
      }
      
      return true;
    } catch (e) {
      console.error('Error processing audio:', e);
      return false;
    }
  }
  return false;
}

/**
 * Handles HTML messages (assistant responses)
 * @param {Object} data - Parsed message data
 * @param {Array} messages - The messages array to update
 * @param {Function} createCardFunc - Function to create UI cards
 * @returns {boolean} - Whether the message was handled
 */
function handleHtmlMessage(data, messages, createCardFunc) {
  if (data && data.type === 'html' && data.content) {
    // Safely update messages array if it exists
    if (Array.isArray(messages)) {
      messages.push(data.content);
    }
    
    const html = data.content.html || '';
    let finalHtml = html;
    
    // Handle thinking content if present
    if (data.content.thinking) {
      finalHtml = `<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>${data.content.thinking}</div></div>${html}`;
    } else if (data.content.reasoning_content) {
      finalHtml = `<div data-title='Thinking Block' class='toggle'><div class='toggle-open'>${data.content.reasoning_content}</div></div>${html}`;
    }
    
    if (data.content.role === 'assistant') {
      // Create card if function is provided
      if (typeof createCardFunc === 'function') {
        createCardFunc('assistant', 
                     '<span class="text-secondary"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>', 
                     finalHtml, 
                     data.content.lang, 
                     data.content.mid, 
                     true);
      }
      
      // UI Updates
      $('#message').show();
      $('#message').val('');
      $('#message').prop('disabled', false);
      $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
      $('#select-role').prop('disabled', false);
      $('#monadic-spinner').hide();
      $('#cancel_query').hide();
      return true;
    }
    return false;
  }
  return false;
}

/**
 * Handles speech-to-text (STT) messages
 * @param {Object} data - Parsed message data
 * @returns {boolean} - Whether the message was handled
 */
function handleSTTMessage(data) {
  if (data && data.type === 'stt') {
    // Update message input with transcribed text
    $('#message').val($('#message').val() + ' ' + data.content);
    
    // Update p-value display if logprob is available
    if (data.logprob !== undefined) {
      $('#asr-p-value').text('Last Speech-to-Text p-value: ' + data.logprob);
    }
    
    // Re-enable controls
    $('#send, #clear, #voice').prop('disabled', false);
    
    // Hide the spinner now that speech recognition is complete
    $('#monadic-spinner').hide();
    
    // Auto submit if enabled
    if ($('#check-easy-submit').is(':checked')) {
      $('#send').click();
    }
    
    // Show success alert if function is available
    if (typeof setAlert === 'function') {
      setAlert('<i class="fa-solid fa-circle-check"></i> Voice recognition finished', 'secondary');
    }
    
    // Set focus back to input field if function is available
    if (typeof setInputFocus === 'function') {
      setInputFocus();
    }
    
    return true;
  }
  return false;
}

/**
 * Handles cancel messages
 * @param {Object} data - Parsed message data
 * @returns {boolean} - Whether the message was handled
 */
function handleCancelMessage(data) {
  if (data && data.type === 'cancel') {
    // Reset input field state
    $('#message').attr('placeholder', 'Type your message...');
    $('#message').prop('disabled', false);
    
    // Re-enable all controls
    $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
    $('#select-role').prop('disabled', false);
    
    // Hide cancel button
    $('#cancel_query').hide();
    
    // Show message input and hide spinner
    $('#message').show();
    $('#monadic-spinner').hide();
    
    // Set focus back to input field if function is available
    if (typeof setInputFocus === 'function') {
      setInputFocus();
    }
    
    return true;
  }
  return false;
}

// Export handlers for browser environments
window.wsHandlers = {
  handleTokenVerification,
  handleErrorMessage,
  handleAudioMessage,
  handleHtmlMessage,
  handleSTTMessage,
  handleCancelMessage
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.wsHandlers;
}