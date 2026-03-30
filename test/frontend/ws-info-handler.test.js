/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-info-handler.js
 *
 * Tests the info message handler:
 * - handleInfo: Stats display, spinner management, app availability checks
 */

function createDOMElement(tag, id) {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Create DOM elements
  const spinner = createDOMElement('div', 'monadic-spinner');
  spinner.innerHTML = '<span><i class="fas fa-comment"></i></span>';
  const appsSelect = createDOMElement('select', 'apps');
  // Add some options by default
  for (let i = 0; i < 3; i++) {
    const opt = document.createElement('option');
    opt.value = `app-${i}`;
    opt.textContent = `App ${i}`;
    appsSelect.appendChild(opt);
  }
  createDOMElement('div', 'custom-apps-dropdown');

  // Mock global functions
  global.formatInfo = jest.fn().mockReturnValue('<div>stats</div>');
  global.setStats = jest.fn();
  global.setAlert = jest.fn();

  // Window globals
  window.messages = [];
  window.apps = {};
  window.callingFunction = false;
  window.streamingResponse = false;
  window.debugWebSocket = false;
  window.setTextResponseCompleted = jest.fn();
  window.setTtsPlaybackStarted = jest.fn();
  window.checkAndHideSpinner = jest.fn();
  window.webUIi18n = undefined;
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-info-handler');

describe('ws-info-handler', () => {
  describe('handleInfo', () => {
    it('calls formatInfo and setStats', () => {
      handlers.handleInfo({ content: { model: 'gpt-4' } });
      expect(global.formatInfo).toHaveBeenCalledWith({ model: 'gpt-4' });
      expect(global.setStats).toHaveBeenCalledWith('<div>stats</div>');
    });

    it('does not call setStats when formatInfo returns empty', () => {
      global.formatInfo = jest.fn().mockReturnValue('');
      handlers.handleInfo({ content: {} });
      expect(global.setStats).not.toHaveBeenCalled();
    });

    describe('initial load (no messages)', () => {
      it('hides spinner immediately', () => {
        window.messages = [];
        handlers.handleInfo({ content: {} });
        expect(document.getElementById('monadic-spinner').style.display).toBe('none');
      });

      it('resets Auto Speech completion flags', () => {
        window.messages = [];
        handlers.handleInfo({ content: {} });
        expect(window.setTextResponseCompleted).toHaveBeenCalledWith(true);
        expect(window.setTtsPlaybackStarted).toHaveBeenCalledWith(true);
      });
    });

    describe('non-initial load', () => {
      it('uses checkAndHideSpinner when not busy', () => {
        window.messages = [{ text: 'hello' }];
        window.callingFunction = false;
        window.streamingResponse = false;

        handlers.handleInfo({ content: {} });

        expect(window.checkAndHideSpinner).toHaveBeenCalled();
      });

      it('does not hide spinner when calling function', () => {
        window.messages = [{ text: 'hello' }];
        window.callingFunction = true;

        handlers.handleInfo({ content: {} });

        expect(window.checkAndHideSpinner).not.toHaveBeenCalled();
      });
    });

    describe('status message', () => {
      it('shows ready message when apps available', () => {
        window.apps = { Chat: { app_name: 'Chat', group: 'OpenAI' } };

        handlers.handleInfo({ content: {} });

        expect(global.setAlert).toHaveBeenCalledWith(
          expect.stringContaining('Ready'),
          'success'
        );
      });

      it('shows warning when no apps available', () => {
        window.apps = {};
        // Clear the select options
        document.getElementById('apps').innerHTML = '';

        handlers.handleInfo({ content: {} });

        expect(global.setAlert).toHaveBeenCalledWith(
          expect.stringContaining('No apps available'),
          'warning'
        );
      });

      it('does not show ready when streaming', () => {
        window.apps = { Chat: { app_name: 'Chat' } };
        window.streamingResponse = true;

        handlers.handleInfo({ content: {} });

        // Should not have ready message
        const readyCalls = global.setAlert.mock.calls.filter(
          c => c[1] === 'success'
        );
        expect(readyCalls).toHaveLength(0);
      });
    });
  });

  describe('module exports', () => {
    it('exports handleInfo', () => {
      expect(typeof handlers.handleInfo).toBe('function');
    });

    it('exposes handlers on window.WsInfoHandler', () => {
      expect(typeof window.WsInfoHandler).toBe('object');
    });
  });
});
