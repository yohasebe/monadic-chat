/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-session-handler.js
 *
 * Tests session-level WebSocket handlers:
 * - Context panel updates
 * - Language changes with RTL support
 * - System info/processing status display
 * - STT completion
 * - PDF management
 * - Message status changes
 * - Success/sample notifications
 */

function createMockElement(id) {
  return {
    prop: jest.fn().mockReturnThis(),
    val: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    html: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    text: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    attr: jest.fn().mockReturnThis(),
    css: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    hide: jest.fn().mockReturnThis(),
    is: jest.fn().mockReturnValue(false),
    append: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    on: jest.fn().mockReturnThis(),
    off: jest.fn().mockReturnThis(),
    click: jest.fn().mockReturnThis(),
    data: jest.fn().mockReturnValue(null),
    find: jest.fn().mockReturnValue({
      length: 1,
      addClass: jest.fn().mockReturnThis(),
      removeClass: jest.fn().mockReturnThis()
    }),
    addClass: jest.fn().mockReturnThis(),
    removeClass: jest.fn().mockReturnThis(),
    modal: jest.fn().mockReturnThis(),
    length: 1,
    0: document.createElement('div'),
    get: jest.fn().mockReturnValue(document.createElement('div'))
  };
}

let mockElements;

function setupMockElements() {
  mockElements = {
    '#discourse': createMockElement('discourse'),
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#conversation-language': createMockElement('conversation-language'),
    '#message': createMockElement('message'),
    '#asr-p-value': createMockElement('asr-p-value'),
    '#send, #clear, #voice': createMockElement('send-clear-voice'),
    '#amplitude': createMockElement('amplitude'),
    '#check-easy-submit': createMockElement('check-easy-submit'),
    '#send': createMockElement('send'),
    '#pdf-titles': createMockElement('pdf-titles')
  };
}

beforeEach(() => {
  setupMockElements();

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    // For dynamically created elements
    if (typeof selector === 'string' && selector.startsWith('<')) {
      const el = createMockElement('dynamic');
      el[0] = document.createElement('div');
      el[0].outerHTML = selector;
      return el;
    }
    return createMockElement('default');
  });

  // Mock DOM for cancel button
  const cancelButton = document.createElement('div');
  cancelButton.id = 'cancel_query';
  document.body.appendChild(cancelButton);

  // Mock global functions
  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.createCard = jest.fn().mockReturnValue($('<div></div>'));
  global.isElementInViewport = jest.fn().mockReturnValue(true);
  global.setInputFocus = jest.fn();

  // Mock global objects
  global.ContextPanel = {
    showLoading: jest.fn(),
    hideLoading: jest.fn(),
    updateContext: jest.fn()
  };
  global.WorkflowViewer = {
    setStage: jest.fn()
  };

  // Window globals
  window.autoScroll = true;
  window.chatBottom = { scrollIntoView: jest.fn() };
  window.debugWebSocket = false;
  window.ws = { send: jest.fn() };
  window.MarkdownRenderer = {
    render: jest.fn().mockReturnValue('<p>rendered</p>'),
    applyRenderers: jest.fn()
  };
  window.currentSampleTimeout = null;
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-session-handler');

describe('ws-session-handler', () => {
  describe('handleContextExtractionStarted', () => {
    it('shows context panel loading state', () => {
      handlers.handleContextExtractionStarted({});
      expect(global.ContextPanel.showLoading).toHaveBeenCalled();
    });
  });

  describe('handleContextUpdate', () => {
    it('updates context panel with data and schema', () => {
      const data = { context: { key: 'value' }, schema: { type: 'object' } };
      handlers.handleContextUpdate(data);

      expect(global.ContextPanel.hideLoading).toHaveBeenCalled();
      expect(global.ContextPanel.updateContext).toHaveBeenCalledWith(
        { key: 'value' },
        { type: 'object' }
      );
    });

    it('updates workflow viewer stage', () => {
      handlers.handleContextUpdate({ context: {} });
      expect(global.WorkflowViewer.setStage).toHaveBeenCalledWith('context');
    });
  });

  describe('handleLanguageUpdated', () => {
    it('shows success alert with language name', () => {
      handlers.handleLanguageUpdated({ language_name: 'Japanese', language: 'ja' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Japanese'),
        'success'
      );
    });

    it('adds rtl-messages class for RTL languages', () => {
      const bodyMock = createMockElement('body');
      global.$ = jest.fn().mockImplementation(selector => {
        if (selector === 'body') return bodyMock;
        return mockElements[selector] || createMockElement('default');
      });

      handlers.handleLanguageUpdated({ language: 'ar', text_direction: 'rtl' });

      expect(bodyMock.addClass).toHaveBeenCalledWith('rtl-messages');
    });

    it('removes rtl-messages class for LTR languages', () => {
      const bodyMock = createMockElement('body');
      global.$ = jest.fn().mockImplementation(selector => {
        if (selector === 'body') return bodyMock;
        return mockElements[selector] || createMockElement('default');
      });

      handlers.handleLanguageUpdated({ language: 'en', text_direction: 'ltr' });

      expect(bodyMock.removeClass).toHaveBeenCalledWith('rtl-messages');
    });
  });

  describe('handleProcessingStatus', () => {
    it('shows info alert with content', () => {
      handlers.handleProcessingStatus({ content: 'Processing...' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Processing...'),
        'info'
      );
    });

    it('creates a system card', () => {
      handlers.handleProcessingStatus({ content: 'Working...' });

      expect(global.createCard).toHaveBeenCalledWith(
        'system',
        expect.any(String),
        expect.any(String),
        'en',
        null,
        true,
        []
      );
    });
  });

  describe('handleSystemInfo', () => {
    it('creates a system info card and appends to discourse', () => {
      handlers.handleSystemInfo({ content: 'System update' });

      expect(global.createCard).toHaveBeenCalled();
      expect(mockElements['#discourse'].append).toHaveBeenCalled();
    });

    it('handles object content by stringifying', () => {
      handlers.handleSystemInfo({ content: { key: 'value' } });

      expect(global.createCard).toHaveBeenCalled();
    });
  });

  describe('handleSTT', () => {
    it('appends transcribed text to message field', () => {
      mockElements['#message'].val = jest.fn(function(v) {
        if (v === undefined) return 'existing';
        return this;
      });

      handlers.handleSTT({ content: 'hello', logprob: 0.95 });

      expect(mockElements['#message'].val).toHaveBeenCalledWith('existing hello');
    });

    it('shows voice recognition finished alert', () => {
      handlers.handleSTT({ content: 'text', logprob: 0.9 });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Voice recognition finished'),
        'secondary'
      );
    });

    it('focuses input after completion', () => {
      handlers.handleSTT({ content: 'text', logprob: 0.9 });

      expect(global.setInputFocus).toHaveBeenCalled();
    });
  });

  describe('handlePDFTitles', () => {
    it('renders PDF titles as rows', () => {
      handlers.handlePDFTitles({ content: ['doc1.pdf', 'doc2.pdf'] });

      expect(mockElements['#pdf-titles'].html).toHaveBeenCalledWith(
        expect.stringContaining('doc1.pdf')
      );
    });

    it('renders empty state when no PDFs', () => {
      handlers.handlePDFTitles({ content: [] });

      expect(mockElements['#pdf-titles'].html).toHaveBeenCalledWith(
        expect.stringContaining('No PDFs imported')
      );
    });

    it('escapes HTML in titles', () => {
      handlers.handlePDFTitles({ content: ['<script>xss</script>'] });

      const htmlArg = mockElements['#pdf-titles'].html.mock.calls[0][0];
      expect(htmlArg).toContain('&lt;script');
      expect(htmlArg).not.toContain('<script>xss');
    });
  });

  describe('handlePDFDeleted', () => {
    it('shows success alert and refreshes list', () => {
      handlers.handlePDFDeleted({ res: 'success', content: 'Deleted doc.pdf' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Deleted doc.pdf'),
        'info'
      );
      expect(window.ws.send).toHaveBeenCalledWith(
        JSON.stringify({ message: 'PDF_TITLES' })
      );
    });

    it('shows error alert on failure', () => {
      handlers.handlePDFDeleted({ res: 'error', content: 'Failed to delete' });

      expect(global.setAlert).toHaveBeenCalledWith('Failed to delete', 'error');
    });
  });

  describe('handleChangeStatus', () => {
    it('adds active class for active messages', () => {
      const statusMock = { addClass: jest.fn().mockReturnThis(), removeClass: jest.fn().mockReturnThis() };
      const cardMock = createMockElement('card');
      cardMock.find = jest.fn().mockReturnValue(statusMock);

      global.$ = jest.fn().mockImplementation(selector => {
        if (selector === '#msg-1') return cardMock;
        return createMockElement('default');
      });

      handlers.handleChangeStatus({ content: [{ mid: 'msg-1', active: true }] });

      expect(statusMock.addClass).toHaveBeenCalledWith('active');
    });

    it('removes active class for inactive messages', () => {
      const statusMock = { addClass: jest.fn().mockReturnThis(), removeClass: jest.fn().mockReturnThis() };
      const cardMock = createMockElement('card');
      cardMock.find = jest.fn().mockReturnValue(statusMock);

      global.$ = jest.fn().mockImplementation(selector => {
        if (selector === '#msg-2') return cardMock;
        return createMockElement('default');
      });

      handlers.handleChangeStatus({ content: [{ mid: 'msg-2', active: false }] });

      expect(statusMock.removeClass).toHaveBeenCalledWith('active');
    });
  });

  describe('handleSuccess', () => {
    it('shows success alert with content', () => {
      handlers.handleSuccess({ content: 'Operation completed' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Operation completed'),
        'success'
      );
    });
  });

  describe('handleSampleSuccess', () => {
    it('clears sample timeout', () => {
      window.currentSampleTimeout = setTimeout(() => {}, 10000);
      const timeoutId = window.currentSampleTimeout;

      handlers.handleSampleSuccess({ role: 'assistant' });

      expect(window.currentSampleTimeout).toBeNull();
    });

    it('hides spinner and cancel button', () => {
      handlers.handleSampleSuccess({ role: 'user' });

      expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
      const cancelButton = document.getElementById('cancel_query');
      expect(cancelButton.style.display).toBe('none');
    });

    it('shows success alert', () => {
      handlers.handleSampleSuccess({ role: 'assistant' });

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Sample message added'),
        'success'
      );
    });
  });

  describe('module exports', () => {
    it('exports all handlers', () => {
      const expectedHandlers = [
        'handleContextExtractionStarted', 'handleContextUpdate',
        'handleLanguageUpdated', 'handleProcessingStatus', 'handleSystemInfo',
        'handleSTT', 'handlePDFTitles', 'handlePDFDeleted',
        'handleChangeStatus', 'handleSuccess', 'handleSampleSuccess'
      ];
      expectedHandlers.forEach(name => {
        expect(typeof handlers[name]).toBe('function');
      });
    });

    it('exposes handlers on window.WsSessionHandler', () => {
      expect(typeof window.WsSessionHandler).toBe('object');
      expect(typeof window.WsSessionHandler.handleSuccess).toBe('function');
    });
  });
});
