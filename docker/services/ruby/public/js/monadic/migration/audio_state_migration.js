// Audio State Migration
// Centralizes audio playback, TTS, and voice recording state management

(function() {
  'use strict';
  
  // Check if migration is enabled
  if (!window.MigrationConfig || !window.MigrationConfig.features.audio) {
    console.log('[AudioStateMigration] Not enabled');
    return;
  }
  
  console.log('[AudioStateMigration] Starting audio state migration');
  
  // Backup original audio variables for rollback
  if (window.RollbackManager) {
    window.RollbackManager.backupValue('globalAudioQueue', window.globalAudioQueue);
    window.RollbackManager.backupValue('isProcessingAudioQueue', window.isProcessingAudioQueue);
    window.RollbackManager.backupValue('currentAudioSequenceId', window.currentAudioSequenceId);
    window.RollbackManager.backupValue('currentSegmentAudio', window.currentSegmentAudio);
    window.RollbackManager.backupValue('currentPCMSource', window.currentPCMSource);
    window.RollbackManager.backupValue('iosAudioBuffer', window.iosAudioBuffer);
    window.RollbackManager.backupValue('isIOSAudioPlaying', window.isIOSAudioPlaying);
  }
  
  // === Audio State Manager ===
  
  window.AudioStateManager = {
    // Audio queue state
    queue: [],
    isProcessing: false,
    currentSequenceId: null,
    currentSegment: null,
    currentSource: null,
    
    // iOS specific
    iosBuffer: [],
    isIOSPlaying: false,
    iosQueue: [],
    iosElement: null,
    
    // TTS state
    tts: {
      enabled: false,
      voice: null,
      rate: 1.0,
      pitch: 1.0,
      volume: 1.0,
      language: 'en-US'
    },
    
    // Voice recording state
    recording: {
      isRecording: false,
      mediaRecorder: null,
      stream: null,
      chunks: [],
      startTime: null
    },
    
    // Audio context
    audioContext: null,
    
    // Processing delays
    delays: {
      queue: window.AUDIO_QUEUE_DELAY || 20,
      error: window.AUDIO_ERROR_DELAY || 50
    },
    
    // === Queue Management ===
    
    addToQueue: function(audioData) {
      try {
        console.log('[AudioStateManager] Adding to queue:', audioData.sequenceId || 'unknown');
        
        this.queue.push(audioData);
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.audio.queue = [...this.queue];
          window.SessionState.notifyListeners('audio:queued', audioData);
        }
        
        // Sync with global variable
        if (window.globalAudioQueue) {
          window.globalAudioQueue.push(audioData);
        }
        
        // Start processing if not already
        if (!this.isProcessing) {
          this.processQueue();
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'addToQueue');
        return false;
      }
    },
    
    processQueue: function() {
      if (this.isProcessing || this.queue.length === 0) {
        return;
      }
      
      this.isProcessing = true;
      
      // Update SessionState
      if (window.SessionState) {
        window.SessionState.audio.isPlaying = true;
      }
      
      // Process next item
      setTimeout(() => {
        this.processNextAudio();
      }, this.delays.queue);
    },
    
    processNextAudio: function() {
      try {
        if (this.queue.length === 0) {
          this.isProcessing = false;
          
          // Update SessionState
          if (window.SessionState) {
            window.SessionState.audio.isPlaying = false;
            window.SessionState.notifyListeners('audio:queue-empty');
          }
          
          return;
        }
        
        const audioData = this.queue.shift();
        this.currentSegment = audioData;
        this.currentSequenceId = audioData.sequenceId;
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.audio.currentSegment = audioData;
          window.SessionState.notifyListeners('audio:playing', audioData);
        }
        
        // Play audio based on type
        if (audioData.type === 'tts') {
          this.playTTS(audioData);
        } else if (audioData.type === 'pcm') {
          this.playPCM(audioData);
        } else {
          this.playAudio(audioData);
        }
        
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'processNextAudio');
        
        // Continue processing queue
        setTimeout(() => {
          this.processNextAudio();
        }, this.delays.error);
      }
    },
    
    clearQueue: function() {
      try {
        console.log('[AudioStateManager] Clearing audio queue');
        
        this.queue = [];
        this.isProcessing = false;
        this.currentSegment = null;
        this.currentSequenceId = null;
        
        // Stop current audio
        if (this.currentSource) {
          this.currentSource.stop();
          this.currentSource = null;
        }
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.audio.queue = [];
          window.SessionState.audio.isPlaying = false;
          window.SessionState.audio.currentSegment = null;
          window.SessionState.notifyListeners('audio:queue-cleared');
        }
        
        // Sync with global variables
        if (window.globalAudioQueue) {
          window.globalAudioQueue = [];
        }
        window.isProcessingAudioQueue = false;
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'clearQueue');
        return false;
      }
    },
    
    // === Audio Playback ===
    
    playAudio: function(audioData) {
      try {
        // Get or create audio context
        if (!this.audioContext) {
          this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
        }
        
        // Implementation depends on audio format
        // This is a placeholder for actual audio playback
        console.log('[AudioStateManager] Playing audio:', audioData);
        
        // Simulate playback completion
        setTimeout(() => {
          this.onAudioComplete();
        }, audioData.duration || 1000);
        
      } catch (error) {
        console.error('[AudioStateManager] Playback error:', error);
        this.onAudioComplete();
      }
    },
    
    playTTS: function(ttsData) {
      try {
        if (!this.tts.enabled) {
          this.onAudioComplete();
          return;
        }
        
        // Use Web Speech API or custom TTS
        const utterance = new SpeechSynthesisUtterance(ttsData.text);
        utterance.voice = this.tts.voice;
        utterance.rate = this.tts.rate;
        utterance.pitch = this.tts.pitch;
        utterance.volume = this.tts.volume;
        utterance.lang = this.tts.language;
        
        utterance.onend = () => {
          this.onAudioComplete();
        };
        
        utterance.onerror = (error) => {
          console.error('[AudioStateManager] TTS error:', error);
          this.onAudioComplete();
        };
        
        speechSynthesis.speak(utterance);
        
      } catch (error) {
        console.error('[AudioStateManager] TTS error:', error);
        this.onAudioComplete();
      }
    },
    
    playPCM: function(pcmData) {
      try {
        if (!this.audioContext) {
          this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
        }
        
        // Convert PCM data to audio buffer
        // This is a placeholder - actual implementation would decode PCM
        console.log('[AudioStateManager] Playing PCM:', pcmData);
        
        // Simulate playback
        setTimeout(() => {
          this.onAudioComplete();
        }, pcmData.duration || 1000);
        
      } catch (error) {
        console.error('[AudioStateManager] PCM playback error:', error);
        this.onAudioComplete();
      }
    },
    
    onAudioComplete: function() {
      this.currentSegment = null;
      
      // Update SessionState
      if (window.SessionState) {
        window.SessionState.audio.currentSegment = null;
        window.SessionState.notifyListeners('audio:complete');
      }
      
      // Process next in queue
      setTimeout(() => {
        this.processNextAudio();
      }, this.delays.queue);
    },
    
    // === Voice Recording ===
    
    startRecording: async function() {
      try {
        if (this.recording.isRecording) {
          console.warn('[AudioStateManager] Already recording');
          return false;
        }
        
        console.log('[AudioStateManager] Starting recording');
        
        // Request microphone access
        this.recording.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        
        // Create media recorder
        this.recording.mediaRecorder = new MediaRecorder(this.recording.stream);
        this.recording.chunks = [];
        
        this.recording.mediaRecorder.ondataavailable = (event) => {
          if (event.data.size > 0) {
            this.recording.chunks.push(event.data);
          }
        };
        
        this.recording.mediaRecorder.onstop = () => {
          this.onRecordingComplete();
        };
        
        // Start recording
        this.recording.mediaRecorder.start();
        this.recording.isRecording = true;
        this.recording.startTime = Date.now();
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.notifyListeners('audio:recording-started');
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'startRecording');
        console.error('[AudioStateManager] Failed to start recording:', error);
        return false;
      }
    },
    
    stopRecording: function() {
      try {
        if (!this.recording.isRecording) {
          console.warn('[AudioStateManager] Not recording');
          return null;
        }
        
        console.log('[AudioStateManager] Stopping recording');
        
        this.recording.isRecording = false;
        
        if (this.recording.mediaRecorder) {
          this.recording.mediaRecorder.stop();
        }
        
        if (this.recording.stream) {
          this.recording.stream.getTracks().forEach(track => track.stop());
        }
        
        const duration = Date.now() - this.recording.startTime;
        
        // Update SessionState
        if (window.SessionState) {
          window.SessionState.notifyListeners('audio:recording-stopped', { duration: duration });
        }
        
        return true;
      } catch (error) {
        window.RollbackManager && window.RollbackManager.recordError(error, 'stopRecording');
        console.error('[AudioStateManager] Failed to stop recording:', error);
        return false;
      }
    },
    
    onRecordingComplete: function() {
      try {
        const blob = new Blob(this.recording.chunks, { type: 'audio/webm' });
        const url = URL.createObjectURL(blob);
        
        // Clear chunks
        this.recording.chunks = [];
        
        // Notify listeners with recorded audio
        if (window.SessionState) {
          window.SessionState.notifyListeners('audio:recording-complete', {
            blob: blob,
            url: url,
            duration: Date.now() - this.recording.startTime
          });
        }
        
        return { blob: blob, url: url };
      } catch (error) {
        console.error('[AudioStateManager] Failed to process recording:', error);
        return null;
      }
    },
    
    // === TTS Configuration ===
    
    setTTSEnabled: function(enabled) {
      this.tts.enabled = enabled;
      
      if (window.SessionState) {
        window.SessionState.audio.enabled = enabled;
        window.SessionState.notifyListeners('audio:tts-toggled', { enabled: enabled });
      }
    },
    
    configureTTS: function(config) {
      Object.assign(this.tts, config);
      
      if (window.SessionState) {
        window.SessionState.notifyListeners('audio:tts-configured', config);
      }
    },
    
    // === State Management ===
    
    getState: function() {
      return {
        queue: this.queue.length,
        isProcessing: this.isProcessing,
        currentSequenceId: this.currentSequenceId,
        isRecording: this.recording.isRecording,
        ttsEnabled: this.tts.enabled,
        hasAudioContext: !!this.audioContext
      };
    },
    
    reset: function() {
      this.clearQueue();
      this.stopRecording();
      this.currentSource = null;
      this.currentSegment = null;
      this.currentSequenceId = null;
      
      if (this.audioContext) {
        this.audioContext.close();
        this.audioContext = null;
      }
      
      console.log('[AudioStateManager] Reset complete');
    }
  };
  
  // === Sync with global variables ===
  
  // Override globalAudioQueue
  Object.defineProperty(window, 'globalAudioQueue', {
    get: function() {
      return window.AudioStateManager.queue;
    },
    set: function(value) {
      window.AudioStateManager.queue = value;
      if (window.SessionState) {
        window.SessionState.audio.queue = value;
      }
    }
  });
  
  // Override isProcessingAudioQueue
  Object.defineProperty(window, 'isProcessingAudioQueue', {
    get: function() {
      return window.AudioStateManager.isProcessing;
    },
    set: function(value) {
      window.AudioStateManager.isProcessing = value;
      if (window.SessionState) {
        window.SessionState.audio.isPlaying = value;
      }
    }
  });
  
  // Override currentSegmentAudio
  Object.defineProperty(window, 'currentSegmentAudio', {
    get: function() {
      return window.AudioStateManager.currentSegment;
    },
    set: function(value) {
      window.AudioStateManager.currentSegment = value;
      if (window.SessionState) {
        window.SessionState.audio.currentSegment = value;
      }
    }
  });
  
  // === Integration with SessionState ===
  
  if (window.SessionState) {
    // Initialize audio state in SessionState
    window.SessionState.audio = {
      ...window.SessionState.audio,
      queue: window.AudioStateManager.queue,
      isPlaying: window.AudioStateManager.isProcessing,
      currentSegment: window.AudioStateManager.currentSegment,
      enabled: window.AudioStateManager.tts.enabled
    };
    
    // Listen for audio events
    window.SessionState.on('audio:clear-queue', function() {
      window.AudioStateManager.clearQueue();
    });
    
    window.SessionState.on('audio:toggle-tts', function(data) {
      window.AudioStateManager.setTTSEnabled(data.enabled);
    });
  }
  
  // === Migration Status ===
  
  window.AudioStateMigration = {
    status: 'active',
    
    // Get migration statistics
    getStats: function() {
      return {
        enabled: window.MigrationConfig.features.audio,
        queueLength: window.AudioStateManager.queue.length,
        isProcessing: window.AudioStateManager.isProcessing,
        isRecording: window.AudioStateManager.recording.isRecording,
        ttsEnabled: window.AudioStateManager.tts.enabled,
        usingSessionState: !!(window.SessionState && window.SessionState.audio)
      };
    },
    
    // Test audio operations
    testOperations: function() {
      console.group('[AudioStateMigration] Testing operations');
      
      const results = {};
      
      try {
        // Test queue operations
        const testAudio = { type: 'test', sequenceId: 'test-1', duration: 100 };
        window.AudioStateManager.addToQueue(testAudio);
        results.addToQueue = window.AudioStateManager.queue.length > 0;
        
        // Test clear queue
        window.AudioStateManager.clearQueue();
        results.clearQueue = window.AudioStateManager.queue.length === 0;
        
        // Test TTS configuration
        window.AudioStateManager.setTTSEnabled(true);
        results.setTTSEnabled = window.AudioStateManager.tts.enabled === true;
        window.AudioStateManager.setTTSEnabled(false);
        
        // Test state
        const state = window.AudioStateManager.getState();
        results.getState = state && typeof state.isProcessing === 'boolean';
        
      } catch (error) {
        console.error('[AudioStateMigration] Test error:', error);
      }
      
      console.table(results);
      console.groupEnd();
      
      return results;
    }
  };
  
  console.log('[AudioStateMigration] Audio state migration complete');
  console.log('[AudioStateMigration] Stats:', window.AudioStateMigration.getStats());
  
})();