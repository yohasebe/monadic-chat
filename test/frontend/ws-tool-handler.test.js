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
  global.setAlert = jest.fn();
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

  describe('handleWait', () => {
    it('sets callingFunction to true', () => {
      handlers.handleWait({ content: 'Processing...' });
      expect(window.callingFunction).toBe(true);
    });

    it('shows spinner', () => {
      handlers.handleWait({ content: 'Processing...' });
      expect(mockElements['#monadic-spinner'].show).toHaveBeenCalled();
    });

    it('shows regular wait messages as alerts', () => {
      global.setAlert = jest.fn();
      handlers.handleWait({ content: 'Please wait...' });
      expect(global.setAlert).toHaveBeenCalledWith('Please wait...', 'warning');
    });

    it('translates generating_ai_user_response key', () => {
      handlers.handleWait({ content: 'generating_ai_user_response' });
      expect(global.getTranslation).toHaveBeenCalledWith(
        'ui.messages.generatingAIUserResponse',
        'Generating AI user response...'
      );
    });

    it('displays agent progress in temp card', () => {
      mockElements['#temp-card'] = {
        length: 1,
        show: jest.fn(),
        detach: jest.fn().mockReturnThis()
      };
      mockElements['#temp-card .card-text'] = { html: jest.fn() };
      mockElements['#discourse'] = { append: jest.fn() };

      handlers.handleWait({
        content: 'Generating code...',
        source: 'OpenAICodeAgent',
        minutes: 1
      });

      expect(mockElements['#temp-card .card-text'].html).toHaveBeenCalledWith(
        expect.stringContaining('Generating code...')
      );
    });

    it('shows step progress with sequential steps', () => {
      mockElements['#temp-card'] = {
        length: 1,
        show: jest.fn(),
        detach: jest.fn().mockReturnThis()
      };
      mockElements['#temp-card .card-text'] = { html: jest.fn() };
      mockElements['#discourse'] = { append: jest.fn() };

      handlers.handleWait({
        content: 'Building app...',
        source: 'OpenAICodeAgent',
        step_progress: {
          mode: 'sequential',
          current: 1,
          steps: ['Plan', 'Code', 'Test']
        }
      });

      const htmlArg = mockElements['#temp-card .card-text'].html.mock.calls[0][0];
      expect(htmlArg).toContain('Plan');
      expect(htmlArg).toContain('Code');
      expect(htmlArg).toContain('Test');
    });

    it('shows parallel progress indicators', () => {
      mockElements['#temp-card'] = {
        length: 1,
        show: jest.fn(),
        detach: jest.fn().mockReturnThis()
      };
      mockElements['#temp-card .card-text'] = { html: jest.fn() };
      mockElements['#discourse'] = { append: jest.fn() };

      handlers.handleWait({
        content: 'Dispatching...',
        source: 'ParallelDispatch',
        parallel_progress: {
          completed: 1,
          total: 3,
          task_names: ['Task A', 'Task B', 'Task C']
        }
      });

      const htmlArg = mockElements['#temp-card .card-text'].html.mock.calls[0][0];
      expect(htmlArg).toContain('1/3 completed');
    });

    it('sets spinner to calling functions for CALLING FUNCTIONS', () => {
      handlers.handleWait({ content: 'CALLING FUNCTIONS' });
      expect(mockElements['#monadic-spinner span'].html).toHaveBeenCalledWith(
        expect.stringContaining('Calling functions')
      );
    });

    it('sets spinner to searching web for SEARCHING WEB', () => {
      handlers.handleWait({ content: 'SEARCHING WEB' });
      expect(mockElements['#monadic-spinner span'].html).toHaveBeenCalledWith(
        expect.stringContaining('Searching web')
      );
    });

    it('updates WorkflowViewer stage', () => {
      handlers.handleWait({ content: 'CALLING FUNCTIONS' });
      expect(global.WorkflowViewer.setStage).toHaveBeenCalledWith('tools');
    });
  });

  describe('module exports', () => {
    it('exports all three handlers', () => {
      expect(typeof handlers.handleToolExecuting).toBe('function');
      expect(typeof handlers.handleMessage).toBe('function');
      expect(typeof handlers.handleWait).toBe('function');
    });

    it('exposes handlers on window.WsToolHandler', () => {
      expect(typeof window.WsToolHandler).toBe('object');
    });
  });
});
