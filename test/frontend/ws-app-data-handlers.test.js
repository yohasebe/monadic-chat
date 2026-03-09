/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-app-data-handlers.js
 *
 * Tests the extracted WebSocket message handlers for:
 * - handleElevenLabsVoices: Populate ElevenLabs TTS voice selector
 * - handleGeminiVoices: Populate Gemini TTS voice selector
 */

// Track prop calls per selector for verification
const propCalls = {};
const valCalls = {};
const triggerCalls = {};

function createSelectElement(id) {
  const options = [];
  let selectedValue = null;

  return {
    _options: options,
    empty: jest.fn(function () { options.length = 0; return this; }),
    append: jest.fn(function (html) {
      // Parse option HTML to extract value and text
      const match = html.match(/value="([^"]*)"[^>]*>([^<]*)</);
      if (match) {
        options.push({ value: match[1], text: match[2], selected: html.includes('selected') });
        if (html.includes('selected')) selectedValue = match[1];
      }
      return this;
    }),
    val: jest.fn(function (v) {
      if (v === undefined) return selectedValue;
      // Check if option exists
      const found = options.find(o => o.value === v);
      if (found) selectedValue = v;
      valCalls[id] = v;
      return this;
    }),
    prop: jest.fn(function (name, value) {
      if (!propCalls[id]) propCalls[id] = {};
      propCalls[id][name] = value;
      return this;
    }),
    trigger: jest.fn(function (event) {
      triggerCalls[id] = event;
      return this;
    }),
    length: 1
  };
}

// Build mock elements
let mockElements;

function setupMockElements() {
  mockElements = {
    '#elevenlabs-tts-voice': createSelectElement('elevenlabs-tts-voice'),
    '#gemini-tts-voice': createSelectElement('gemini-tts-voice'),
    '#tts-provider': createSelectElement('tts-provider'),
    '#elevenlabs-flash-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-multilingual-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-v3-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe-v2': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#elevenlabs-stt-scribe-experimental': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-flash-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-pro-provider-option': { prop: jest.fn().mockReturnThis(), length: 1 },
    '#gemini-stt-flash': { prop: jest.fn().mockReturnThis(), length: 1 }
  };
}

beforeEach(() => {
  setupMockElements();

  // Clear tracking
  Object.keys(propCalls).forEach(k => delete propCalls[k]);
  Object.keys(valCalls).forEach(k => delete valCalls[k]);
  Object.keys(triggerCalls).forEach(k => delete triggerCalls[k]);

  // Mock jQuery
  global.$ = jest.fn().mockImplementation(selector => {
    // Handle "#apps option" selector to return option count with jQuery methods
    if (selector === '#apps option') {
      const appsEl = mockElements['#apps'];
      const len = appsEl && appsEl._options ? appsEl._options.length : 0;
      const noop = jest.fn().mockReturnValue({ length: 0, first: jest.fn().mockReturnValue({ val: jest.fn(), length: 0 }) });
      return { length: len, filter: noop, first: jest.fn().mockReturnValue({ val: jest.fn(), length: 0 }) };
    }

    // Handle attribute selector for option existence check
    if (typeof selector === 'string' && selector.includes('option[value=')) {
      // Extract the voice ID from the selector
      const match = selector.match(/option\[value="([^"]+)"\]/);
      if (match) {
        const voiceId = match[1];
        // Check if option exists in any select
        for (const key of Object.keys(mockElements)) {
          const el = mockElements[key];
          if (el._options) {
            const found = el._options.find(o => o.value === voiceId);
            if (found) return { length: 1 };
          }
        }
      }
      return { length: 0 };
    }
    // Default mock element with all common jQuery methods
    return mockElements[selector] || {
      prop: jest.fn().mockReturnThis(),
      val: jest.fn().mockReturnThis(),
      trigger: jest.fn().mockReturnThis(),
      append: jest.fn().mockReturnThis(),
      html: jest.fn().mockReturnThis(),
      text: jest.fn().mockReturnThis(),
      show: jest.fn().mockReturnThis(),
      hide: jest.fn().mockReturnThis(),
      empty: jest.fn().mockReturnThis(),
      focus: jest.fn().mockReturnThis(),
      on: jest.fn().mockReturnThis(),
      data: jest.fn().mockReturnValue(null),
      find: jest.fn().mockReturnValue({
        removeClass: jest.fn().mockReturnThis(),
        addClass: jest.fn().mockReturnThis()
      }),
      parent: jest.fn().mockReturnValue({
        length: 0,
        removeClass: jest.fn().mockReturnThis(),
        attr: jest.fn().mockReturnValue('')
      }),
      toggleClass: jest.fn().mockReturnThis(),
      hasClass: jest.fn().mockReturnValue(false),
      removeClass: jest.fn().mockReturnThis(),
      addClass: jest.fn().mockReturnThis(),
      attr: jest.fn().mockReturnValue(''),
      first: jest.fn().mockReturnValue({ length: 0, val: jest.fn().mockReturnValue(null) }),
      filter: jest.fn().mockReturnValue({
        length: 0,
        first: jest.fn().mockReturnValue({ length: 0, val: jest.fn().mockReturnValue(null) })
      }),
      is: jest.fn().mockReturnValue(false),
      length: 0
    };
  });

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
    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'v1', name: 'Rachel' },
          { voice_id: 'v2', name: 'Drew' }
        ]
      };

      handlers.handleElevenLabsVoices(data);

      const el = mockElements['#elevenlabs-tts-voice'];
      expect(el.empty).toHaveBeenCalled();
      expect(el.append).toHaveBeenCalledTimes(2);
      expect(el._options).toHaveLength(2);
      expect(el._options[0].value).toBe('v1');
      expect(el._options[0].text).toBe('Rachel');
      expect(el._options[1].value).toBe('v2');
      expect(el._options[1].text).toBe('Drew');
    });

    it('enables TTS and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      // TTS provider options should be enabled
      expect(mockElements['#elevenlabs-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-multilingual-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-v3-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      // STT options should be enabled
      expect(mockElements['#elevenlabs-stt-scribe-v2'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#elevenlabs-stt-scribe'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleElevenLabsVoices(data);

      expect(mockElements['#elevenlabs-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-multilingual-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-v3-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#elevenlabs-stt-scribe-v2'].prop).toHaveBeenCalledWith('disabled', true);
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

      // v2 should be selected
      expect(mockElements['#elevenlabs-tts-voice'].val).toHaveBeenCalledWith('v2');
    });

    it('restores saved provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'elevenlabs-flash';
        return null;
      });

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      expect(mockElements['#tts-provider'].val).toHaveBeenCalledWith('elevenlabs-flash');
    });

    it('does not restore non-elevenlabs provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = {
        content: [{ voice_id: 'v1', name: 'Rachel' }]
      };

      handlers.handleElevenLabsVoices(data);

      // Should not try to set a non-elevenlabs provider
      expect(mockElements['#tts-provider'].val).not.toHaveBeenCalled();
    });
  });

  describe('handleGeminiVoices', () => {
    it('populates voice selector with voices', () => {
      const data = {
        content: [
          { voice_id: 'Aoede', name: 'Aoede' },
          { voice_id: 'Charon', name: 'Charon' }
        ]
      };

      handlers.handleGeminiVoices(data);

      const el = mockElements['#gemini-tts-voice'];
      expect(el.empty).toHaveBeenCalled();
      expect(el._options).toHaveLength(2);
      expect(el._options[0].value).toBe('Aoede');
      expect(el._options[1].value).toBe('Charon');
    });

    it('enables provider and STT options when voices are available', () => {
      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#gemini-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#gemini-pro-provider-option'].prop).toHaveBeenCalledWith('disabled', false);
      expect(mockElements['#gemini-stt-flash'].prop).toHaveBeenCalledWith('disabled', false);
    });

    it('disables all options when no voices', () => {
      const data = { content: [] };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#gemini-flash-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#gemini-pro-provider-option'].prop).toHaveBeenCalledWith('disabled', true);
      expect(mockElements['#gemini-stt-flash'].prop).toHaveBeenCalledWith('disabled', true);
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

      expect(mockElements['#gemini-tts-voice'].val).toHaveBeenCalledWith('Charon');
    });

    it('restores saved gemini provider from cookie', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'gemini-flash';
        return null;
      });

      const data = {
        content: [{ voice_id: 'Aoede', name: 'Aoede' }]
      };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#tts-provider'].val).toHaveBeenCalledWith('gemini-flash');
    });

    it('does not restore non-gemini provider', () => {
      global.getCookie = jest.fn((name) => {
        if (name === 'tts-provider') return 'openai-tts-4o';
        return null;
      });

      const data = { content: [{ voice_id: 'Aoede', name: 'Aoede' }] };

      handlers.handleGeminiVoices(data);

      expect(mockElements['#tts-provider'].val).not.toHaveBeenCalled();
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
      // Set up additional mock elements needed for apps handler
      mockElements['#monadic-version-number'] = { html: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#apps'] = createSelectElement('apps');
      mockElements['#custom-apps-dropdown'] = { append: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-title'] = { text: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-icon'] = { html: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-desc'] = { html: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#monadic-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#websearch-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#tools-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#math-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#show-all-models'] = { prop: jest.fn().mockReturnValue(false), length: 1 };
      const modelEl = createSelectElement('model');
      modelEl.html = jest.fn().mockReturnThis();
      mockElements['#model'] = modelEl;
      mockElements['#model-selected'] = { text: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#start'] = { focus: jest.fn().mockReturnThis(), length: 1 };

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

      expect(mockElements['#monadic-version-number'].html).toHaveBeenCalledWith('1.0.0-beta.8 (Docker)');
    });

    it('sets version string with Local indicator', () => {
      const data = {
        version: '1.0.0-beta.8',
        docker: false,
        content: {}
      };

      handlers.handleAppsMessage(data);

      expect(mockElements['#monadic-version-number'].html).toHaveBeenCalledWith('1.0.0-beta.8 (Local)');
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

      const data = {
        version: '1.0.0',
        docker: true,
        content: {
          ChatOpenAI: { app_name: 'ChatOpenAI', description: 'New desc', group: 'OpenAI' }
        }
      };

      // Mock #apps to return current app
      mockElements['#apps'].val = jest.fn(function(v) {
        if (v === undefined) return 'ChatOpenAI';
        return this;
      });

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
      // #apps dropdown should have been appended to (group separators + options)
      expect(mockElements['#apps'].append).toHaveBeenCalled();
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
      // Set up mock elements for parameters handler
      mockElements['#apps'] = createSelectElement('apps');
      // Pre-populate with an option so DOM-ready guard passes
      mockElements['#apps']._options.push({ value: 'ChatOpenAI', text: 'Chat', selected: true });
      const modelEl = createSelectElement('model');
      modelEl.html = jest.fn().mockReturnThis();
      mockElements['#model'] = modelEl;
      mockElements['#model-selected'] = { text: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-title'] = { text: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-icon'] = { html: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#base-app-desc'] = { html: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#monadic-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#tools-badge'] = { show: jest.fn().mockReturnThis(), hide: jest.fn().mockReturnThis(), length: 1 };
      mockElements['#show-all-models'] = { prop: jest.fn().mockReturnValue(false), length: 1 };
      mockElements['#start'] = { focus: jest.fn().mockReturnThis(), length: 1 };

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
      mockElements['#apps'].val = jest.fn(function(v) {
        if (v === undefined) return 'ChatOpenAI';
        return this;
      });

      const data = {
        content: { model: 'gpt-4o' }
      };

      handlers.handleParametersMessage(data);

      expect(global.getModelsForApp).toHaveBeenCalled();
      expect(mockElements['#start'].focus).toHaveBeenCalled();
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
