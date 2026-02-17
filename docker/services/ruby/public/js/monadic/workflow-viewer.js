/**
 * Workflow Viewer — Floating Panel
 *
 * Visualises each MDSL app's internal pipeline as an interactive node graph
 * using maxGraph. Rendered inside a draggable, resizable floating panel.
 */

/* global maxgraph */

const WorkflowViewer = (function () {
  'use strict';

  let Graph, HierarchicalLayout, Rectangle, Point;

  // ── State ────────────────────────────────────────────────────
  let graph = null;
  let panelEl = null;
  let container = null;
  let currentApp = null;
  let pendingApp = null;
  let currentData = null;
  let expandedGroups = {};
  let tooltip = null;
  let initialised = false;
  let viewStates = {};       // Per-app saved view: { scale, tx, ty }
  let skipNextResize = false; // Suppress ResizeObserver after view restore
  let themeHandler = null;   // Stored for cleanup in destroy()
  let cellsByType = {};      // { 'input': cell, 'model': cell, ... }
  let edgesByKey = {};       // { 'input→prompt': edgeCell, ... }
  let activeStage = null;    // Current highlight stage
  let activeTool = null;     // Currently executing tool name
  let needsRefreshOnOpen = false; // Deferred graph refresh (e.g. theme changed while hidden)

  // ── Colours ──────────────────────────────────────────────────
  function colours() {
    var style = getComputedStyle(document.documentElement);
    var v = function (n, fb) { return style.getPropertyValue(n).trim() || fb; };
    var dk = document.documentElement.getAttribute('data-theme') === 'dark' ||
             document.documentElement.classList.contains('dark-theme');
    return {
      input:    dk ? '#1e3a5f' : '#dbeafe',  response:   dk ? '#1e3a5f' : '#dbeafe',
      prompt:   dk ? '#3b1f5e' : '#ede9fe',  model:      dk ? '#1a3a2a' : '#dcfce7',
      tool:     dk ? '#4a2c1a' : '#ffedd5',  toolGroup:  dk ? '#3d2a14' : '#fff7ed',
      agent:    dk ? '#3b1a1a' : '#fee2e2',  feature:    dk ? '#2a2a2a' : '#f3f4f6',
      context:  dk ? '#3a3520' : '#fef9c3',
      inputBdr:    dk ? '#3b82f6' : '#3b82f6',  responseBdr: dk ? '#3b82f6' : '#3b82f6',
      promptBdr:   dk ? '#8b5cf6' : '#7c3aed',  modelBdr:    dk ? '#22c55e' : '#16a34a',
      toolBdr:     dk ? '#f97316' : '#ea580c',  agentBdr:    dk ? '#ef4444' : '#dc2626',
      featureBdr:  dk ? '#6b7280' : '#9ca3af',  contextBdr:  dk ? '#eab308' : '#ca8a04',
      text:    v('--text-primary', '#333'),
      textSub: dk ? '#9ca3af' : '#6b7280',
      edge:    dk ? '#6b7280' : '#9ca3af',
    };
  }

  var LEGEND = [
    { label: 'Input/Response', colour: '#3b82f6' },
    { label: 'Prompt',         colour: '#7c3aed' },
    { label: 'Model',          colour: '#16a34a' },
    { label: 'Tool',           colour: '#ea580c' },
    { label: 'Agent',          colour: '#dc2626' },
    { label: 'Feature',        colour: '#9ca3af' },
    { label: 'Context',        colour: '#ca8a04' }
  ];

  // ── View state save/restore ─────────────────────────────────
  function saveViewState() {
    if (!graph || !currentApp) return;
    var view = graph.getView();
    viewStates[currentApp] = {
      scale: view.scale || 1,
      tx: (view.translate ? view.translate.x : 0),
      ty: (view.translate ? view.translate.y : 0)
    };
  }

  function restoreViewState() {
    if (!graph || !currentApp || !viewStates[currentApp]) return false;
    var vs = viewStates[currentApp];
    graph.getView().scaleAndTranslate(vs.scale, vs.tx, vs.ty);
    return true;
  }

  // ── Expand/collapse ──────────────────────────────────────────
  function getExpanded() {
    return (currentApp && expandedGroups[currentApp]) || new Set();
  }
  function toggleGroup(key) {
    if (!currentApp) return;
    if (!expandedGroups[currentApp]) expandedGroups[currentApp] = new Set();
    var s = expandedGroups[currentApp];
    if (s.has(key)) s.delete(key); else s.add(key);
    refreshGraph();
  }
  function refreshGraph() {
    if (!currentData || !container || !Graph) return;
    cellsByType = {};
    edgesByKey = {};
    activeStage = null;
    // Preserve zoom level across expand/collapse rebuild
    var savedScale = graph ? (graph.getView().scale || 1) : null;
    container.innerHTML = '';
    createGraph();
    renderGraph(buildGraphData(currentData, getExpanded()), !!savedScale);
    // Re-center graph at the preserved zoom level
    if (savedScale && graph) {
      var view = graph.getView();
      view.scaleAndTranslate(1, 0, 0);
      var bounds = graph.getGraphBounds();
      if (bounds && bounds.width > 0 && bounds.height > 0) {
        var cw = container.clientWidth, ch = container.clientHeight;
        if (cw > 0 && ch > 0) {
          var tx = -bounds.x + (cw / savedScale - bounds.width) / 2;
          var ty = -bounds.y + (ch / savedScale - bounds.height) / 2;
          view.scaleAndTranslate(savedScale, tx, ty);
        }
      }
    }
  }

  // ── Layout constants ───────────────────────────────────────
  var FONT_SIZE = 12;
  var LINE_H = 22;
  var HEAD_H = 26;
  var PAD = 10;
  var SIDE_GAP = 40;
  var OVERLAP_GAP = 12;

  // ── Style helpers ──────────────────────────────────────────
  function makeStyle(fill, stroke, extra) {
    var base = {
      shape: 'rectangle', rounded: true,
      fillColor: fill, strokeColor: stroke,
      fontColor: colours().text, fontSize: FONT_SIZE,
      fontFamily: 'Montserrat, sans-serif',
      whiteSpace: 'wrap', overflow: 'hidden',
      autoSize: false, resizable: false,
      align: 'left', verticalAlign: 'middle',
      spacingLeft: PAD, spacingRight: PAD,
      spacingTop: 6, spacingBottom: 6,
    };
    return Object.assign(base, extra || {});
  }

  function edgeStyle(dashed, noArrow, exitEntry) {
    var c = colours();
    var s = {
      strokeColor: c.edge, strokeWidth: 1.5,
      endArrow: noArrow ? 'none' : 'classic',
      endSize: noArrow ? 0 : 6,
      rounded: true,
      dashed: dashed ? true : false,
      dashPattern: dashed ? '5 3' : undefined,
    };
    if (exitEntry) Object.assign(s, exitEntry);
    return s;
  }

  function truncate(str, len) {
    return (!str) ? '' : (str.length > len ? str.substring(0, len - 1) + '\u2026' : str);
  }

  function escHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  var ACRONYMS = { pdf: 'PDF', html: 'HTML', api: 'API', url: 'URL', tts: 'TTS', stt: 'STT', abc: 'ABC' };
  function titleCase(str) {
    return str.replace(/\b\w+/g, function (w) {
      var lower = w.toLowerCase();
      return ACRONYMS[lower] || (w.charAt(0).toUpperCase() + w.slice(1));
    });
  }

  /**
   * Build an HTML label for a node.
   * opts: expandable, collapsible, separator, noBullets, scrollText, scrollHeight
   */
  function label(heading, bodyLines, opts) {
    opts = opts || {};
    var c = colours();
    var sub = opts.subColor || c.textSub;

    // Heading with expand/collapse indicator
    var headHtml = heading || '';
    if (opts.expandable) headHtml = '<span style="opacity:0.4">\u25b8</span> ' + headHtml;
    else if (opts.collapsible) headHtml = '<span style="opacity:0.4">\u25be</span> ' + headHtml;

    var html = '<div style="line-height:' + HEAD_H + 'px"><b>' + headHtml + '</b></div>';

    // Scrollable text area (System Prompt expanded)
    if (opts.scrollText) {
      html += '<div style="border-top:1px solid rgba(128,128,128,0.3);margin-top:2px;padding-top:4px">';
      html += '<div class="wv-scroll-text" style="max-height:' + (opts.scrollHeight || 120) + 'px;' +
              'color:' + sub + ';font-size:' + FONT_SIZE + 'px;' +
              'pointer-events:auto">' + escHtml(opts.scrollText) + '</div>';
      html += '</div>';
      return html;
    }

    // Regular body lines
    if (bodyLines && bodyLines.length > 0) {
      var useBullets = !opts.noBullets;
      var bodyHtml = bodyLines.map(function (l) {
        var prefix = useBullets ? '\u2022 ' : '';
        return '<div style="line-height:' + LINE_H + 'px;font-weight:normal;color:' + sub + '">' + prefix + l + '</div>';
      }).join('');

      if (opts.separator) {
        html += '<div style="border-top:1px solid rgba(128,128,128,0.3);margin-top:2px;padding-top:4px">' + bodyHtml + '</div>';
      } else {
        html += '<div style="margin-top:4px">' + bodyHtml + '</div>';
      }
    }

    return html;
  }

  function calcSize(bodyCount, minW, opts) {
    opts = opts || {};
    var h = HEAD_H;
    if (opts.scrollArea) {
      h += 22 + opts.scrollArea;
    } else if (bodyCount > 0) {
      h += 6 + bodyCount * LINE_H;
    }
    return { w: minW || 180, h: h + PAD * 2 };
  }

  // ── Overlap resolution ──────────────────────────────────────

  /**
   * After Phase 3 positioning, detect and resolve node overlaps.
   * Only side nodes are moved; flow nodes stay fixed.
   */
  function resolveOverlaps(cellMap, graphData) {
    var flowSet = {};
    graphData.nodes.forEach(function (n) { if (n.flow) flowSet[n.id] = true; });

    var cells = [];
    graphData.nodes.forEach(function (n) {
      var c = cellMap[n.id];
      if (!c || !c.geometry) return;
      cells.push({ id: n.id, geo: c.geometry, movable: !flowSet[n.id] });
    });

    for (var iter = 0; iter < 10; iter++) {
      var moved = false;
      cells.sort(function (a, b) { return a.geo.y - b.geo.y; });

      for (var i = 0; i < cells.length; i++) {
        for (var j = i + 1; j < cells.length; j++) {
          var a = cells[i], b = cells[j];
          if (!b.movable) continue;
          // Must overlap horizontally
          if (a.geo.x + a.geo.width <= b.geo.x || b.geo.x + b.geo.width <= a.geo.x) continue;
          // Check vertical overlap
          var needed = a.geo.y + a.geo.height + OVERLAP_GAP;
          if (needed > b.geo.y) {
            b.geo.y = needed;
            moved = true;
          }
        }
      }
      if (!moved) break;
    }
  }

  // ── Graph data adapter ───────────────────────────────────────

  function buildGraphData(data, expanded) {
    expanded = expanded || new Set();
    var nodes = [];
    var flowEdges = [];
    var sideEdges = [];
    var id = 0;
    var nid = function () { return 'n' + (++id); };

    // 1. User Input
    var inputId = nid();
    var inputTypes = data.input_types || ['text'];
    var inputBody = (inputTypes.length > 1) ? inputTypes.map(function (t) { return titleCase(t); }) : [];
    nodes.push({ id: inputId, type: 'input', heading: 'User Input', body: inputBody, flow: true });

    // 2. System Prompt — expandable (scrollable when expanded)
    var promptId = nid();
    var promptExp = expanded.has('prompt');
    nodes.push({
      id: promptId, type: 'prompt', heading: 'System Prompt',
      body: [], flow: true,
      promptText: promptExp ? (data.system_prompt || null) : null,
      expandKey: promptExp ? null : 'prompt',
      collapseKey: promptExp ? 'prompt' : null,
      tooltip: promptExp ? 'Click to collapse' : 'Click to show excerpt'
    });
    flowEdges.push({ from: inputId, to: promptId });

    // 3. Model — expandable
    var modelLabel = (data.models && data.models[0]) || 'model';
    var modelId = nid();
    var core = data.core || {};
    var modelExp = expanded.has('model');
    var modelBody = [];
    if (modelExp) {
      if (data.provider) modelBody.push('provider: ' + data.provider);
      if ((data.models || []).length > 1) modelBody.push('models: ' + data.models.join(', '));
      if (core.temperature != null) modelBody.push('temperature: ' + core.temperature);
      if (core.reasoning_effort) modelBody.push('reasoning: ' + core.reasoning_effort);
      if (core.context_size) modelBody.push('context: ' + core.context_size + ' msgs');
      if (core.max_tokens) modelBody.push('max tokens: ' + core.max_tokens);
    }
    nodes.push({
      id: modelId, type: 'model', heading: truncate(modelLabel, 28), body: modelBody, flow: true,
      expandKey: modelExp ? null : 'model',
      collapseKey: modelExp ? 'model' : null,
      tooltip: modelExp ? 'Click to collapse' : 'Click to show parameters'
    });
    flowEdges.push({ from: promptId, to: modelId });

    // 4. Response
    var responseId = nid();
    var outTypes = data.output_types || [];
    var responseBody = outTypes.map(function (t) { return titleCase(t + ' output'); });
    nodes.push({ id: responseId, type: 'response', heading: 'Response', body: responseBody, flow: true });
    flowEdges.push({ from: modelId, to: responseId });

    // ── Tools — side node of Model ──────────────────────────────
    var tools = data.tools || [];
    var sharedGroups = data.shared_tool_groups || [];
    var hasTools = tools.length > 0 || sharedGroups.length > 0;

    if (hasTools) {
      var grouped = new Set();
      sharedGroups.forEach(function (g) { (g.tool_names || []).forEach(function (n) { grouped.add(n); }); });
      var inlineTools = tools.filter(function (t) { return !grouped.has(t.name); });

      var toolBody = [];
      sharedGroups.forEach(function (g) {
        var names = g.tool_names || [];
        var gk = 'tg:' + g.name;
        var isExp = expanded.has(gk);
        var arrow = (names.length > 0) ? (isExp ? '\u25be ' : '\u25b8 ') : '';
        var gLock = (g.visibility === 'conditional') ? '\uD83D\uDD12 ' : '';
        toolBody.push(arrow + gLock + titleCase(g.name.replace(/_/g, ' ')) + ' (' + names.length + ')');
        if (isExp) names.forEach(function (n) { toolBody.push('\u00a0\u00a0\u00a0\u00a0' + titleCase(n.replace(/_/g, ' '))); });
      });
      inlineTools.forEach(function (t) {
        var tLock = (t.visibility === 'conditional') ? '\uD83D\uDD12 ' : '';
        toolBody.push(tLock + titleCase(t.name.replace(/_/g, ' ')));
      });

      var toolId = nid();
      nodes.push({
        id: toolId, type: 'toolGroup', heading: 'Tools', body: toolBody,
        flow: false, sideOf: modelId, side: 'right',
        isToolContainer: true, tooltip: 'Click a group to expand/collapse'
      });
      sideEdges.push({ from: modelId, to: toolId, dashed: true, direction: 'right' });
    }

    // ── Agents — side nodes of Model ────────────────────────────
    var agents = data.agents || {};
    Object.keys(agents).forEach(function (name) {
      var aId = nid();
      var ak = 'agent:' + name;
      var aExp = expanded.has(ak);
      var aBody = aExp ? ['model: ' + agents[name]] : [];
      nodes.push({
        id: aId, type: 'agent', heading: titleCase(name.replace(/_/g, ' ')), body: aBody,
        flow: false, sideOf: modelId, side: 'right',
        expandKey: aExp ? null : ak, collapseKey: aExp ? ak : null,
        tooltip: aExp ? 'Click to collapse' : 'Click to show details'
      });
      sideEdges.push({ from: modelId, to: aId, dashed: true, direction: 'right' });
    });

    // ── Features — side node of Model (right) ─────────────────
    var features = data.features || {};
    var onFeatures = Object.keys(features).filter(function (f) { return features[f]; });
    if (onFeatures.length > 0) {
      var fId = nid();
      nodes.push({
        id: fId, type: 'feature', heading: 'Features',
        body: onFeatures.map(function (f) { return titleCase(f.replace(/_/g, ' ')); }),
        flow: false, sideOf: modelId, side: 'right'
      });
      sideEdges.push({ from: modelId, to: fId, dashed: true, noArrow: true, direction: 'right' });
    }

    // ── Message History — always shown, left of Response ─────────
    var hId = nid();
    nodes.push({
      id: hId, type: 'history', heading: 'Message History',
      body: [],
      flow: false, sideOf: responseId, side: 'left'
    });
    sideEdges.push({ from: responseId, to: hId, dashed: true, noArrow: true, direction: 'left' });

    // ── Monadic Context — only when context_schema has fields ──
    var ctx = data.context_schema;
    var hasContext = ctx && ctx.fields && ctx.fields.length > 0;
    var cId = hasContext ? nid() : null;
    if (hasContext) {
      var contextBody = ctx.fields.map(function (f) { return f.label || f.name; });
      nodes.push({
        id: cId, type: 'context', heading: 'Monadic Context',
        body: contextBody,
        flow: false, sideOf: responseId, side: 'left'
      });
      sideEdges.push({ from: responseId, to: cId, dashed: true, direction: 'left' });
    }

    var feedbackEdges = [{ from: hId, to: inputId }];
    if (hasContext) {
      feedbackEdges.push({ from: cId, to: inputId });
    }

    return {
      nodes: nodes, flowEdges: flowEdges, sideEdges: sideEdges,
      feedbackEdges: feedbackEdges
    };
  }

  // ── Node styles ──────────────────────────────────────────────

  function getNodeStyle(type) {
    var c = colours();
    switch (type) {
    case 'input': case 'response':
      return makeStyle(c.input, c.inputBdr, { arcSize: 40 });
    case 'prompt':
      return makeStyle(c.prompt, c.promptBdr, { rounded: false });
    case 'model':
      return makeStyle(c.model, c.modelBdr);
    case 'toolGroup':
      return makeStyle(c.toolGroup, c.toolBdr, { strokeWidth: 1.5 });
    case 'agent':
      return makeStyle(c.agent, c.agentBdr, { strokeWidth: 1.5 });
    case 'feature':
      return makeStyle(c.feature, c.featureBdr);
    case 'history':
    case 'context':
      return makeStyle(c.context, c.contextBdr);
    default:
      return makeStyle(c.feature, c.featureBdr);
    }
  }

  // ── Rendering ────────────────────────────────────────────────

  function renderGraph(graphData, skipFit) {
    if (!graph) return;
    var parent = graph.getDefaultParent();
    var cellMap = {};
    var sideNodes = [];

    // Phase 1: insert all nodes + flow edges
    graph.batchUpdate(function () {
      graphData.nodes.forEach(function (n) {
        var bodyCount = n.body ? n.body.length : 0;
        var isExpanded = !!n.collapseKey;
        var hasScrollText = !!n.promptText;
        var isSideWithBody = !n.flow && bodyCount > 0;

        // Build label
        var lbl;
        if (hasScrollText) {
          lbl = label(n.heading, null, {
            collapsible: true, scrollText: n.promptText, scrollHeight: 120
          });
        } else {
          lbl = label(n.heading, n.body, {
            expandable: !!n.expandKey, collapsible: !!n.collapseKey,
            subColor: colours().textSub,
            separator: (isExpanded && bodyCount > 0) || isSideWithBody,
            noBullets: n.isToolContainer
          });
        }

        // Determine width
        var minW;
        if (hasScrollText) minW = 320;
        else if (n.isToolContainer) minW = 240;
        else if (n.type === 'feature' || n.type === 'context' || n.type === 'history') minW = 200;
        else minW = 220;

        // Determine size
        var size;
        if (hasScrollText) {
          size = calcSize(0, minW, { scrollArea: 120 });
        } else {
          size = calcSize(bodyCount, minW);
        }

        var cell = graph.insertVertex(parent, n.id, lbl, 0, 0, size.w, size.h, getNodeStyle(n.type));
        if (n.tooltip) cell.tooltip = n.tooltip;
        if (n.expandKey) cell.expandKey = n.expandKey;
        if (n.collapseKey) cell.collapseKey = n.collapseKey;
        if (n.isToolContainer) cell.isToolContainer = true;
        cell.nodeType = n.type;
        cellsByType[n.type] = cell;
        cellMap[n.id] = cell;

        if (!n.flow) {
          cell._sideOf = n.sideOf;
          sideNodes.push({ id: n.id, sideOf: n.sideOf, side: n.side || 'right' });
        }
      });

      graphData.flowEdges.forEach(function (e) {
        var src = cellMap[e.from], tgt = cellMap[e.to];
        if (src && tgt) {
          var edgeCell = graph.insertEdge(parent, null, '', src, tgt, edgeStyle(e.dashed, e.noArrow));
          edgesByKey[src.id + '\u2192' + tgt.id] = edgeCell;
        }
      });
    });

    // Phase 2: hierarchical layout on flow nodes only
    // Hide side nodes so layout ignores them
    sideNodes.forEach(function (sn) {
      var c = cellMap[sn.id];
      if (c) c.setVisible(false);
    });

    var layout = new HierarchicalLayout(graph);
    layout.orientation = 'north';
    layout.intraCellSpacing = 24;
    layout.interRankCellSpacing = 32;
    layout.interHierarchySpacing = 24;
    layout.disableEdgeStyle = false;
    layout.execute(parent);

    // Phase 3: position side nodes on left/right, center-aligned with parent
    graph.batchUpdate(function () {
      var leftSide = [], rightSide = [];
      sideNodes.forEach(function (sn) {
        if (sn.side === 'left') leftSide.push(sn);
        else rightSide.push(sn);
      });

      // Helper: position a column of side nodes
      function positionColumn(nodes, direction) {
        if (nodes.length === 0) return;
        var byParent = {};
        nodes.forEach(function (sn) {
          if (!byParent[sn.sideOf]) byParent[sn.sideOf] = [];
          byParent[sn.sideOf].push(sn.id);
        });

        var pids = Object.keys(byParent).sort(function (a, b) {
          var ya = cellMap[a] && cellMap[a].geometry ? cellMap[a].geometry.y : 0;
          var yb = cellMap[b] && cellMap[b].geometry ? cellMap[b].geometry.y : 0;
          return ya - yb;
        });

        // For right column: consistent X from max right-edge of parents
        var colX;
        if (direction === 'right') {
          colX = 0;
          pids.forEach(function (pid) {
            var pc = cellMap[pid];
            if (pc && pc.geometry) {
              var re = pc.geometry.x + pc.geometry.width + SIDE_GAP;
              if (re > colX) colX = re;
            }
          });
        }

        var nextY = -Infinity;
        pids.forEach(function (parentId) {
          var pc = cellMap[parentId];
          if (!pc || !pc.geometry) return;
          var pg = pc.geometry;

          // Center-align first side node with parent
          var firstId = byParent[parentId][0];
          var firstCell = cellMap[firstId];
          var firstH = (firstCell && firstCell.geometry) ? firstCell.geometry.height : 0;
          var idealY = pg.y + pg.height / 2 - firstH / 2;
          var yOff = Math.max(idealY, nextY);

          byParent[parentId].forEach(function (sideId) {
            var sc = cellMap[sideId];
            if (!sc || !sc.geometry) return;
            sc.setVisible(true);
            var sg = sc.geometry;
            sg.x = (direction === 'right') ? colX : pg.x - sg.width - SIDE_GAP;
            sg.y = yOff;
            yOff += sg.height + 12;
          });
          nextY = yOff;
        });
      }

      positionColumn(rightSide, 'right');
      positionColumn(leftSide, 'left');
      resolveOverlaps(cellMap, graphData);

      // Add side edges with horizontal exit/entry constraints
      graphData.sideEdges.forEach(function (e) {
        var src = cellMap[e.from], tgt = cellMap[e.to];
        if (!src || !tgt || !src.geometry || !tgt.geometry) return;

        var srcG = src.geometry, tgtG = tgt.geometry;
        var tgtCenterY = tgtG.y + tgtG.height / 2;
        var srcRelY = (tgtCenterY - srcG.y) / srcG.height;
        var canHorizontal = srcRelY >= 0.05 && srcRelY <= 0.95;

        var ee;
        if (e.direction === 'right') {
          if (canHorizontal) {
            ee = { exitX: 1, exitY: srcRelY, entryX: 0, entryY: 0.5 };
          } else {
            ee = { exitX: 1, exitY: Math.max(0.05, Math.min(0.95, srcRelY)), entryX: 0, entryY: 0.5 };
          }
        } else if (e.direction === 'left') {
          if (canHorizontal) {
            ee = { exitX: 0, exitY: srcRelY, entryX: 1, entryY: 0.5 };
          } else {
            ee = { exitX: 0, exitY: Math.max(0.05, Math.min(0.95, srcRelY)), entryX: 1, entryY: 0.5 };
          }
        }

        var edge = graph.insertEdge(parent, null, '', src, tgt, edgeStyle(e.dashed, e.noArrow, ee));
        edgesByKey[src.id + '\u2192' + tgt.id] = edge;

        // Add elbow waypoint when edge can't be perfectly horizontal
        if (!canHorizontal && edge.geometry && ee) {
          var exitAbsY = srcG.y + Math.max(0.05, Math.min(0.95, srcRelY)) * srcG.height;
          var midX = (e.direction === 'right')
            ? (srcG.x + srcG.width + tgtG.x) / 2
            : (tgtG.x + tgtG.width + srcG.x) / 2;
          edge.geometry.points = [
            new Point(midX, exitAbsY),
            new Point(midX, tgtCenterY)
          ];
        }
      });

      // Feedback edges: History/Context → User Input (orthogonal L-shaped routes)
      if (graphData.feedbackEdges) {
        graphData.feedbackEdges.forEach(function (fe, idx) {
          var fromCell = cellMap[fe.from], inputCell = cellMap[fe.to];
          if (fromCell && inputCell && fromCell.geometry && inputCell.geometry) {
            var fg = fromCell.geometry, ig = inputCell.geometry;
            var leftX = Math.min(fg.x, ig.x) - 40 - idx * 20;
            var fbStyle = edgeStyle(true, false, {
              exitX: 0, exitY: 0.5,
              entryX: 0, entryY: 0.5
            });
            var fbEdge = graph.insertEdge(parent, null, '', fromCell, inputCell, fbStyle);
            if (fbEdge.geometry) {
              fbEdge.geometry.points = [
                new Point(leftX, fg.y + fg.height / 2),
                new Point(leftX, ig.y + ig.height / 2)
              ];
            }
          }
        });
      }
    });

    setupScrollAreas();
    if (!skipFit) fitGraphToContainer();
  }

  /** Enable scrolling inside prompt scroll areas without triggering graph pan */
  function setupScrollAreas() {
    if (!container) return;
    var areas = container.querySelectorAll('.wv-scroll-text');
    areas.forEach(function (el) {
      el.addEventListener('wheel', function (e) { e.stopPropagation(); }, { passive: true });
      el.addEventListener('pointerdown', function (e) { e.stopPropagation(); });
    });
  }

  function fitGraphToContainer() {
    if (!graph || !container) return;
    var view = graph.getView();
    view.scaleAndTranslate(1, 0, 0);
    var bounds = graph.getGraphBounds();
    if (!bounds || bounds.width === 0 || bounds.height === 0) return;
    var cw = container.clientWidth, ch = container.clientHeight;
    if (cw === 0 || ch === 0) return;
    var pad = 24;
    var sx = (cw - pad * 2) / bounds.width;
    var sy = (ch - pad * 2) / bounds.height;
    var scale = Math.min(sx, sy, 1.2);
    scale = Math.max(scale, 0.15);
    var tx = -bounds.x + (cw / scale - bounds.width) / 2;
    var ty = -bounds.y + (ch / scale - bounds.height) / 2;
    view.scaleAndTranslate(scale, tx, ty);
  }

  // ── Click handling ───────────────────────────────────────────

  function setupClickHandler() {
    if (!container) return;
    var downPos = null;
    container.addEventListener('pointerdown', function (e) {
      // Don't track clicks inside scroll areas (let them scroll)
      if (e.target.closest && e.target.closest('.wv-scroll-text')) return;
      downPos = { x: e.clientX, y: e.clientY };
    }, true);
    container.addEventListener('pointerup', function (evt) {
      if (!downPos || !graph) { downPos = null; return; }
      var dx = evt.clientX - downPos.x, dy = evt.clientY - downPos.y;
      downPos = null;
      if (Math.abs(dx) > 5 || Math.abs(dy) > 5) return;
      var rect = container.getBoundingClientRect();
      var x = evt.clientX - rect.left, y = evt.clientY - rect.top;
      var cell = graph.getCellAt(x, y);
      if (!cell) return;
      if (cell.isToolContainer && currentData) { handleToolClick(cell, x, y); return; }
      if (cell.expandKey) toggleGroup(cell.expandKey);
      else if (cell.collapseKey) toggleGroup(cell.collapseKey);
    }, true);
  }

  function handleToolClick(cell, x, y) {
    var view = graph.getView();
    var scale = view.scale || 1;
    var cellScreenY;
    var state = view.getState(cell);
    if (state) {
      cellScreenY = state.y;
    } else if (cell.geometry) {
      var vty = view.translate ? view.translate.y : 0;
      cellScreenY = (cell.geometry.y + vty) * scale;
    } else {
      return;
    }
    // spacingTop(6) + header(HEAD_H) + separator(margin:2 + border:1 + padding:4 = 7)
    var bodyTop = (6 + HEAD_H + 7) * scale;
    var lineH = LINE_H * scale;
    var localY = y - cellScreenY - bodyTop;
    if (localY < 0) return;
    var idx = Math.floor(localY / lineH);
    if (idx < 0) idx = 0;

    var groups = currentData.shared_tool_groups || [];
    var exp = getExpanded();
    var cur = 0;
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i], names = g.tool_names || [], gk = 'tg:' + g.name;
      var isExp = exp.has(gk);
      if (idx === cur && names.length > 0) { toggleGroup(gk); return; }
      cur += 1;
      if (isExp) {
        if (idx < cur + names.length) { toggleGroup(gk); return; }
        cur += names.length;
      }
    }
  }

  // ── Tooltip ──────────────────────────────────────────────────

  function setupTooltips() {
    if (!container) return;
    container.addEventListener('mousemove', function (evt) {
      if (!graph) return;
      var rect = container.getBoundingClientRect();
      var cell = graph.getCellAt(evt.clientX - rect.left, evt.clientY - rect.top);
      container.style.cursor = (cell && (cell.expandKey || cell.collapseKey || cell.isToolContainer)) ? 'pointer' : '';
      if (cell && cell.tooltip) showTooltip(evt.clientX, evt.clientY, cell.tooltip);
      else hideTooltip();
    });
    container.addEventListener('mouseleave', function () { hideTooltip(); container.style.cursor = ''; });
  }
  function showTooltip(x, y, text) {
    if (!tooltip) { tooltip = document.createElement('div'); tooltip.className = 'wv-tooltip'; document.body.appendChild(tooltip); }
    tooltip.textContent = text; tooltip.style.display = 'block';
    tooltip.style.left = (x + 12) + 'px'; tooltip.style.top = (y + 12) + 'px';
  }
  function hideTooltip() { if (tooltip) tooltip.style.display = 'none'; }

  // ── Panel title ──────────────────────────────────────────────

  function updateTitle(name) {
    var el = document.getElementById('workflowViewerLabel');
    if (!el) return;
    var base = 'Workflow Viewer';
    if (typeof i18next !== 'undefined' && i18next.t) {
      var t = i18next.t('ui.workflowViewer');
      if (t && t !== 'ui.workflowViewer') base = t;
    }
    el.innerHTML = '<i class="fas fa-project-diagram me-1"></i> ' + base + (name ? ' \u2014 ' + name : '');
  }

  function buildLegend() {
    if (!panelEl) return;
    var el = panelEl.querySelector('.workflow-viewer-legend');
    if (!el) return;
    el.innerHTML = '';
    LEGEND.forEach(function (i) {
      var s = document.createElement('span'); s.className = 'wv-legend-item';
      s.innerHTML = '<span class="wv-legend-swatch" style="background:' + i.colour + '"></span>' + i.label;
      el.appendChild(s);
    });
  }

  // ── Graph creation ─────────────────────────────────────────

  function createGraph() {
    if (graph) { graph.destroy(); graph = null; }
    graph = new Graph(container);
    graph.setHtmlLabels(true);
    graph.setCellsMovable(false); graph.setCellsResizable(false);
    graph.setCellsEditable(false); graph.setCellsCloneable(false);
    graph.setCellsDeletable(false); graph.setCellsDisconnectable(false);
    graph.setConnectable(false); graph.setCellsSelectable(false);
    graph.setAutoSizeCells(true); graph.setPanning(true);
    var h = graph.getPlugin('PanningHandler');
    if (h) { h.useLeftButtonForPanning = true; h.ignoreCell = true; }
    return graph;
  }

  // ── Floating panel: drag, resize, persistence ──────────────

  var MIN_PANEL_W = 320;
  var MIN_PANEL_H = 200;
  var DEFAULT_W = 520;
  var DEFAULT_H = 380;
  var RESIZE_ZONE = 6;
  var STORAGE_KEY = 'wv-panel-rect';

  var panelRect = null;          // { left, top, width, height }
  var isDragging = false;
  var isResizing = false;
  var resizeDir = '';             // 'n','s','e','w','ne','nw','se','sw'
  var dragStart = { x: 0, y: 0 };
  var rectStart = null;

  var CURSOR_MAP = {
    n: 'ns-resize', s: 'ns-resize', e: 'ew-resize', w: 'ew-resize',
    ne: 'nesw-resize', sw: 'nesw-resize', nw: 'nwse-resize', se: 'nwse-resize'
  };

  function savePanelRect() {
    if (!panelRect) return;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(panelRect)); } catch (e) { /* ignore */ }
  }

  function loadPanelRect() {
    try {
      var s = localStorage.getItem(STORAGE_KEY);
      if (s) return JSON.parse(s);
    } catch (e) { /* ignore */ }
    return null;
  }

  function defaultRect() {
    var vw = window.innerWidth, vh = window.innerHeight;
    return {
      left: Math.max(20, vw - DEFAULT_W - 20),
      top: 60,
      width: Math.min(DEFAULT_W, vw - 40),
      height: Math.min(DEFAULT_H, vh - 80)
    };
  }

  function applyPanelRect(rect) {
    var vw = window.innerWidth, vh = window.innerHeight;
    // Clamp size
    rect.width = Math.max(MIN_PANEL_W, Math.min(rect.width, vw - 20));
    rect.height = Math.max(MIN_PANEL_H, Math.min(rect.height, vh - 20));
    // Clamp position (ensure at least 40px visible)
    rect.left = Math.max(-rect.width + 40, Math.min(rect.left, vw - 40));
    rect.top = Math.max(0, Math.min(rect.top, vh - 40));
    // Apply
    panelEl.style.left = rect.left + 'px';
    panelEl.style.top = rect.top + 'px';
    panelEl.style.width = rect.width + 'px';
    panelEl.style.height = rect.height + 'px';
    panelEl.style.right = 'auto';
    panelRect = rect;
  }

  function getCurrentRect() {
    if (!panelEl) return defaultRect();
    var r = panelEl.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  }

  // Detect which resize direction based on pointer position within panel
  function detectResizeDir(e) {
    if (!panelEl) return '';
    var r = panelEl.getBoundingClientRect();
    var x = e.clientX - r.left, y = e.clientY - r.top;
    var w = r.width, h = r.height;
    var top = y < RESIZE_ZONE, bot = y > h - RESIZE_ZONE;
    var left = x < RESIZE_ZONE, right = x > w - RESIZE_ZONE;
    if (top && left) return 'nw';
    if (top && right) return 'ne';
    if (bot && left) return 'sw';
    if (bot && right) return 'se';
    if (top) return 'n';
    if (bot) return 's';
    if (left) return 'w';
    if (right) return 'e';
    return '';
  }

  function setupDrag() {
    if (!panelEl) return;
    var headerEl = panelEl.querySelector('.wv-panel-header');
    if (!headerEl) return;

    headerEl.addEventListener('pointerdown', function (e) {
      // Don't drag when clicking buttons in the header
      if (e.target.closest && e.target.closest('.wv-panel-controls')) return;
      if (e.button !== 0) return;
      e.preventDefault();
      headerEl.setPointerCapture(e.pointerId);
      isDragging = true;
      headerEl.classList.add('wv-dragging');
      dragStart = { x: e.clientX, y: e.clientY };
      rectStart = getCurrentRect();
    });

    headerEl.addEventListener('pointermove', function (e) {
      if (!isDragging || !rectStart) return;
      var dx = e.clientX - dragStart.x, dy = e.clientY - dragStart.y;
      var newRect = {
        left: rectStart.left + dx,
        top: rectStart.top + dy,
        width: rectStart.width,
        height: rectStart.height
      };
      applyPanelRect(newRect);
    });

    function stopDrag() {
      if (!isDragging) return;
      isDragging = false;
      headerEl.classList.remove('wv-dragging');
      savePanelRect();
    }
    headerEl.addEventListener('pointerup', stopDrag);
    headerEl.addEventListener('pointercancel', stopDrag);
    headerEl.addEventListener('lostpointercapture', stopDrag);
  }

  function setupResize() {
    if (!panelEl) return;

    // Update cursor on hover near edges
    panelEl.addEventListener('pointermove', function (e) {
      if (isDragging || isResizing) return;
      var dir = detectResizeDir(e);
      panelEl.style.cursor = dir ? CURSOR_MAP[dir] : '';
    });

    panelEl.addEventListener('pointerdown', function (e) {
      if (isDragging) return;
      var dir = detectResizeDir(e);
      if (!dir) return;
      // Don't start resize from header area (let drag handle it)
      if (e.target.closest && e.target.closest('.wv-panel-header')) return;
      e.preventDefault();
      e.stopPropagation();
      panelEl.setPointerCapture(e.pointerId);
      isResizing = true;
      resizeDir = dir;
      dragStart = { x: e.clientX, y: e.clientY };
      rectStart = getCurrentRect();
    });

    // Also allow corner grip to initiate se resize
    var grip = panelEl.querySelector('.wv-resize-grip');
    if (grip) {
      grip.addEventListener('pointerdown', function (e) {
        if (e.button !== 0) return;
        e.preventDefault();
        e.stopPropagation();
        panelEl.setPointerCapture(e.pointerId);
        isResizing = true;
        resizeDir = 'se';
        dragStart = { x: e.clientX, y: e.clientY };
        rectStart = getCurrentRect();
      });
    }

    panelEl.addEventListener('pointermove', function (e) {
      if (!isResizing || !rectStart) return;
      var dx = e.clientX - dragStart.x, dy = e.clientY - dragStart.y;
      var r = {
        left: rectStart.left,
        top: rectStart.top,
        width: rectStart.width,
        height: rectStart.height
      };

      if (resizeDir.indexOf('e') >= 0) r.width = rectStart.width + dx;
      if (resizeDir.indexOf('w') >= 0) { r.width = rectStart.width - dx; r.left = rectStart.left + dx; }
      if (resizeDir.indexOf('s') >= 0) r.height = rectStart.height + dy;
      if (resizeDir.indexOf('n') >= 0) { r.height = rectStart.height - dy; r.top = rectStart.top + dy; }

      // Enforce minimum size (prevent left/top from jumping when hitting min)
      if (r.width < MIN_PANEL_W) {
        if (resizeDir.indexOf('w') >= 0) r.left = rectStart.left + rectStart.width - MIN_PANEL_W;
        r.width = MIN_PANEL_W;
      }
      if (r.height < MIN_PANEL_H) {
        if (resizeDir.indexOf('n') >= 0) r.top = rectStart.top + rectStart.height - MIN_PANEL_H;
        r.height = MIN_PANEL_H;
      }

      applyPanelRect(r);
    });

    function stopResize() {
      if (!isResizing) return;
      isResizing = false;
      resizeDir = '';
      panelEl.style.cursor = '';
      savePanelRect();
      if (graph) fitGraphToContainer();
    }
    panelEl.addEventListener('pointerup', stopResize);
    panelEl.addEventListener('pointercancel', stopResize);
    panelEl.addEventListener('lostpointercapture', stopResize);
  }

  // ── Toggle button active state ─────────────────────────────

  function setToggleActive(active) {
    var btn = document.getElementById('toggle-workflow-viewer');
    if (!btn) return;
    if (active) btn.classList.add('wv-active');
    else btn.classList.remove('wv-active');
  }

  // ── SVG export ──────────────────────────────────────────────

  function buildExportCSS() {
    return [
      "@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600&display=swap');",
      "foreignObject div { font-family: 'Montserrat', 'Segoe UI', sans-serif; }",
      "foreignObject b { font-weight: 600; }",
      ".wv-scroll-text { overflow: hidden; }"
    ].join('\n');
  }

  // ── Real-time highlighting ─────────────────────────────────

  // requestAnimationFrame handles for node glow pulses  { cellId → rafId }
  var pulseFrames = {};

  // Start a smooth pulsing drop-shadow glow on an SVG node via rAF.
  // CSS filter:drop-shadow follows the element's alpha shape (rounded rect).
  // maxCycles: 0 = unlimited (default), >0 = settle to static glow after N cycles.
  function startNodePulse(cellId, node, isError, maxCycles) {
    stopNodePulse(cellId, node);
    var startTime = performance.now();
    var r = isError ? '239, 68, 68' : '59, 130, 246';
    var period = 1500; // ms per cycle
    var limit = maxCycles || 0;
    function frame(now) {
      var elapsed = now - startTime;
      if (limit > 0 && elapsed >= period * limit) {
        // Settle to a subtle static glow
        node.style.filter = 'drop-shadow(0 0 4px rgba(' + r + ', 0.45))';
        delete pulseFrames[cellId];
        return;
      }
      var t = (Math.sin(elapsed / 750 * Math.PI) + 1) / 2; // 0→1→0
      var blur = 2 + t * 8;       // 2px → 10px
      var opacity = 0.2 + t * 0.8; // 0.2 → 1.0
      node.style.filter = 'drop-shadow(0 0 ' + blur + 'px rgba(' + r + ', ' + opacity + '))';
      pulseFrames[cellId] = requestAnimationFrame(frame);
    }
    pulseFrames[cellId] = requestAnimationFrame(frame);
  }

  function stopNodePulse(cellId, node) {
    if (pulseFrames[cellId]) {
      cancelAnimationFrame(pulseFrames[cellId]);
      delete pulseFrames[cellId];
    }
    if (node) node.style.filter = '';
  }

  function stopAllNodePulses() {
    Object.keys(pulseFrames).forEach(function (id) {
      cancelAnimationFrame(pulseFrames[id]);
    });
    pulseFrames = {};
  }

  function applyHighlight(cell, className, maxCycles) {
    if (!graph || !cell) return;
    var state = graph.getView().getState(cell);
    if (!state || !state.shape || !state.shape.node) return;
    var node = state.shape.node;
    node.classList.add(className);
    // For node highlights, use filter:drop-shadow() with rAF-driven pulse.
    // state.shape.node is an SVG element; drop-shadow follows the shape's
    // alpha channel, producing a rounded glow that extends outside the border.
    if (className === 'wv-node-active' || className === 'wv-node-error') {
      startNodePulse(cell.id || className, node, className === 'wv-node-error', maxCycles);
    }
  }

  function removeHighlight(cell, className) {
    if (!graph || !cell) return;
    var state = graph.getView().getState(cell);
    if (!state || !state.shape || !state.shape.node) return;
    var node = state.shape.node;
    node.classList.remove(className);
    if (className === 'wv-node-active' || className === 'wv-node-error') {
      stopNodePulse(cell.id || className, node);
    }
  }

  function clearAllHighlights() {
    var classes = ['wv-node-active', 'wv-edge-active', 'wv-node-error'];
    if (!graph) return;
    stopAllNodePulses();
    var parent = graph.getDefaultParent();
    if (!parent || !parent.children) return;
    var view = graph.getView();
    parent.children.forEach(function (cell) {
      var state = view.getState(cell);
      if (state && state.shape && state.shape.node) {
        var node = state.shape.node;
        classes.forEach(function (c) {
          node.classList.remove(c);
        });
        node.style.filter = '';
      }
    });
    activeStage = null;
  }

  function setStageInternal(stage) {
    if (!graph || !panelEl || panelEl.classList.contains('wv-panel-collapsed')) return;
    clearAllHighlights();
    if (activeTool) { activeTool = null; resetToolHeading(); }
    activeStage = stage;

    if (stage === 'done') return; // Clear only

    if (stage === 'error') {
      if (cellsByType['model']) {
        applyHighlight(cellsByType['model'], 'wv-node-error');
      }
      return;
    }

    // Stage → active node types
    var nodeMap = {
      'input': ['input'],
      'prompt': ['input', 'prompt'],
      'model': ['input', 'prompt', 'model'],
      'tools': ['input', 'prompt', 'model', 'toolGroup'],
      'response': ['input', 'prompt', 'model', 'response'],
      'context': ['response', 'context']
    };

    var activeNodes = nodeMap[stage] || [];
    var primaryNode = activeNodes[activeNodes.length - 1];

    // Pulse-glow on primary node.
    // 'context' stage arrives after 'done' with no subsequent clear,
    // so limit its pulse to 3 cycles then settle to a static glow.
    var pulseCycles = (stage === 'context') ? 3 : 0;
    if (primaryNode && cellsByType[primaryNode]) {
      applyHighlight(cellsByType[primaryNode], 'wv-node-active', pulseCycles);
    }

    // Flow-animate edges along the chain
    var flowChain = ['input', 'prompt', 'model', 'response'];
    for (var i = 0; i < flowChain.length - 1; i++) {
      var fromType = flowChain[i], toType = flowChain[i + 1];
      if (activeNodes.indexOf(fromType) >= 0 && activeNodes.indexOf(toType) >= 0) {
        var fromCell = cellsByType[fromType], toCell = cellsByType[toType];
        if (fromCell && toCell) {
          var key = fromCell.id + '\u2192' + toCell.id;
          if (edgesByKey[key]) applyHighlight(edgesByKey[key], 'wv-edge-active');
        }
      }
    }

    // tools: model→toolGroup edge
    if (stage === 'tools' && cellsByType['model'] && cellsByType['toolGroup']) {
      var tk = cellsByType['model'].id + '\u2192' + cellsByType['toolGroup'].id;
      if (edgesByKey[tk]) applyHighlight(edgesByKey[tk], 'wv-edge-active');
    }

  }

  // ── Active tool display ────────────────────────────────────

  function setActiveToolInternal(toolName, callCount) {
    if (!graph || !panelEl || panelEl.classList.contains('wv-panel-collapsed')) return;
    activeTool = toolName;
    var toolCell = cellsByType['toolGroup'];
    if (!toolCell || !toolName) return;
    var state = graph.getView().getState(toolCell);
    if (!state || !state.shape || !state.shape.node) return;
    var headingEl = state.shape.node.querySelector('b');
    if (headingEl) {
      var displayName = titleCase(toolName.replace(/_/g, ' '));
      var countStr = callCount ? ' (' + callCount + ')' : '';
      headingEl.innerHTML = 'Tools <span style="font-weight:normal;opacity:0.7">\u2014 ' + escHtml(displayName) + countStr + '</span>';
    }
  }

  function resetToolHeading() {
    var toolCell = cellsByType['toolGroup'];
    if (!toolCell || !graph) return;
    var state = graph.getView().getState(toolCell);
    if (!state || !state.shape || !state.shape.node) return;
    var headingEl = state.shape.node.querySelector('b');
    if (headingEl) headingEl.textContent = 'Tools';
  }

  // ── Public API ─────────────────────────────────────────────

  return {
    init: function () {
      if (initialised) return;
      if (typeof window.maxgraph === 'undefined') { console.warn('[WorkflowViewer] maxGraph not loaded'); return; }
      Graph = window.maxgraph.Graph;
      HierarchicalLayout = window.maxgraph.HierarchicalLayout;
      Rectangle = window.maxgraph.Rectangle;
      Point = window.maxgraph.Point;
      panelEl = document.getElementById('workflow-viewer-panel');
      container = document.getElementById('workflow-viewer-container');
      if (!panelEl || !container) { console.warn('[WorkflowViewer] Panel not found'); return; }
      // Move panel to body so position:fixed is relative to viewport,
      // not constrained by any ancestor with transform/filter/will-change
      if (panelEl.parentNode !== document.body) {
        document.body.appendChild(panelEl);
      }
      var self = this;
      var btn = document.getElementById('toggle-workflow-viewer');
      if (btn) btn.addEventListener('click', function () { self.toggle(); });
      var closeBtn = document.getElementById('wv-close');
      if (closeBtn) closeBtn.addEventListener('click', function () { self.close(); });
      var zi = document.getElementById('wv-zoom-in'), zo = document.getElementById('wv-zoom-out'), zf = document.getElementById('wv-zoom-fit');
      if (zi) zi.addEventListener('click', function () { if (graph) graph.zoomIn(); });
      if (zo) zo.addEventListener('click', function () { if (graph) graph.zoomOut(); });
      if (zf) zf.addEventListener('click', function () { fitGraphToContainer(); });
      setupTooltips(); setupClickHandler(); buildLegend();
      setupDrag(); setupResize();
      // Load persisted panel rect (applied when panel opens)
      panelRect = loadPanelRect() || defaultRect();
      // Refresh graph colours when theme changes
      themeHandler = function () {
        if (graph && currentData && container) {
          if (panelEl && !panelEl.classList.contains('wv-panel-collapsed')) {
            refreshGraph();
          } else {
            needsRefreshOnOpen = true;
          }
        }
        buildLegend();
      };
      window.addEventListener('theme-applied', themeHandler);
      // Re-clamp panel position when viewport resizes
      window.addEventListener('resize', function () {
        if (panelRect && panelEl && !panelEl.classList.contains('wv-panel-collapsed')) {
          applyPanelRect(panelRect);
        }
      });
      // ResizeObserver: detect container becoming visible (e.g. session start with panel open)
      if (typeof ResizeObserver !== 'undefined') {
        var resizeTimer = null;
        new ResizeObserver(function () {
          if (skipNextResize || !graph || !container || container.clientWidth === 0) return;
          clearTimeout(resizeTimer);
          resizeTimer = setTimeout(function () {
            if (!restoreViewState()) fitGraphToContainer();
          }, 80);
        }).observe(container);
      }
      initialised = true;
    },
    open: function () {
      if (!panelEl) return;
      // Apply saved or default rect before showing
      applyPanelRect(panelRect || defaultRect());
      panelEl.classList.remove('wv-panel-collapsed');
      setToggleActive(true);
      var self = this;
      requestAnimationFrame(function () {
        if (pendingApp) { self._doLoadApp(pendingApp); pendingApp = null; }
        else if (needsRefreshOnOpen && currentData) {
          // Theme or other deferred change while panel was hidden → full rebuild
          needsRefreshOnOpen = false;
          refreshGraph();
        } else if (graph) {
          // Revalidate view states after display:none → display:flex transition.
          // While hidden, the container has 0 dimensions, so view states may
          // have been computed with invalid bounds.
          graph.sizeDidChange();
          if (restoreViewState()) {
            skipNextResize = true;
            setTimeout(function () { skipNextResize = false; }, 200);
          } else {
            fitGraphToContainer();
          }
        }
      });
    },
    close: function () {
      if (!panelEl) return;
      saveViewState();
      panelRect = getCurrentRect();
      savePanelRect();
      panelEl.classList.add('wv-panel-collapsed');
      hideTooltip();
      setToggleActive(false);
    },
    toggle: function () {
      if (this.isOpen()) { this.close(); return; }
      var sel = document.getElementById('apps'), n = sel ? sel.value : null;
      if (n && n !== currentApp) pendingApp = n;
      this.open();
    },
    isOpen: function () { return panelEl ? !panelEl.classList.contains('wv-panel-collapsed') : false; },
    loadApp: function (name) {
      if (!container || !Graph || !name) return;
      if (this.isOpen()) { this._doLoadApp(name); return; }
      pendingApp = name;
    },
    _doLoadApp: function (name) {
      if (!container || !Graph || !name) return;
      saveViewState(); // Save current app's view before switching
      currentApp = name; currentData = null; updateTitle(null);
      container.innerHTML = '<div class="workflow-viewer-message"><i class="fas fa-spinner fa-spin me-2"></i>Loading...</div>';
      fetch('/api/app/' + encodeURIComponent(name) + '/graph')
        .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(function (data) {
          if (data.error) throw new Error(data.error);
          currentData = data;
          updateTitle(data.display_name || data.app_name || name);
          container.innerHTML = '';
          createGraph();
          renderGraph(buildGraphData(data, getExpanded()));
        })
        .catch(function (err) {
          container.innerHTML = '<div class="workflow-viewer-message"><i class="fas fa-exclamation-triangle me-2"></i>Failed: ' + (err.message || '?') + '</div>';
          console.error('[WorkflowViewer]', err);
        });
    },
    destroy: function () {
      if (graph) { graph.destroy(); graph = null; }
      hideTooltip();
      if (tooltip && tooltip.parentNode) { tooltip.parentNode.removeChild(tooltip); tooltip = null; }
      if (themeHandler) { window.removeEventListener('theme-applied', themeHandler); themeHandler = null; }
      currentApp = null; currentData = null; pendingApp = null;
      viewStates = {}; expandedGroups = {}; initialised = false;
      stopAllNodePulses();
      cellsByType = {}; edgesByKey = {}; activeStage = null; activeTool = null;
      isDragging = false; isResizing = false; resizeDir = '';
      needsRefreshOnOpen = false;
    },
    exportSvg: function (opts) {
      opts = opts || {};
      if (!graph || !container) return null;
      var svgRoot = container.querySelector('svg');
      if (!svgRoot) return null;

      // Reset view to 1:1 for accurate bounds, then restore
      var view = graph.getView();
      var savedScale = view.scale, savedTx = view.translate.x, savedTy = view.translate.y;
      view.scaleAndTranslate(1, 0, 0);
      var bounds = graph.getGraphBounds();
      view.scaleAndTranslate(savedScale, savedTx, savedTy);
      if (!bounds || bounds.width === 0) return null;

      var pad = opts.padding || 30;
      var vbX = bounds.x - pad, vbY = bounds.y - pad;
      var vbW = bounds.width + pad * 2, vbH = bounds.height + pad * 2;

      var clone = svgRoot.cloneNode(true);
      clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      clone.setAttribute('xmlns:xhtml', 'http://www.w3.org/1999/xhtml');
      clone.setAttribute('viewBox', [vbX, vbY, vbW, vbH].join(' '));
      var width = opts.width || 800;
      clone.setAttribute('width', String(width));
      clone.setAttribute('height', String(Math.round(width * vbH / vbW)));

      // Embed CSS for fonts
      var styleEl = document.createElementNS('http://www.w3.org/2000/svg', 'style');
      styleEl.textContent = buildExportCSS();
      clone.insertBefore(styleEl, clone.firstChild);

      var serializer = new XMLSerializer();
      return '<?xml version="1.0" encoding="UTF-8"?>\n' + serializer.serializeToString(clone);
    },
    setStage: function (stage) {
      setStageInternal(stage);
    },
    setActiveTool: function (toolName, callCount) {
      setActiveToolInternal(toolName, callCount);
    },
    clearHighlights: function () {
      clearAllHighlights();
    }
  };
})();

document.addEventListener('DOMContentLoaded', function () { WorkflowViewer.init(); });
if (typeof window !== 'undefined') window.WorkflowViewer = WorkflowViewer;
if (typeof module !== 'undefined' && module.exports) module.exports = WorkflowViewer;
