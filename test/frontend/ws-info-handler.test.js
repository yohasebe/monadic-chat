/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-info-handler.js
 *
 * Tests the info message handler:
 * - handleInfo: Stats display, spinner management, app availability checks
 */

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    hide: jest.fn().mockReturnThis(),
    show: jest.fn().mockReturnThis(),
    html: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    append: jest.fn().mockReturnThis(),
    val: jest.fn(function(v) { if (v === undefined) return ''; return this; }),
    trigger: jest.fn().mockReturnThis(),
    first: jest.fn().mockReturnValue({ val: jest.fn().mockReturnValue('Chat') }),
    find: jest.fn().mockReturnValue({
      length: 0,
      removeClass: jest.fn().mockReturnThis(),
      addClass: jest.fn().mockReturnThis(),
      html: jest.fn().mockReturnThis()
    }),
    on: jest.fn().mockReturnThis(),
    data: jest.fn().mockReturnValue('OpenAI'),
    toggleClass: jest.fn().mockReturnThis(),
    hasClass: jest.fn().mockReturnValue(false)
  };
}

let mockElements;

beforeEach(() => {
  mockElements = {
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#apps': createMockElement('apps'),
    '#apps option': { length: 3 },
    '#apps option:not(:disabled)': {
      first: jest.fn().mockReturnValue({ val: jest.fn().mockReturnValue('Chat') })
    },
    '#custom-apps-dropdown': createMockElement('custom-apps-dropdown'),
    '.custom-dropdown-group': createMockElement('groups')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    if (typeof selector === 'string' && selector.includes('<')) {
      return { length: 1, 0: document.createElement('div') };
    }
    return createMockElement('default');
  });

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
        expect(mockElements['#monadic-spinner'].hide).toHaveBeenCalled();
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
        expect(mockElements['#monadic-spinner'].hide).not.toHaveBeenCalled();
      });
    });

    describe('status message', () => {
      it('shows ready message when apps available', () => {
        window.apps = { Chat: { app_name: 'Chat', group: 'OpenAI' } };
        mockElements['#apps option'] = { length: 1 };

        handlers.handleInfo({ content: {} });

        expect(global.setAlert).toHaveBeenCalledWith(
          expect.stringContaining('Ready'),
          'success'
        );
      });

      it('shows warning when no apps available', () => {
        window.apps = {};
        mockElements['#apps option'] = { length: 0 };

        handlers.handleInfo({ content: {} });

        expect(global.setAlert).toHaveBeenCalledWith(
          expect.stringContaining('No apps available'),
          'warning'
        );
      });

      it('does not show ready when streaming', () => {
        window.apps = { Chat: { app_name: 'Chat' } };
        mockElements['#apps option'] = { length: 1 };
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
