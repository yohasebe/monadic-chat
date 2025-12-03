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

  // Track if Mermaid has been initialized
  let mermaidInitialized = false;

  const escapeHtml = (text) => String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

  const scheduleTask = (fn) => {
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(fn, { timeout: 500 });
    } else if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(fn);
    } else {
      setTimeout(fn, 0);
    }
  };

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

    /**
     * Initialize Mermaid with configuration
     * @private
     */
    _initMermaid: function() {
      if (mermaidInitialized || typeof window.mermaid === 'undefined') {
        return;
      }

      try {
        window.mermaid.initialize({
          startOnLoad: false,  // We manually control rendering
          securityLevel: 'strict',
          theme: 'default'
        });
        mermaidInitialized = true;
      } catch (err) {
        console.error('Failed to initialize Mermaid:', err);
      }
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

      // Debug: Log render call
      console.log('[MarkdownRenderer.render] Called with options:', options, 'Text starts with:', text.substring(0, 80));

      // 1. Check if this is Monadic JSON
      const isMonadic = this.isMonadicJson(text, options);
      console.log('[MarkdownRenderer.render] isMonadicJson result:', isMonadic);

      if (isMonadic) {
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
    isMonadicJson: function(text, options = {}) {
      if (!text) return false;

      // Forced flag takes precedence
      if (options.isMonadic) {
        return this._looksLikeMonadicJson(text);
      }

      // Apps that use Monadic structure
      const monadicApps = [
        'auto_forge_openai',
        'auto_forge_claude',
        'auto_forge_grok',
        'concept_visualizer_openai',
        'concept_visualizer_claude',
        'chat_plus_openai',
        'chat_plus_claude',
        'chat_plus_gemini',
        'chat_plus_grok',
        'chat_plus_mistral',
        'chat_plus_deepseek',
        'chat_plus_cohere',
        'chat_plus_perplexity',
        'chat_plus_ollama',
        'language_practice_plus_claude'
      ];

      const appName = options.appName;
      if (appName) {
        // Convert CamelCase to snake_case for comparison
        // e.g., "ChatPlusClaude" -> "chat_plus_claude"
        const snakeCaseAppName = appName
          .replace(/([A-Z])/g, '_$1')  // Insert _ before capitals
          .toLowerCase()
          .replace(/^_/, '');           // Remove leading _

        if (monadicApps.includes(snakeCaseAppName)) {
          return this._looksLikeMonadicJson(text);
        }
      }

      // Fallback auto-detection
      return this._looksLikeMonadicJson(text);
    },

    _looksLikeMonadicJson: function(text) {
      // Check if valid JSON with Monadic structure
      const extracted = this._extractMonadicJson(text);
      return extracted !== null;
    },

    /**
     * Sanitize JSON string by escaping raw newlines and other control characters
     * within string literals. This handles LLMs that output JSON with actual
     * newlines inside strings instead of properly escaped \n sequences.
     *
     * @param {string} jsonStr - Raw JSON string that may have unescaped newlines
     * @returns {string} Sanitized JSON string ready for JSON.parse()
     */
    _sanitizeJsonString: function(jsonStr) {
      if (!jsonStr || typeof jsonStr !== 'string') return jsonStr;

      // We need to replace raw newlines/tabs/etc. inside string values only
      // Strategy: Process character by character, tracking if we're inside a string
      let result = '';
      let inString = false;
      let escapeNext = false;

      for (let i = 0; i < jsonStr.length; i++) {
        const char = jsonStr[i];
        const charCode = jsonStr.charCodeAt(i);

        if (escapeNext) {
          // Previous char was backslash, this is an escape sequence
          result += char;
          escapeNext = false;
          continue;
        }

        if (char === '\\' && inString) {
          // Escape character inside string
          result += char;
          escapeNext = true;
          continue;
        }

        if (char === '"') {
          // Toggle string state
          inString = !inString;
          result += char;
          continue;
        }

        if (inString) {
          // Inside a string - escape control characters
          if (charCode === 0x0A) {
            // Newline -> \n
            result += '\\n';
          } else if (charCode === 0x0D) {
            // Carriage return -> \r
            result += '\\r';
          } else if (charCode === 0x09) {
            // Tab -> \t
            result += '\\t';
          } else if (charCode < 0x20) {
            // Other control characters -> \uXXXX
            result += '\\u' + charCode.toString(16).padStart(4, '0');
          } else {
            result += char;
          }
        } else {
          // Outside string - keep as-is (whitespace between JSON elements is valid)
          result += char;
        }
      }

      return result;
    },

    /**
     * Extract Monadic JSON from text, handling various formats:
     * 1. Pure JSON string
     * 2. JSON wrapped in markdown code blocks (```json ... ``` or ``` ... ```)
     * 3. Text with embedded JSON (extracts the JSON portion)
     *
     * @param {string} text - Text that may contain Monadic JSON
     * @returns {object|null} Parsed JSON object or null if not found
     */
    _extractMonadicJson: function(text) {
      if (!text || typeof text !== 'string') return null;

      // Normalize the text: trim and remove potential BOM or invisible characters
      const normalizedText = text.trim().replace(/^\uFEFF/, '');

      // Try 1: Direct parse (pure JSON)
      try {
        const obj = JSON.parse(normalizedText);
        if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
          console.log('[MonadicJSON] Successfully parsed as pure JSON');
          return obj;
        }
      } catch (e) {
        // Try with sanitization (handles raw newlines in strings)
        try {
          const sanitized = this._sanitizeJsonString(normalizedText);
          const obj = JSON.parse(sanitized);
          if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
            console.log('[MonadicJSON] Successfully parsed as pure JSON (after sanitization)');
            return obj;
          }
        } catch (e2) {
          // Not pure JSON, continue to other methods
          console.log('[MonadicJSON] Direct parse failed:', e.message, 'First 100 chars:', normalizedText.substring(0, 100));
        }
      }

      // Try 2: Extract from markdown code block (```json ... ``` or ``` ... ```)
      // Use a more flexible regex to handle various whitespace patterns
      const codeBlockPatterns = [
        /```json\s*([\s\S]*?)```/,     // ```json ... ```
        /```\s*([\s\S]*?)```/,          // ``` ... ```
        /`{3,}json\s*([\s\S]*?)`{3,}/,  // Handle multiple backticks
      ];

      for (const pattern of codeBlockPatterns) {
        const codeBlockMatch = normalizedText.match(pattern);
        if (codeBlockMatch) {
          const extractedContent = codeBlockMatch[1].trim();
          console.log('[MonadicJSON] Code block found, content starts with:', extractedContent.substring(0, 50));
          try {
            const obj = JSON.parse(extractedContent);
            if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
              console.log('[MonadicJSON] Successfully extracted from code block');
              return obj;
            }
          } catch (e) {
            // Try with sanitization (handles raw newlines in strings from Mistral, etc.)
            try {
              const sanitized = this._sanitizeJsonString(extractedContent);
              const obj = JSON.parse(sanitized);
              if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
                console.log('[MonadicJSON] Successfully extracted from code block (after sanitization)');
                return obj;
              }
            } catch (e2) {
              console.log('[MonadicJSON] Code block parse failed:', e.message);
            }
          }
        }
      }

      // Try 3: Find JSON object pattern in text
      // Use a more careful regex that finds balanced braces
      const jsonStartIndex = normalizedText.indexOf('{');
      if (jsonStartIndex !== -1) {
        // Find the matching closing brace by counting brace depth
        let depth = 0;
        let jsonEndIndex = -1;
        let inString = false;
        let escapeNext = false;

        for (let i = jsonStartIndex; i < normalizedText.length; i++) {
          const char = normalizedText[i];

          if (escapeNext) {
            escapeNext = false;
            continue;
          }

          if (char === '\\') {
            escapeNext = true;
            continue;
          }

          if (char === '"' && !escapeNext) {
            inString = !inString;
            continue;
          }

          if (!inString) {
            if (char === '{') depth++;
            if (char === '}') {
              depth--;
              if (depth === 0) {
                jsonEndIndex = i;
                break;
              }
            }
          }
        }

        if (jsonEndIndex !== -1) {
          const potentialJson = normalizedText.substring(jsonStartIndex, jsonEndIndex + 1);
          try {
            const obj = JSON.parse(potentialJson);
            if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
              console.log('[MonadicJSON] Successfully extracted JSON from text');
              return obj;
            }
          } catch (e) {
            // Try with sanitization (handles raw newlines in strings)
            try {
              const sanitized = this._sanitizeJsonString(potentialJson);
              const obj = JSON.parse(sanitized);
              if (typeof obj === 'object' && obj !== null && ('message' in obj || 'context' in obj)) {
                console.log('[MonadicJSON] Successfully extracted JSON from text (after sanitization)');
                return obj;
              }
            } catch (e2) {
              console.log('[MonadicJSON] Embedded JSON parse failed:', e.message, 'Attempted JSON:', potentialJson.substring(0, 200));
            }
          }
        }
      }

      console.log('[MonadicJSON] All extraction methods failed');
      return null;
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
        // Use extraction function to handle various formats
        const obj = typeof monadicJson === 'string'
          ? this._extractMonadicJson(monadicJson)
          : monadicJson;

        if (!obj) {
          // Extraction failed, fallback to markdown
          return this.renderMarkdown(monadicJson, options);
        }

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
        const escaped = escapeHtml(content);
        html = html.replace(
          new RegExp(`ABC_BLOCK_PLACEHOLDER_${index}`, 'g'),
          `<div class="abc-code"><pre>${escaped}</pre></div>`
        );
      });

      mermaidBlocks.forEach((content, index) => {
        const escaped = escapeHtml(content);
        html = html.replace(
          new RegExp(`MERMAID_BLOCK_PLACEHOLDER_${index}`, 'g'),
          `<div class="mermaid-code"><pre>${escaped}</pre></div>`
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

      // Initialize Mermaid once
      this._initMermaid();

      // 1. highlight.js
      if (window.SyntaxHighlight) {
        scheduleTask(() => {
          try {
            window.SyntaxHighlight.apply(container);
          } catch (err) {
            console.error('Failed to apply syntax highlighting:', err);
          }
        });
      }

      // 2. MathJax
      if (window.MathJax?.typesetPromise) {
        scheduleTask(() => {
          try {
            window.MathJax.typesetPromise([container]).catch(err => {
              console.error('MathJax rendering failed:', err);
            });
          } catch (err) {
            console.error('Failed to initialize MathJax:', err);
          }
        });
      }

      // 3. ABCJS / applyAbc
      if (typeof window.applyAbc === 'function' && window.jQuery) {
        scheduleTask(() => {
          try {
            window.applyAbc(window.jQuery(container));
          } catch (err) {
            console.error('applyAbc failed:', err);
          }
        });
      } else if (window.ABCJS) {
        scheduleTask(() => {
          try {
            const abcElements = container.querySelectorAll('.abc-notation, .abc-code');
            abcElements.forEach(el => {
              let abc = '';
              if (el.dataset.abc) {
                abc = decodeURIComponent(el.dataset.abc);
              } else {
                const pre = el.querySelector('pre');
                abc = pre ? pre.textContent : el.textContent;
              }
              if (abc) {
                window.ABCJS.renderAbc(el, abc);
              }
            });
          } catch (err) {
            console.error('ABC notation rendering failed:', err);
          }
        });
      }

      // 4. Mermaid / applyMermaid
      if (typeof window.applyMermaid === 'function' && window.jQuery) {
        scheduleTask(() => {
          try {
            window.applyMermaid(window.jQuery(container));
          } catch (err) {
            console.error('applyMermaid failed:', err);
          }
        });
      } else if (window.mermaid) {
        scheduleTask(() => {
          try {
            const mermaidElements = container.querySelectorAll('.mermaid:not([data-processed]), .mermaid-code:not([data-processed])');
            if (mermaidElements.length > 0) {
              mermaidElements.forEach(el => el.setAttribute('data-processed', 'true'));
              window.mermaid.run({ nodes: Array.from(mermaidElements) }).catch(err => {
                console.error('[MarkdownRenderer] Mermaid run() failed:', err);
              });
            }
          } catch (err) {
            console.error('Mermaid rendering failed:', err);
          }
        });
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
  console.log('[MarkdownRenderer] Module exported to window.MarkdownRenderer');

})(window);
