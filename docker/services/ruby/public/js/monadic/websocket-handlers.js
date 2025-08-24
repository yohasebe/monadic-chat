/**
 * WebSocket message handlers for Monadic Chat
 * 
 * This module contains extractable handler functions for different types of WebSocket messages.
 * These functions can be tested independently, making the codebase more maintainable.
 */

/**
 * Renders a thinking block with unified design across all providers
 * @param {string} thinkingContent - The thinking/reasoning content to display
 * @param {string} title - Optional custom title (defaults to "Thinking Process")
 * @returns {string} - HTML string for the thinking block
 */
function renderThinkingBlock(thinkingContent, title = null) {
  // Use translated title if not provided
  if (!title && typeof webUIi18n !== 'undefined') {
    title = webUIi18n.t('ui.messages.thinkingProcess');
  } else if (!title) {
    title = "Thinking Process";
  }
  const blockId = 'thinking-' + Math.random().toString(36).substr(2, 9);
  
  return `
    <div class="thinking-block" id="${blockId}">
      <div class="thinking-block-header" onclick="toggleThinkingBlock('${blockId}')">
        <div class="thinking-block-title">
          <i class="fas fa-chevron-right thinking-block-icon"></i>
          <i class="fas fa-brain"></i>
          <span>${title}</span>
        </div>
      </div>
      <div class="thinking-block-content">
        <pre>${escapeHtml(thinkingContent)}</pre>
      </div>
    </div>
  `;
}

/**
 * Toggles the visibility of a thinking block
 * @param {string} blockId - The ID of the thinking block to toggle
 */
function toggleThinkingBlock(blockId) {
  const block = document.getElementById(blockId);
  if (block) {
    block.classList.toggle('expanded');
  }
}

// Make toggleThinkingBlock globally accessible
window.toggleThinkingBlock = toggleThinkingBlock;

/**
 * Escapes HTML special characters to prevent XSS
 * @param {string} text - Text to escape
 * @returns {string} - Escaped text
 */
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

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
            // Create or clear the temp-card for streaming
            if (!$("#temp-card").length) {
              // Create a new temporary card for streaming text
              const tempCard = $(`
                <div id="temp-card" class="card mt-3 streaming-card"> 
                  <div class="card-header p-2 ps-3">
                    <span class="text-secondary"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>
                  </div>
                  <div class="card-body role-assistant">
                    <div class="card-text"></div>
                  </div>
                </div>
              `);
              $("#discourse").append(tempCard);
            } else if (data.fragment.start === true || data.fragment.is_first === true) {
              // If this is marked as the first fragment of a streaming response, clear the existing content
              $("#temp-card .card-text").empty();
            }
            
            // Add text to the temporary card
            const tempText = $("#temp-card .card-text");
            if (tempText.length) {
              // Use DocumentFragment for efficient DOM manipulation while preserving newlines
              const docFrag = document.createDocumentFragment();
              const lines = text.split('\n');
              
              lines.forEach((line, index) => {
                // Add line break for all lines except the first
                if (index > 0) {
                  docFrag.appendChild(document.createElement('br'));
                }
                // Add text node for each line (automatically escapes HTML)
                if (line) {
                  docFrag.appendChild(document.createTextNode(line));
                }
              });
              
              // Append all at once for better performance
              tempText[0].appendChild(docFrag);
            } else {
              // Basic fallback - append to some container if available
              const streamingContainer = document.getElementById('streaming-container');
              if (streamingContainer) {
                streamingContainer.textContent += text;
              }
            }
          }
        }
      }
      
      // Check if this is a Web Speech API message
      if (data.audio && data.audio.type === 'web_speech') {
        if (window.speechSynthesis && isAutoSpeech) {
          try {
            // Get text from data
            const text = data.audio.content || '';
            
            // Use the browser's Web Speech API directly
            const utterance = new SpeechSynthesisUtterance(text);
            
            // Get voice settings from UI
            const voiceElement = document.getElementById('webspeech-voice');
            if (voiceElement && voiceElement.value) {
              // Find the matching voice object
              const selectedVoice = window.speechSynthesis.getVoices().find(v => 
                v.name === voiceElement.value);
              
              if (selectedVoice) {
                utterance.voice = selectedVoice;
              }
            }
            
            // Get speed setting
            const speedElement = document.getElementById('tts-speed');
            if (speedElement && speedElement.value) {
              utterance.rate = parseFloat(speedElement.value) || 1.0;
            }
            
            // Speak the text
            window.speechSynthesis.speak(utterance);
          } catch (e) {
            console.error("Error using Web Speech API in fragment_with_audio:", e);
          }
        }
      }
      // Process regular audio data
      else if (data.audio && typeof processAudio === 'function') {
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
            
            // Add to audio queue instead of processing immediately
            const sequenceId = data.sequence_id || data.audio.sequence_id || Date.now().toString();
            const mimeType = data.audio.mime_type || null;
            
            if (typeof addToAudioQueue === 'function') {
              addToAudioQueue(audioData, sequenceId, mimeType);
            } else {
              // Fallback to direct processing if queue not available
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
    
    // Update status to "Ready for input" after token verification
    if (typeof setAlert === 'function') {
      const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
    }
    
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
    
    // Create error card with System header (same as system_info)
    // Use jQuery's text() method to properly escape the content
    const $errorDiv = $('<div class="error-message"><i class="fas fa-exclamation-circle"></i> </div>');
    
    // Handle both string and object error content
    let errorContent = data.content;
    if (typeof errorContent === 'object' && errorContent !== null) {
      // Extract error message from object
      errorContent = errorContent.message || errorContent.error || JSON.stringify(errorContent);
    }
    
    $errorDiv.append($('<span>').text(errorContent));
    
    const errorElement = createCard("system", 
      "<span class='text-success'><i class='fas fa-database'></i></span> <span class='fw-bold fs-6 text-success'>System</span>", 
      $errorDiv[0].outerHTML, 
      "en", 
      null, 
      true, 
      []
    );
    $("#discourse").append(errorElement);
    
    // Don't call setAlert here as we've already created the error card
    // This prevents duplicate error messages
    
    // Auto-scroll if enabled
    if (autoScroll) {
      const chatBottom = document.getElementById('chat-bottom');
      if (!isElementInViewport(chatBottom)) {
        chatBottom.scrollIntoView(false);
      }
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
      
      // Check if this is a finishing marker
      if (data.finished === true) {
        // This is just a marker, no audio to process
        return true;
      }
      
      // Add to audio queue if available
      const sequenceId = data.sequence_id || data.t_index || Date.now().toString();
      
      // Check if this is a segmented TTS playback
      if (data.is_segment) {
        // For segmented playback, use global audio queue to ensure proper sequencing
        if (typeof window.addToGlobalAudioQueue === 'function') {
          window.addToGlobalAudioQueue({
            data: audioData,
            sequenceId: sequenceId,
            segmentIndex: data.segment_index,
            totalSegments: data.total_segments,
            mimeType: data.mime_type // Pass MIME type if available
          });
        } else if (typeof addToAudioQueue === 'function') {
          addToAudioQueue(audioData, sequenceId, data.mime_type);
        } else if (typeof processAudio === 'function') {
          // Fallback to direct processing
          processAudio(audioData);
        }
      } else {
        // Normal audio processing
        if (typeof addToAudioQueue === 'function') {
          addToAudioQueue(audioData, sequenceId, data.mime_type);
        } else if (typeof processAudio === 'function') {
          // Fallback to direct processing
          processAudio(audioData);
        }
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
    // Hide the temp-card as we're about to show the final HTML
    $('#temp-card').hide();
    
    // Safely update messages array if it exists
    if (Array.isArray(messages)) {
      messages.push(data.content);
    }
    
    const html = data.content.html || '';
    let finalHtml = html;
    
    // Handle thinking content if present with unified design
    if (data.content.thinking) {
      const thinkingTitle = typeof webUIi18n !== 'undefined' ? 
        webUIi18n.t('ui.messages.thinkingProcess') : "Thinking Process";
      finalHtml = renderThinkingBlock(data.content.thinking, thinkingTitle) + html;
    } else if (data.content.reasoning_content) {
      const reasoningTitle = typeof webUIi18n !== 'undefined' ? 
        webUIi18n.t('ui.messages.reasoningProcess') : "Reasoning Process";
      finalHtml = renderThinkingBlock(data.content.reasoning_content, reasoningTitle) + html;
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
      
      // Check if we should hide spinner - hide if not calling function OR if streaming is complete
      if (!window.callingFunction || window.streamingResponse) {
        $('#monadic-spinner').hide();
        $('#cancel_query').hide();
        
        // Reset streaming flag
        if (window.streamingResponse) {
          window.streamingResponse = false;
        }
        
        // Clear the "Connected" status and show "Ready for input"
        if (typeof setAlert === 'function') {
          const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
        }
      } else {
        // Keep spinner visible but update message
        $('#monadic-spinner span').html('<i class="fas fa-cogs fa-pulse"></i> Processing tools');
      }
      
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
      const voiceMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.voiceRecognitionFinished') : 'Voice recognition finished';
      setAlert(`<i class="fa-solid fa-circle-check"></i> ${voiceMsg}`, 'secondary');
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
    $('#message').attr('placeholder', typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messagePlaceholder') : 'Type your message...');
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
    if (window.streamingResponse !== undefined) {
      window.streamingResponse = false;
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