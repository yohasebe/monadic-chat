/**
 * Audio encoding utilities for Monadic Chat
 * Requires lamejs to be loaded (https://github.com/zhuker/lamejs)
 */

// Convert audio blob to MP3 format using lamejs
function convertToMP3(audioBlob, callback, quality = 128) {
  // Start timing the conversion
  const startTime = performance.now();
  
  // Create a FileReader to read the audio blob
  const fileReader = new FileReader();
  
  fileReader.onload = function() {
    // Get the audio data as ArrayBuffer
    const arrayBuffer = this.result;
    
    // Convert ArrayBuffer to Float32Array
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    
    audioContext.decodeAudioData(arrayBuffer, function(audioBuffer) {
      // Get audio details for encoding
      const channels = audioBuffer.numberOfChannels;
      const sampleRate = audioBuffer.sampleRate;
      
      // lamejs works with 1 or 2 channels only
      const numChannels = Math.min(channels, 2);
      
      // Create MP3 encoder
      const mp3Encoder = new lamejs.Mp3Encoder(numChannels, sampleRate, quality);
      const mp3Data = [];
      
      // Process each channel
      let samples = new Int16Array(audioBuffer.length * numChannels);
      let leftChannel, rightChannel;
      
      // Get channel data
      leftChannel = audioBuffer.getChannelData(0);
      rightChannel = (numChannels > 1) ? audioBuffer.getChannelData(1) : leftChannel;
      
      // Convert Float32Array to Int16Array for lamejs
      for (let i = 0; i < audioBuffer.length; i++) {
        // Scale Float32 to Int16 range and ensure it's within bounds
        const left = Math.max(-32768, Math.min(32767, leftChannel[i] * 32768));
        const right = Math.max(-32768, Math.min(32767, rightChannel[i] * 32768));
        
        samples[i * numChannels] = left;
        if (numChannels > 1) {
          samples[i * numChannels + 1] = right;
        }
      }
      
      // Process in chunks to avoid memory issues
      const chunkSize = 1152; // Must be multiple of 576 for lamejs
      
      for (let i = 0; i < samples.length; i += chunkSize * numChannels) {
        const chunk = samples.subarray(i, i + chunkSize * numChannels);
        const mp3buf = mp3Encoder.encodeBuffer(chunk);
        if (mp3buf.length > 0) {
          mp3Data.push(mp3buf);
        }
      }
      
      // Finalize the MP3
      const mp3buf = mp3Encoder.flush();
      if (mp3buf.length > 0) {
        mp3Data.push(mp3buf);
      }
      
      // Create a Blob from the MP3 data
      const mp3Blob = new Blob(mp3Data, { type: 'audio/mp3' });
      
      // Calculate time taken (not logged)
      const endTime = performance.now();
      
      // Return the MP3 blob
      callback(mp3Blob);
    }, function(error) {
      console.error("Error decoding audio data:", error);
      // Fall back to original blob if decoding fails
      callback(audioBlob);
    });
  };
  
  fileReader.readAsArrayBuffer(audioBlob);
}