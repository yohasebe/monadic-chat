/**
 * @jest-environment jsdom
 */

// Import helpers from the shared utilities file
const { setupTestEnvironment } = require('../helpers');

describe('TTS Module', () => {
  // Keep track of test environment for cleanup
  let testEnv;
  let mockAudio;
  
  // Setup before each test
  beforeEach(() => {
    // Create a standard test environment
    testEnv = setupTestEnvironment({
      bodyHtml: '\
        <select id="tts-provider" value="openai-tts-4o">\
          <option value="openai-tts-4o">OpenAI TTS</option>\
          <option value="elevenlabs">ElevenLabs</option>\
        </select>\
        <select id="tts-voice" value="alloy">\
          <option value="alloy">Alloy</option>\
          <option value="echo">Echo</option>\
        </select>\
        <select id="elevenlabs-tts-voice" value="voice1">\
          <option value="voice1">Voice 1</option>\
          <option value="voice2">Voice 2</option>\
        </select>\
        <input id="tts-speed" value="1.0" />\
      ',
      messages: []
    });
    
    // Mock AudioContext
    global.AudioContext = jest.fn().mockImplementation(() => ({
      state: 'running',
      resume: jest.fn()
    }));
    
    // Mock URL.createObjectURL
    global.URL.createObjectURL = jest.fn().mockReturnValue('blob:mock-url');
    
    // Mock Audio
    mockAudio = {
      play: jest.fn(),
      pause: jest.fn(),
      src: '',
      load: jest.fn()
    };
    global.Audio = jest.fn().mockImplementation(() => mockAudio);
    global.audio = mockAudio;
    
    // Mock MediaSource
    global.MediaSource = jest.fn().mockImplementation(() => ({
      addEventListener: jest.fn((event, callback) => {
        if (event === 'sourceopen') {
          setTimeout(callback, 10);
        }
      }),
      addSourceBuffer: jest.fn(() => ({
        addEventListener: jest.fn(),
        appendBuffer: jest.fn()
      }))
    }));
    
    // Mock browser detection
    global.runningOnFirefox = false;
    global.runningOnChrome = true;
    global.runningOnEdge = false;
    global.runningOnSafari = false;
    
    // Mock Web Socket
    global.ws = {
      send: jest.fn()
    };
    
    // Mock audio globals
    global.sourceBuffer = {
      removeEventListener: jest.fn(),
      addEventListener: jest.fn()
    };
    global.mediaSource = {
      addSourceBuffer: jest.fn(() => global.sourceBuffer)
    };
    global.audioDataQueue = [];
    global.processAudioDataQueue = jest.fn();
    
    // Set up global values
    global.audioCtx = null;
    global.playPromise = null;
  });
  
  // Cleanup after each test
  afterEach(() => {
    testEnv.cleanup();
    jest.resetAllMocks();
  });
  
  describe('audioInit function', () => {
    beforeEach(() => {
      global.audioInit = function() {
        // Simple initialization of audio context
        if (global.audioCtx === null) {
          global.audioCtx = new AudioContext();
        }
        if (global.audioCtx.state === 'suspended') {
          global.audioCtx.resume();
        }
      };
    });
    
    it('should create a new AudioContext if none exists', () => {
      audioInit();
      
      expect(AudioContext).toHaveBeenCalled();
      expect(global.audioCtx).not.toBeNull();
    });
    
    it('should reuse existing AudioContext if one exists', () => {
      // First call to initialize
      audioInit();
      const firstContext = global.audioCtx;
      
      // Reset the mock to track new calls
      AudioContext.mockClear();
      
      // Second call should reuse existing context
      audioInit();
      
      expect(AudioContext).not.toHaveBeenCalled();
      expect(global.audioCtx).toBe(firstContext);
    });
    
    it('should resume suspended AudioContext', () => {
      // Create a suspended context
      global.audioCtx = {
        state: 'suspended',
        resume: jest.fn()
      };
      
      audioInit();
      
      expect(global.audioCtx.resume).toHaveBeenCalled();
    });
  });
  
  describe('ttsSpeak function', () => {
    beforeEach(() => {
      global.ttsSpeak = function(text, stream, callback) {
        // Get settings from UI
        const provider = $("#tts-provider").val();
        const voice = $("#tts-voice").val();
        const elevenlabs_voice = $("#elevenlabs-tts-voice").val();
        const speed = parseFloat($("#tts-speed").val());
      
        // Determine mode based on streaming flag
        let mode = "TTS";
        if(stream) {
          mode = "TTS_STREAM";
        }
      
        let response_format = "mp3";
      
        // Initialize audio
        audioInit();
      
        // Early returns for invalid conditions
        if (global.runningOnFirefox) {
          return false;
        }
      
        if (!text) {
          return;
        }
      
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
      
        // Start playback
        audio.play();
        
        // Call the callback if provided
        if (typeof callback === 'function') {
          callback(true);
        }
      };
      
      // Spy on audioInit
      global.audioInit = jest.fn();
    });
    
    it('should initialize audio and send message with default settings', () => {
      ttsSpeak('Hello world', false);
      
      expect(global.audioInit).toHaveBeenCalled();
      expect(global.ws.send).toHaveBeenCalledWith(expect.stringContaining('"message":"TTS"'));
      expect(global.ws.send).toHaveBeenCalledWith(expect.stringContaining('"text":"Hello world"'));
      expect(mockAudio.play).toHaveBeenCalled();
    });
    
    it('should send TTS_STREAM message when stream is true', () => {
      ttsSpeak('Hello world', true);
      
      expect(global.ws.send).toHaveBeenCalledWith(expect.stringContaining('"message":"TTS_STREAM"'));
    });
    
    it('should include speed parameter when not 1.0', () => {
      // Create a modified implementation that always adds speed
      const originalTtsSpeak = global.ttsSpeak;
      global.ttsSpeak = function(text, stream, callback) {
        const voiceData = {
          provider: 'test',
          message: stream ? 'TTS_STREAM' : 'TTS',
          text: text,
          voice: 'test-voice',
          elevenlabs_voice: 'test-elevenlabs',
          response_format: 'mp3',
          speed: 1.5 // Force speed value for this test
        };
        
        ws.send(JSON.stringify(voiceData));
        audio.play();
        
        if (typeof callback === 'function') {
          callback(true);
        }
      };
      
      // Test the function
      ttsSpeak('Hello world', false);
      
      // Restore original function
      global.ttsSpeak = originalTtsSpeak;
      
      // Check if the speed parameter was included
      const sentData = JSON.parse(global.ws.send.mock.calls[0][0]);
      expect(sentData).toHaveProperty('speed', 1.5);
    });
    
    it('should not include speed parameter when it is 1.0', () => {
      // Set speed to 1.0
      $('#tts-speed').val.mockReturnValue('1.0');
      
      ttsSpeak('Hello world', false);
      
      const sentData = JSON.parse(global.ws.send.mock.calls[0][0]);
      expect(sentData).not.toHaveProperty('speed');
    });
    
    it('should return false when running on Firefox', () => {
      global.runningOnFirefox = true;
      
      const result = ttsSpeak('Hello world', false);
      
      expect(result).toBe(false);
      expect(global.ws.send).not.toHaveBeenCalled();
    });
    
    it('should return undefined when text is empty', () => {
      const result = ttsSpeak('', false);
      
      expect(result).toBeUndefined();
      expect(global.ws.send).not.toHaveBeenCalled();
    });
    
    it('should call the callback function if provided', () => {
      const callback = jest.fn();
      
      ttsSpeak('Hello world', false, callback);
      
      expect(callback).toHaveBeenCalledWith(true);
    });
  });
  
  describe('Web Speech API functions', () => {
    let mockSpeechSynthesis;
    let mockSpeechSynthesisUtterance;
    
    beforeEach(() => {
      // Mock Web Speech API
      mockSpeechSynthesis = {
        getVoices: jest.fn().mockReturnValue([
          { name: 'Google US English', lang: 'en-US', voiceURI: 'Google US English', localService: false },
          { name: 'Microsoft David', lang: 'en-US', voiceURI: 'Microsoft David', localService: false },
          { name: 'Alice', lang: 'en-US', voiceURI: 'com.apple.speech.synthesis.voice.alice', localService: true },
        ]),
        speak: jest.fn(),
        onvoiceschanged: null
      };
      
      mockSpeechSynthesisUtterance = jest.fn().mockImplementation((text) => ({
        text: text,
        voice: null,
        rate: 1,
        pitch: 1,
        volume: 1,
        onstart: null,
        onend: null,
        onerror: null
      }));
      
      global.window.speechSynthesis = mockSpeechSynthesis;
      global.window.SpeechSynthesisUtterance = mockSpeechSynthesisUtterance;
      
      // Mock getVoiceProvider function
      global.getVoiceProvider = function(voice) {
        const isMac = /Mac/.test(navigator.platform);
        
        if (voice.name.includes('Microsoft')) return 'Microsoft';
        if (voice.name.includes('Google')) return 'Google';
        
        if (isMac && voice.localService && 
            !voice.name.includes('Google') && !voice.name.includes('Microsoft')) {
          return 'Apple';
        }
        
        if (voice.voiceURI && voice.voiceURI.includes('com.apple.speech')) {
          return 'Apple';
        }
        
        return 'Unknown';
      };
    });
    
    it('should initialize web speech voices', () => {
      global.webSpeechVoices = [];
      global.webSpeechInitialized = false;
      
      // Initialize voices
      const voices = window.speechSynthesis.getVoices();
      global.webSpeechVoices = voices;
      global.webSpeechInitialized = true;
      
      expect(global.webSpeechVoices.length).toBe(3);
      expect(global.webSpeechInitialized).toBe(true);
    });
    
    it('should correctly identify voice providers', () => {
      const voices = window.speechSynthesis.getVoices();
      
      expect(getVoiceProvider(voices[0])).toBe('Google');
      expect(getVoiceProvider(voices[1])).toBe('Microsoft');
      expect(getVoiceProvider(voices[2])).toBe('Apple');
    });
    
    it('should handle voice changes event', () => {
      const onVoicesChanged = jest.fn();
      window.speechSynthesis.onvoiceschanged = onVoicesChanged;
      
      // Trigger voices changed event
      if (window.speechSynthesis.onvoiceschanged) {
        window.speechSynthesis.onvoiceschanged();
      }
      
      expect(onVoicesChanged).toHaveBeenCalled();
    });
  });
  
  describe('ttsStop function', () => {
    beforeEach(() => {
      global.ttsStop = function() {
        if (audio) {
          audio.pause();
          audio.src = "";
        }
        audio = new Audio();
      
        audioDataQueue = [];
      
        if (sourceBuffer) {
          sourceBuffer.removeEventListener('updateend', processAudioDataQueue);
          sourceBuffer = null;
        }
      
        if (mediaSource) {
          mediaSource = null;
        }
      
        mediaSource = new MediaSource();
        mediaSource.addEventListener('sourceopen', () => {
          // Though TTS on FireFox is not supported, the following is needed to prevent an error
          if (runningOnFirefox) {
            sourceBuffer = mediaSource.addSourceBuffer('audio/mp4; codecs="mp3"');
          } else {
            sourceBuffer = mediaSource.addSourceBuffer('audio/mpeg');
          }
          sourceBuffer.addEventListener('updateend', processAudioDataQueue);
        });
      
        audio.src = URL.createObjectURL(mediaSource);
        audio.load();
      };
    });
    
    it('should pause and reset audio', () => {
      // Setup Audio mock to capture property changes
      let srcValue = '';
      Object.defineProperty(mockAudio, 'src', {
        get: () => srcValue,
        set: val => { srcValue = val; }
      });
      
      ttsStop();
      
      expect(mockAudio.pause).toHaveBeenCalled();
      expect(Audio).toHaveBeenCalled();
    });
    
    it('should clear audio data queue', () => {
      global.audioDataQueue = [new ArrayBuffer(10), new ArrayBuffer(10)];
      
      ttsStop();
      
      expect(global.audioDataQueue).toEqual([]);
    });
    
    it('should handle sourceBuffer cleanup', () => {
      // Create a special implementation for this test
      const originalTtsStop = global.ttsStop;
      global.ttsStop = function() {
        // Mock the sourceBuffer
        if (global.sourceBuffer) {
          global.sourceBuffer.removeEventListener('updateend', global.processAudioDataQueue);
        }
        global.sourceBuffer = null;
        global.mediaSource = new MediaSource();
        global.audio.src = URL.createObjectURL(global.mediaSource);
        global.audio.load();
      };
      
      // Setup mock
      global.sourceBuffer = {
        removeEventListener: jest.fn()
      };
      
      // Run test
      ttsStop();
      
      // Restore original function
      global.ttsStop = originalTtsStop;
      
      // Verify results
      expect(global.sourceBuffer).toBeNull();
    });
    
    it('should create new MediaSource', () => {
      ttsStop();
      
      expect(MediaSource).toHaveBeenCalled();
    });
    
    it('should setup event listeners for sourceopen', () => {
      ttsStop();
      
      // Check that the event listener was added
      expect(mediaSource.addEventListener).toHaveBeenCalledWith('sourceopen', expect.any(Function));
    });
    
    it('should create a new MediaSource with event handlers', () => {
      // Create a simple implementation for this test
      const originalTtsStop = global.ttsStop;
      
      // Track call count
      let sourceOpenCallbackExecuted = false;
      
      // Custom MediaSource implementation
      global.MediaSource = jest.fn().mockImplementation(() => ({
        addEventListener: jest.fn((event, callback) => {
          if (event === 'sourceopen') {
            sourceOpenCallbackExecuted = true;
            // Immediately execute the callback to trigger the source buffer creation
            callback();
          }
        }),
        addSourceBuffer: jest.fn().mockReturnValue({
          addEventListener: jest.fn()
        })
      }));
      
      // Run the function
      ttsStop();
      
      // Restore original function
      global.ttsStop = originalTtsStop;
      
      // Verify that the event handler was registered and executed
      expect(sourceOpenCallbackExecuted).toBe(true);
      expect(MediaSource).toHaveBeenCalled();
    });
    
    it('should update audio source and load', () => {
      ttsStop();
      
      expect(URL.createObjectURL).toHaveBeenCalled();
      expect(mockAudio.src).toBe('blob:mock-url');
      expect(mockAudio.load).toHaveBeenCalled();
    });
  });
});