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

function createDOMElement(tag, id) {
  const el = document.createElement(tag);
  el.id = id;
  document.body.appendChild(el);
  return el;
}

beforeEach(() => {
  // Create DOM elements
  const spinner = createDOMElement('div', 'monadic-spinner');
  spinner.innerHTML = '<span></span>';
  const tempCard = createDOMElement('div', 'temp-card');
  tempCard.style.display = 'none';
  tempCard.innerHTML = '<div class="card-body role-assistant"><div class="card-text"></div></div>';
  createDOMElement('div', 'chat');
  const tempStatus = document.createElement('div');
  tempStatus.className = 'status';
  tempCard.appendChild(tempStatus);
  createDOMElement('div', 'indicator');
  createDOMElement('div', 'discourse');

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
  document.body.innerHTML = '';
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
      const tempCard = document.getElementById('temp-card');
      tempCard.style.display = 'none';
      handlers.handleToolExecuting({ content: 'test_tool' });
      expect(tempCard.style.display).toBe('');
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
        const spinner = document.getElementById('monadic-spinner');
        expect(spinner.style.display).not.toBe('none');
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
        document.getElementById('chat').innerHTML = '<p>old</p>';
        handlers.handleMessage({ content: 'CLEAR' });
        expect(document.getElementById('chat').innerHTML).toBe('');
      });

      it('hides temp-card status', () => {
        handlers.handleMessage({ content: 'CLEAR' });
        const status = document.querySelector('#temp-card .status');
        expect(status.style.display).toBe('none');
      });

      it('shows indicator', () => {
        document.getElementById('indicator').style.display = 'none';
        handlers.handleMessage({ content: 'CLEAR' });
        expect(document.getElementById('indicator').style.display).toBe('');
      });
    });

    it('does nothing for unknown content', () => {
      handlers.handleMessage({ content: 'UNKNOWN' });
      expect(window.ws.send).not.toHaveBeenCalled();
    });
  });

  describe('handleWait', () => {
    it('sets callingFunction to true', () => {
      handlers.handleWait({ content: 'Processing...' });
      expect(window.callingFunction).toBe(true);
    });

    it('shows spinner', () => {
      document.getElementById('monadic-spinner').style.display = 'none';
      handlers.handleWait({ content: 'Processing...' });
      expect(document.getElementById('monadic-spinner').style.display).toBe('');
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
      handlers.handleWait({
        content: 'Generating code...',
        source: 'OpenAICodeAgent',
        minutes: 1
      });

      const cardText = document.querySelector('#temp-card .card-text');
      expect(cardText.innerHTML).toContain('Generating code...');
    });

    it('shows step progress with sequential steps', () => {
      handlers.handleWait({
        content: 'Building app...',
        source: 'OpenAICodeAgent',
        step_progress: {
          mode: 'sequential',
          current: 1,
          steps: ['Plan', 'Code', 'Test']
        }
      });

      const cardText = document.querySelector('#temp-card .card-text');
      expect(cardText.innerHTML).toContain('Plan');
      expect(cardText.innerHTML).toContain('Code');
      expect(cardText.innerHTML).toContain('Test');
    });

    it('shows parallel progress indicators', () => {
      handlers.handleWait({
        content: 'Dispatching...',
        source: 'ParallelDispatch',
        parallel_progress: {
          completed: 1,
          total: 3,
          task_names: ['Task A', 'Task B', 'Task C']
        }
      });

      const cardText = document.querySelector('#temp-card .card-text');
      expect(cardText.innerHTML).toContain('1/3 completed');
    });

    it('sets spinner to calling functions for CALLING FUNCTIONS', () => {
      handlers.handleWait({ content: 'CALLING FUNCTIONS' });
      const spinnerSpan = document.querySelector('#monadic-spinner span');
      expect(spinnerSpan.innerHTML).toContain('Calling functions');
    });

    it('sets spinner to searching web for SEARCHING WEB', () => {
      handlers.handleWait({ content: 'SEARCHING WEB' });
      const spinnerSpan = document.querySelector('#monadic-spinner span');
      expect(spinnerSpan.innerHTML).toContain('Searching web');
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
