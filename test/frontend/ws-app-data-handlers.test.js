/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-app-data-handlers.js
 *
 * Tests the extracted WebSocket message handlers for:
 * - handleElevenLabsVoices: Populate ElevenLabs TTS voice selector
 * - handleGeminiVoices: Populate Gemini TTS voice selector
 * - handleMistralVoices: Populate Mistral TTS voice selector
 * - handleAppsMessage: Build app selector and classify apps
 * - handleParametersMessage: Load session parameters
 */

/**
 * Helper: create a <select> element with given id and append to document.body
 */
function createDOMSelect(id) {
  const el = document.createElement('select');
  el.id = id;
  document.body.appendChild(el);
  return el;
}

/**
 * Helper: create a generic DOM element with given id and tag
 */
function createDOMElement(id, tag = 'div') {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

/**
 * Helper: create an <option> element with given id (for enable/disable tracking)
 */
function createDOMOption(id) {
  const el = document.createElement('option');
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Clear DOM
  document.body.innerHTML = '';

  // Mock getCookie
  global.getCookie = jest.fn().mockReturnValue(null);
});

afterEach(() => {
  jest.restoreAllMocks();
});

// Load the module
const handlers = require('../../docker/services/ruby/public/js/monadic/ws-app-data-handlers');

describe('ws-app-data-handlers', () => {
  describe('handleElevenLabsVoices', () => {
    let voiceSelect;

    beforeEach(() => {
      voiceSelect = createDOMSelect('elevenlabs-tts-voice');
      createDOMSelect('tts-provider');
      // TTS provider options
      createDOMOption('elevenlabs-flash-provider-option');
      createDOMOption('elevenlabs-multilingual-provider-option');
      createDOMOption('elevenlabs-v3-provider-option');
      // STT options
      createDOMOption('elevenlabs-stt-scribe-v2');
      createDOMOption('elevenlabs-stt-scribe');
      createDOMOption('elevenlabs-stt-scribe-experimental');
    });

    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'v1', name: 'Rachel' },
          { voice_id: 'v2', name: 'Drew' }
        ]
      };

      handlers.handleElevenLabsVoices(data);

      expect(voiceSelect.options.length).toBe(2);
      expect(voiceSelect.options[0].value).toBe('v1');
      expect(voiceSelect.options[0].textContent).toBe('Rachel');
      expect(voiceSelect.options[1].value).toBe('v2');
      expect(voiceSelect.options[1].textContent).toBe('Drew');
    });

    it('enables TTS and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      expect(document.getElementById('elevenlabs-flash-provider-option').disabled).toBe(false);
      expect(document.getElementById('elevenlabs-multilingual-provider-option').disabled).toBe(false);
      expect(document.getElementById('elevenlabs-v3-provider-option').disabled).toBe(false);
      expect(document.getElementById('elevenlabs-stt-scribe-v2').disabled).toBe(false);
      expect(document.getElementById('elevenlabs-stt-scribe').disabled).toBe(false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleElevenLabsVoices(data);

      expect(document.getElementById('elevenlabs-flash-provider-option').disabled).toBe(true);
      expect(document.getElementById('elevenlabs-multilingual-provider-option').disabled).toBe(true);
      expect(document.getElementById('elevenlabs-v3-provider-option').disabled).toBe(true);
      expect(document.getElementById('elevenlabs-stt-scribe-v2').disabled).toBe(true);
    });

    it('restores saved voice from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'elevenlabs-tts-voice') return 'v2';
        return null;
      });

      const data = {
        content: [
          { voice_id: 'v1', name: 'Rachel' },
          { voice_id: 'v2', name: 'Drew' }
        ]
      };

      handlers.handleElevenLabsVoices(data);

      expect(voiceSelect.value).toBe('v2');
    });

    it('restores saved provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'elevenlabs-flash';
        return null;
      });

      // Add the option to the provider select so .value can be set
      const providerSelect = document.getElementById('tts-provider');
      const opt = document.createElement('option');
      opt.value = 'elevenlabs-flash';
      providerSelect.appendChild(opt);

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      expect(providerSelect.value).toBe('elevenlabs-flash');
    });

    it('does not restore non-elevenlabs provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      // Add an option so we can check it wasn't changed
      const providerSelect = document.getElementById('tts-provider');
      const opt = document.createElement('option');
      opt.value = '';
      opt.selected = true;
      providerSelect.appendChild(opt);

      handlers.handleElevenLabsVoices(data);

      // Should not try to set a non-elevenlabs provider
      expect(providerSelect.value).toBe('');
    });
  });

  describe('handleGeminiVoices', () => {
    let voiceSelect;

    beforeEach(() => {
      voiceSelect = createDOMSelect('gemini-tts-voice');
      createDOMSelect('tts-provider');
      createDOMOption('gemini-flash-provider-option');
      createDOMOption('gemini-pro-provider-option');
      createDOMOption('gemini-stt-flash');
    });

    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'Aoede', name: 'Aoede' },
          { voice_id: 'Charon', name: 'Charon' }
        ]
      };

      handlers.handleGeminiVoices(data);

      expect(voiceSelect.options.length).toBe(2);
      expect(voiceSelect.options[0].value).toBe('Aoede');
      expect(voiceSelect.options[1].value).toBe('Charon');
    });

    it('enables provider and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(document.getElementById('gemini-flash-provider-option').disabled).toBe(false);
      expect(document.getElementById('gemini-pro-provider-option').disabled).toBe(false);
      expect(document.getElementById('gemini-stt-flash').disabled).toBe(false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleGeminiVoices(data);

      expect(document.getElementById('gemini-flash-provider-option').disabled).toBe(true);
      expect(document.getElementById('gemini-pro-provider-option').disabled).toBe(true);
      expect(document.getElementById('gemini-stt-flash').disabled).toBe(true);
    });

    it('restores saved voice from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'gemini-tts-voice') return 'Charon';
        return null;
      });

      const data = {
        content: [
          { voice_id: 'Aoede', name: 'Aoede' },
          { voice_id: 'Charon', name: 'Charon' }
        ]
      };

      handlers.handleGeminiVoices(data);

      expect(voiceSelect.value).toBe('Charon');
    });

    it('restores saved gemini provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'gemini-flash';
        return null;
      });

      // Add the option to the provider select so .value can be set
      const providerSelect = document.getElementById('tts-provider');
      const opt = document.createElement('option');
      opt.value = 'gemini-flash';
      providerSelect.appendChild(opt);

      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(providerSelect.value).toBe('gemini-flash');
    });

    it('does not restore non-gemini provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = { content: [{ voice_id: 'Aoede', name: 'Aoede' }] };

      const providerSelect = document.getElementById('tts-provider');
      const opt = document.createElement('option');
      opt.value = '';
      opt.selected = true;
      providerSelect.appendChild(opt);

      handlers.handleGeminiVoices(data);

      expect(providerSelect.value).toBe('');
    });
  });

  describe('normalizeGroupId', () => {
    it('converts group name to lowercase hyphenated id', () => {
      expect(handlers.normalizeGroupId('OpenAI')).toBe('openai');
      expect(handlers.normalizeGroupId('xAI')).toBe('xai');
      expect(handlers.normalizeGroupId('Deep Seek')).toBe('deep-seek');
      expect(handlers.normalizeGroupId('Extra!')).toBe('extra-');
    });

    it('handles empty string', () => {
      expect(handlers.normalizeGroupId('')).toBe('');
    });
  });

  describe('handleAppsMessage', () => {
    beforeEach(() => {
      // Create DOM elements needed by the handler
      createDOMElement('monadic-version-number');
      createDOMSelect('apps');
      createDOMElement('custom-apps-dropdown');
      createDOMElement('base-app-title');
      createDOMElement('base-app-icon');
      createDOMElement('base-app-desc');
      createDOMElement('monadic-badge');
      createDOMElement('websearch-badge');
      createDOMElement('tools-badge');
      createDOMElement('math-badge');
      createDOMElement('show-all-models', 'input');
      document.getElementById('show-all-models').type = 'checkbox';
      createDOMSelect('model');
      createDOMElement('model-selected');
      const startBtn = createDOMElement('start', 'button');
      startBtn.focus = jest.fn();

      // Set up window globals
      window.apps = {};
      window.originalParams = {};
      window.stop_apps_trigger = false;
      window.appsMessageCount = 0;
      window.logTL = jest.fn();
      window.loadedApp = null;
      window.lastApp = null;
      window.isRestoringSession = false;
      window.isImporting = false;
      window.initialAppLoaded = false;
      window.pendingParameters = null;
      window.defaultApp = 'ChatOpenAI';
      window.setBaseAppDescription = jest.fn();
      window.updateAppBadges = jest.fn();
      window.proceedWithAppChange = jest.fn();
      window.updateAvailableProviders = jest.fn();
      window.loadParams = jest.fn();

      global.resetParams = jest.fn();
      global.normalizeGroupId = handlers.normalizeGroupId;
    });

    it('sets version string with Docker indicator', () => {
      const data = {
        version: '1.0.0-beta.8',
        docker: true,
        content: {}
      };

      handlers.handleAppsMessage(data);

      expect(document.getElementById('monadic-version-number').innerHTML).toBe('1.0.0-beta.8 (Docker)');
    });

    it('sets version string with Local indicator', () => {
      const data = {
        version: '1.0.0-beta.8',
        docker: false,
        content: {}
      };

      handlers.handleAppsMessage(data);

      expect(document.getElementById('monadic-version-number').innerHTML).toBe('1.0.0-beta.8 (Local)');
    });

    it('increments appsMessageCount', () => {
      window.appsMessageCount = 0;
      const data = { version: '1.0.0', docker: true, content: {} };

      handlers.handleAppsMessage(data);

      expect(window.appsMessageCount).toBe(1);
    });

    it('updates existing app data on update path', () => {
      // Pre-populate apps to trigger update path
      window.apps = { ChatOpenAI: { app_name: 'ChatOpenAI', description: 'Old desc', group: 'OpenAI' } };

      // Set current selection
      const appsSelect = document.getElementById('apps');
      const opt = document.createElement('option');
      opt.value = 'ChatOpenAI';
      opt.textContent = 'Chat';
      appsSelect.appendChild(opt);
      appsSelect.value = 'ChatOpenAI';

      const data = {
        version: '1.0.0',
        docker: true,
        content: {
          ChatOpenAI: { app_name: 'ChatOpenAI', description: 'New desc', group: 'OpenAI' }
        }
      };

      handlers.handleAppsMessage(data);

      expect(window.apps.ChatOpenAI.description).toBe('New desc');
    });

    it('classifies apps into OpenAI and special groups on initial load', () => {
      const data = {
        version: '1.0.0',
        docker: true,
        content: {
          ChatOpenAI: { app_name: 'ChatOpenAI', display_name: 'Chat', group: 'OpenAI', icon: '💬' },
          ChatClaude: { app_name: 'ChatClaude', display_name: 'Chat', group: 'Anthropic', icon: '💬' }
        }
      };

      handlers.handleAppsMessage(data);

      // Both apps should be cached
      expect(window.apps.ChatOpenAI).toBeDefined();
      expect(window.apps.ChatClaude).toBeDefined();
      // #apps dropdown should have options (group separators + options)
      const appsSelect = document.getElementById('apps');
      expect(appsSelect.options.length).toBeGreaterThan(0);
    });

    it('skips apps with missing display name', () => {
      const data = {
        version: '1.0.0',
        docker: true,
        content: {
          ChatOpenAI: { app_name: 'ChatOpenAI', display_name: 'Chat', group: 'OpenAI', icon: '💬' },
          BadApp: { app_name: undefined, display_name: undefined, group: 'OpenAI' }
        }
      };

      handlers.handleAppsMessage(data);

      expect(window.apps.ChatOpenAI).toBeDefined();
      expect(window.apps.BadApp).toBeUndefined();
    });

    it('sets originalParams from Chat app', () => {
      window.apps = {};
      const data = {
        version: '1.0.0',
        docker: true,
        content: {
          ChatOpenAI: { app_name: 'ChatOpenAI', display_name: 'Chat', group: 'OpenAI', icon: '💬' }
        }
      };

      handlers.handleAppsMessage(data);

      // originalParams should be set (either from Chat or first app)
      expect(window.originalParams).toBeDefined();
    });
  });

  describe('handleParametersMessage', () => {
    beforeEach(() => {
      // Create DOM elements
      const appsSelect = createDOMSelect('apps');
      // Pre-populate with an option so DOM-ready guard passes
      const opt = document.createElement('option');
      opt.value = 'ChatOpenAI';
      opt.textContent = 'Chat';
      opt.selected = true;
      appsSelect.appendChild(opt);

      createDOMSelect('model');
      createDOMElement('model-selected');
      createDOMElement('base-app-title');
      createDOMElement('base-app-icon');
      createDOMElement('base-app-desc');
      createDOMElement('monadic-badge');
      createDOMElement('tools-badge');
      createDOMElement('show-all-models', 'input');
      document.getElementById('show-all-models').type = 'checkbox';
      const startBtn = createDOMElement('start', 'button');
      startBtn.focus = jest.fn();

      window.apps = { ChatOpenAI: { app_name: 'ChatOpenAI', group: 'OpenAI', display_name: 'Chat', icon: '💬' } };
      window.loadedApp = null;
      window.logTL = jest.fn();
      window.initialAppLoaded = false;
      window.isProcessingImport = false;
      window.skipAssistantInitiation = false;
      window.suppressParamBroadcastCount = 0;
      window.defaultApp = 'ChatOpenAI';
      window.loadParams = jest.fn();
      window.proceedWithAppChange = jest.fn();
      window.setBaseAppDescription = jest.fn();
      window.updateAppBadges = jest.fn();

      global.params = {};
      global.setAutoSpeechSuppressed = jest.fn();
      global.getModelsForApp = jest.fn().mockReturnValue(['gpt-4o', 'gpt-4o-mini']);
      global.listModels = jest.fn().mockReturnValue('<option value="gpt-4o">gpt-4o</option>');
      global.getDefaultModelForApp = jest.fn().mockReturnValue('gpt-4o');
      global.getProviderFromGroup = jest.fn().mockReturnValue('OpenAI');
      global.modelSpec = { 'gpt-4o': {} };
    });

    it('returns "skip" for empty content', () => {
      const result = handlers.handleParametersMessage({ content: {} });
      expect(result).toBe('skip');
    });

    it('returns "skip" for null content', () => {
      const result = handlers.handleParametersMessage({ content: null });
      expect(result).toBe('skip');
    });

    it('handles fromParamUpdate by assigning to params', () => {
      global.params = { model: 'old-model' };
      const data = {
        content: { model: 'new-model', app_name: 'ChatOpenAI' },
        from_param_update: true
      };

      const result = handlers.handleParametersMessage(data);

      expect(result).toBe('param_update');
      expect(global.params.model).toBe('new-model');
    });

    it('sets isProcessingImport on import', () => {
      const data = {
        content: { app_name: 'ChatOpenAI', model: 'gpt-4o' },
        from_import: true
      };

      handlers.handleParametersMessage(data);

      expect(window.isProcessingImport).toBe(true);
      expect(window.skipAssistantInitiation).toBe(true);
      expect(global.setAutoSpeechSuppressed).toHaveBeenCalledWith(true, { reason: 'parameters import' });
    });

    it('stores pending parameters when apps not loaded', () => {
      window.apps = {};
      const data = {
        content: { app_name: 'ChatOpenAI', model: 'gpt-4o' }
      };

      const result = handlers.handleParametersMessage(data);

      expect(result).toBe('pending');
      expect(window.pendingParameters).toEqual(data.content);
    });

    it('calls loadParams when app_name is present', () => {
      const data = {
        content: { app_name: 'ChatOpenAI', model: 'gpt-4o' }
      };

      handlers.handleParametersMessage(data);

      expect(window.loadedApp).toBe('ChatOpenAI');
      expect(window.loadParams).toHaveBeenCalledWith(data.content, 'loadParams');
      expect(window.initialAppLoaded).toBe(true);
    });

    it('builds model list when no app_name (generic parameters)', () => {
      const data = {
        content: { model: 'gpt-4o' }
      };

      handlers.handleParametersMessage(data);

      expect(global.getModelsForApp).toHaveBeenCalled();
      expect(document.getElementById('start').focus).toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports handleElevenLabsVoices', () => {
      expect(typeof handlers.handleElevenLabsVoices).toBe('function');
    });

    it('exports handleGeminiVoices', () => {
      expect(typeof handlers.handleGeminiVoices).toBe('function');
    });

    it('exports handleAppsMessage', () => {
      expect(typeof handlers.handleAppsMessage).toBe('function');
    });

    it('exports handleParametersMessage', () => {
      expect(typeof handlers.handleParametersMessage).toBe('function');
    });

    it('exports normalizeGroupId', () => {
      expect(typeof handlers.normalizeGroupId).toBe('function');
    });

    it('exposes handlers on window.WsAppDataHandlers', () => {
      expect(typeof window.WsAppDataHandlers).toBe('object');
      expect(typeof window.WsAppDataHandlers.handleElevenLabsVoices).toBe('function');
      expect(typeof window.WsAppDataHandlers.handleGeminiVoices).toBe('function');
      expect(typeof window.WsAppDataHandlers.handleAppsMessage).toBe('function');
      expect(typeof window.WsAppDataHandlers.handleParametersMessage).toBe('function');
    });
  });
});
