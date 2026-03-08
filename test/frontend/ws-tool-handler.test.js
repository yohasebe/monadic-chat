/**
 * @jest-environment jsdom
 */

/**
 * Tests for ws-tool-handler.js
 *
 * Tests tool execution lifecycle handlers:
 * - handleToolExecuting: Tool start UI updates
 * - handleMessage: DONE/CLEAR signal processing
 */

function createMockElement(id) {
  return {
    length: 1,
    0: document.createElement('div'),
    show: jest.fn().mockReturnThis(),
    hide: jest.fn().mockReturnThis(),
    html: jest.fn().mockReturnThis(),
    is: jest.fn().mockReturnValue(false),
    find: jest.fn().mockReturnValue({
      html: jest.fn().mockReturnThis()
    })
  };
}

let mockElements;

beforeEach(() => {
  mockElements = {
    '#temp-card': createMockElement('temp-card'),
    '#monadic-spinner': createMockElement('monadic-spinner'),
    '#monadic-spinner span': createMockElement('monadic-spinner-span'),
    '#chat': createMockElement('chat'),
    '#temp-card .status': createMockElement('temp-card-status'),
    '#indicator': createMockElement('indicator')
  };

  global.$ = jest.fn().mockImplementation(selector => {
    if (typeof selector === 'string' && mockElements[selector]) {
      return mockElements[selector];
    }
    return createMockElement('default');
  });

  // Mock global functions
  global.updateToolStatus = jest.fn();
  global.getTranslation = jest.fn((key, fallback) => fallback);
  global.WorkflowViewer = { setStage: jest.fn(), setActiveTool: jest.fn() };

  // Window globals
  window.toolCallCount = 0;
  window.currentToolName = '';
  window.callingFunction = false;
  window.ws = { send: jest.fn() };
});

afterEach(() => {
  jest.restoreAllMocks();
});

const handlers = require('../../docker/services/ruby/public/js/monadic/ws-tool-handler');

describe('ws-tool-handler', () => {
  describe('handleToolExecuting', () => {
    it('increments toolCallCount', () => {
      handlers.handleToolExecuting({ content: 'search_web' });
      expect(window.toolCallCount).toBe(1);

      handlers.handleToolExecuting({ content: 'read_file' });
      expect(window.toolCallCount).toBe(2);
    });

    it('sets currentToolName', () => {
      handlers.handleToolExecuting({ content: 'search_web' });
      expect(window.currentToolName).toBe('search_web');
    });

    it('shows temp card when hidden', () => {
      mockElements['#temp-card'].is = jest.fn().mockReturnValue(true);  // is(":hidden") = true
      handlers.handleToolExecuting({ content: 'test_tool' });
      expect(mockElements['#temp-card'].show).toHaveBeenCalled();
    });

    it('calls updateToolStatus with name and count', () => {
      handlers.handleToolExecuting({ content: 'my_tool' });
      expect(global.updateToolStatus).toHaveBeenCalledWith('my_tool', 1);
    });

    it('updates WorkflowViewer', () => {
      handlers.handleToolExecuting({ content: 'search_web' });
      expect(global.WorkflowViewer.setActiveTool).toHaveBeenCalledWith('search_web', 1);
    });
  });

  describe('handleMessage', () => {
    describe('DONE with tool_calls', () => {
      it('sets callingFunction to true', () => {
        handlers.handleMessage({ content: 'DONE', finish_reason: 'tool_calls' });
        expect(window.callingFunction).toBe(true);
      });

      it('shows spinner with processing tools text', () => {
        handlers.handleMessage({ content: 'DONE', finish_reason: 'tool_calls' });
        expect(mockElements['#monadic-spinner'].show).toHaveBeenCalled();
      });

      it('sends HTML message via WebSocket', () => {
        handlers.handleMessage({ content: 'DONE', finish_reason: 'tool_calls' });
        expect(window.ws.send).toHaveBeenCalledWith(JSON.stringify({ message: 'HTML' }));
      });
    });

    describe('DONE without tool_calls', () => {
      it('sets callingFunction to false', () => {
        window.callingFunction = true;
        handlers.handleMessage({ content: 'DONE', finish_reason: 'stop' });
        expect(window.callingFunction).toBe(false);
      });

      it('sets WorkflowViewer stage to done', () => {
        handlers.handleMessage({ content: 'DONE', finish_reason: 'stop' });
        expect(global.WorkflowViewer.setStage).toHaveBeenCalledWith('done');
      });

      it('sends HTML message via WebSocket', () => {
        handlers.handleMessage({ content: 'DONE', finish_reason: 'stop' });
        expect(window.ws.send).toHaveBeenCalledWith(JSON.stringify({ message: 'HTML' }));
      });
    });

    describe('CLEAR', () => {
      it('clears chat HTML', () => {
        handlers.handleMessage({ content: 'CLEAR' });
        expect(mockElements['#chat'].html).toHaveBeenCalledWith('');
      });

      it('hides temp-card status', () => {
        handlers.handleMessage({ content: 'CLEAR' });
        expect(mockElements['#temp-card .status'].hide).toHaveBeenCalled();
      });

      it('shows indicator', () => {
        handlers.handleMessage({ content: 'CLEAR' });
        expect(mockElements['#indicator'].show).toHaveBeenCalled();
      });
    });

    it('does nothing for unknown content', () => {
      handlers.handleMessage({ content: 'UNKNOWN' });
      expect(window.ws.send).not.toHaveBeenCalled();
      expect(mockElements['#chat'].html).not.toHaveBeenCalled();
    });
  });

  describe('module exports', () => {
    it('exports both handlers', () => {
      expect(typeof handlers.handleToolExecuting).toBe('function');
      expect(typeof handlers.handleMessage).toBe('function');
    });

    it('exposes handlers on window.WsToolHandler', () => {
      expect(typeof window.WsToolHandler).toBe('object');
    });
  });
});
