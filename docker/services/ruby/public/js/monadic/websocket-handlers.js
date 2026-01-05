/**
 * WebSocket message handlers for Monadic Chat
 * 
 * This module contains extractable handler functions for different types of WebSocket messages.
 * These functions can be tested independently, making the codebase more maintainable.
 */

/**
 * Renders a thinking block with unified design across all providers
 * Uses Bootstrap card style matching the temp-reasoning-card for consistency
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

  // Use Bootstrap card style with subtle, blended design
  return `
    <div class="card mt-3 thinking-block" id="${blockId}">
      <div class="card-header p-2 ps-3 thinking-block-header" onclick="toggleThinkingBlock('${blockId}')" style="cursor: pointer;">
        <div class="fs-6 card-title mb-0 text-muted d-flex align-items-center">
          <i class="fas fa-chevron-right thinking-block-icon me-2"></i>
          <i class="fas fa-brain me-2"></i>
          <span>${title}</span>
        </div>
      </div>
      <div class="card-body thinking-block-content" style="max-height: 0; overflow: hidden; padding: 0; transition: max-height 0.3s ease-out, padding 0.3s ease-out;">
        <div class="card-text">${escapeHtml(thinkingContent).replace(/\n/g, '<br>')}</div>
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
  if (!block) return;

  const content = block.querySelector('.thinking-block-content');
  if (!content) return;

  const isExpanding = !block.classList.contains('expanded');

  if (isExpanding) {
    // Measure actual content height before expanding (with padding)
    content.style.maxHeight = 'none';
    content.style.overflow = 'visible';
    content.style.padding = '1rem';  // Bootstrap card-body default padding
    const actualHeight = content.scrollHeight;
    content.style.maxHeight = '0';
    content.style.overflow = 'hidden';
    content.style.padding = '0';

    // Force reflow
    content.offsetHeight;

    // Apply actual height for smooth animation
    block.classList.add('expanded');
    content.style.maxHeight = actualHeight + 'px';
    content.style.padding = '1rem';

    // Remove inline max-height after animation completes
    setTimeout(() => {
      if (block.classList.contains('expanded')) {
        content.style.maxHeight = 'none';
      }
    }, 500);
  } else {
    // Collapsing: set current height first
    const currentHeight = content.scrollHeight;
    content.style.maxHeight = currentHeight + 'px';

    // Force reflow
    content.offsetHeight;

    // Then collapse to 0
    block.classList.remove('expanded');
    content.style.maxHeight = '0';
    content.style.padding = '0';
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
      const inForeground = typeof window !== 'undefined' && typeof window.isForegroundTab === 'function' ? window.isForegroundTab() : !(typeof document !== 'undefined' && document.hidden);
      // Check for auto_speech flag
      const isAutoSpeech = data.auto_speech === true;
      const suppressionActive = (typeof window !== 'undefined') &&
        typeof window.isAutoSpeechSuppressed === 'function' &&
        window.isAutoSpeechSuppressed();

      // First process the fragment part
      if (data.fragment) {
        if (!inForeground) {
          // Skip streaming fragment rendering in background tabs
        } else if (typeof window.handleFragmentMessage === 'function') {
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
                  <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
                    <div class="fs-5 card-title mb-0">
                      <span class="card-role-icon"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>
                    </div>
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
        if (!inForeground) {
          return true;
        }
        if (suppressionActive) {
          if (window.speechSynthesis) {
            try {
              window.speechSynthesis.cancel();
            } catch (cancelErr) {
              console.warn('[Auto TTS] Failed to cancel Web Speech synthesis during suppression:', cancelErr);
            }
          }
          return true;
        }

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
        if (!inForeground) {
          return true;
        }
        // The audio processing might vary between environments
        try {
          if (suppressionActive) {
            // Ensure any queued audio is cleared so playback cannot start later
            if (typeof clearAudioQueue === 'function') {
              clearAudioQueue();
            }
            if (typeof window.resetAudioVariables === 'function') {
              window.resetAudioVariables();
            }
            window.autoSpeechActive = false;
            window.autoPlayAudio = false;
            return true;
          }

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
                  window.audio.play().catch(err => console.error("Error auto-playing audio:", err));
                }
              }
              
              // For iOS devices, ensure auto-playback
              if (window.isIOS && !window.isIOSAudioPlaying && window.iosAudioElement) {
                window.iosAudioElement.play().catch(err => console.error("Error auto-playing iOS audio:", err));
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
    
    // Don't show "Ready for input" immediately after token verification
    // The actual ready state will be set when processing is complete
    // Keep showing the current processing status (e.g., "Verifying token")
    
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

    // On error, set both flags to true to ensure spinner hides
    if (typeof window.setTextResponseCompleted === 'function') {
      window.setTextResponseCompleted(true);
    }
    if (typeof window.setTtsPlaybackStarted === 'function') {
      window.setTtsPlaybackStarted(true);
    }
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      $('#monadic-spinner').hide();
    }
    
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
// Track processed audio messages to prevent duplicates
const processedAudioIds = new Set();
const MAX_PROCESSED_IDS = 100; // Limit size to prevent memory issues

function handleAudioMessage(data, processAudio) {
  if (data && data.type === 'audio') {
    try {
      if (typeof window.isForegroundTab === 'function' && !window.isForegroundTab()) {
        return true;
      }
      // Check if this is a finishing marker (no audio to process)
      if (data.finished === true) {
        return true;
      }

      // Check if content is a valid string
      if (typeof data.content !== 'string') {
        // Non-string content is unexpected - log error but return true to prevent fallback
        // Returning true indicates "handled" (skipped) to avoid duplicate processing in fallback
        console.error('[handleAudioMessage] Invalid content format:', typeof data.content);
        return true;
      }

      // Empty string content is valid for finished markers, skip silently
      if (data.content === '') {
        return true;
      }

      // Generate unique ID for this audio message to prevent duplicate processing
      const audioId = data.sequence_id || data.t_index ||
                      (data.content ? data.content.substring(0, 50) : Date.now().toString());

      // Check if we've already processed this exact audio
      if (processedAudioIds.has(audioId)) {
        console.debug('[handleAudioMessage] Skipping duplicate audio:', audioId);
        return true;
      }

      // Mark as processed
      processedAudioIds.add(audioId);

      // Clean up old IDs to prevent memory bloat
      if (processedAudioIds.size > MAX_PROCESSED_IDS) {
        const idsArray = Array.from(processedAudioIds);
        for (let i = 0; i < idsArray.length - MAX_PROCESSED_IDS / 2; i++) {
          processedAudioIds.delete(idsArray[i]);
        }
      }

      // Process audio data
      const audioData = Uint8Array.from(atob(data.content), c => c.charCodeAt(0));

      // Skip if decoded data is empty
      if (!audioData || audioData.length === 0) {
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
 * @param {Function} createCardFunc - Function to create UI cards
 * @returns {boolean} - Whether the message was handled
 */
function handleHtmlMessage(data, createCardFunc) {
  if (data && data.type === 'html' && data.content) {
    // Check if more content is coming (tool calls in progress)
    const moreComing = data.more_coming === true;

    // Note: We do NOT hide temp-card here. Instead, we remove it AFTER creating the final card.
    // This ensures the user sees streaming content until the final card replaces it.

    // Note: Message is already added to window.messages via SessionState.addMessage
    // in websocket.js before this handler is called - no need to push here

    // Phase 2: Use MarkdownRenderer if html field is missing
    let html;
    if (data.content.html) {
      html = data.content.html;
    } else if (data.content.text) {
      // Client-side rendering with MarkdownRenderer
      html = window.MarkdownRenderer ?
        window.MarkdownRenderer.render(data.content.text, { appName: data.content.app_name }) :
        data.content.text;
    } else {
      console.error("Message has neither html nor text field:", data.content);
      html = "";
    }
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
        // Calculate turn number based on existing assistant cards + 1 (excluding temp-card)
        const turnNumber = $('#discourse .card:not(#temp-card) .role-assistant').length + 1;
        createCardFunc('assistant',
                     '<span class="text-secondary"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>',
                     finalHtml,
                     data.content.lang,
                     data.content.mid,
                     true,
                     [],  // images
                     turnNumber);

        // Remove temp-card AFTER the final card is created
        // This ensures smooth transition from streaming display to final card
        // (moreComing block will create a new temp-card if needed)
        $('#temp-card').remove();
      }

      // Note: Auto TTS highlighting is handled in processSequentialAudio()
      // when the first audio segment arrives, not here during card creation

      // UI Updates
      $('#message').show();
      $('#message').val('');
      $('#message').prop('disabled', false);
      $('#send, #clear, #image-file, #voice, #doc, #url').prop('disabled', false);
      $('#select-role').prop('disabled', false);
      
      // Check if we should hide spinner - hide if not calling function OR if streaming is complete
      if (!window.callingFunction || window.streamingResponse) {
        // Mark text response as completed and check if we can hide spinner
        if (typeof window.setTextResponseCompleted === 'function') {
          window.setTextResponseCompleted(true);
        }
        if (typeof window.checkAndHideSpinner === 'function') {
          window.checkAndHideSpinner();
        } else {
          // Fallback if function not available
          $('#monadic-spinner').hide();
        }
        $('#cancel_query').hide();
        
        // Reset streaming flag
        if (window.streamingResponse) {
          window.streamingResponse = false;
        }
        
        // Clear the "Connected" status and show "Ready for input"
        // Only update if system is not busy
        if (typeof setAlert === 'function' && typeof window.isSystemBusy === 'function' && !window.isSystemBusy()) {
          const readyMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.readyForInput') : 'Ready for input';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${readyMsg}`, "success");
        }
      } else {
        // Keep spinner visible but update message
        $('#monadic-spinner span').html('<i class="fas fa-cogs fa-pulse"></i> Processing tools');
      }

      // If more content is coming (tool calls in progress), prepare for next streaming
      console.log('[handleHtmlMessage] moreComing:', moreComing, 'data.more_coming:', data.more_coming);
      if (moreComing) {
        console.log('[handleHtmlMessage] Preparing temp-card for next streaming');
        // Reset streaming state for next response
        window.callingFunction = true;
        window.streamingResponse = true;
        window.responseStarted = false;
        if (window.UIState) {
          window.UIState.set('streamingResponse', true);
          window.UIState.set('isStreaming', true);
        }

        // Reset fragment tracking to accept new fragments
        window._lastProcessedSequence = -1;
        window._lastProcessedIndex = -1;

        // Remove any existing temp-card to avoid duplicates
        $('#temp-card').remove();

        // Create new temp-card for next streaming
        const tempCard = $(`
          <div id="temp-card" class="card mt-3 streaming-card">
            <div class="card-header p-2 ps-3 d-flex justify-content-between align-items-center">
              <div class="fs-5 card-title mb-0">
                <span class="card-role-icon"><i class="fas fa-robot"></i></span> <span class="fw-bold fs-6 assistant-color">Assistant</span>
              </div>
            </div>
            <div class="card-body role-assistant">
              <div class="card-text"></div>
            </div>
          </div>
        `);
        $('#discourse').append(tempCard);
        tempCard.show();
        console.log('[handleHtmlMessage] temp-card created and shown, length:', $('#temp-card').length);

        // Show processing indicator
        const processingToolsText = typeof webUIi18n !== 'undefined'
          ? webUIi18n.t('ui.messages.spinnerProcessingTools')
          : 'Processing tools';
        $('#monadic-spinner span').html(`<i class="fas fa-cogs fa-pulse"></i> ${processingToolsText}`);
        $('#monadic-spinner').show();
        document.getElementById('cancel_query').style.setProperty('display', 'flex', 'important');
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
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      $("#monadic-spinner").hide();
    }
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
    // Use checkAndHideSpinner to respect Auto Speech mode
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      $('#monadic-spinner').hide();
    }
    
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
    // Use checkAndHideSpinner to respect Auto Speech mode
    if (typeof window.checkAndHideSpinner === 'function') {
      window.checkAndHideSpinner();
    } else {
      $('#monadic-spinner').hide();
    }
    
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

// Helper function to clear processed audio IDs (call when starting new TTS)
function clearProcessedAudioIds() {
  if (typeof processedAudioIds !== 'undefined') {
    processedAudioIds.clear();
  }
}

// Check if an audio ID has already been processed
function isAudioProcessed(audioId) {
  if (typeof processedAudioIds !== 'undefined') {
    return processedAudioIds.has(audioId);
  }
  return false;
}

// Mark an audio ID as processed
function markAudioProcessed(audioId) {
  if (typeof processedAudioIds !== 'undefined') {
    processedAudioIds.add(audioId);
    // Clean up old IDs to prevent memory bloat
    if (processedAudioIds.size > MAX_PROCESSED_IDS) {
      const idsArray = Array.from(processedAudioIds);
      for (let i = 0; i < idsArray.length - MAX_PROCESSED_IDS / 2; i++) {
        processedAudioIds.delete(idsArray[i]);
      }
    }
  }
}

function canPlayAudioInForeground() {
  return typeof window.isForegroundTab === "function" ? window.isForegroundTab() : !(typeof document !== "undefined" && document.hidden);
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
  handleCancelMessage,
  clearProcessedAudioIds,
  isAudioProcessed,
  markAudioProcessed
};

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.wsHandlers;
}
