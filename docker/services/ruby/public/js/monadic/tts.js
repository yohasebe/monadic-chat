// audio context
let audioCtx = null;
let playPromise = null;
let ttsAudio = null;

// Web Speech API voices storage
let webSpeechVoices = [];
let webSpeechInitialized = false;

// Create a lazy initializer for audioContext to prevent unnecessary contexts
function audioInit() {
  if (audioCtx === null) {
    // Create a new AudioContext only when needed
    audioCtx = new AudioContext();
    
    // For macOS specifically, add an event listener to close context when inactive
    const isMac = /Mac/.test(navigator.platform);
    if (isMac) {
      // Close audio context when window loses focus (important for macOS)
      window.addEventListener('blur', function() {
        if (audioCtx && audioCtx.state !== 'closed') {
          // Just suspend (don't close) in case we need it again soon
          audioCtx.suspend().catch(err => console.warn('Error suspending AudioContext:', err));
        }
      }, { passive: true });
    }
  }
  
  if (audioCtx.state === 'suspended') {
    audioCtx.resume().catch(err => console.warn('Error resuming AudioContext:', err));
  }
}

// Helper function to determine voice provider and quality
function getVoiceProvider(voice) {
  const isMac = /Mac/.test(navigator.platform);
  
  // Check for Microsoft and Google first (explicit in name)
  if (voice.name.includes('Microsoft')) return 'Microsoft';
  if (voice.name.includes('Google')) return 'Google';
  
  // Check for Apple voices on Mac
  if (isMac && voice.localService && 
      !voice.name.includes('Google') && !voice.name.includes('Microsoft')) {
    return 'Apple';
  }
  
  // Check voiceURI for Apple pattern
  if (voice.voiceURI && voice.voiceURI.includes('com.apple.speech')) {
    return 'Apple';
  }
  
  return 'Unknown';
}

// Helper to determine if a voice is high quality
function isHighQualityVoice(voice) {
  // Apply the same logic as in filterHighQualityVoices
  // This ensures consistency between checking and filtering
  const testVoices = [voice];
  const result = filterHighQualityVoices(testVoices);
  return result.length > 0;
}

// Filter for high-quality voices
function filterHighQualityVoices(voices) {
  // Only exclude the most problematic voices (novelty/effects voices)
  const lowQualityAppleVoices = [
    'Bad News', 'Bahh', 'Bells', 'Boing', 'Bubbles', 
    'Cellos', 'Deranged', 'Good News', 'Hysterical', 'Pipe Organ', 
    'Trinoids', 'Whisper', 'Zarvox'
  ];

  // Core list of typical high-quality voices available on most Macs
  const knownGoodVoices = [
    // English
    'Samantha', 'Alex', 'Daniel', 'Fred', 'Karen', 'Moira', 'Tessa', 'Veena',
    // Japanese
    'Kyoko', 'Otoya', 'O-ren',
    // Other languages
    'Mei-Jia', 'Sin-ji', 'Ting-Ting', 'Yuna', 'Thomas', 'Amelie', 'Anna'
  ];
  
  // Debug voice list if needed
  const debugVoices = false;
  if (debugVoices) {
    console.log("All available voices:");
    voices.forEach(v => console.log(`${v.name} [${v.lang}] - URI: ${v.voiceURI || 'N/A'}, Local: ${v.localService}`));
  }
  
  // Apply more permissive filtering
  return voices.filter(voice => {
    const provider = getVoiceProvider(voice);
    const name = voice.name || '';
    
    // Always include Microsoft and Google voices
    if (provider === 'Microsoft' || provider === 'Google') {
      return true;
    }
    
    // For Apple voices, apply more permissive filtering
    if (provider === 'Apple') {
      // Exclude only the most problematic voices (novelty/effects voices)
      if (lowQualityAppleVoices.some(lowQuality => 
          name.toLowerCase().includes(lowQuality.toLowerCase()))) {
        return false;
      }
      
      // Include any voice with premium/neural indicators
      if (name.toLowerCase().includes('premium') || 
          name.toLowerCase().includes('neural') ||
          name.toLowerCase().includes('siri') ||
          (voice.voiceURI && (
            voice.voiceURI.toLowerCase().includes('premium') ||
            voice.voiceURI.toLowerCase().includes('enhanced')
          ))) {
        return true;
      }
      
      // Include known good voices list
      if (knownGoodVoices.some(goodVoice => 
          name.toLowerCase().includes(goodVoice.toLowerCase()))) {
        return true;
      }
      
      // Include any standard voice that isn't marked as excluded
      // and has a reasonable name length
      if (name.length >= 3 && !name.match(/^(com\.|sys\.|_)/i)) {
        return true;
      }
      
      // Fall through - include most voices by default 
      return true;
    }
    
    // Include most provider voices
    return true;
  });
}

// Initialize Web Speech API
function initWebSpeech() {
  // Check if Web Speech API is available
  if (typeof window.speechSynthesis === 'undefined') {
    console.warn('Web Speech API is not supported in this browser');
    return false;
  }

  // Initialize only once
  if (webSpeechInitialized) return true;
  
  // Get available voices
  webSpeechVoices = window.speechSynthesis.getVoices();
  
  // In some browsers, getVoices() returns an empty array on first call
  // A voiceschanged event is fired when voices are available
  if (webSpeechVoices.length === 0) {
    window.speechSynthesis.addEventListener('voiceschanged', function() {
      webSpeechVoices = window.speechSynthesis.getVoices();
      populateWebSpeechVoices();
    });
  } else {
    populateWebSpeechVoices();
  }
  
  webSpeechInitialized = true;
  return true;
}

// Function to reset all audio-related variables when switching TTS modes
function resetAudioVariables() {
  console.debug("Resetting audio variables for TTS mode switch");
  
  // Stop any ongoing Web Speech API
  if (typeof window.speechSynthesis !== 'undefined') {
    try {
      window.speechSynthesis.cancel();
    } catch (e) {
      console.warn('Error stopping speech synthesis:', e);
    }
  }
  
  // Stop and cleanup ttsAudio
  if (ttsAudio) {
    try {
      ttsAudio.pause();
      if (ttsAudio.srcObject) {
        ttsAudio.srcObject = null;
      }
      ttsAudio.src = "";
      ttsAudio.load();
      ttsAudio = null;
    } catch (e) {
      console.warn('Error cleaning up ttsAudio:', e);
    }
  }
  
  // Stop and cleanup window.audio
  if (window.audio) {
    try {
      window.audio.pause();
      if (window.audio.srcObject) {
        window.audio.srcObject = null;
      }
      window.audio.src = "";
      window.audio.load();
    } catch (e) {
      console.warn('Error cleaning up window.audio:', e);
    }
  }
  
  // Clear audio data queue
  if (typeof audioDataQueue !== 'undefined') {
    audioDataQueue = [];
  }
  
  // Clear SourceBuffer
  if (typeof sourceBuffer !== 'undefined' && sourceBuffer) {
    try {
      if (typeof processAudioDataQueue === 'function') {
        sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
      }
      sourceBuffer = null;
    } catch (e) {
      console.warn('Error cleaning up sourceBuffer:', e);
    }
  }
  
  // Clear MediaSource
  if (typeof mediaSource !== 'undefined' && mediaSource) {
    try {
      if (mediaSource.readyState === 'open') {
        try {
          mediaSource.endOfStream();
        } catch (e) {
          console.warn('Error ending media source stream:', e);
        }
      }
      mediaSource = null;
    } catch (e) {
      console.warn('Error cleaning up mediaSource:', e);
    }
  }
  
  // For iOS-specific buffers
  if (typeof iosAudioBuffer !== 'undefined') {
    iosAudioBuffer = [];
  }
  if (typeof iosAudioQueue !== 'undefined') {
    iosAudioQueue = [];
  }
  if (typeof isIOSAudioPlaying !== 'undefined') {
    isIOSAudioPlaying = false;
  }
  if (typeof iosAudioElement !== 'undefined' && iosAudioElement) {
    try {
      iosAudioElement.pause();
      iosAudioElement.src = "";
      iosAudioElement.load();
      iosAudioElement = null;
    } catch (e) {
      console.warn('Error cleaning up iosAudioElement:', e);
    }
  }
  
  // Reset play promise
  playPromise = null;
  
  // For macOS specifically, properly manage AudioContext
  const isMac = /Mac/.test(navigator.platform);
  if (isMac && audioCtx && audioCtx.state !== 'closed') {
    // Suspend but don't close - we might need it again soon
    audioCtx.suspend().catch(err => console.warn('Error suspending AudioContext:', err));
  }
  
  // Hide any spinners
  $("#monadic-spinner").hide();
}

// Populate the Web Speech voices in the dropdown
function populateWebSpeechVoices() {
  const webSpeechSelect = $("#webspeech-voice");
  if (webSpeechSelect.length === 0) return;
  
  webSpeechSelect.empty();
  
  // Filter for high-quality voices
  const highQualityVoices = filterHighQualityVoices(webSpeechVoices);
  console.debug(`Found ${highQualityVoices.length} high-quality voices out of ${webSpeechVoices.length} total voices`);
  
  // Hide Web Speech option if no quality voices available
  const ttsProviderSelect = $("#tts-provider");
  const webspeechOption = ttsProviderSelect.find("option[value='webspeech']");
  
  if (highQualityVoices.length === 0) {
    // Hide the webspeech option if no quality voices available
    webspeechOption.hide();
    // If webspeech was selected, switch to another provider
    if (ttsProviderSelect.val() === "webspeech") {
      ttsProviderSelect.val("openai").trigger("change");
    }
    return;
  } else {
    // Show the webspeech option if quality voices are available
    webspeechOption.show();
  }
  
  // Group voices by language for better organization
  const voicesByLang = {};
  highQualityVoices.forEach(voice => {
    const lang = voice.lang || 'unknown';
    if (!voicesByLang[lang]) {
      voicesByLang[lang] = [];
    }
    voicesByLang[lang].push(voice);
  });
  
  // Sort languages alphabetically
  const sortedLangs = Object.keys(voicesByLang).sort();
  
  // Create language optgroups and add voices
  sortedLangs.forEach(lang => {
    // Create language group
    const languageGroup = $("<optgroup></optgroup>").attr("label", lang);
    
    // Sort voices by name within each language
    const sortedVoices = voicesByLang[lang].sort((a, b) => {
      return a.name.localeCompare(b.name);
    });
    
    // Add voices to this language group
    sortedVoices.forEach(voice => {
      // Get provider for display
      const provider = getVoiceProvider(voice);
      
      // Create a more informative label
      let qualityIndicator = "";
      
      // Add quality indicator if available
      if (voice.name.toLowerCase().includes('neural') || 
          voice.name.toLowerCase().includes('premium') ||
          (voice.voiceURI && (
            voice.voiceURI.includes('premium') || 
            voice.voiceURI.includes('enhanced')
          ))) {
        qualityIndicator = "★ ";  // Star for premium voices
      }
      
      const option = $("<option></option>")
        .val(voice.name) // Use voice name as value (more stable than index)
        .text(`${qualityIndicator}${voice.name} [${provider}]`)
        .attr("data-provider", provider)
        .attr("data-lang", voice.lang)
        .attr("data-index", webSpeechVoices.indexOf(voice)) // Store index as data attribute if needed
        .attr("title", `Voice: ${voice.name}\nProvider: ${provider}\nLanguage: ${voice.lang}`);
      
      // Mark default voice as selected or use saved voice
      if (window.savedWebspeechVoice && voice.name === window.savedWebspeechVoice) {
        option.prop('selected', true);
      } else if (voice.default && !window.savedWebspeechVoice) {
        option.prop('selected', true);
      }
      
      languageGroup.append(option);
    });
    
    webSpeechSelect.append(languageGroup);
  });
  
  // Try to select appropriate default voice if no default is set
  if (webSpeechSelect.find("option:selected").length === 0) {
    // Try to find a voice matching browser language
    const browserLang = navigator.language || 'en-US';
    let matchingOption = webSpeechSelect.find(`option[data-lang^="${browserLang.split('-')[0]}"]`).first();
    
    // If no match, default to English if available
    if (matchingOption.length === 0) {
      matchingOption = webSpeechSelect.find('option[data-lang^="en"]').first();
    }
    
    // Select the matching option
    if (matchingOption.length > 0) {
      matchingOption.prop('selected', true);
    }
  }
  
  // Add change event listener to save the selected voice in cookie
  webSpeechSelect.off('change').on('change', function() {
    const selectedVoice = $(this).val();
    if (selectedVoice && typeof setCookie === 'function') {
      setCookie('webspeech-voice', selectedVoice, 365); // Save for 1 year
      console.debug("Saved Web Speech voice to cookie:", selectedVoice);
    }
  });
}

// Speak text using Web Speech API
function speakWithWebSpeech(text, speed, callback) {
  // Check if Web Speech API is available
  if (typeof window.speechSynthesis === 'undefined') {
    console.error('Web Speech API is not supported in this browser');
    if (typeof callback === 'function') callback(false);
    // Hide spinner on error
    $("#monadic-spinner").hide();
    return false;
  }
  
  // Get filtered high-quality voices
  const highQualityVoices = filterHighQualityVoices(webSpeechVoices);
  
  // If no high-quality voices available, fallback to cloud providers
  if (highQualityVoices.length === 0) {
    console.warn('No high-quality Web Speech voices available, falling back to cloud provider');
    const ttsProviderSelect = $("#tts-provider");
    ttsProviderSelect.val("openai").trigger("change");
    if (typeof callback === 'function') callback(false);
    // Hide spinner on error
    $("#monadic-spinner").hide();
    return false;
  }
  
  // Cancel any previous speech
  window.speechSynthesis.cancel();
  
  // Create a new utterance
  const utterance = new SpeechSynthesisUtterance(text);
  
  // Set voice if selected
  const voiceSelect = $("#webspeech-voice");
  if (voiceSelect.length > 0) {
    const voiceValue = voiceSelect.val();
    
    // Try to find the voice by name
    const selectedVoice = webSpeechVoices.find(v => v.name === voiceValue);
    
    if (selectedVoice) {
      utterance.voice = selectedVoice;
      
      // Log provider information for debugging
      const provider = getVoiceProvider(utterance.voice);
      console.debug(`Using ${provider} voice: ${utterance.voice.name}`);
    } else {
      // Fallback to index-based method (for backward compatibility)
      const voiceIndex = parseInt(voiceValue, 10);
      if (!isNaN(voiceIndex) && webSpeechVoices.length > voiceIndex) {
        utterance.voice = webSpeechVoices[voiceIndex];
        
        // Log provider information for debugging
        const provider = getVoiceProvider(utterance.voice);
        console.debug(`Using ${provider} voice by index: ${utterance.voice.name}`);
      }
    }
  }
  
  // Set speech rate (speed)
  utterance.rate = speed;
  
  // Set event handlers
  utterance.onend = function() {
    // Hide spinner when speech ends
    $("#monadic-spinner").hide();
    // Reset spinner to default state for other operations
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-comment fa-pulse"></i> Starting');
    
    if (typeof callback === 'function') callback(true);
  };
  
  utterance.onerror = function(event) {
    console.error('SpeechSynthesis error:', event);
    // Hide spinner on error
    $("#monadic-spinner").hide();
    // Reset spinner to default state
    $("#monadic-spinner")
      .find("span")
      .html('<i class="fas fa-comment fa-pulse"></i> Starting');
    
    if (typeof callback === 'function') callback(false);
  };
  
  // Start speaking
  window.speechSynthesis.speak(utterance);
  return true;
}

function ttsSpeak(text, stream, callback) {
  // Get settings from UI
  const provider = $("#tts-provider").val();
  const speed = parseFloat($("#tts-speed").val());

  // Early returns for invalid conditions
  if (!text) {
    return false;
  }
  
  // Use Web Speech API for webspeech provider
  if (provider === "webspeech") {
    // Initialize Web Speech API if not already initialized
    if (!webSpeechInitialized) {
      initWebSpeech();
    }
    
    // Double-check that high-quality voices are available
    const highQualityVoices = filterHighQualityVoices(webSpeechVoices);
    if (highQualityVoices.length === 0) {
      console.warn("No high-quality voices available. Falling back to cloud TTS.");
      // Auto-switch to cloud provider
      $("#tts-provider").val("openai").trigger("change");
      // Use new provider
      return ttsSpeak(text, stream, callback);
    }
    
    return speakWithWebSpeech(text, speed, callback);
  }
  
  // Firefox check only for traditional TTS methods
  if (runningOnFirefox) {
    return false;
  }
  
  // For traditional TTS providers (OpenAI, ElevenLabs)
  const voice = $("#tts-voice").val();
  const elevenlabs_voice = $("#elevenlabs-tts-voice").val();
  
  // Determine mode based on streaming flag
  let mode = stream ? "TTS_STREAM" : "TTS";
  let response_format = "mp3";

  // Initialize audio
  audioInit();

  // Prepare voice data for sending
  const voiceData = {
    provider: provider,
    message: mode,
    text: text,
    voice: voice,
    elevenlabs_voice: elevenlabs_voice,
    response_format: response_format
  };

  // Add speed if it is defined and it is not 1.0
  if (speed && speed !== 1.0) {
    voiceData.speed = speed;
  }

  // Send the request to the server
  ws.send(JSON.stringify(voiceData));

  // Create audio element if it doesn't exist
  if (!ttsAudio && window.audio) {
    ttsAudio = window.audio;
  } else if (!ttsAudio) {
    ttsAudio = new Audio();
  }
  
  // Start playback (safely)
  try {
    if (ttsAudio && ttsAudio.play) {
      const playPromise = ttsAudio.play();
      if (playPromise !== undefined) {
        playPromise.catch(() => {});
      }
    }
  } catch (e) {
    // Silently handle errors
  }
  
  // Call the callback if provided
  if (typeof callback === 'function') {
    callback(true);
  }
}

function ttsStop() {
  // Stop Web Speech API if active
  if (typeof window.speechSynthesis !== 'undefined') {
    try {
      window.speechSynthesis.cancel();
    } catch (e) {
      console.warn('Error stopping speech synthesis:', e);
    }
  }

  // Handle both ttsAudio and window.audio with a single function
  const stopAudioElement = (audio) => {
    if (audio) {
      try {
        audio.pause();
        
        // Cancel any queued audio tasks
        if (audio.srcObject) {
          audio.srcObject = null;
        }
        
        // Remove all event listeners
        audio.oncanplay = null;
        audio.onplay = null;
        audio.onended = null;
        audio.onerror = null;
        
        // Clear source and reload to free resources
        audio.src = "";
        audio.load();
      } catch (e) {
        console.warn('Error stopping audio element:', e);
      }
    }
  };
  
  // Stop both audio elements
  stopAudioElement(ttsAudio);
  stopAudioElement(window.audio);

  // Reset the audio queue if available
  if (typeof audioDataQueue !== 'undefined') {
    audioDataQueue = [];
  }

  // Clean up MediaSource and SourceBuffer
  try {
    if (typeof sourceBuffer !== 'undefined' && sourceBuffer) {
      if (typeof processAudioDataQueue === 'function') {
        sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
      }
      sourceBuffer = null;
    }

    if (typeof mediaSource !== 'undefined' && mediaSource) {
      // Properly close MediaSource if possible
      if (mediaSource.readyState === 'open') {
        try {
          mediaSource.endOfStream();
        } catch (e) {
          console.warn('Error ending media source stream:', e);
        }
      }
      
      mediaSource = null;
      
      // Create a new MediaSource if possible
      if (typeof MediaSource !== 'undefined') {
        mediaSource = new MediaSource();
        mediaSource.addEventListener('sourceopen', () => {
          try {
            sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
            if (typeof processAudioDataQueue === 'function') {
              sourceBuffer.addEventListener('updateend', processAudioDataQueue);
            }
          } catch (e) {
            console.warn('Error creating source buffer:', e);
          }
        });

        // Create a new audio element for playback
        ttsAudio = new Audio();
        ttsAudio.src = URL.createObjectURL(mediaSource);
        ttsAudio.load();
      } else {
        // For browsers without MediaSource support (like iOS Safari)
        ttsAudio = new Audio();
      }
    }
    
    // For macOS specifically, properly manage AudioContext
    const isMac = /Mac/.test(navigator.platform);
    if (isMac && audioCtx && audioCtx.state !== 'closed') {
      // Suspend but don't close - we might need it again soon
      audioCtx.suspend().catch(err => console.warn('Error suspending AudioContext:', err));
    }
    
  } catch (e) {
    console.warn('Error in ttsStop:', e);
    // Fallback
    ttsAudio = new Audio();
  }
  
  // Clear any pending audio promises
  playPromise = null;
}

// Export functions to window for browser environment
window.audioInit = audioInit;
window.ttsSpeak = ttsSpeak;
window.ttsStop = ttsStop;
window.initWebSpeech = initWebSpeech;
window.populateWebSpeechVoices = populateWebSpeechVoices;
window.resetAudioVariables = resetAudioVariables;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    audioInit,
    ttsSpeak,
    ttsStop,
    initWebSpeech,
    populateWebSpeechVoices,
    resetAudioVariables
  };
}
