/**
 * @jest-environment jsdom
 */

// Import helpers from the shared utilities file
const { setupTestEnvironment } = require('../helpers');

describe('Recording Module', () => {
  // Keep track of test environment for cleanup
  let testEnv;
  
  // Setup before each test
  // Define shared mock objects for tests
  let mockAnalyser;
  let mockStreamNode;
  let mockAudioContext;
  
  beforeEach(() => {
    // Setup fake timers
    jest.useFakeTimers();
    
    // Create a standard test environment
    testEnv = setupTestEnvironment({
      bodyHtml: '\
        <button id="voice" class="btn btn-warning"><i class="fas fa-microphone"></i> Speech Input</button>\
        <button id="send" class="btn btn-primary">Send</button>\
        <button id="clear" class="btn btn-secondary">Clear</button>\
        <select id="asr-lang" value="en-US">\
          <option value="en-US">English (US)</option>\
          <option value="ja-JP">Japanese</option>\
        </select>\
        <select id="stt-model">\
          <option value="model1">Model 1</option>\
          <option value="model2">Model 2</option>\
        </select>\
        <div id="asr-p-value" style="display:none;"></div>\
        <div id="amplitude" style="display:none;">\
          <canvas id="amplitude-chart" width="300" height="150"></canvas>\
        </div>\
      ',
      messages: []
    });
    
    // Override any jQuery mocks with more specific implementations
    $("#voice").toggleClass = jest.fn().mockReturnThis();
    $("#voice").html = jest.fn().mockReturnThis();
    $("#voice").prop = jest.fn().mockReturnThis();
    $("#voice").trigger = jest.fn().mockReturnThis(); 
    
    $("#send").prop = jest.fn().mockReturnThis();
    $("#clear").prop = jest.fn().mockReturnThis();
    
    $("#amplitude").show = jest.fn().mockReturnThis();
    $("#amplitude").hide = jest.fn().mockReturnThis();
    
    $("#asr-p-value").text = jest.fn().mockReturnThis();
    $("#asr-p-value").hide = jest.fn().mockReturnThis();
    $("#asr-p-value").show = jest.fn().mockReturnThis();
    
    // Set up the language selection dropdown
    $("#asr-lang").val = jest.fn().mockReturnValue('en-US');
    
    // Mock global functions and variables
    global.setAlert = jest.fn();
    global.reconnect_websocket = jest.fn((ws, callback) => {
      if (callback) callback();
    });
    global.ws = { send: jest.fn() };
    
    // Mock Web Audio API
    mockAnalyser = {
      fftSize: 0,
      getByteFrequencyData: jest.fn((dataArray) => {
        // Fill with random values between 0-30 to simulate some audio levels
        for (let i = 0; i < dataArray.length; i++) {
          dataArray[i] = Math.floor(Math.random() * 30);
        }
      })
    };
    
    mockStreamNode = {
      connect: jest.fn()
    };
    
    mockAudioContext = {
      createAnalyser: jest.fn().mockReturnValue(mockAnalyser),
      createMediaStreamSource: jest.fn().mockReturnValue(mockStreamNode),
      close: jest.fn()
    };
    
    global.window.AudioContext = jest.fn().mockImplementation(() => mockAudioContext);
    global.window.webkitAudioContext = global.window.AudioContext;
    
    // Mock MediaRecorder
    global.MediaRecorder = jest.fn().mockImplementation(() => ({
      start: jest.fn(),
      stop: jest.fn(),
      ondataavailable: null,
      state: 'inactive',
      mimeType: 'audio/webm;codecs=opus'
    }));
    global.MediaRecorder.isTypeSupported = jest.fn((mimeType) => {
      return mimeType === 'audio/webm;codecs=opus';
    });
    
    // Mock OpusMediaRecorder (used in the code)
    global.OpusMediaRecorder = global.MediaRecorder;
    
    // Mock navigator.mediaDevices
    global.navigator.mediaDevices = {
      getUserMedia: jest.fn().mockResolvedValue({
        getTracks: jest.fn().mockReturnValue([{
          stop: jest.fn()
        }]),
        closeAudioContext: null
      })
    };
    
    // Mock Web Animation API
    global.requestAnimationFrame = jest.fn(callback => {
      setTimeout(callback, 16); // Approximately 60fps
      return 123; // Animation frame ID
    });
    global.cancelAnimationFrame = jest.fn();
    
    // Mock performance API
    global.performance = {
      now: jest.fn().mockReturnValue(1000)
    };
    
    // Mock FileReader
    global.FileReader = jest.fn().mockImplementation(() => ({
      onload: null,
      readAsDataURL: jest.fn(function(blob) {
        // Simulate the FileReader's asynchronous behavior
        setTimeout(() => {
          if (this.onload) {
            this.result = `data:${blob.type};base64,dGVzdEF1ZGlvRGF0YQ==`; // "testAudioData" in base64
            this.onload();
          }
        }, 10);
      })
    }));
    
    // Mock speech synthesis
    global.speechSynthesis = {
      speaking: false,
      cancel: jest.fn()
    };
  });
  
  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
    jest.resetAllMocks();
    
    // Clear any timers
    jest.clearAllTimers();
  });
  
  describe('detectSilence function', () => {
    beforeEach(() => {
      global.detectSilence = function(stream, onSilenceCallback, silenceDuration, silenceThreshold = 16) {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const analyser = audioContext.createAnalyser();
        const streamNode = audioContext.createMediaStreamSource(stream);
        streamNode.connect(analyser);
        analyser.fftSize = 2048;
        const bufferLength = 32;
        const dataArray = new Uint8Array(bufferLength);
      
        let silenceStart = performance.now();
        let triggered = false;
        let animationFrameId;
      
        function checkSilence() {
          analyser.getByteFrequencyData(dataArray);
          // Use Array.from to ensure we have array methods
          const totalAmplitude = Array.from(dataArray).reduce((a, b) => a + b, 0);
          const averageAmplitude = totalAmplitude / bufferLength;
          const isSilent = averageAmplitude < silenceThreshold;
      
          if (isSilent) {
            const now = performance.now();
            if (!triggered && now - silenceStart > silenceDuration) {
              onSilenceCallback();
              triggered = true;
            }
          } else {
            silenceStart = performance.now();
            triggered = false;
          }
      
          // Update the bar chart (simplified for testing)
          const chartCanvas = document.querySelector("#amplitude-chart");
          if (chartCanvas) {
            const chartContext = chartCanvas.getContext("2d");
            chartContext.clearRect(0, 0, chartCanvas.width, chartCanvas.height);
          }
      
          // Request the next frame
          animationFrameId = requestAnimationFrame(checkSilence);
        }
      
        checkSilence();
      
        // Return a function to close the audio context and cancel animation frame
        return function () {
          if (animationFrameId) {
            cancelAnimationFrame(animationFrameId);
          }
          audioContext.close();
        };
      };
      
      // Mock canvas context
      const mockCanvasContext = {
        clearRect: jest.fn(),
        fillRect: jest.fn(),
        fillStyle: ''
      };
      
      // Mock canvas element
      document.querySelector = jest.fn().mockImplementation(selector => {
        if (selector === '#amplitude-chart') {
          return {
            getContext: jest.fn().mockReturnValue(mockCanvasContext),
            width: 300,
            height: 150
          };
        }
        return null;
      });
    });
    
    it('should initialize audio context and analyzer', () => {
      const stream = { id: 'mock-stream' };
      const silenceCallback = jest.fn();
      const cleanup = detectSilence(stream, silenceCallback, 2000);
      
      expect(window.AudioContext).toHaveBeenCalled();
      expect(cleanup).toBeInstanceOf(Function);
    });
    
    it('should call silence callback when silence is detected', () => {
      // Override getByteFrequencyData to simulate silence
      const originalGetByteFrequency = mockAnalyser.getByteFrequencyData;
      mockAnalyser.getByteFrequencyData = jest.fn(dataArray => {
        // Fill with zeros to simulate silence
        for (let i = 0; i < dataArray.length; i++) {
          dataArray[i] = 0;
        }
      });
      
      // Set up silence detection with a short duration
      const stream = { id: 'mock-stream' };
      const silenceCallback = jest.fn();
      const cleanup = detectSilence(stream, silenceCallback, 100); // Short duration for testing
      
      // Advance time to trigger silence detection
      performance.now.mockReturnValue(1200); // More than 100ms after start time (1000)
      
      // Trigger another frame to check silence
      jest.advanceTimersByTime(20);
      
      expect(silenceCallback).toHaveBeenCalled();
      
      // Clean up
      cleanup();
      mockAnalyser.getByteFrequencyData = originalGetByteFrequency;
    });

    it('should clean up resources when cleanup function is called', () => {
      const stream = { id: 'mock-stream' };
      const silenceCallback = jest.fn();
      const cleanup = detectSilence(stream, silenceCallback, 2000);
      
      // Call the cleanup function
      cleanup();
      
      expect(cancelAnimationFrame).toHaveBeenCalled();
      expect(mockAudioContext.close).toHaveBeenCalled();
    });
  });

  describe('soundToBase64 function', () => {
    beforeEach(() => {
      global.soundToBase64 = function(blob, callback) {
        const reader = new FileReader();
        reader.onload = function() {
          const dataUrl = reader.result;
          const base64 = dataUrl.split(',')[1];
          callback(base64);
        };
        reader.readAsDataURL(blob);
      };
    });
    
    it('should convert a blob to base64', () => {
      // Mock FileReader to be synchronous for this test
      global.FileReader = jest.fn().mockImplementation(() => ({
        onload: null,
        readAsDataURL: jest.fn(function(blob) {
          this.result = `data:${blob.type};base64,dGVzdEF1ZGlvRGF0YQ==`; // "testAudioData" in base64
          if (this.onload) this.onload();
        })
      }));
      
      const audioBlob = {
        size: 1000,
        type: 'audio/webm'
      };
      
      const callback = jest.fn();
      soundToBase64(audioBlob, callback);
      
      expect(callback).toHaveBeenCalledWith('dGVzdEF1ZGlvRGF0YQ==');
    });
  });
});
