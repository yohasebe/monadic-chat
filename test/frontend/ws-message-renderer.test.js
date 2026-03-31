/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-message-renderer.js
 *
 * Tests the extracted WebSocket message handlers for:
 * - handlePastMessages: Restore and render chat history
 * - handleEditSuccess: Apply edited message content
 * - handleDisplaySample: Render sample messages
 */

beforeEach(() => {
  // Set up real DOM elements for getElementById calls
  document.body.innerHTML = `
    <div id="discourse"></div>
    <select id="apps"></select>
    <select id="model"></select>
    <span id="start-label"></span>
  `;

  // Mock global functions
  global.createCard = jest.fn().mockImplementation(() => {
    return document.createElement('div');
  });
  global.renderMessage = jest.fn().mockReturnValue('<p>rendered</p>');
  global.formatInfo = jest.fn().mockReturnValue('info html');
  global.setStats = jest.fn();
  global.setAlert = jest.fn();
  global.setAutoSpeechSuppressed = jest.fn();
  global.isAutoSpeechSuppressed = jest.fn().mockReturnValue(false);
  global.applyToggle = jest.fn();
  global.applyMermaid = jest.fn();
  global.applyDrawIO = jest.fn();
  global.applyMathJax = jest.fn();
  global.applyAbc = jest.fn();
  global.formatSourceCode = jest.fn();
  global.cleanupListCodeBlocks = jest.fn();
  global.setCopyCodeButton = jest.fn();
  global.isElementInViewport = jest.fn().mockReturnValue(true);
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.params = {};
  global.mids = { clear: jest.fn(), add: jest.fn() };

  // Window globals
  window.messages = [];
  window.params = {};
  window.autoScroll = true;
  window.chatBottom = document.createElement('div');
  window.initialLoadComplete = false;
  window.isRestoringSession = true;
  window.isProcessingImport = false;
  window.skipAssistantInitiation = false;
  window.debugWebSocket = false;
  window.logTL = jest.fn();
  window.i18nReady = Promise.resolve();
  window.updateAIUserButtonState = jest.fn();
  window.MarkdownRenderer = {
    render: jest.fn().mockReturnValue('<p>rendered</p>'),
    applyRenderers: jest.fn()
  };
  window.SessionState = {
    clearMessages: jest.fn(),
    addMessage: jest.fn(),
    setCurrentApp: jest.fn(),
    clearResetFlags: jest.fn(),
    app: {}
  };
  window.toBool = (value) => {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') return value === 'true';
    return !!value;
  };
});

afterEach(() => {
  jest.restoreAllMocks();
});

// Load the module
const handlers = require('../../docker/services/ruby/public/js/monadic/ws-message-renderer');

describe('ws-message-renderer', () => {
  describe('handlePastMessages', () => {
    it('renders user and assistant messages from history', () => {
      const data = {
        content: [
          { role: 'system', text: 'You are helpful', mid: 'sys-1' },
          { role: 'user', text: 'Hello', mid: 'u-1', active: true },
          { role: 'assistant', text: 'Hi there!', mid: 'a-1', active: true }
        ]
      };

      handlers.handlePastMessages(data);

      // Should clear discourse (innerHTML = '')
      const discourseEl = document.getElementById('discourse');
      // discourse was cleared then cards appended
      expect(discourseEl).not.toBeNull();
      // Should clear mids
      expect(global.mids.clear).toHaveBeenCalled();
      // Should create cards for user and assistant (not system at index 0)
      expect(global.createCard).toHaveBeenCalledTimes(2);
      // Should add mids
      expect(global.mids.add).toHaveBeenCalledTimes(3);
    });

    it('sets isRestoringSession to false', () => {
      window.isRestoringSession = true;

      handlers.handlePastMessages({ content: [] });

      expect(window.isRestoringSession).toBe(false);
    });

    it('syncs with SessionState', () => {
      const data = {
        content: [
          { role: 'user', text: 'test', mid: 'u-1' }
        ]
      };

      handlers.handlePastMessages(data);

      expect(window.SessionState.clearMessages).toHaveBeenCalled();
      expect(window.SessionState.addMessage).toHaveBeenCalled();
    });

    it('sets initialLoadComplete to true', () => {
      window.initialLoadComplete = false;

      handlers.handlePastMessages({ content: [] });

      expect(window.initialLoadComplete).toBe(true);
    });

    it('suppresses auto speech on import', () => {
      handlers.handlePastMessages({ content: [], from_import: true });

      expect(global.setAutoSpeechSuppressed).toHaveBeenCalledWith(true, { reason: 'past_messages import' });
      // isProcessingImport is set to true during import, then cleared at end of handlePastMessages
      // So we verify the suppression call happened instead
      expect(window.skipAssistantInitiation).toBe(true);
    });

    it('updates AI User button state', () => {
      const messages = [
        { role: 'user', text: 'Hello', mid: 'u-1' }
      ];

      handlers.handlePastMessages({ content: messages });

      expect(window.updateAIUserButtonState).toHaveBeenCalledWith(messages);
    });

    it('assigns restored mids for messages without mid', () => {
      const data = {
        content: [
          { role: 'user', text: 'No mid' }
        ]
      };

      handlers.handlePastMessages(data);

      // The message should have gotten a generated mid
      expect(global.mids.add).toHaveBeenCalled();
      const addedMid = global.mids.add.mock.calls[0][0];
      expect(addedMid).toMatch(/^restored-/);
    });
  });

  describe('handleEditSuccess', () => {
    it('shows success alert', () => {
      // Create a card element in the DOM with a .card-text child
      const cardEl = document.createElement('div');
      cardEl.id = 'msg-1';
      const cardText = document.createElement('div');
      cardText.className = 'card-text';
      cardEl.appendChild(cardText);
      document.body.appendChild(cardEl);

      const data = {
        content: 'Message updated',
        mid: 'msg-1',
        html: '<p>Updated text</p>'
      };

      handlers.handleEditSuccess(data);

      expect(global.setAlert).toHaveBeenCalledWith(
        expect.stringContaining('Message updated'),
        'success'
      );
    });

    it('returns early if card not found', () => {
      const data = { content: 'Updated', mid: 'msg-missing', html: '<p>text</p>' };

      // Should not throw
      handlers.handleEditSuccess(data);
    });

    it('applies renderers to updated content', () => {
      // Create a card element in the DOM with a .card-text child
      const cardEl = document.createElement('div');
      cardEl.id = 'msg-1';
      const cardText = document.createElement('div');
      cardText.className = 'card-text';
      cardEl.appendChild(cardText);
      document.body.appendChild(cardEl);

      const data = {
        content: 'Updated',
        mid: 'msg-1',
        html: '<p>New content</p>'
      };

      handlers.handleEditSuccess(data);

      expect(cardText.innerHTML).toBe('<p>New content</p>');
      expect(window.MarkdownRenderer.applyRenderers).toHaveBeenCalled();
    });
  });

  describe('handleDisplaySample', () => {
    it('creates and appends a card for the sample message', () => {
      const data = {
        content: {
          mid: 'sample-1',
          role: 'assistant',
          text: 'Sample response',
          badge: '<span>Assistant</span>'
        }
      };

      handlers.handleDisplaySample(data);

      expect(global.createCard).toHaveBeenCalledWith(
        'assistant',
        '<span>Assistant</span>',
        expect.any(String),
        'en',
        'sample-1',
        true
      );
      expect(window.SessionState.addMessage).toHaveBeenCalled();
    });

    it('skips if message already exists', () => {
      // Create a real DOM element with the existing id
      const existingEl = document.createElement('div');
      existingEl.id = 'existing-1';
      document.body.appendChild(existingEl);

      const data = {
        content: {
          mid: 'existing-1',
          role: 'user',
          text: 'Existing',
          badge: '<span>User</span>'
        }
      };

      handlers.handleDisplaySample(data);

      expect(global.createCard).not.toHaveBeenCalled();
    });

    it('skips if content is invalid', () => {
      handlers.handleDisplaySample({ content: null });
      expect(global.createCard).not.toHaveBeenCalled();

      handlers.handleDisplaySample({ content: { mid: 'x' } });
      expect(global.createCard).not.toHaveBeenCalled();
    });

    it('uses MarkdownRenderer for assistant messages', () => {
      const data = {
        content: {
          mid: 'sample-2',
          role: 'assistant',
          text: '**bold**',
          badge: '<span>Assistant</span>'
        }
      };

      handlers.handleDisplaySample(data);

      expect(window.MarkdownRenderer.render).toHaveBeenCalledWith('**bold**');
    });

    it('escapes HTML for user messages', () => {
      const data = {
        content: {
          mid: 'sample-3',
          role: 'user',
          text: '<script>alert("xss")</script>',
          badge: '<span>User</span>'
        }
      };

      handlers.handleDisplaySample(data);

      // createCard should be called with escaped text
      const renderedHtml = global.createCard.mock.calls[0][2];
      expect(renderedHtml).toContain('&lt;script&gt;');
      expect(renderedHtml).not.toContain('<script>');
    });
  });

  describe('module exports', () => {
    it('exports handlePastMessages', () => {
      expect(typeof handlers.handlePastMessages).toBe('function');
    });

    it('exports handleEditSuccess', () => {
      expect(typeof handlers.handleEditSuccess).toBe('function');
    });

    it('exports handleDisplaySample', () => {
      expect(typeof handlers.handleDisplaySample).toBe('function');
    });

    it('exposes handlers on window.WsMessageRenderer', () => {
      expect(typeof window.WsMessageRenderer).toBe('object');
      expect(typeof window.WsMessageRenderer.handlePastMessages).toBe('function');
      expect(typeof window.WsMessageRenderer.handleEditSuccess).toBe('function');
      expect(typeof window.WsMessageRenderer.handleDisplaySample).toBe('function');
    });
  });
});
