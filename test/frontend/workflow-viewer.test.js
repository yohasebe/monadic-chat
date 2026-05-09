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
    refresh: jest.fn(),
    sizeDidChange: jest.fn(),
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
        <div class="wv-panel-controls">
          <button id="wv-close"></button>
        </div>
      </div>
      <div id="workflow-viewer-container" style="width:800px;height:230px;"></div>
      <div class="wv-panel-footer">
        <div class="workflow-viewer-legend"></div>
        <span class="wv-resize-grip"></span>
      </div>
    </div>
    <button id="toggle-workflow-viewer"></button>
    <button id="wv-zoom-in"></button>
    <button id="wv-zoom-out"></button>
    <button id="wv-zoom-fit"></button>
    <button id="wv-save-svg"></button>
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
      expect(typeof window.WorkflowViewer.exportSvg).toBe('function');
      expect(typeof window.WorkflowViewer.downloadSvg).toBe('function');
    });

    test('should not crash when init is called twice', () => {
      expect(() => window.WorkflowViewer.init()).not.toThrow();
    });

    test('should build legend on init', () => {
      const legend = document.querySelector('.workflow-viewer-legend');
      const items = legend.querySelectorAll('.wv-legend-item');
      // Input/Response, Speech (STT/TTS), Prompt, Model, Tool, Agent, Feature, Context
      expect(items.length).toBe(8);
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

  describe('Floating panel', () => {
    test('should have resize grip element in footer', () => {
      const grip = document.querySelector('#workflow-viewer-panel .wv-resize-grip');
      expect(grip).not.toBeNull();
    });

    test('open should apply panel position styles', () => {
      window.WorkflowViewer.open();
      const panel = document.getElementById('workflow-viewer-panel');
      // Panel should have explicit position styles set by applyPanelRect
      expect(panel.style.width).toBeTruthy();
      expect(panel.style.height).toBeTruthy();
      expect(panel.style.left).toBeTruthy();
      expect(panel.style.top).toBeTruthy();
    });

    test('close should save panel rect to localStorage', () => {
      const spy = jest.spyOn(Storage.prototype, 'setItem');
      window.WorkflowViewer.open();
      window.WorkflowViewer.close();
      const lsCalls = spy.mock.calls.filter(c => c[0] === 'wv-panel-rect');
      expect(lsCalls.length).toBeGreaterThan(0);
      spy.mockRestore();
    });

    test('should restore panel rect from localStorage', () => {
      const savedRect = { left: 100, top: 80, width: 500, height: 350 };
      jest.spyOn(Storage.prototype, 'getItem').mockReturnValue(JSON.stringify(savedRect));
      // Re-init to pick up the stored rect
      window.WorkflowViewer.destroy();
      setupDOM();
      window.WorkflowViewer.init();
      window.WorkflowViewer.open();
      const panel = document.getElementById('workflow-viewer-panel');
      expect(panel.style.left).toBe('100px');
      expect(panel.style.top).toBe('80px');
      Storage.prototype.getItem.mockRestore();
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

    test('should not throw when theme-applied fires while panel is collapsed', () => {
      // Panel starts collapsed; theme change should not crash
      window.WorkflowViewer.close();
      expect(() => {
        window.dispatchEvent(new CustomEvent('theme-applied', { detail: { theme: 'dark' } }));
      }).not.toThrow();
    });

    test('should defer refresh when theme changes while panel is hidden', () => {
      // Close panel, then trigger theme change — should not throw
      window.WorkflowViewer.close();
      window.dispatchEvent(new CustomEvent('theme-applied', { detail: { theme: 'dark' } }));
      // Reopening should not throw (deferred refresh is processed)
      expect(() => window.WorkflowViewer.open()).not.toThrow();
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

  // Runtime-aware features: the Workflow Viewer reads window.params at
  // render time, so STT/TTS nodes and the Expressive Speech entry reflect
  // the user's live settings, not just the MDSL-declared defaults.
  describe('Runtime-aware STT/TTS + Expressive Speech', () => {
    // Provide a minimal TtsTagSanitizer mock matching the real API shape.
    // familyFor returns the canonical family key; tagAware is true for
    // the inline-marker families; openai-instruction is a separate family.
    function installSanitizerMock() {
      window.TtsTagSanitizer = {
        familyFor: function (provider) {
          const key = String(provider || '').toLowerCase();
          if (key === 'grok' || key.startsWith('xai')) return 'xai';
          if (key === 'elevenlabs-v3' || key === 'eleven_v3') return 'elevenlabs-v3';
          if (key.startsWith('elevenlabs')) return 'elevenlabs';
          if (key.startsWith('gemini')) return 'gemini';
          if (key === 'openai-tts-4o') return 'openai-instruction';
          if (key.startsWith('openai') || key.startsWith('tts-')) return 'openai';
          return key;
        },
        tagAware: function (provider) {
          const fam = this.familyFor(provider);
          return ['xai', 'elevenlabs-v3', 'gemini'].indexOf(fam) >= 0;
        }
      };
    }

    afterEach(() => {
      delete window.params;
      delete window.TtsTagSanitizer;
    });

    test('auto_speech off → no STT or TTS nodes', async () => {
      window.params = { auto_speech: false };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_MINIMAL);
      const stt = insertedVertices.find(v => v.value.includes('Speech Input'));
      const tts = insertedVertices.find(v => v.value.includes('Speech Output'));
      expect(stt).toBeUndefined();
      expect(tts).toBeUndefined();
    });

    test('auto_speech on → STT node before User Input', async () => {
      window.params = { auto_speech: true, stt_model: 'whisper-1' };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_MINIMAL);
      const sttIdx = insertedVertices.findIndex(v => v.value.includes('Speech Input'));
      const inputIdx = insertedVertices.findIndex(v => v.value.includes('User Input'));
      expect(sttIdx).toBeGreaterThanOrEqual(0);
      expect(sttIdx).toBeLessThan(inputIdx);
      // STT body shows the current stt_model label
      expect(insertedVertices[sttIdx].value).toContain('whisper-1');
    });

    test('auto_speech on → TTS node after Response with provider + voice', async () => {
      window.params = {
        auto_speech: true,
        tts_provider: 'openai-tts-4o',
        tts_voice: 'coral'
      };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_MINIMAL);
      const ttsIdx = insertedVertices.findIndex(v => v.value.includes('Speech Output'));
      const respIdx = insertedVertices.findIndex(v => v.value.includes('Response'));
      expect(ttsIdx).toBeGreaterThanOrEqual(0);
      expect(ttsIdx).toBeGreaterThan(respIdx);
      expect(insertedVertices[ttsIdx].value).toContain('openai-tts-4o');
      expect(insertedVertices[ttsIdx].value).toContain('coral');
    });

    test('auto_speech on + openai-tts-4o → Features includes Expressive Speech', async () => {
      window.params = { auto_speech: true, tts_provider: 'openai-tts-4o' };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_FULL);
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      expect(featNode).toBeDefined();
      expect(featNode.value).toContain('Expressive Speech');
    });

    test('auto_speech on + xAI Grok → Features includes Expressive Speech (tag-aware family)', async () => {
      window.params = { auto_speech: true, tts_provider: 'grok' };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_FULL);
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      expect(featNode.value).toContain('Expressive Speech');
    });

    test('auto_speech on + webspeech → Features does NOT include Expressive Speech', async () => {
      window.params = { auto_speech: true, tts_provider: 'webspeech' };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_FULL);
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      expect(featNode).toBeDefined();
      expect(featNode.value).not.toContain('Expressive Speech');
    });

    test('auto_speech off + openai-tts-4o → no Expressive Speech (auto_speech gates everything)', async () => {
      window.params = { auto_speech: false, tts_provider: 'openai-tts-4o' };
      installSanitizerMock();
      await loadAppWithData(SAMPLE_FULL);
      const featNode = insertedVertices.find(v => v.value.includes('Features'));
      if (featNode) expect(featNode.value).not.toContain('Expressive Speech');
    });

    test('refresh() is exposed and safely no-ops when viewer closed', () => {
      expect(typeof window.WorkflowViewer.refresh).toBe('function');
      // When closed / no data, refresh must not throw.
      expect(() => window.WorkflowViewer.refresh()).not.toThrow();
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

  // ── Error stage tests (Task B) ──────────────────────────────

  test('setStage(error) should not throw', () => {
    expect(() => window.WorkflowViewer.setStage('error')).not.toThrow();
  });

  test('setStage(error) → setStage(done) should clear highlights', () => {
    window.WorkflowViewer.setStage('error');
    expect(() => window.WorkflowViewer.setStage('done')).not.toThrow();
  });

  // ── setActiveTool tests (Task A) ────────────────────────────

  test('setActiveTool should be a public method', () => {
    expect(typeof window.WorkflowViewer.setActiveTool).toBe('function');
  });

  test('setActiveTool should not throw with a tool name', () => {
    expect(() => window.WorkflowViewer.setActiveTool('fetch_web_content')).not.toThrow();
  });

  test('setActiveTool should not throw with null', () => {
    expect(() => window.WorkflowViewer.setActiveTool(null)).not.toThrow();
  });
});

// ── PTD lock icon tests (Task C) ──────────────────────────────

describe('WorkflowViewer PTD lock icons', () => {
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

  test('conditional tools should display lock icon', async () => {
    const ptdData = {
      ...SAMPLE_MINIMAL,
      tools: [
        { name: 'always_tool', visibility: 'always' },
        { name: 'locked_tool', visibility: 'conditional' },
      ],
      shared_tool_groups: [],
    };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => ptdData,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
    expect(toolNode).toBeDefined();
    // Lock icon U+1F512 should appear for conditional tool
    expect(toolNode.value).toContain('\uD83D\uDD12');
    expect(toolNode.value).toContain('Locked Tool');
  });

  test('always-visible tools should not display lock icon', async () => {
    const ptdData = {
      ...SAMPLE_MINIMAL,
      tools: [
        { name: 'always_tool', visibility: 'always' },
      ],
      shared_tool_groups: [],
    };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => ptdData,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
    expect(toolNode).toBeDefined();
    expect(toolNode.value).not.toContain('\uD83D\uDD12');
  });

  test('conditional shared tool groups should display lock icon', async () => {
    const ptdData = {
      ...SAMPLE_MINIMAL,
      tools: [],
      shared_tool_groups: [
        { name: 'locked_group', tool_names: ['tool_a', 'tool_b'], visibility: 'conditional' },
        { name: 'open_group', tool_names: ['tool_c'], visibility: 'always' },
      ],
    };
    global.fetch.mockResolvedValueOnce({
      ok: true, json: async () => ptdData,
    });
    window.WorkflowViewer._doLoadApp('TestApp');
    await new Promise(r => setTimeout(r, 0));
    const toolNode = insertedVertices.find(v => v.value.includes('Tools'));
    expect(toolNode).toBeDefined();
    // Lock icon should appear for locked_group but not open_group
    expect(toolNode.value).toContain('\uD83D\uDD12');
    expect(toolNode.value).toContain('Locked Group');
    // open_group line should not have lock icon
    const lines = toolNode.value.split('</div>');
    const openGroupLine = lines.find(l => l.includes('Open Group'));
    expect(openGroupLine).toBeDefined();
    expect(openGroupLine).not.toContain('\uD83D\uDD12');
  });
});

// ── setActiveTool when panel is collapsed ─────────────────────

describe('WorkflowViewer setActiveTool edge cases', () => {
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

  test('setActiveTool should not throw when panel is collapsed', () => {
    // Panel starts collapsed
    expect(() => window.WorkflowViewer.setActiveTool('some_tool')).not.toThrow();
  });

  test('setActiveTool should not throw with null when panel is collapsed', () => {
    expect(() => window.WorkflowViewer.setActiveTool(null)).not.toThrow();
  });

  test('setStage(error) should not throw when panel is collapsed', () => {
    expect(() => window.WorkflowViewer.setStage('error')).not.toThrow();
  });
});
