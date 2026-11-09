/**
 * The kinds of content the page draws, from one table
 * (lib/monadic/render_formats.json, given by the server in
 * <script type="application/json" id="render-formats">): each kind's id,
 * the code fence languages and the file extensions it is known by. Drawing
 * itself is WorkbenchRender's (workbench-render.js); this file says which
 * kind a fence or a file is, and draws the kinds the chat shows in the
 * chat's cards.
 *
 * In a card, a placeholder (div.mermaid-code, made by markdown-renderer.js
 * from a ```mermaid fence) keeps its source, hidden behind a switch; the
 * drawing goes beside it. A placeholder is drawn once: applying again to
 * the same source changes nothing while it is drawn or being drawn (a
 * drawing that failed is drawn again only when the user asks), and a new
 * source lets the old drawing go first. One observer lets go of what is
 * drawn when its placeholder leaves the document (a card replaced, removed
 * or reset), and keeps the switch and the drawing beside a placeholder that
 * was moved.
 */
(function (window) {
  'use strict';

  // The kinds drawn in the chat's cards, by the class of their placeholder.
  const CHAT_PLACEHOLDERS = { diagram: 'div.mermaid-code' };

  let table = null;

  function t(key, fallback) {
    return (typeof webUIi18n !== 'undefined' && webUIi18n.t) ? webUIi18n.t(`ui.render.${key}`) || fallback : fallback;
  }

  function formats() {
    if (table) return table;
    let parsed = window.RenderFormatsTable || null;
    if (!parsed && typeof document !== 'undefined') {
      const el = document.getElementById('render-formats');
      try {
        parsed = el ? JSON.parse(el.textContent) : null;
      } catch (_) {
        parsed = null;
      }
    }
    table = Array.isArray(parsed) ? parsed : [];
    return table;
  }

  function format(id) {
    return formats().find((f) => f.id === id) || null;
  }

  function forFence(lang) {
    const name = String(lang || '').trim().toLowerCase();
    const found = name && formats().find((f) => f.fences.includes(name));
    return found ? found.id : null;
  }

  // The kind a file name is drawn as: two-part extensions first.
  function forName(name) {
    const base = String(name || '').split('/').pop().toLowerCase();
    for (const f of formats()) {
      if (f.compound_extensions.some((ext) => base.endsWith(`.${ext}`) && base.length > ext.length + 1)) return f.id;
    }
    const dot = base.lastIndexOf('.');
    const ext = dot > 0 ? base.slice(dot + 1) : '';
    const found = ext && formats().find((f) => f.extensions.includes(ext));
    return found ? found.id : null;
  }

  // Mermaid's source as a model writes it into a chat: line ends and
  // escaped entities made plain, Western "smart" punctuation folded to
  // ASCII so the parser takes it. CJK marks are left alone: the long-vowel
  // mark (U+30FC) and the corner brackets (U+300C/U+300D) are characters of
  // their own, and folding them breaks Japanese labels. The same rule is
  // sanitize_mermaid_code in mermaid_grapher_tools.rb.
  function sanitizeMermaidSource(text) {
    if (!text) return text;
    return text
      .replace(/\r\n/g, '\n')
      .replace(/\\n/g, '\n')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/[‐-―−－]/g, '-')
      .replace(/[‘’′＇]/g, "'")
      .replace(/[“”″＂]/g, '"');
  }

  const PREPARE = { diagram: sanitizeMermaidSource };

  // ---- drawing in the chat's cards --------------------------------------

  // placeholder → { source, handle, wrap, toggle, state: 'drawing' | 'drawn' | 'failed' }
  const drawn = new WeakMap();
  // Placeholders drawn now, so that the observer finds what to let go.
  const live = new Set();
  let observer = null;

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined && text !== null) el.textContent = String(text);
    return el;
  }

  function letGo(placeholder) {
    const record = drawn.get(placeholder);
    if (!record) return;
    drawn.delete(placeholder);
    live.delete(placeholder);
    if (record.handle) record.handle.dispose();
    if (record.wrap && record.wrap.parentNode) record.wrap.remove();
    if (record.toggle && record.toggle.parentNode) record.toggle.remove();
  }

  // The switch just before the placeholder, the drawing just after it.
  function keepBeside(placeholder, record) {
    if (record.toggle.nextSibling !== placeholder) placeholder.before(record.toggle);
    if (placeholder.nextSibling !== record.wrap) placeholder.after(record.wrap);
  }

  // What leaves the document lets its drawings go; what moved keeps its
  // switch and drawing beside it.
  function watch() {
    if (observer || typeof MutationObserver === 'undefined' || typeof document === 'undefined') return;
    observer = new MutationObserver(() => {
      live.forEach((placeholder) => {
        if (!placeholder.isConnected) letGo(placeholder);
        else keepBeside(placeholder, drawn.get(placeholder));
      });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  function download(svg, name) {
    const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml;charset=utf-8' }));
    const a = element('a');
    a.href = url;
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  // A switch above the source that shows or hides it (the drawing stays).
  function sourceToggle(placeholder) {
    const label = t('toggleSource', 'Toggle Mermaid Diagram');
    const toggle = element('div', 'sourcecode-toggle unselectable');
    const icon = element('i', 'fa-solid fa-toggle-off');
    toggle.append(icon, document.createTextNode(` ${label}`));
    toggle.addEventListener('click', () => {
      const hidden = placeholder.style.display === 'none';
      placeholder.style.display = hidden ? '' : 'none';
      icon.className = hidden ? 'fa-solid fa-toggle-on' : 'fa-solid fa-toggle-off';
    });
    return toggle;
  }

  function drawPlaceholder(placeholder, id, index) {
    const pre = placeholder.querySelector('pre');
    const source = (pre ? pre.textContent : placeholder.textContent).trim();
    const before = drawn.get(placeholder);
    if (before && before.source === source) {
      keepBeside(placeholder, before);
      return before;
    }
    if (before) letGo(placeholder);
    if (!window.WorkbenchRender) return null;

    placeholder.classList.add('sourcecode');
    placeholder.style.display = 'none';
    const toggle = sourceToggle(placeholder);
    placeholder.parentNode.insertBefore(toggle, placeholder);
    const wrap = element('div', 'diagram-wrapper render-wrap');
    const box = element('div', 'diagram');
    const actions = element('div', 'render-actions mb-3');
    wrap.append(box, actions);
    placeholder.parentNode.insertBefore(wrap, placeholder.nextSibling);

    const prepare = PREPARE[id] || ((text) => text);
    const handle = window.WorkbenchRender.draw(box, id, prepare(source), {});
    const record = { source, handle, wrap, toggle, state: 'drawing' };
    drawn.set(placeholder, record);
    live.add(placeholder);
    watch();
    handle.done.then(() => {
      if (drawn.get(placeholder) !== record) return;
      record.state = 'drawn';
      const button = element('button', 'btn btn-secondary btn-sm', t('downloadSvg', 'Download SVG'));
      button.type = 'button';
      button.addEventListener('click', () => {
        const svg = drawn.get(placeholder) === record ? handle.svg() : null;
        if (svg) download(svg, `diagram-${index + 1}.svg`);
      });
      actions.appendChild(button);
    }, (error) => {
      if (drawn.get(placeholder) !== record) return;
      record.state = 'failed';
      const alert = element('div', 'alert alert-danger');
      alert.append(element('strong', null, t('diagramFailed', 'Mermaid Syntax Error:')), element('br'),
        document.createTextNode(error && error.message ? error.message : ''));
      // Drawn again only when the user asks (a broken diagram is not
      // drawn over and over).
      const retry = element('button', 'btn btn-secondary btn-sm', t('retry', 'Try again'));
      retry.type = 'button';
      retry.addEventListener('click', () => {
        if (drawn.get(placeholder) !== record) return;
        letGo(placeholder);
        drawPlaceholder(placeholder, id, index);
      });
      box.replaceChildren(alert);
      actions.replaceChildren(retry);
    });
    return record;
  }

  // The image of a placeholder's drawing as a data: URL that needs nothing
  // else (for a copy of the card, such as the PDF export, whose life is not
  // the card's). null while it is being drawn, when it failed, or for a
  // placeholder not drawn.
  function selfContainedSrc(placeholder) {
    const record = drawn.get(placeholder);
    if (!record || record.state !== 'drawn') return null;
    const svg = record.handle.svg();
    if (!svg) return null;
    const bytes = new TextEncoder().encode(svg);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return `data:image/svg+xml;base64,${btoa(binary)}`;
  }

  // What a copy of root shows of the drawings in it: each placeholder with
  // its switch and drawing becomes the drawing's own image when it is drawn,
  // and its source, shown, otherwise. root itself is not changed.
  function printable(root) {
    const copy = root.cloneNode(true);
    const live = Object.values(CHAT_PLACEHOLDERS).flatMap((selector) => Array.from(root.querySelectorAll(selector)));
    const copies = Object.values(CHAT_PLACEHOLDERS).flatMap((selector) => Array.from(copy.querySelectorAll(selector)));
    copies.forEach((placeholder, i) => {
      const before = placeholder.previousElementSibling;
      if (before && before.classList.contains('sourcecode-toggle')) before.remove();
      const after = placeholder.nextElementSibling;
      if (after && after.classList.contains('render-wrap')) after.remove();
      const src = selfContainedSrc(live[i]);
      let shown;
      if (src) {
        shown = element('img', 'workbench-svg');
        shown.alt = '';
        shown.src = src;
      } else {
        const pre = placeholder.querySelector('pre');
        shown = element('pre', null, (pre || placeholder).textContent);
      }
      placeholder.replaceWith(shown);
    });
    return copy;
  }

  // Draws the placeholders in container of the kinds the chat shows.
  // Drawing the same source again does nothing.
  function apply(container) {
    const root = container && container.querySelectorAll ? container : (container && container[0]);
    if (!root || !root.querySelectorAll) return;
    Object.entries(CHAT_PLACEHOLDERS).forEach(([id, selector]) => {
      root.querySelectorAll(selector).forEach((placeholder, index) => drawPlaceholder(placeholder, id, index));
    });
  }

  const api = {
    formats, format, forFence, forName, apply, sanitizeMermaidSource, selfContainedSrc, printable,
    // For tests: what is drawn for a placeholder now, and a fresh table.
    _drawnFor: (placeholder) => drawn.get(placeholder) || null,
    _reset() {
      table = null;
      live.forEach(letGo);
      if (observer) observer.disconnect();
      observer = null;
    }
  };
  window.Renderers = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
