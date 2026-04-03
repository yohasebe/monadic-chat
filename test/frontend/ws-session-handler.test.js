/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-session-handler.js (vanilla JS version)
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

beforeEach(() => {
  // Setup DOM
  document.body.innerHTML = `
    <div id="discourse"></div>
    <div id="monadic-spinner" style="display: none;"></div>
    <select id="conversation-language"><option value="en">English</option><option value="ja">Japanese</option><option value="ar">Arabic</option></select>
    <textarea id="message" placeholder="Type..."></textarea>
    <div id="asr-p-value" style="display: none;"></div>
    <button id="send"></button>
    <button id="clear"></button>
    <button id="voice"></button>
    <div id="amplitude" style="display: none;"></div>
    <input type="checkbox" id="check-easy-submit" />
    <div id="pdf-titles"></div>
    <div id="cancel_query"></div>
    <div id="pdfDeleteConfirmation"></div>
    <div id="pdfToDelete"></div>
    <button id="pdfDeleteConfirmed"></button>
  `;

  // Mock bootstrap
  global.bootstrap = {
    Modal: {
      getOrCreateInstance: jest.fn().mockReturnValue({ show: jest.fn(), hide: jest.fn() })
    },
    Tooltip: jest.fn()
  };

  // Mock global functions
  global.setAlert = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.createCard = jest.fn().mockImplementation(function() {
    var el = document.createElement('div');
    el.className = 'card';
    el.innerHTML = '<div class="card-body"></div>';
    return { 0: el, length: 1 };
  });
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
      handlers.handleLanguageUpdated({ language: 'ar', text_direction: 'rtl' });

      expect(document.body.classList.contains('rtl-messages')).toBe(true);
    });

    it('removes rtl-messages class for LTR languages', () => {
      document.body.classList.add('rtl-messages');
      handlers.handleLanguageUpdated({ language: 'en', text_direction: 'ltr' });

      expect(document.body.classList.contains('rtl-messages')).toBe(false);
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
      // Card should be appended to discourse
      var discourse = document.getElementById('discourse');
      expect(discourse.children.length).toBeGreaterThan(0);
    });

    it('handles object content by stringifying', () => {
      handlers.handleSystemInfo({ content: { key: 'value' } });

      expect(global.createCard).toHaveBeenCalled();
    });
  });

  describe('handleSTT', () => {
    it('appends transcribed text to message field', () => {
      var messageEl = document.getElementById('message');
      messageEl.value = 'existing';

      handlers.handleSTT({ content: 'hello', logprob: 0.95 });

      expect(messageEl.value).toBe('existing hello');
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

      var pdfTitles = document.getElementById('pdf-titles');
      expect(pdfTitles.innerHTML).toContain('doc1.pdf');
    });

    it('renders empty state when no PDFs', () => {
      handlers.handlePDFTitles({ content: [] });

      var pdfTitles = document.getElementById('pdf-titles');
      expect(pdfTitles.innerHTML).toContain('No PDFs imported');
    });

    it('escapes HTML in titles', () => {
      handlers.handlePDFTitles({ content: ['<script>xss</script>'] });

      var pdfTitles = document.getElementById('pdf-titles');
      expect(pdfTitles.innerHTML).toContain('&lt;script');
      expect(pdfTitles.innerHTML).not.toContain('<script>xss');
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
      var card = document.createElement('div');
      card.id = 'msg-1';
      card.innerHTML = '<div class="status"></div>';
      document.getElementById('discourse').appendChild(card);

      handlers.handleChangeStatus({ content: [{ mid: 'msg-1', active: true }] });

      expect(card.querySelector('.status').classList.contains('active')).toBe(true);
    });

    it('removes active class for inactive messages', () => {
      var card = document.createElement('div');
      card.id = 'msg-2';
      card.innerHTML = '<div class="status active"></div>';
      document.getElementById('discourse').appendChild(card);

      handlers.handleChangeStatus({ content: [{ mid: 'msg-2', active: false }] });

      expect(card.querySelector('.status').classList.contains('active')).toBe(false);
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

      handlers.handleSampleSuccess({ role: 'assistant' });

      expect(window.currentSampleTimeout).toBeNull();
    });

    it('hides spinner and cancel button', () => {
      var spinner = document.getElementById('monadic-spinner');
      spinner.style.display = '';

      handlers.handleSampleSuccess({ role: 'user' });

      expect(spinner.style.display).toBe('none');
      var cancelButton = document.getElementById('cancel_query');
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
