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
    <div class="message-input-wrapper">
      <textarea id="message" placeholder="Type..."></textarea>
      <div id="message-partial-overlay" aria-hidden="true"></div>
    </div>
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
  window.sendPdfWsMessage = jest.fn();
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

    it('leaves messageEl.value untouched when overlay is not active (legacy batch path)', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = 'kept';
      // Overlay element present but not .is-active — must NOT consume.
      overlay.classList.remove('is-active');

      handlers.handleSTT({ content: 'final', logprob: 0.9 });

      // Legacy path appends with a single space separator.
      expect(messageEl.value).toBe('kept final');
    });
  });

  describe('handleSTTPartial (overlay)', () => {
    it('renders mirror prefix + grey-italic partial spans', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = '';

      handlers.handleSTTPartial({ content: 'hello world' });

      expect(overlay.classList.contains('is-active')).toBe(true);
      expect(overlay.querySelector('.stt-mirror')).not.toBeNull();
      expect(overlay.querySelector('.stt-partial')).not.toBeNull();
      expect(overlay.querySelector('.stt-partial').textContent).toBe('hello world');
      // Empty start → mirror is empty (no separator inserted).
      expect(overlay.querySelector('.stt-mirror').textContent).toBe('');
      // Crucially, the textarea value must stay untouched.
      expect(messageEl.value).toBe('');
    });

    it('mirror prefix includes a separator space when textarea has content without trailing whitespace', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = 'typed before';

      handlers.handleSTTPartial({ content: 'spoken' });

      expect(overlay.querySelector('.stt-mirror').textContent).toBe('typed before ');
      expect(overlay.querySelector('.stt-partial').textContent).toBe('spoken');
      expect(messageEl.value).toBe('typed before');
    });

    it('skips separator when textarea already ends with whitespace', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = 'typed before\n';

      handlers.handleSTTPartial({ content: 'spoken' });

      expect(overlay.querySelector('.stt-mirror').textContent).toBe('typed before\n');
      expect(messageEl.value).toBe('typed before\n');
    });

    it('overwrites previous partial on subsequent delta (no append, no leak)', () => {
      var overlay = document.getElementById('message-partial-overlay');

      handlers.handleSTTPartial({ content: 'one' });
      handlers.handleSTTPartial({ content: 'one two' });
      handlers.handleSTTPartial({ content: 'one two three' });

      // Exactly one partial span in the overlay — not three concatenated.
      expect(overlay.querySelectorAll('.stt-partial').length).toBe(1);
      expect(overlay.querySelector('.stt-partial').textContent).toBe('one two three');
    });

    it('re-reads mirror prefix from textarea on each delta (user typed during stream)', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = '';

      handlers.handleSTTPartial({ content: 'live' });
      expect(overlay.querySelector('.stt-mirror').textContent).toBe('');

      // User types into the textarea mid-stream.
      messageEl.value = 'user typed: ';
      handlers.handleSTTPartial({ content: 'live partial' });

      // Mirror prefix reflects the latest textarea value at delta time.
      expect(overlay.querySelector('.stt-mirror').textContent).toBe('user typed: ');
      expect(overlay.querySelector('.stt-partial').textContent).toBe('live partial');
      // Textarea content is preserved verbatim.
      expect(messageEl.value).toBe('user typed: ');
    });

    it('handleSTT commits final, appends to textarea, clears overlay (active path)', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = 'prefix';

      handlers.handleSTTPartial({ content: 'live partial' });
      expect(overlay.classList.contains('is-active')).toBe(true);

      handlers.handleSTT({ content: 'final transcript', logprob: 0.9 });

      // Final transcript appended to whatever the textarea had at commit time.
      expect(messageEl.value).toBe('prefix final transcript');
      // Overlay torn down.
      expect(overlay.classList.contains('is-active')).toBe(false);
      expect(overlay.children.length).toBe(0);
    });

    it('handleSTT preserves text the user typed during streaming', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = '';

      handlers.handleSTTPartial({ content: 'hello' });
      // User types while partial is on screen — must survive commit.
      messageEl.value = 'note: ';
      handlers.handleSTT({ content: 'hello world', logprob: 0.92 });

      expect(messageEl.value).toBe('note: hello world');
      expect(overlay.classList.contains('is-active')).toBe(false);
    });

    it('clearSTTPartialOverlay tears down without touching textarea', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');
      messageEl.value = 'kept';

      handlers.handleSTTPartial({ content: 'in flight' });
      handlers.clearSTTPartialOverlay();

      expect(overlay.classList.contains('is-active')).toBe(false);
      expect(overlay.children.length).toBe(0);
      expect(messageEl.value).toBe('kept');
    });

    // Belt-and-braces fallback for browsers without :has() — the wrapper
    // gets a mirror class so the placeholder-hiding CSS rule can target
    // it directly. Pins the contract that the JS class toggle stays in
    // lockstep with overlay.is-active.
    it('mirrors has-partial-overlay class on the wrapper while overlay is active', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var wrapper = overlay.closest('.message-input-wrapper');
      expect(wrapper).not.toBeNull();
      expect(wrapper.classList.contains('has-partial-overlay')).toBe(false);

      handlers.handleSTTPartial({ content: 'live' });
      expect(wrapper.classList.contains('has-partial-overlay')).toBe(true);

      handlers.clearSTTPartialOverlay();
      expect(wrapper.classList.contains('has-partial-overlay')).toBe(false);
    });

    it('removes has-partial-overlay class on final STT commit (via handleSTT)', () => {
      var overlay = document.getElementById('message-partial-overlay');
      var wrapper = overlay.closest('.message-input-wrapper');
      var messageEl = document.getElementById('message');
      messageEl.value = '';

      handlers.handleSTTPartial({ content: 'streaming' });
      expect(wrapper.classList.contains('has-partial-overlay')).toBe(true);

      handlers.handleSTT({ content: 'streaming done', logprob: 0.9 });
      expect(wrapper.classList.contains('has-partial-overlay')).toBe(false);
    });

    it('mirrors textarea scrollTop to overlay on scroll while overlay is active', () => {
      // Continuous sync (not just per-delta): if the user scrolls the
      // textarea between partial deltas, the overlay must follow without
      // waiting for the next delta. Reproduce by firing a synthetic
      // 'scroll' event after the overlay is active.
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');

      handlers.handleSTTPartial({ content: 'partial' });
      expect(overlay.classList.contains('is-active')).toBe(true);

      // jsdom does not run real layout, so we drive scrollTop manually
      // and dispatch the event the listener is registered for.
      messageEl.scrollTop = 42;
      messageEl.dispatchEvent(new Event('scroll'));
      expect(overlay.scrollTop).toBe(42);

      messageEl.scrollTop = 99;
      messageEl.dispatchEvent(new Event('scroll'));
      expect(overlay.scrollTop).toBe(99);
    });

    it('detaches the scroll listener when overlay is cleared', () => {
      // After clearSTTPartialOverlay, subsequent scrolls must NOT touch
      // overlay.scrollTop — otherwise stale listeners pile up across
      // recording sessions and keep firing even when the overlay is
      // hidden.
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');

      handlers.handleSTTPartial({ content: 'partial' });
      handlers.clearSTTPartialOverlay();

      overlay.scrollTop = 0;
      messageEl.scrollTop = 77;
      messageEl.dispatchEvent(new Event('scroll'));
      expect(overlay.scrollTop).toBe(0); // unchanged
    });

    it('passes _alreadyAppended: true to wsHandlers.handleSTTMessage when overlay was active', () => {
      // Production has window.wsHandlers.handleSTTMessage defined.
      // Without the flag, that delegate ALSO appends data.content to
      // messageEl.value, producing the doubled-message bug observed
      // in dogfood. handleSTT must signal "we already wrote it" so
      // the delegate can skip its append.
      var messageEl = document.getElementById('message');
      messageEl.value = '';

      var sttHandlerSpy = jest.fn(function(_data) { return true; });
      window.wsHandlers = { handleSTTMessage: sttHandlerSpy };

      handlers.handleSTTPartial({ content: 'hello' });
      handlers.handleSTT({ content: 'hello world', logprob: 0.9 });

      expect(sttHandlerSpy).toHaveBeenCalledTimes(1);
      var arg = sttHandlerSpy.mock.calls[0][0];
      expect(arg._alreadyAppended).toBe(true);
      expect(arg.content).toBe('hello world');

      delete window.wsHandlers;
    });

    it('does NOT pass _alreadyAppended when overlay was inactive (legacy path)', () => {
      // If no partial preceded handleSTT (overlay never activated),
      // the delegate is the only writer — must NOT receive the flag,
      // otherwise the legacy batch path produces an empty textarea.
      var sttHandlerSpy = jest.fn(function(_data) { return true; });
      window.wsHandlers = { handleSTTMessage: sttHandlerSpy };

      handlers.handleSTT({ content: 'fresh batch', logprob: 0.9 });

      expect(sttHandlerSpy).toHaveBeenCalledTimes(1);
      var arg = sttHandlerSpy.mock.calls[0][0];
      expect(arg._alreadyAppended).toBeUndefined();
      expect(arg.content).toBe('fresh batch');

      delete window.wsHandlers;
    });

    it('does not double-attach the scroll listener across multiple partials', () => {
      // handleSTTPartial is called many times during one recording. The
      // attach guard must be idempotent so we end up with exactly one
      // listener, not N.
      var overlay = document.getElementById('message-partial-overlay');
      var messageEl = document.getElementById('message');

      var spy = jest.spyOn(messageEl, 'addEventListener');
      handlers.handleSTTPartial({ content: 'a' });
      handlers.handleSTTPartial({ content: 'a b' });
      handlers.handleSTTPartial({ content: 'a b c' });

      var scrollAttaches = spy.mock.calls.filter(function(c) { return c[0] === 'scroll'; });
      expect(scrollAttaches.length).toBe(1);
      spy.mockRestore();

      // Sanity: one sync still works after the duplicates were suppressed.
      messageEl.scrollTop = 12;
      messageEl.dispatchEvent(new Event('scroll'));
      expect(overlay.scrollTop).toBe(12);
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
      expect(window.sendPdfWsMessage).toHaveBeenCalledWith(
        { message: 'PDF_TITLES' }
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
        'handleSTT', 'handleSTTPartial', 'clearSTTPartialOverlay',
        'handlePDFTitles', 'handlePDFDeleted',
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
