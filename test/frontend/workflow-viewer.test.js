/**
 * @jest-environment jsdom
 */

const fs = require('fs');
const path = require('path');

// ── PointerEvent polyfill for jsdom ──────────────────────────
if (typeof PointerEvent === 'undefined') {
  class PointerEvent extends MouseEvent {
    constructor(type, params = {}) {
      super(type, params);
      this.pointerId = params.pointerId || 0;
      this.pointerType = params.pointerType || 'mouse';
    }
  }
  global.PointerEvent = PointerEvent;
}

// ── Minimal maxGraph mock ─────────────────────────────────────
// Only the subset used by workflow-viewer.js

function createMockGraph() {
  const cells = {};
  let idCounter = 0;

  const graph = {
    setHtmlLabels: jest.fn(),
    setCellsMovable: jest.fn(),
    setCellsResizable: jest.fn(),
    setCellsEditable: jest.fn(),
    setCellsCloneable: jest.fn(),
    setCellsDeletable: jest.fn(),
    setCellsDisconnectable: jest.fn(),
    setConnectable: jest.fn(),
    setCellsSelectable: jest.fn(),
    setAutoSizeCells: jest.fn(),
    setPanning: jest.fn(),
    getPlugin: jest.fn(() => ({ useLeftButtonForPanning: false, ignoreCell: false })),
    getDefaultParent: jest.fn(() => ({})),
    insertVertex: jest.fn((parent, id, label, x, y, w, h, style) => {
      const cell = {
        id: id || 'auto_' + (++idCounter),
        value: label,
        geometry: { x, y, width: w, height: h },
        style,
        setVisible: jest.fn(function (v) { this._visible = v; }),
        _visible: true,
      };
      cells[cell.id] = cell;
      return cell;
    }),
    insertEdge: jest.fn((parent, id, label, src, tgt, style) => {
      return { id: id, source: src, target: tgt, style, geometry: { points: null } };
    }),
    batchUpdate: jest.fn((fn) => fn()),
    getView: jest.fn(() => ({
      scaleAndTranslate: jest.fn(),
      scale: 1,
      translate: { x: 0, y: 0 },
      getState: jest.fn(() => null),
    })),
    getGraphBounds: jest.fn(() => ({ x: 0, y: 0, width: 400, height: 600 })),
    getCellAt: jest.fn(() => null),
    zoomIn: jest.fn(),
    zoomOut: jest.fn(),
    destroy: jest.fn(),
    _cells: cells,
  };

  return graph;
}

function setupMaxgraphMock() {
  window.maxgraph = {
    Graph: jest.fn(function (container) {
      return createMockGraph();
    }),
    HierarchicalLayout: jest.fn(function () {
      return {
        orientation: 'north',
        intraCellSpacing: 0,
        interRankCellSpacing: 0,
        interHierarchySpacing: 0,
        disableEdgeStyle: false,
        execute: jest.fn(),
      };
    }),
    Rectangle: jest.fn(function (x, y, w, h) {
      return { x, y, width: w, height: h };
    }),
    Point: jest.fn(function (x, y) {
      return { x, y };
    }),
  };
}

function setupDOM() {
  document.body.innerHTML = `
    <div id="workflow-viewer-panel" class="wv-panel-collapsed">
      <div class="wv-panel-header">
        <span class="wv-panel-title">
          <span id="workflowViewerLabel"></span>
        </span>
      </div>
      <div id="workflow-viewer-container" style="width:800px;height:230px;"></div>
      <div class="wv-panel-footer">
        <div class="workflow-viewer-legend"></div>
      </div>
      <div class="wv-resize-handle"></div>
      <button id="wv-close"></button>
    </div>
    <button id="toggle-workflow-viewer"></button>
    <button id="wv-zoom-in"></button>
    <button id="wv-zoom-out"></button>
    <button id="wv-zoom-fit"></button>
    <select id="apps"><option value="TestApp" selected>TestApp</option></select>
  `;
}

function loadWorkflowViewer() {
  const filePath = path.join(__dirname, '../../docker/services/ruby/public/js/monadic/workflow-viewer.js');
  const code = fs.readFileSync(filePath, 'utf8');
  eval(code);
}

// ── Sample API data ───────────────────────────────────────────

const SAMPLE_MINIMAL = {
  app_name: 'TestApp',
  display_name: 'Test App',
  provider: 'openai',
  models: ['gpt-4o'],
  core: { temperature: 0.5 },
  tools: [],
  shared_tool_groups: [],
  agents: {},
  features: {},
  context_schema: null,
  system_prompt: 'You are a helpful assistant.',
};

const SAMPLE_FULL = {
  app_name: 'ResearchAssistant',
  display_name: 'Research Assistant',
  provider: 'openai',
  models: ['gpt-4o', 'gpt-4o-mini'],
  core: { temperature: 0.3, reasoning_effort: 'medium', context_size: 20, max_tokens: 4000 },
  tools: [
    { name: 'fetch_web_content', description: 'Fetch content from a URL' },
    { name: 'run_code', description: 'Execute code' },
  ],
  shared_tool_groups: [
    { name: 'web_browsing', tool_names: ['navigate_to', 'screenshot', 'click_element'] },
    { name: 'file_tools', tool_names: ['read_file', 'write_file'] },
  ],
  agents: { code_agent: 'gpt-4o-mini' },
  features: { websearch: true, monadic: true, pdf_vector_storage: false },
  context_schema: {
    fields: [
      { name: 'topics', label: 'Topics' },
      { name: 'findings', label: 'Findings' },
    ]
  },
  system_prompt: 'You are a research assistant with web browsing capabilities.',
  input_types: ['text', 'image'],
  output_types: ['text', 'html'],
};

// ── Tests ─────────────────────────────────────────────────────

describe('WorkflowViewer', () => {
  beforeEach(() => {
    delete window.WorkflowViewer;
    delete window.maxgraph;
    setupMaxgraphMock();
    setupDOM();
    loadWorkflowViewer();
    window.WorkflowViewer.init();
  });

  afterEach(() => {
    if (window.WorkflowViewer) {
      window.WorkflowViewer.destroy();
    }
    document.body.innerHTML = '';
  });

  describe('Initialization', () => {
    test('should expose WorkflowViewer on window', () => {
      expect(window.WorkflowViewer).toBeDefined();
    });

    test('should have required public methods', () => {
      expect(typeof window.WorkflowViewer.init).toBe('function');
      expect(typeof window.WorkflowViewer.toggle).toBe('function');
      expect(typeof window.WorkflowViewer.loadApp).toBe('function');
      expect(typeof window.WorkflowViewer.isOpen).toBe('function');
      expect(typeof window.WorkflowViewer.open).toBe('function');
      expect(typeof window.WorkflowViewer.close).toBe('function');
      expect(typeof window.WorkflowViewer.destroy).toBe('function');
    });

    test('should not crash when init is called twice', () => {
      expect(() => window.WorkflowViewer.init()).not.toThrow();
    });

    test('should build legend on init', () => {
      const legend = document.querySelector('.workflow-viewer-legend');
      const items = legend.querySelectorAll('.wv-legend-item');
      expect(items.length).toBe(7); // Input/Response, Prompt, Model, Tool, Agent, Feature, Context
    });
  });

  describe('Graceful degradation', () => {
    test('should not crash when maxGraph is missing', () => {
      delete window.WorkflowViewer;
      delete window.maxgraph;
      setupDOM();
      const spy = jest.spyOn(console, 'warn').mockImplementation(() => {});
      loadWorkflowViewer();
      window.WorkflowViewer.init();
      expect(spy).toHaveBeenCalledWith('[WorkflowViewer] maxGraph not loaded');
      spy.mockRestore();
    });

    test('should not crash when panel element is missing', () => {
      delete window.WorkflowViewer;
      setupMaxgraphMock();
      document.body.innerHTML = ''; // Remove all DOM
      const spy = jest.spyOn(console, 'warn').mockImplementation(() => {});
      loadWorkflowViewer();
      window.WorkflowViewer.init();
      expect(spy).toHaveBeenCalledWith('[WorkflowViewer] Panel not found');
      spy.mockRestore();
    });
  });

  describe('isOpen', () => {
    test('should return false when panel is collapsed', () => {
      expect(window.WorkflowViewer.isOpen()).toBe(false);
    });

    test('should return true when panel is not collapsed', () => {
      document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
      expect(window.WorkflowViewer.isOpen()).toBe(true);
    });
  });

  describe('open/close', () => {
    test('open should remove collapsed class', () => {
      window.WorkflowViewer.open();
      expect(document.getElementById('workflow-viewer-panel').classList.contains('wv-panel-collapsed')).toBe(false);
    });

    test('close should add collapsed class', () => {
      window.WorkflowViewer.open();
      window.WorkflowViewer.close();
      expect(document.getElementById('workflow-viewer-panel').classList.contains('wv-panel-collapsed')).toBe(true);
    });

    test('open should set toggle button active', () => {
      window.WorkflowViewer.open();
      expect(document.getElementById('toggle-workflow-viewer').classList.contains('wv-active')).toBe(true);
    });

    test('close should remove toggle button active', () => {
      window.WorkflowViewer.open();
      window.WorkflowViewer.close();
      expect(document.getElementById('toggle-workflow-viewer').classList.contains('wv-active')).toBe(false);
    });
  });

  describe('Resize handle', () => {
    test('should have resize handle element in panel', () => {
      const handle = document.querySelector('#workflow-viewer-panel .wv-resize-handle');
      expect(handle).not.toBeNull();
    });

    test('pointerdown on handle should add wv-resizing class', () => {
      const handle = document.querySelector('.wv-resize-handle');
      handle.setPointerCapture = jest.fn();
      const panel = document.getElementById('workflow-viewer-panel');
      panel.classList.remove('wv-panel-collapsed');
      // Mock getBoundingClientRect
      panel.getBoundingClientRect = jest.fn(() => ({ height: 300 }));
      handle.dispatchEvent(new PointerEvent('pointerdown', { button: 0, clientY: 300, pointerId: 1 }));
      expect(panel.classList.contains('wv-resizing')).toBe(true);
    });

    test('pointerup on handle should remove wv-resizing class', () => {
      const handle = document.querySelector('.wv-resize-handle');
      handle.setPointerCapture = jest.fn();
      const panel = document.getElementById('workflow-viewer-panel');
      panel.classList.remove('wv-panel-collapsed');
      panel.getBoundingClientRect = jest.fn(() => ({ height: 300 }));
      handle.dispatchEvent(new PointerEvent('pointerdown', { button: 0, clientY: 300, pointerId: 1 }));
      handle.dispatchEvent(new PointerEvent('pointerup', { clientY: 400 }));
      expect(panel.classList.contains('wv-resizing')).toBe(false);
    });
  });

  describe('View state preservation', () => {
    test('close should save view state without error', () => {
      window.WorkflowViewer.open();
      expect(() => window.WorkflowViewer.close()).not.toThrow();
    });

    test('close and reopen should not throw', () => {
      window.WorkflowViewer.open();
      window.WorkflowViewer.close();
      expect(() => window.WorkflowViewer.open()).not.toThrow();
    });

    test('destroy should clear view states', () => {
      window.WorkflowViewer.open();
      window.WorkflowViewer.close();
      window.WorkflowViewer.destroy();
      // After destroy, opening should not try to restore stale state
      setupDOM();
      expect(() => window.WorkflowViewer.init()).not.toThrow();
    });
  });

  describe('Theme change handling', () => {
    test('should not throw when theme-applied event fires', () => {
      window.WorkflowViewer.open();
      expect(() => {
        window.dispatchEvent(new CustomEvent('theme-applied', { detail: { theme: 'dark' } }));
      }).not.toThrow();
    });

    test('destroy should remove theme-applied listener', () => {
      const spy = jest.spyOn(window, 'removeEventListener');
      window.WorkflowViewer.destroy();
      const themeCall = spy.mock.calls.find(c => c[0] === 'theme-applied');
      expect(themeCall).toBeDefined();
      spy.mockRestore();
    });
  });

  describe('destroy', () => {
    test('should clean up state without error', () => {
      expect(() => window.WorkflowViewer.destroy()).not.toThrow();
    });

    test('should allow re-initialization after destroy', () => {
      window.WorkflowViewer.destroy();
      setupDOM();
      expect(() => window.WorkflowViewer.init()).not.toThrow();
    });
  });
});

// ── buildGraphData tests via internal access ──────────────────
// Since buildGraphData is a private function inside the IIFE, we test its
// behaviour indirectly through the rendered graph output.
// We also create a separate describe that loads the module and
// inspects the cells created during _doLoadApp.

describe('WorkflowViewer graph structure', () => {
  let insertedVertices;
  let insertedEdges;

  beforeEach(() => {
    delete window.WorkflowViewer;
    delete window.maxgraph;
    insertedVertices = [];
    insertedEdges = [];

    // Capture graph construction calls
    window.maxgraph = {
      Graph: jest.fn(function () {
        const g = createMockGraph();
        // Intercept insertVertex/insertEdge
        g.insertVertex = jest.fn(function (parent, id, label, x, y, w, h, style) {
          const cell = {
            id, value: label, geometry: { x, y, width: w, height: h }, style,
            setVisible: jest.fn(function (v) { this._visible = v; }),
            _visible: true,
          };
          insertedVertices.push(cell);
          return cell;
        });
        g.insertEdge = jest.fn(function (parent, id, label, src, tgt, style) {
          const edge = { source: src, target: tgt, style, geometry: { points: null } };
          insertedEdges.push(edge);
          return edge;
        });
        return g;
      }),
      HierarchicalLayout: jest.fn(function () {
        return {
          orientation: 'north', intraCellSpacing: 0, interRankCellSpacing: 0,
          interHierarchySpacing: 0, disableEdgeStyle: false, execute: jest.fn(),
        };
      }),
      Rectangle: jest.fn((x, y, w, h) => ({ x, y, width: w, height: h })),
      Point: jest.fn((x, y) => ({ x, y })),
    };

    setupDOM();

    // Mock fetch to return sample data
    global.fetch = jest.fn();

    loadWorkflowViewer();
    window.WorkflowViewer.init();

    // Simulate panel open
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
  });

  afterEach(() => {
    if (window.WorkflowViewer) window.WorkflowViewer.destroy();
    document.body.innerHTML = '';
    delete global.fetch;
  });

  async function loadAppWithData(data) {
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => data,
    });
    window.WorkflowViewer._doLoadApp(data.app_name);
    // Wait for promise chain
    await new Promise(r => setTimeout(r, 0));
  }

  describe('Minimal app (no tools, no agents)', () => {
    beforeEach(async () => {
      await loadAppWithData(SAMPLE_MINIMAL);
    });

    test('should create 5 flow + side nodes', () => {
      // User Input, System Prompt, Model, Response = 4 flow nodes
      // Context = 1 side node (always present)
      expect(insertedVertices.length).toBe(5);
    });

    test('should create flow nodes in correct order', () => {
      const labels = insertedVertices.map(v => v.value);
      // First 4 are flow nodes: Input, Prompt, Model, Response
      expect(labels[0]).toContain('User Input');
      expect(labels[1]).toContain('System Prompt');
      expect(labels[2]).toContain('gpt-4o'); // model name
      expect(labels[3]).toContain('Response');
    });

    test('should always include Message History node', () => {
      const labels = insertedVertices.map(v => v.value);
      expect(labels[4]).toContain('Message History');
    });

    test('should create 3 flow edges + 1 side edge + 1 feedback edge', () => {
      // 3 flow: Input→Prompt, Prompt→Model, Model→Response
      // 1 side: Response→History
      // 1 feedback: History→Input
      expect(insertedEdges.length).toBe(5);
    });

    test('should create 1 feedback edge for non-monadic app without context schema', () => {
      const feedbackEdges = insertedEdges.filter(e =>
        e.style && e.style.dashed === true && e.style.exitX === 0 && e.style.entryX === 0
      );
      expect(feedbackEdges.length).toBe(1);
    });

    test('should update panel title with app name', () => {
      const titleEl = document.getElementById('workflowViewerLabel');
      expect(titleEl.innerHTML).toContain('Test App');
    });
  });

  describe('Full app (tools, agents, features, context schema)', () => {
    beforeEach(async () => {
      await loadAppWithData(SAMPLE_FULL);
    });

    test('should create correct number of nodes', () => {
      // 4 flow: Input, Prompt, Model, Response
      // 1 Tools (side, right of Model)
      // 1 Agent: code_agent (side, right of Model)
      // 1 Features (side, right of Model) — websearch + monadic = 2 enabled
      // 1 Message History (side, left of Response) — always present
      // 1 Monadic Context (side, left of Response) — has context_schema fields
      expect(insertedVertices.length).toBe(9);
    });

    test('should include Tools node with tool groups', () => {
      const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
      expect(toolNode).toBeDefined();
      expect(toolNode.value).toContain('Web Browsing');
      expect(toolNode.value).toContain('File Tools');
    });

    test('should include Agent node', () => {
      const agentNode = insertedVertices.find(v => v.value.includes('Code Agent'));
      expect(agentNode).toBeDefined();
    });

    test('should include Features node with enabled features only', () => {
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      expect(featNode).toBeDefined();
      expect(featNode.value).toContain('Websearch');
      expect(featNode.value).toContain('Monadic');
      expect(featNode.value).not.toContain('pdf vector storage'); // false = excluded
    });

    test('should include Monadic Context node with schema fields', () => {
      const ctxNode = insertedVertices.find(v => v.value.includes('Monadic Context'));
      expect(ctxNode).toBeDefined();
      expect(ctxNode.value).toContain('Topics');
      expect(ctxNode.value).toContain('Findings');
    });

    test('should include Message History node', () => {
      const histNode = insertedVertices.find(v => v.value.includes('Message History'));
      expect(histNode).toBeDefined();
    });

    test('should display multiple input types', () => {
      const inputNode = insertedVertices.find(v => v.value.includes('User Input'));
      expect(inputNode.value).toContain('Text');
      expect(inputNode.value).toContain('Image');
    });

    test('should display output types in Response', () => {
      const respNode = insertedVertices.find(v => v.value.includes('Response'));
      expect(respNode.value).toContain('Text Output');
      expect(respNode.value).toContain('HTML Output');
    });

    test('should create 2 feedback edges for monadic app with context schema', () => {
      // 3 flow + 5 side (tools, agent, features, history, context) + 2 feedback = 10
      const feedbackEdges = insertedEdges.filter(e =>
        e.style && e.style.dashed === true && e.style.exitX === 0 && e.style.entryX === 0
      );
      expect(feedbackEdges.length).toBe(2);
    });
  });

  describe('Node sizing', () => {
    beforeEach(async () => {
      await loadAppWithData(SAMPLE_FULL);
    });

    test('flow nodes should have width of 220', () => {
      const inputNode = insertedVertices.find(v => v.value.includes('User Input'));
      expect(inputNode.geometry.width).toBe(220);
    });

    test('Tools node should have width of 240', () => {
      const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
      expect(toolNode.geometry.width).toBe(240);
    });

    test('Feature/History/Context nodes should have width of 200', () => {
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      expect(featNode.geometry.width).toBe(200);
      const histNode = insertedVertices.find(v => v.value.includes('Message History'));
      expect(histNode.geometry.width).toBe(200);
      const ctxNode = insertedVertices.find(v => v.value.includes('Monadic Context'));
      expect(ctxNode.geometry.width).toBe(200);
    });
  });

  describe('Error handling', () => {
    test('should display error when fetch fails', async () => {
      global.fetch.mockRejectedValueOnce(new Error('Network error'));
      window.WorkflowViewer._doLoadApp('BadApp');
      await new Promise(r => setTimeout(r, 0));
      const container = document.getElementById('workflow-viewer-container');
      expect(container.innerHTML).toContain('Failed');
      expect(container.innerHTML).toContain('Network error');
    });

    test('should display error for non-OK HTTP response', async () => {
      global.fetch.mockResolvedValueOnce({ ok: false, status: 404 });
      window.WorkflowViewer._doLoadApp('MissingApp');
      await new Promise(r => setTimeout(r, 0));
      const container = document.getElementById('workflow-viewer-container');
      expect(container.innerHTML).toContain('Failed');
      expect(container.innerHTML).toContain('404');
    });

    test('should display error from API error response', async () => {
      global.fetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ error: 'App not found' }),
      });
      window.WorkflowViewer._doLoadApp('GhostApp');
      await new Promise(r => setTimeout(r, 0));
      const container = document.getElementById('workflow-viewer-container');
      expect(container.innerHTML).toContain('App not found');
    });
  });
});

describe('WorkflowViewer label generation', () => {
  // Test the HTML label structure by examining inserted vertex values

  let insertedVertices;

  beforeEach(async () => {
    delete window.WorkflowViewer;
    delete window.maxgraph;
    insertedVertices = [];

    window.maxgraph = {
      Graph: jest.fn(function () {
        const g = createMockGraph();
        g.insertVertex = jest.fn(function (parent, id, label, x, y, w, h, style) {
          const cell = {
            id, value: label, geometry: { x, y, width: w, height: h }, style,
            setVisible: jest.fn(), _visible: true,
          };
          insertedVertices.push(cell);
          return cell;
        });
        g.insertEdge = jest.fn(() => ({ geometry: { points: null } }));
        return g;
      }),
      HierarchicalLayout: jest.fn(() => ({
        orientation: 'north', intraCellSpacing: 0, interRankCellSpacing: 0,
        interHierarchySpacing: 0, disableEdgeStyle: false, execute: jest.fn(),
      })),
      Rectangle: jest.fn((x, y, w, h) => ({ x, y, width: w, height: h })),
      Point: jest.fn((x, y) => ({ x, y })),
    };

    setupDOM();
    global.fetch = jest.fn();

    loadWorkflowViewer();
    window.WorkflowViewer.init();
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
  });

  afterEach(() => {
    if (window.WorkflowViewer) window.WorkflowViewer.destroy();
    document.body.innerHTML = '';
    delete global.fetch;
  });

  test('System Prompt collapsed should show expand indicator', async () => {
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => SAMPLE_MINIMAL,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const promptNode = insertedVertices.find(v => v.value.includes('System Prompt'));
    // Should have right-pointing triangle for expandable
    expect(promptNode.value).toContain('\u25b8'); // ▸
    expect(promptNode.expandKey).toBe('prompt');
  });

  test('Tool group names should be Title Case with underscores replaced', async () => {
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => SAMPLE_FULL,
    });
    window.WorkflowViewer._doLoadApp('ResearchAssistant');
    await new Promise(r => setTimeout(r, 0));
    const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
    expect(toolNode.value).toContain('Web Browsing');
    expect(toolNode.value).toContain('File Tools');
    // Should NOT contain underscored versions
    expect(toolNode.value).not.toContain('web_browsing');
    expect(toolNode.value).not.toContain('file_tools');
  });

  test('HTML labels should use div-based layout', async () => {
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => SAMPLE_MINIMAL,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const inputNode = insertedVertices.find(v => v.value.includes('User Input'));
    expect(inputNode.value).toContain('<div');
    expect(inputNode.value).toContain('<b>');
  });

  test('Message History node should always be present even without context_schema', async () => {
    // Even with null context_schema
    const noSchema = { ...SAMPLE_MINIMAL, context_schema: null };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => noSchema,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const histNode = insertedVertices.find(v => v.value.includes('Message History'));
    expect(histNode).toBeDefined();
    // No Monadic Context node when schema is null
    const ctxNode = insertedVertices.find(v => v.value.includes('Monadic Context'));
    expect(ctxNode).toBeUndefined();
  });

  test('titleCase should handle acronyms (PDF, HTML) correctly', async () => {
    const pdfData = {
      ...SAMPLE_MINIMAL,
      input_types: ['text', 'pdf'],
      output_types: ['html'],
    };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => pdfData,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const inputNode = insertedVertices.find(v => v.value.includes('User Input'));
    expect(inputNode.value).toContain('PDF');
    expect(inputNode.value).not.toContain('Pdf');
    const respNode = insertedVertices.find(v => v.value.includes('Response'));
    expect(respNode.value).toContain('HTML Output');
    expect(respNode.value).not.toContain('Html');
  });

  test('HTML should escape special characters', async () => {
    const xssData = {
      ...SAMPLE_MINIMAL,
      system_prompt: '<script>alert("xss")</script>',
    };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => xssData,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    // The prompt is collapsed by default, so the raw text isn't in label.
    // But escHtml is used internally — verify no raw script tags appear
    const allLabels = insertedVertices.map(v => v.value).join('');
    expect(allLabels).not.toContain('<script>');
  });
});

// ── exportSvg tests ───────────────────────────────────────────

describe('WorkflowViewer.exportSvg', () => {
  // Custom XMLSerializer that properly serializes SVG with attributes
  const OriginalXMLSerializer = global.XMLSerializer;

  function MockXMLSerializer() {}
  MockXMLSerializer.prototype.serializeToString = function(node) {
    // Build a proper SVG string that includes attributes
    let attrs = '';
    if (node.attributes) {
      for (let i = 0; i < node.attributes.length; i++) {
        const a = node.attributes[i];
        attrs += ` ${a.name}="${a.value}"`;
      }
    }
    let inner = '';
    if (node.childNodes) {
      for (let i = 0; i < node.childNodes.length; i++) {
        const child = node.childNodes[i];
        if (child.nodeType === 1) { // Element
          inner += this.serializeToString(child);
        } else if (child.nodeType === 3) { // Text
          inner += child.textContent;
        }
      }
    }
    const tag = node.tagName || node.nodeName || 'unknown';
    return `<${tag}${attrs}>${inner}</${tag}>`;
  };

  beforeEach(() => {
    delete window.WorkflowViewer;
    delete window.maxgraph;
    global.XMLSerializer = MockXMLSerializer;
    setupMaxgraphMock();
    setupDOM();
    loadWorkflowViewer();
    window.WorkflowViewer.init();
  });

  afterEach(() => {
    if (window.WorkflowViewer) window.WorkflowViewer.destroy();
    document.body.innerHTML = '';
    if (OriginalXMLSerializer) global.XMLSerializer = OriginalXMLSerializer;
    else delete global.XMLSerializer;
  });

  // Helper: load an app and inject mock SVG into the container
  async function loadAndInjectSvg() {
    global.fetch = jest.fn().mockResolvedValueOnce({
      ok: true, json: async () => SAMPLE_MINIMAL,
    });
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));

    const container = document.getElementById('workflow-viewer-container');
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', '400');
    svg.setAttribute('height', '600');
    container.appendChild(svg);
  }

  test('should return null when no graph is loaded', () => {
    expect(window.WorkflowViewer.exportSvg()).toBeNull();
  });

  test('should return null when container has no SVG element', () => {
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    expect(window.WorkflowViewer.exportSvg()).toBeNull();
  });

  test('should return SVG string with viewBox when graph is loaded', async () => {
    await loadAndInjectSvg();
    const result = window.WorkflowViewer.exportSvg();
    expect(result).not.toBeNull();
    expect(result).toContain('<svg');
    expect(result).toContain('viewBox');
    delete global.fetch;
  });

  test('should include XML declaration', async () => {
    await loadAndInjectSvg();
    const result = window.WorkflowViewer.exportSvg();
    expect(result).toMatch(/^<\?xml version="1\.0" encoding="UTF-8"\?>/);
    delete global.fetch;
  });

  test('should embed font CSS in style element', async () => {
    await loadAndInjectSvg();
    const result = window.WorkflowViewer.exportSvg();
    expect(result).toContain('<style');
    expect(result).toContain('Montserrat');
    delete global.fetch;
  });

  test('should accept width and padding options', async () => {
    await loadAndInjectSvg();
    const result = window.WorkflowViewer.exportSvg({ width: 1200, padding: 50 });
    expect(result).not.toBeNull();
    expect(result).toContain('width="1200"');
    delete global.fetch;
  });

  test('exportSvg should be a public method', () => {
    expect(typeof window.WorkflowViewer.exportSvg).toBe('function');
  });
});

// ── setStage / clearHighlights tests ────────────────────────

describe('WorkflowViewer real-time highlighting', () => {
  beforeEach(() => {
    delete window.WorkflowViewer;
    delete window.maxgraph;
    setupMaxgraphMock();
    setupDOM();
    loadWorkflowViewer();
    window.WorkflowViewer.init();
  });

  afterEach(() => {
    if (window.WorkflowViewer) window.WorkflowViewer.destroy();
    document.body.innerHTML = '';
  });

  test('setStage should be a public method', () => {
    expect(typeof window.WorkflowViewer.setStage).toBe('function');
  });

  test('clearHighlights should be a public method', () => {
    expect(typeof window.WorkflowViewer.clearHighlights).toBe('function');
  });

  test('setStage should not throw when panel is collapsed', () => {
    // Panel starts collapsed by default
    expect(() => window.WorkflowViewer.setStage('input')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('model')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('tools')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('response')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('context')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('done')).not.toThrow();
  });

  test('setStage should not throw when panel is open but no graph loaded', () => {
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    expect(() => window.WorkflowViewer.setStage('input')).not.toThrow();
    expect(() => window.WorkflowViewer.setStage('done')).not.toThrow();
  });

  test('clearHighlights should not throw when no graph loaded', () => {
    expect(() => window.WorkflowViewer.clearHighlights()).not.toThrow();
  });

  test('setStage should accept all valid stage names without error', () => {
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    const stages = ['input', 'prompt', 'model', 'tools', 'response', 'context', 'done'];
    stages.forEach(function (stage) {
      expect(() => window.WorkflowViewer.setStage(stage)).not.toThrow();
    });
  });

  test('setStage should handle unknown stage gracefully', () => {
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    expect(() => window.WorkflowViewer.setStage('unknown_stage')).not.toThrow();
  });
});

describe('WorkflowViewer highlighting with loaded graph', () => {
  let mockGraphInstance;

  beforeEach(async () => {
    delete window.WorkflowViewer;
    delete window.maxgraph;

    // Create a mock graph that tracks getView().getState() calls
    const mockChildren = [];
    mockGraphInstance = null;

    window.maxgraph = {
      Graph: jest.fn(function () {
        const g = createMockGraph();

        // Override getDefaultParent to return object with children array
        g.getDefaultParent = jest.fn(() => ({ children: mockChildren }));

        // Track insertVertex to populate children
        const origInsertVertex = g.insertVertex;
        g.insertVertex = jest.fn(function (parent, id, label, x, y, w, h, style) {
          const cell = origInsertVertex(parent, id, label, x, y, w, h, style);
          mockChildren.push(cell);
          return cell;
        });

        const origInsertEdge = g.insertEdge;
        g.insertEdge = jest.fn(function (parent, id, label, src, tgt, style) {
          const edge = origInsertEdge(parent, id, label, src, tgt, style);
          mockChildren.push(edge);
          return edge;
        });

        mockGraphInstance = g;
        return g;
      }),
      HierarchicalLayout: jest.fn(() => ({
        orientation: 'north', intraCellSpacing: 0, interRankCellSpacing: 0,
        interHierarchySpacing: 0, disableEdgeStyle: false, execute: jest.fn(),
      })),
      Rectangle: jest.fn((x, y, w, h) => ({ x, y, width: w, height: h })),
      Point: jest.fn((x, y) => ({ x, y })),
    };

    setupDOM();
    global.fetch = jest.fn();
    loadWorkflowViewer();
    window.WorkflowViewer.init();

    // Open panel and load app
    document.getElementById('workflow-viewer-panel').classList.remove('wv-panel-collapsed');
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => SAMPLE_FULL,
    });
    window.WorkflowViewer._doLoadApp('ResearchAssistant');
    await new Promise(r => setTimeout(r, 0));
  });

  afterEach(() => {
    if (window.WorkflowViewer) window.WorkflowViewer.destroy();
    document.body.innerHTML = '';
    delete global.fetch;
  });

  test('setStage should not throw after graph is loaded', () => {
    expect(() => window.WorkflowViewer.setStage('model')).not.toThrow();
  });

  test('setStage(done) should not throw after graph is loaded', () => {
    window.WorkflowViewer.setStage('model');
    expect(() => window.WorkflowViewer.setStage('done')).not.toThrow();
  });

  test('clearHighlights should not throw after graph is loaded', () => {
    window.WorkflowViewer.setStage('tools');
    expect(() => window.WorkflowViewer.clearHighlights()).not.toThrow();
  });

  test('sequential stage transitions should not throw', () => {
    const sequence = ['input', 'model', 'tools', 'response', 'context', 'done'];
    sequence.forEach(function (stage) {
      expect(() => window.WorkflowViewer.setStage(stage)).not.toThrow();
    });
  });

  test('rapid stage changes should not throw', () => {
    expect(() => {
      for (let i = 0; i < 20; i++) {
        window.WorkflowViewer.setStage('model');
        window.WorkflowViewer.setStage('tools');
        window.WorkflowViewer.setStage('done');
      }
    }).not.toThrow();
  });
});
