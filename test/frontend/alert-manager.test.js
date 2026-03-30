/**
 * Tests for alert-manager.js
 *
 * Status messages, error cards, and message deletion.
 */

// Setup DOM and globals
document.body.innerHTML = `
  <div id="status-message"></div>
  <div id="stats-message"></div>
  <div id="monadic-spinner"></div>
  <div id="discourse"></div>
`;

// Mock dependencies
global.createCard = function(role, badge, msg) {
  const card = document.createElement('div');
  card.className = 'card';
  card.innerHTML = '<div class="card-text">' + msg + '</div>';
  return card;
};
global.detachEventListeners = jest.fn();
global.getTranslation = function(key, fallback) { return fallback; };
global.ws = { send: jest.fn() };
global.mids = new Set();
global.messages = [];
global.window.SessionState = { removeMessage: jest.fn() };
global.window.StatusConfig = undefined;

const {
  setAlertClass,
  setAlert,
  setStats,
  clearStatusMessage,
  clearErrorCards,
  deleteMessage
} = require('../../docker/services/ruby/public/js/monadic/alert-manager');

describe('alert-manager', () => {
  beforeEach(() => {
    document.getElementById('status-message').innerHTML = '';
    document.getElementById('status-message').className = '';
    document.getElementById('stats-message').innerHTML = '';
    document.getElementById('discourse').innerHTML = '';
    jest.clearAllMocks();
    global.messages = [];
    global.mids = new Set();
  });

  describe('setAlertClass', () => {
    it('adds text-success class', () => {
      setAlertClass('success');
      expect(document.getElementById('status-message').classList.contains('text-success')).toBe(true);
    });

    it('maps error to danger', () => {
      setAlertClass('error');
      expect(document.getElementById('status-message').classList.contains('text-danger')).toBe(true);
    });

    it('adds text-warning class', () => {
      setAlertClass('warning');
      expect(document.getElementById('status-message').classList.contains('text-warning')).toBe(true);
    });
  });

  describe('setAlert', () => {
    it('displays success message in status-message', () => {
      setAlert('<i class="fa"></i> Ready', 'success');
      expect(document.getElementById('status-message').innerHTML).toContain('Ready');
    });

    it('translates CALLING FUNCTIONS message', () => {
      setAlert('CALLING FUNCTIONS', 'warning');
      expect(document.getElementById('status-message').innerHTML).toContain('Calling functions');
    });

    it('translates SEARCHING WEB message', () => {
      setAlert('SEARCHING WEB', 'warning');
      expect(document.getElementById('status-message').innerHTML).toContain('Searching web');
    });

    it('converts generic uppercase messages to sentence case', () => {
      setAlert('SOME LONG STATUS MESSAGE', 'info');
      expect(document.getElementById('status-message').innerHTML).toBe('Some long status message');
    });

    it('creates error card for error type', () => {
      setAlert('Something broke', 'error');
      const errorCards = document.querySelectorAll('.error-message-card');
      expect(errorCards.length).toBe(1);
    });
  });

  describe('setStats', () => {
    it('sets stats message HTML', () => {
      setStats('<b>100 tokens</b>');
      expect(document.getElementById('stats-message').innerHTML).toBe('<b>100 tokens</b>');
    });

    it('handles empty string', () => {
      setStats('');
      expect(document.getElementById('stats-message').innerHTML).toBe('');
    });
  });

  describe('clearStatusMessage', () => {
    it('clears status message', () => {
      document.getElementById('status-message').innerHTML = 'test';
      clearStatusMessage();
      expect(document.getElementById('status-message').innerHTML).toBe('');
    });
  });

  describe('deleteMessage', () => {
    it('removes card from DOM and notifies server', () => {
      const card = document.createElement('div');
      card.id = 'msg-123';
      card.className = 'card';
      document.getElementById('discourse').appendChild(card);
      global.messages = [{ mid: 'msg-123', text: 'hello' }];
      global.mids = new Set(['msg-123']);

      deleteMessage('msg-123');

      expect(document.getElementById('msg-123')).toBeNull();
      expect(ws.send).toHaveBeenCalledWith(expect.stringContaining('msg-123'));
      expect(mids.has('msg-123')).toBe(false);
    });
  });

  describe('exports', () => {
    it('exports alert functions to window', () => {
      expect(window.setAlert).toBe(setAlert);
      expect(window.setStats).toBe(setStats);
      expect(window.deleteMessage).toBe(deleteMessage);
    });
  });
});
