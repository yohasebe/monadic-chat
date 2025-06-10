// Improved audio queue processing without arbitrary delays

// Process the global audio queue immediately without delays
function processGlobalAudioQueueImproved() {
  if (globalAudioQueue.length === 0) {
    isProcessingAudioQueue = false;
    currentAudioSequenceId = null;
    return;
  }
  
  isProcessingAudioQueue = true;
  const audioItem = globalAudioQueue.shift();
  currentAudioSequenceId = audioItem.sequenceId;
  
  // Choose appropriate playback method based on device
  if (window.isIOS || window.basicAudioMode) {
    playAudioForIOSFromQueueImproved(audioItem.data);
  } else {
    playAudioFromQueueImproved(audioItem);
  }
}

// Improved iOS audio playback without delays
function playAudioForIOSFromQueueImproved(audioData) {
  try {
    // Add to iOS buffer
    iosAudioBuffer.push(audioData);
    
    // Process immediately if not already playing
    if (!isIOSAudioPlaying) {
      processIOSAudioBufferWithQueueImproved();
    }
  } catch (e) {
    console.error("Error in iOS audio queue:", e);
    // Continue immediately on error
    isProcessingAudioQueue = false;
    processGlobalAudioQueueImproved();
  }
}

// Improved iOS buffer processor without delays
function processIOSAudioBufferWithQueueImproved() {
  if (iosAudioBuffer.length === 0) {
    isIOSAudioPlaying = false;
    // Process next item immediately
    isProcessingAudioQueue = false;
    processGlobalAudioQueueImproved();
    return;
  }
  
  isIOSAudioPlaying = true;
  
  try {
    // Combine all buffered chunks
    let totalLength = 0;
    iosAudioBuffer.forEach(chunk => totalLength += chunk.length);
    
    const combinedData = new Uint8Array(totalLength);
    let offset = 0;
    
    iosAudioBuffer.forEach(chunk => {
      combinedData.set(chunk, offset);
      offset += chunk.length;
    });
    
    iosAudioBuffer = [];
    
    // Create and play audio
    const blob = new Blob([combinedData], { type: 'audio/mpeg' });
    const blobUrl = URL.createObjectURL(blob);
    
    if (!iosAudioElement) {
      iosAudioElement = new Audio();
    }
    
    // Pre-load next audio while current is playing
    const preloadNext = () => {
      if (globalAudioQueue.length > 0) {
        // Start processing next item immediately
        isIOSAudioPlaying = false;
        isProcessingAudioQueue = false;
        processGlobalAudioQueueImproved();
      }
    };
    
    iosAudioElement.onended = function() {
      URL.revokeObjectURL(blobUrl);
      preloadNext();
    };
    
    iosAudioElement.onerror = function() {
      URL.revokeObjectURL(blobUrl);
      preloadNext();
    };
    
    iosAudioElement.src = blobUrl;
    
    // Use promises for better control flow
    iosAudioElement.play().then(() => {
      // Audio started successfully
    }).catch(err => {
      console.error("Failed to play iOS audio:", err);
      URL.revokeObjectURL(blobUrl);
      preloadNext();
    });
    
  } catch (e) {
    console.error("Error in iOS buffer processing:", e);
    isIOSAudioPlaying = false;
    isProcessingAudioQueue = false;
    // Process next item immediately
    processGlobalAudioQueueImproved();
  }
}

// Alternative approach using Promise-based queue
class AudioQueueManager {
  constructor() {
    this.queue = [];
    this.isPlaying = false;
    this.currentAudio = null;
  }
  
  add(audioData) {
    this.queue.push(audioData);
    if (!this.isPlaying) {
      this.processNext();
    }
  }
  
  async processNext() {
    if (this.queue.length === 0) {
      this.isPlaying = false;
      return;
    }
    
    this.isPlaying = true;
    const audioItem = this.queue.shift();
    
    try {
      await this.playAudio(audioItem);
      // Immediately process next without delay
      this.processNext();
    } catch (error) {
      console.error("Audio playback error:", error);
      // Continue with next item immediately
      this.processNext();
    }
  }
  
  async playAudio(audioItem) {
    return new Promise((resolve, reject) => {
      const audio = new Audio();
      const blob = new Blob([audioItem.data], { type: audioItem.mimeType || 'audio/mpeg' });
      const url = URL.createObjectURL(blob);
      
      audio.onended = () => {
        URL.revokeObjectURL(url);
        resolve();
      };
      
      audio.onerror = (e) => {
        URL.revokeObjectURL(url);
        reject(e);
      };
      
      audio.src = url;
      this.currentAudio = audio;
      
      audio.play().catch(reject);
    });
  }
  
  stop() {
    this.queue = [];
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio = null;
    }
    this.isPlaying = false;
  }
}

// Usage example:
// const audioQueue = new AudioQueueManager();
// audioQueue.add({ data: audioData, mimeType: 'audio/mpeg' });