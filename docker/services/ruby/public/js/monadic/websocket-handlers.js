/**
 * WebSocket message handlers for Monadic Chat
 * 
 * This module contains extractable handler functions for different types of WebSocket messages.
 * These functions can be tested independently, making the codebase more maintainable.
 */

/**
 * Handles combined fragment with audio messages (optimized for auto_speech)
 * @param {Object} data - Parsed message data containing fragment and audio
 * @param {Function} processAudio - Function to process audio data
 * @returns {boolean} - Whether the message was handled
 */
function handleFragmentWithAudio(data, processAudio) {
  if (data && data.type === 'fragment_with_audio') {
    try {
      // Check for auto_speech flag
      const isAutoSpeech = data.auto_speech === true;
      // First process the fragment part
      if (data.fragment) {
        // Add fragment to DOM or update UI as needed
        if (typeof window.handleFragmentMessage === 'function') {
          window.handleFragmentMessage(data.fragment);
        } else {
          // Fallback direct processing if global handler not available
          if (data.fragment.type === 'fragment') {
            const text = data.fragment.content || '';
            if (typeof window.updateStreamingText === 'function') {
              window.updateStreamingText(text);
            } else {
              // Basic fallback - append to some container
              const streamingContainer = document.getElementById('streaming-container');
              if (streamingContainer) {
                streamingContainer.textContent += text;
              }
            }
          }
        }
      }
      
      // Then process the audio part
      if (data.audio && typeof processAudio === 'function') {
        // The audio processing might vary between environments
        try {
          // Extract audio content
          if (data.audio.content && typeof data.audio.content === 'string') {
            const audioData = Uint8Array.from(atob(data.audio.content), c => c.charCodeAt(0));
            
            // Set flag to ensure audio auto-play is triggered
            window.autoPlayAudio = true;
            
            // Set auto-speech flag if present in original message
            if (isAutoSpeech) {
              window.autoSpeechActive = true;
            }
            
            // Process the audio data
            processAudio(audioData);
            
            // Immediately ensure audio is playing on standard browsers
            if (!window.firefoxAudioMode && !window.basicAudioMode && window.audio) {
              if (window.audio.paused) {
                window.audio.play().catch(err => console.log("Error auto-playing audio:", err));
              }
            }
            
            // For iOS devices, ensure auto-playback
            if (window.isIOS && !window.isIOSAudioPlaying && window.iosAudioElement) {
              window.iosAudioElement.play().catch(err => console.log("Error auto-playing iOS audio:", err));
            }
          }
        } catch (audioError) {
          console.error('Error processing audio in combined message:', audioError);
        }
      }
      
      return true;
    } catch (e) {
      console.error('Error handling fragment_with_audio message:', e);
      return false;
    }
  }
  return false;
}

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
    // First enable all basic controls
    $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
    $('#message').show();
    $('#message').prop('disabled', false);
    $('#monadic-spinner').hide();
    
    // Special handling for AI User errors (critical for Perplexity)
    const isAIUserError = data.content && data.content.toString().includes("AI User error");
    if (isAIUserError) {
      // Explicitly re-enable the AI User button 
      $('#ai_user').prop('disabled', false);
    }
    
    // Show error message
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
      finalHtml = `<div data-title='Thinking Block' class='toggle'><span class="toggle-text">Show thinking details</span><div class='toggle-open'>${data.content.thinking}</div></div>${html}`;
    } else if (data.content.reasoning_content) {
      finalHtml = `<div data-title='Thinking Block' class='toggle'><span class="toggle-text">Show reasoning process</span><div class='toggle-open'>${data.content.reasoning_content}</div></div>${html}`;
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
 * Handles sample message success confirmations
 * @param {Object} data - Parsed message data
 * @returns {boolean} - Whether the message was handled
 */
function handleSampleSuccess(data) {
  if (data && data.type === 'sample_success') {
    // Clear any pending timeout to prevent error message
    if (window.currentSampleTimeout) {
      clearTimeout(window.currentSampleTimeout);
      window.currentSampleTimeout = null;
    }
    
    // Hide UI elements
    $("#monadic-spinner").hide();
    $('#cancel_query').hide();
    
    // Show success alert
    const roleText = data.role === "user" ? "User" : 
                    data.role === "assistant" ? "Assistant" : "System";
    
    if (typeof setAlert === 'function') {
      setAlert(`<i class='fas fa-check-circle'></i> Sample ${roleText} message added`, "success");
    }
    
    return true;
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
    
    // Make sure amplitude chart is hidden
    $('#amplitude').hide();
    
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
    // More comprehensive UI reset to ensure all elements are properly enabled
    // Reset input field state
    $('#message').attr('placeholder', 'Type your message...');
    $('#message').prop('disabled', false);
    
    // Re-enable all controls - include AI user button explicitly
    $('#send, #clear, #image-file, #voice, #doc, #url, #ai_user').prop('disabled', false);
    $('#select-role').prop('disabled', false);
    $('#ai_user_provider').prop('disabled', false);
    
    // Hide cancel button
    $('#cancel_query').hide();
    
    // Show message input and hide spinner
    $('#message').show();
    $('#monadic-spinner').hide();
    
    // Reset any flags that might be in an inconsistent state
    if (window.responseStarted !== undefined) {
      window.responseStarted = false;
    }
    if (window.callingFunction !== undefined) {
      window.callingFunction = false;
    }
    
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
  handleFragmentWithAudio,
  handleTokenVerification,
  handleErrorMessage,
  handleAudioMessage,
  handleHtmlMessage,
  handleSampleSuccess,
  handleSTTMessage,
  handleCancelMessage
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.wsHandlers;
}