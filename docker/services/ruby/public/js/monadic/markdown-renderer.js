/**
 * Unified Markdown renderer with support for:
 * - Monadic JSON structure (AutoForge, ConceptVisualizer, etc.)
 * - Code highlighting (highlight.js)
 * - MathJax expressions
 * - ABC notation
 * - Mermaid diagrams
 */

(function(window) {
  'use strict';

  // markdown-it instance (will be initialized when markdown-it is loaded)
  let md = null;

  const MarkdownRenderer = {
    /**
     * Initialize markdown-it instance
     * @private
     */
    _initMarkdownIt: function() {
      if (md || typeof window.markdownit === 'undefined') {
        return;
      }

      md = window.markdownit({
        html: true,
        linkify: true,
        typographer: true,
        highlight: function (code, lang) {
          // Escape HTML manually (md is not yet available in this context)
          const escaped = code
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
          const langClass = lang ? ` class="language-${lang}"` : '';
          return `<pre><code${langClass}>${escaped}</code></pre>`;
        }
      });
    },

    // ===== Main Entry Point =====

    /**
     * Main entry point: Auto-detect content type and render
     *
     * @param {string} text - Input text (Markdown or Monadic JSON)
     * @param {object} options - Options { appName: string }
     * @returns {string} HTML
     */
    render: function(text, options = {}) {
      if (!text) return '';

      // Initialize markdown-it if needed
      this._initMarkdownIt();

      // 1. Check if this is Monadic JSON
      if (this.isMonadicJson(text, options.appName)) {
        return this.renderMonadicJson(text, options);
      }

      // 2. Normal Markdown processing
      return this.renderMarkdown(text, options);
    },

    // ===== Monadic JSON Detection =====

    /**
     * Detect if content is Monadic JSON structure
     *
     * @param {string} text - Text to check
     * @param {string} appName - Application name
     * @returns {boolean}
     */
    isMonadicJson: function(text, appName) {
      // Apps that use Monadic structure
      const monadicApps = [
        'auto_forge_openai',
        'auto_forge_claude',
        'auto_forge_grok',
        'concept_visualizer_openai',
        'concept_visualizer_claude',
      ];

      if (!appName || !monadicApps.includes(appName.toLowerCase())) {
        return false;
      }

      // Check if valid JSON with Monadic structure
      try {
        const obj = JSON.parse(text);
        return typeof obj === 'object' && (obj.message || obj.context);
      } catch {
        return false;
      }
    },

    // ===== Monadic JSON Rendering =====

    /**
     * Render Monadic JSON to HTML
     *
     * @param {string} monadicJson - Monadic JSON string
     * @param {object} options - Options
     * @returns {string} HTML
     */
    renderMonadicJson: function(monadicJson, options) {
      try {
        const obj = typeof monadicJson === 'string'
          ? JSON.parse(monadicJson)
          : monadicJson;

        return this.jsonToHtml(obj, { iteration: 0 });
      } catch (err) {
        console.error('MarkdownRenderer: Failed to parse Monadic JSON:', err);
        // Fallback to normal Markdown
        return this.renderMarkdown(monadicJson, options);
      }
    },

    /**
     * Convert Monadic JSON structure to HTML
     * (Mirrors Ruby's HtmlRenderer#json_to_html)
     *
     * @param {object} hash - JSON object
     * @param {object} options - Options { iteration: number }
     * @returns {string} HTML
     */
    jsonToHtml: function(hash, options) {
      if (typeof hash !== 'object' || hash === null) {
        return String(hash);
      }

      const iteration = (options.iteration || 0) + 1;
      let output = '';

      // Handle message first if present
      if (hash.message) {
        output += this.renderMarkdown(hash.message);
        output += '<hr />';
        // Clone hash without message
        hash = Object.keys(hash)
          .filter(k => k !== 'message')
          .reduce((obj, k) => ({ ...obj, [k]: hash[k] }), {});
      }

      // Render remaining fields
      for (const [key, value] of Object.entries(hash)) {
        output += this.renderField(key, value, iteration, options);
      }

      return output;
    },

    /**
     * Render individual field based on type
     */
    renderField: function(key, value, iteration, options) {
      const displayKey = this.snakeToCapitalized(key);
      const dataKey = key.toLowerCase();

      // Handle empty values
      if (value === null || value === undefined || value === '' ||
          (Array.isArray(value) && value.length === 0)) {
        return `<div class='json-item json-simple' data-depth='${iteration}' data-key='${dataKey}'>
          <span>${displayKey}: </span>
          <span style='color: #999; font-style: italic;'>no value</span>
        </div>`;
      }

      // Special handling for context
      if (key.toLowerCase() === 'context') {
        const content = this.jsonToHtml(value, { ...options, iteration });
        return `
          <div class='json-item context' data-depth='${iteration}' data-key='context'>
            <div class='json-header' onclick='toggleItem(this)'>
              <span>Context</span>
              <i class='fas fa-chevron-down float-right'></i>
              <span class='toggle-text'>click to toggle</span>
            </div>
            <div class='json-content' style='display: block;'>
              ${content}
            </div>
          </div>`;
      }

      // Render based on type
      if (typeof value === 'object' && !Array.isArray(value)) {
        const content = this.jsonToHtml(value, { ...options, iteration });
        return `
          <div class='json-item' data-depth='${iteration}' data-key='${dataKey}'>
            <div class='json-header' onclick='toggleItem(this)'>
              <span>${displayKey}</span>
              <i class='fas fa-chevron-down float-right'></i>
              <span class='toggle-text'>click to toggle</span>
            </div>
            <div class='json-content' style='display: block;'>
              ${content}
            </div>
          </div>`;
      } else if (Array.isArray(value)) {
        return this.renderArrayField(displayKey, value, dataKey, iteration, options);
      } else {
        return this.renderSimpleField(displayKey, value, dataKey, iteration);
      }
    },

    renderArrayField: function(displayKey, value, dataKey, iteration, options) {
      // Special handling for citations
      if (dataKey === 'citations' && value.every(v => typeof v === 'string' && v.match(/^https?:\/\//i))) {
        const items = value.map((url, idx) =>
          `<li><a href='${url}' target='_blank' rel='noopener noreferrer'>[${idx + 1}] ${decodeURIComponent(url)}</a></li>`
        ).join('\n');

        return `
          <div class='json-item' data-depth='${iteration}' data-key='${dataKey}'>
            <div class='json-header' onclick='toggleItem(this)'>
              <span>Citations</span>
              <i class='fas fa-chevron-down float-right'></i>
              <span class='toggle-text'>click to toggle</span>
            </div>
            <div class='json-content' style='display: block;'>
              <ol>${items}</ol>
            </div>
          </div>`;
      }

      // Simple string array
      if (value.every(v => typeof v === 'string')) {
        const isLong = value.some(v => v.length > 50) || value.join(', ').length > 150;

        if (isLong) {
          const items = value.map(v => `<li>${v}</li>`).join('\n');
          return `
            <div class='json-item' data-depth='${iteration}' data-key='${dataKey}'>
              <div class='json-header' onclick='toggleItem(this)'>
                <span>${displayKey}</span>
                <i class='fas fa-chevron-down float-right'></i>
                <span class='toggle-text'>click to toggle</span>
              </div>
              <div class='json-content' style='display: block;'>
                <ol style='font-weight: normal;'>${items}</ol>
              </div>
            </div>`;
        } else {
          return `<div class='json-item' data-depth='${iteration}' data-key='${dataKey}'>
            <span style='white-space: nowrap;'>${displayKey}: </span>
            <span style='font-weight: normal;'>[${value.join(', ')}]</span>
          </div>`;
        }
      }

      // Complex array
      const items = value.map(v => {
        if (typeof v === 'string') {
          return `<li>${this.renderMarkdown(v)}</li>`;
        } else {
          return `<li>${this.jsonToHtml(v, { ...options, iteration })}</li>`;
        }
      }).join('\n');

      return `
        <div class='json-item' data-depth='${iteration}' data-key='${dataKey}'>
          <div class='json-header' onclick='toggleItem(this)'>
            <span>${displayKey}</span>
            <i class='fas fa-chevron-down float-right'></i>
            <span class='toggle-text'>click to toggle</span>
          </div>
          <div class='json-content' style='display: block;'>
            <ul class='no-bullets'>${items}</ul>
          </div>
        </div>`;
    },

    renderSimpleField: function(displayKey, value, dataKey, iteration) {
      const strValue = String(value);

      if (!strValue.includes('\n')) {
        // Single line
        if (strValue === 'no value') {
          return `<div class='json-item json-simple' data-depth='${iteration}' data-key='${dataKey}'>
            <span>${displayKey}: </span>
            <span style='color: #999; font-style: italic;'>${strValue}</span>
          </div>`;
        } else {
          return `<div class='json-item json-simple' data-depth='${iteration}' data-key='${dataKey}'>
            <span>${displayKey}: </span>
            <span>${strValue}</span>
          </div>`;
        }
      } else {
        // Multi-line
        return `<div class='json-item json-simple' data-depth='${iteration}' data-key='${dataKey}'>
          <span>${displayKey}: </span>
          <span>${this.renderMarkdown(strValue)}</span>
        </div>`;
      }
    },

    snakeToCapitalized: function(snakeStr) {
      return String(snakeStr)
        .split('_')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' ');
    },

    // ===== Normal Markdown Rendering =====

    /**
     * Render Markdown to HTML with placeholder protection
     *
     * @param {string} markdown - Markdown text
     * @param {object} options - Options (unused currently)
     * @returns {string} HTML with placeholders for special content
     */
    renderMarkdown: function(markdown, options = {}) {
      if (!markdown) return '';

      // Fallback if markdown-it not loaded
      if (!md) {
        console.warn('markdown-it not loaded, returning plain text');
        return markdown.replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/\n/g, '<br>');
      }

      let text = markdown;

      // 1. MathJax block expressions をプレースホルダーに
      const mathBlocks = [];
      text = text.replace(/\$\$([\s\S]+?)\$\$/g, (match, content) => {
        const index = mathBlocks.length;
        mathBlocks.push(content);
        return `MATH_BLOCK_PLACEHOLDER_${index}`;
      });

      // 2. MathJax inline expressions をプレースホルダーに
      const mathInline = [];
      text = text.replace(/\$(.+?)\$/g, (match, content) => {
        const index = mathInline.length;
        mathInline.push(content);
        return `MATH_INLINE_PLACEHOLDER_${index}`;
      });

      // 3. ABC notation をプレースホルダーに
      const abcBlocks = [];
      text = text.replace(/```abc\n([\s\S]+?)```/g, (match, content) => {
        const index = abcBlocks.length;
        abcBlocks.push(content);
        return `ABC_BLOCK_PLACEHOLDER_${index}`;
      });

      // 4. Mermaid diagrams をプレースホルダーに
      const mermaidBlocks = [];
      text = text.replace(/```mermaid\n([\s\S]+?)```/g, (match, content) => {
        const index = mermaidBlocks.length;
        mermaidBlocks.push(content);
        return `MERMAID_BLOCK_PLACEHOLDER_${index}`;
      });

      // 5. markdown-it で Markdown → HTML 変換
      let html = md.render(text);

      // 6-9. プレースホルダーを復元
      mathBlocks.forEach((content, index) => {
        html = html.replace(
          new RegExp(`MATH_BLOCK_PLACEHOLDER_${index}`, 'g'),
          `$$${content}$$`
        );
      });

      mathInline.forEach((content, index) => {
        html = html.replace(
          new RegExp(`MATH_INLINE_PLACEHOLDER_${index}`, 'g'),
          `$${content}$`
        );
      });

      abcBlocks.forEach((content, index) => {
        const escaped = encodeURIComponent(content);
        html = html.replace(
          new RegExp(`ABC_BLOCK_PLACEHOLDER_${index}`, 'g'),
          `<div class="abc-notation" data-abc="${escaped}"></div>`
        );
      });

      mermaidBlocks.forEach((content, index) => {
        html = html.replace(
          new RegExp(`MERMAID_BLOCK_PLACEHOLDER_${index}`, 'g'),
          `<div class="mermaid">${content}</div>`
        );
      });

      return html;
    },

    // ===== Post-Processing (Unified) =====

    /**
     * Apply all renderers to a container
     *
     * @param {HTMLElement} container - Container element to render
     */
    applyRenderers: function(container) {
      if (!container) {
        console.warn('MarkdownRenderer.applyRenderers: container is null');
        return;
      }

      // 1. highlight.js
      if (window.SyntaxHighlight) {
        try {
          window.SyntaxHighlight.apply(container);
        } catch (err) {
          console.error('Failed to apply syntax highlighting:', err);
        }
      }

      // 2. MathJax
      if (window.MathJax?.typesetPromise) {
        try {
          window.MathJax.typesetPromise([container]).catch(err => {
            console.error('MathJax rendering failed:', err);
          });
        } catch (err) {
          console.error('Failed to initialize MathJax:', err);
        }
      }

      // 3. ABCJS
      if (window.ABCJS) {
        try {
          const abcElements = container.querySelectorAll('.abc-notation');
          abcElements.forEach(el => {
            const abc = decodeURIComponent(el.dataset.abc || '');
            if (abc) {
              window.ABCJS.renderAbc(el, abc);
            }
          });
        } catch (err) {
          console.error('ABC notation rendering failed:', err);
        }
      }

      // 4. Mermaid
      if (window.mermaid) {
        try {
          const mermaidElements = container.querySelectorAll('.mermaid:not([data-processed])');
          if (mermaidElements.length > 0) {
            window.mermaid.init(undefined, mermaidElements);
          }
        } catch (err) {
          console.error('Mermaid rendering failed:', err);
        }
      }
    },

    /**
     * Render and apply all renderers in one call
     *
     * @param {string} text - Input text (Markdown or Monadic JSON)
     * @param {HTMLElement} container - Container to insert rendered HTML
     * @param {object} options - Options { appName: string }
     */
    renderAndApply: function(text, container, options = {}) {
      const html = this.render(text, options);
      if (container) {
        container.innerHTML = html;
        this.applyRenderers(container);
      }
      return html;
    }
  };

  // Export to global scope
  window.MarkdownRenderer = MarkdownRenderer;

})(window);
