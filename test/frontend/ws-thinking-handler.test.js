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

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    append: jest.fn().mockReturnThis(),
    empty: jest.fn().mockReturnThis(),
    find: jest.fn().mockReturnValue({
      length: 1,
      0: document.createElement('div'),
      empty: jest.fn().mockReturnThis(),
      appendChild: jest.fn()
    })
  };
}

let mockElements;

beforeEach(() => {
  // Create a real DOM element for temp-reasoning-card .card-text
  document.body.innerHTML = '';

  mockElements = {
    '#temp-reasoning-card': { length: 0 },
    '#temp-reasoning-card .card-text': { length: 0 },
    '#discourse': createMockElement('discourse'),
    '#temp-card': createMockElement('temp-card')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    // For HTML strings (card creation), return a mock with append
    if (typeof selector === 'string' && selector.includes('<')) {
      return { length: 1, 0: document.createElement('div') };
    }
    return createMockElement('default');
  });

  // Mock global functions
  global.WorkflowViewer = { setStage: jest.fn(), setActiveTool: jest.fn() };
  global.ensureThinkingSpinnerVisible = jest.fn();
  window.setReasoningStreamActive = jest.fn();
  window._lastProcessedSequence = 0;
  window._lastProcessedIndex = 0;
  window.webUIi18n = undefined;
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
      expect(mockElements['#discourse'].append).toHaveBeenCalled();
    });

    it('uses reasoning title for reasoning type', () => {
      // Track the HTML passed to $()
      const htmlArgs = [];
      global.$ = jest.fn().mockImplementation(selector => {
        if (typeof selector === 'string' && selector.includes('<')) {
          htmlArgs.push(selector);
          return { length: 1, 0: document.createElement('div') };
        }
        if (typeof selector === 'string' && mockElements[selector]) {
          return mockElements[selector];
        }
        return createMockElement('default');
      });

      handlers.handleThinking({ type: 'reasoning', content: 'test' });
      expect(htmlArgs.some(h => h.includes('Reasoning Process'))).toBe(true);
    });

    it('appends content to existing reasoning card', () => {
      const cardText = document.createElement('div');
      mockElements['#temp-reasoning-card'] = { length: 1 };
      mockElements['#temp-reasoning-card .card-text'] = {
        length: 1,
        0: cardText
      };

      handlers.handleThinking({ type: 'thinking', content: 'Hello\nWorld' });

      // DocumentFragment was appended to cardText
      expect(cardText.textContent).toBe('HelloWorld');
      expect(cardText.querySelectorAll('br').length).toBe(1);
    });
  });

  describe('handleClearFragments', () => {
    it('empties temp-card card-text', () => {
      const cardTextMock = { empty: jest.fn().mockReturnThis() };
      mockElements['#temp-card'] = {
        length: 1,
        find: jest.fn().mockReturnValue(cardTextMock)
      };

      handlers.handleClearFragments({});

      expect(mockElements['#temp-card'].find).toHaveBeenCalledWith('.card-text');
      expect(cardTextMock.empty).toHaveBeenCalled();
    });

    it('resets sequence tracking', () => {
      window._lastProcessedSequence = 5;
      window._lastProcessedIndex = 3;

      const cardTextMock = { empty: jest.fn().mockReturnThis() };
      mockElements['#temp-card'] = {
        length: 1,
        find: jest.fn().mockReturnValue(cardTextMock)
      };

      handlers.handleClearFragments({});

      expect(window._lastProcessedSequence).toBe(-1);
      expect(window._lastProcessedIndex).toBe(-1);
    });

    it('does nothing when temp-card does not exist', () => {
      mockElements['#temp-card'] = { length: 0 };
      // Should not throw
      handlers.handleClearFragments({});
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
