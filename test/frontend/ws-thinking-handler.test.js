/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-thinking-handler.js
 *
 * Tests thinking/reasoning display and fragment management:
 * - handleThinking: Create/update reasoning cards
 * - handleClearFragments: Reset fragment buffer between tool calls
 */

beforeEach(() => {
  // Set up a clean DOM
  document.body.innerHTML = '';

  // Create #discourse element (the container the source appends cards to)
  const discourse = document.createElement('div');
  discourse.id = 'discourse';
  document.body.appendChild(discourse);

  // Mock global functions
  global.WorkflowViewer = { setStage: jest.fn(), setActiveTool: jest.fn() };
  global.ensureThinkingSpinnerVisible = jest.fn();
  window.setReasoningStreamActive = jest.fn();
  window._lastProcessedSequence = 0;
  window._lastProcessedIndex = 0;
  window.webUIi18n = undefined;

  // Keep a minimal $ mock for any residual jQuery usage in other modules
  global.$ = jest.fn().mockReturnValue({ length: 0 });
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-thinking-handler');

describe('ws-thinking-handler', () => {
  describe('handleThinking', () => {
    it('does nothing for empty content', () => {
      handlers.handleThinking({ type: 'thinking', content: '' });
      expect(global.WorkflowViewer.setStage).not.toHaveBeenCalled();
    });

    it('sets workflow stage to model', () => {
      handlers.handleThinking({ type: 'thinking', content: 'test' });
      expect(global.WorkflowViewer.setStage).toHaveBeenCalledWith('model');
    });

    it('activates reasoning stream', () => {
      handlers.handleThinking({ type: 'thinking', content: 'test' });
      expect(window.setReasoningStreamActive).toHaveBeenCalledWith(true);
    });

    it('calls ensureThinkingSpinnerVisible', () => {
      handlers.handleThinking({ type: 'thinking', content: 'test' });
      expect(global.ensureThinkingSpinnerVisible).toHaveBeenCalled();
    });

    it('creates reasoning card when none exists', () => {
      handlers.handleThinking({ type: 'thinking', content: 'test' });
      const card = document.getElementById('temp-reasoning-card');
      expect(card).not.toBeNull();
      // Card should be appended to #discourse
      expect(document.getElementById('discourse').contains(card)).toBe(true);
    });

    it('uses reasoning title for reasoning type', () => {
      handlers.handleThinking({ type: 'reasoning', content: 'test' });
      const card = document.getElementById('temp-reasoning-card');
      expect(card).not.toBeNull();
      expect(card.innerHTML).toContain('Reasoning Process');
    });

    it('uses thinking title for thinking type', () => {
      handlers.handleThinking({ type: 'thinking', content: 'test' });
      const card = document.getElementById('temp-reasoning-card');
      expect(card).not.toBeNull();
      expect(card.innerHTML).toContain('Thinking Process');
    });

    it('appends content to existing reasoning card', () => {
      // First call creates the card
      handlers.handleThinking({ type: 'thinking', content: 'Hello\nWorld' });

      const cardText = document.querySelector('#temp-reasoning-card .card-text');
      expect(cardText).not.toBeNull();
      expect(cardText.textContent).toBe('HelloWorld');
      expect(cardText.querySelectorAll('br').length).toBe(1);
    });

    it('appends to existing card on subsequent calls', () => {
      handlers.handleThinking({ type: 'thinking', content: 'First' });
      handlers.handleThinking({ type: 'thinking', content: 'Second' });

      const cardText = document.querySelector('#temp-reasoning-card .card-text');
      expect(cardText.textContent).toBe('FirstSecond');
    });
  });

  describe('handleClearFragments', () => {
    it('empties temp-card card-text', () => {
      // Create temp-card with content
      const tempCard = document.createElement('div');
      tempCard.id = 'temp-card';
      tempCard.innerHTML = '<div class="card-text">Some content</div>';
      document.body.appendChild(tempCard);

      handlers.handleClearFragments({});

      const cardText = tempCard.querySelector('.card-text');
      expect(cardText.innerHTML).toBe('');
    });

    it('resets sequence tracking', () => {
      // Create temp-card so the handler proceeds
      const tempCard = document.createElement('div');
      tempCard.id = 'temp-card';
      tempCard.innerHTML = '<div class="card-text"></div>';
      document.body.appendChild(tempCard);

      window._lastProcessedSequence = 5;
      window._lastProcessedIndex = 3;

      handlers.handleClearFragments({});

      expect(window._lastProcessedSequence).toBe(-1);
      expect(window._lastProcessedIndex).toBe(-1);
    });

    it('does nothing when temp-card does not exist', () => {
      // No temp-card in DOM - should not throw
      handlers.handleClearFragments({});
      // If we get here without error, the test passes
    });
  });

  describe('module exports', () => {
    it('exports both handlers', () => {
      expect(typeof handlers.handleThinking).toBe('function');
      expect(typeof handlers.handleClearFragments).toBe('function');
    });

    it('exposes handlers on window.WsThinkingHandler', () => {
      expect(typeof window.WsThinkingHandler).toBe('object');
    });
  });
});
