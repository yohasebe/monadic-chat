/**
 * Unified Markdown renderer with support for:
 * - Code highlighting (highlight.js)
 * - KaTeX math expressions
 * - ABC notation
 * - Mermaid diagrams
 */

(function(window) {
  'use strict';

  // markdown-it instance (will be initialized when markdown-it is loaded)
  let md = null;

  // Canonical escapeHtml lives in text-utils.js (window.escapeHtml), loaded
  // earlier in the bundle. This delegate also escapes single quotes —
  // harmless in the <pre> text contexts used below (renders identically).
  const escapeHtml = (text) => window.escapeHtml(text);

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

      // Whitelist the in-app `mc:` URL scheme so RAG citations of the
      // form `[Title](mc:conv:abc-123)` survive markdown-it's default
      // URL sanitization. The library-panel intercepts clicks on these
      // and opens the Conversation Viewer modal.
      const origValidateLink = md.validateLink;
      md.validateLink = function(url) {
        if (typeof url === 'string' && url.indexOf('mc:') === 0) return true;
        return origValidateLink(url);
      };

      // Override link renderer:
      //   - external links open in a new tab (existing behavior)
      //   - mc: links stay in-page so the click handler can intercept them;
      //     we tag them with data-mc-link for the global click handler.
      const defaultLinkOpen = md.renderer.rules.link_open ||
        function(tokens, idx, options, _env, self) {
          return self.renderToken(tokens, idx, options);
        };

      md.renderer.rules.link_open = function(tokens, idx, options, env, self) {
        const token = tokens[idx];
        const hrefIdx = token.attrIndex('href');
        const href = hrefIdx >= 0 ? token.attrs[hrefIdx][1] : '';
        const isMcLink = typeof href === 'string' && href.indexOf('mc:') === 0;

        if (isMcLink) {
          // Tag for the global click handler; do NOT open in a new tab.
          if (token.attrIndex('data-mc-link') < 0) {
            token.attrPush(['data-mc-link', href]);
          }
          if (token.attrIndex('class') < 0) {
            token.attrPush(['class', 'mc-conv-link']);
          }
          return defaultLinkOpen(tokens, idx, options, env, self);
        }

        const targetIdx = token.attrIndex('target');
        if (targetIdx < 0) {
          token.attrPush(['target', '_blank']);
        } else {
          token.attrs[targetIdx][1] = '_blank';
        }
        const relIdx = token.attrIndex('rel');
        if (relIdx < 0) {
          token.attrPush(['rel', 'noopener noreferrer']);
        } else {
          token.attrs[relIdx][1] = 'noopener noreferrer';
        }
        return defaultLinkOpen(tokens, idx, options, env, self);
      };
    },

    // ===== Main Entry Point =====

    /**
     * Main entry point: render Markdown text
     *
     * @param {string} text - Markdown text
     * @returns {string} HTML
     */
    render: function(text) {
      if (!text) return '';

      // Strip TTS audio-control markers for display when the active provider
      // emits them (xAI today; registry-driven so new providers register a
      // sanitizer without touching this file). The raw text still reaches
      // the TTS engine via a separate backend buffer, so the voice keeps
      // its expressive markers while the transcript reads as plain speech.
      //
      // sanitizeForDisplay collapses runs of spaces/tabs (to tidy whitespace
      // left by removed markers). That must NOT touch fenced code blocks: for
      // indentation-sensitive content — notably Mermaid `mindmap`, whose
      // hierarchy IS the indentation — collapsing 2/4/6-space indents to one
      // space flattens every node and makes Mermaid throw "There can be only
      // one root". Protect fenced blocks with placeholders across the sanitize
      // call (TTS markers never appear inside code fences, so this is loss-free).
      if (typeof window !== 'undefined' && window.TtsTagSanitizer && window.TtsTagSanitizer.tagAware()) {
        var ttsCodeFences = [];
        text = text.replace(/```[\s\S]*?```/g, function(block) {
          var idx = ttsCodeFences.length;
          ttsCodeFences.push(block);
          return '\x00TTSCODEFENCE' + idx + '\x00';
        });
        text = window.TtsTagSanitizer.sanitizeForDisplay(text);
        if (ttsCodeFences.length) {
          text = text.replace(/\x00TTSCODEFENCE(\d+)\x00/g, function(_m, i) {
            return ttsCodeFences[Number(i)];
          });
        }
      }

      // Initialize markdown-it if needed
      this._initMarkdownIt();

      return this.renderMarkdown(text);
    },

    // ===== Normal Markdown Rendering =====

    /**
     * Render Markdown to HTML with placeholder protection
     *
     * @param {string} markdown - Markdown text
     * @returns {string} HTML with placeholders for special content
     */
    renderMarkdown: function(markdown) {
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

      // 0a. Protect vocabulary substitution tokens (${TOKEN}, TOKEN = UPPER_CASE) behind placeholders
      // Must run BEFORE math extraction so the token's `$` is never paired as a
      // KaTeX inline-math delimiter. Restored to the literal `${TOKEN}` AFTER all
      // other placeholder restorations so the vocabulary DOM walker can decorate it.
      // Pattern mirrors the backend/walker regex exactly: /\$\{([A-Z][A-Z_]*)\}/g
      const vocabTokens = [];
      text = text.replace(/\$\{([A-Z][A-Z_]*)\}/g, (match) => {
        const index = vocabTokens.length;
        vocabTokens.push(match);
        return `VOCAB_TOKEN_PLACEHOLDER_${index}`;
      });

      // 0. Fix emphasis with CJK punctuation
      // markdown-it has issues with **「 and similar patterns
      // Insert zero-width space (U+200B) to create proper word boundary
      // CJK opening brackets: 「『（【〈《"'｛〔
      // CJK closing brackets: 」』）】〉》"'｝〕
      const cjkOpenBrackets = `「『（【〈《"'｛〔`;
      const cjkCloseBrackets = `」』）】〉》"'｝〕`;
      // Bold: ** or __ followed by CJK opening brackets
      text = text.replace(new RegExp('(\\*\\*|__)([' + cjkOpenBrackets + '])', 'g'), '$1\u200B$2');
      // Bold: CJK closing brackets followed by ** or __
      text = text.replace(new RegExp('([' + cjkCloseBrackets + '])(\\*\\*|__)', 'g'), '$1\u200B$2');
      // Italic: * or _ (single) followed by CJK opening brackets (but not ** or __)
      text = text.replace(new RegExp('(?<!\\*)(\\*)(?!\\*)([' + cjkOpenBrackets + '])', 'g'), '$1\u200B$2');
      text = text.replace(new RegExp('(?<!_)(_)(?!_)([' + cjkOpenBrackets + '])', 'g'), '$1\u200B$2');
      // Italic: CJK closing brackets followed by * or _ (single)
      text = text.replace(new RegExp('([' + cjkCloseBrackets + '])(\\*)(?!\\*)', 'g'), '$1\u200B$2');
      text = text.replace(new RegExp('([' + cjkCloseBrackets + '])(_)(?!_)', 'g'), '$1\u200B$2');

      // 1. Protect math block expressions (KaTeX) behind placeholders
      const mathBlocks = [];
      text = text.replace(/\$\$([\s\S]+?)\$\$/g, (match, content) => {
        const index = mathBlocks.length;
        mathBlocks.push(content);
        return `MATH_BLOCK_PLACEHOLDER_${index}`;
      });

      // 2. Protect math inline expressions (KaTeX) behind placeholders
      const mathInline = [];
      text = text.replace(/\$(.+?)\$/g, (match, content) => {
        const index = mathInline.length;
        mathInline.push(content);
        return `MATH_INLINE_PLACEHOLDER_${index}`;
      });

      // 3. Protect ABC notation behind placeholders
      const abcBlocks = [];
      text = text.replace(/```abc\n([\s\S]+?)```/g, (match, content) => {
        const index = abcBlocks.length;
        abcBlocks.push(content);
        return `ABC_BLOCK_PLACEHOLDER_${index}`;
      });

      // 4. Protect Mermaid diagrams behind placeholders
      const mermaidBlocks = [];
      text = text.replace(/```mermaid\n([\s\S]+?)```/g, (match, content) => {
        const index = mermaidBlocks.length;
        mermaidBlocks.push(content);
        return `MERMAID_BLOCK_PLACEHOLDER_${index}`;
      });

      // 5. Protect DrawIO diagrams behind placeholders
      const drawioBlocks = [];
      // 5a. Fenced code blocks: ```drawio ... ``` (case-insensitive, flexible whitespace)
      text = text.replace(/```[Dd]raw[Ii][Oo]\s*\n([\s\S]+?)```/g, (match, content) => {
        const index = drawioBlocks.length;
        drawioBlocks.push(content);
        return `DRAWIO_BLOCK_PLACEHOLDER_${index}`;
      });
      // 5b. Raw DrawIO XML without code fences (auto-detect <mxfile>...</mxfile>)
      // Requires <diagram inside to prevent false positives from prose mentions of <mxfile>
      text = text.replace(/(<\?xml[^>]*\?>\s*\n)?<mxfile\b[\s\S]*?<diagram\b[\s\S]*?<\/mxfile>/g, (match) => {
        const index = drawioBlocks.length;
        drawioBlocks.push(match);
        return `DRAWIO_BLOCK_PLACEHOLDER_${index}`;
      });

      // 5. Convert Markdown to HTML with markdown-it
      let html = md.render(text);

      // 6-9. Restore placeholders (replacing directly with KaTeX-rendered HTML)
      // A placeholder is put back by its whole number (10 is not 1 followed
      // by 0), with its text as it is ($ in it is not a replacement pattern).
      var katexMacros = { "\\R": "\\mathbb{R}", "\\N": "\\mathbb{N}", "\\Z": "\\mathbb{Z}", "\\Q": "\\mathbb{Q}", "\\C": "\\mathbb{C}" };
      mathBlocks.forEach((content, index) => {
        var rendered;
        if (typeof katex !== 'undefined') {
          try {
            rendered = katex.renderToString(content.trim(), { displayMode: true, throwOnError: false, trust: true, macros: katexMacros });
          } catch (e) { rendered = `$$${content}$$`; }
        } else {
          rendered = `$$${content}$$`;
        }
        html = html.replace(
          new RegExp(`MATH_BLOCK_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => rendered
        );
      });

      mathInline.forEach((content, index) => {
        var rendered;
        if (typeof katex !== 'undefined') {
          try {
            rendered = katex.renderToString(content.trim(), { displayMode: false, throwOnError: false, trust: true, macros: katexMacros });
          } catch (e) { rendered = `$${content}$`; }
        } else {
          rendered = `$${content}$`;
        }
        html = html.replace(
          new RegExp(`MATH_INLINE_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => rendered
        );
      });

      abcBlocks.forEach((content, index) => {
        const escaped = escapeHtml(content);
        html = html.replace(
          new RegExp(`ABC_BLOCK_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => `<div class="abc-code"><pre>${escaped}</pre></div>`
        );
      });

      mermaidBlocks.forEach((content, index) => {
        const escaped = escapeHtml(content);
        html = html.replace(
          new RegExp(`MERMAID_BLOCK_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => `<div class="mermaid-code"><pre>${escaped}</pre></div>`
        );
      });

      drawioBlocks.forEach((content, index) => {
        const escaped = escapeHtml(content);
        html = html.replace(
          new RegExp(`DRAWIO_BLOCK_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => `<div class="drawio-code"><pre>${escaped}</pre></div>`
        );
      });

      // 10. Restore vocabulary tokens to their literal `${TOKEN}` form
      // Done LAST so the returned HTML contains the literal text the vocabulary
      // DOM walker (ws-vocabulary-handler.js) looks for and decorates.
      vocabTokens.forEach((original, index) => {
        html = html.replace(
          new RegExp(`VOCAB_TOKEN_PLACEHOLDER_${index}(?!\\d)`, 'g'),
          () => original
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
        scheduleTask(() => {
          try {
            window.SyntaxHighlight.apply(container);
          } catch (err) {
            console.error('Failed to apply syntax highlighting:', err);
          }
        });
      }

      // 2. KaTeX — rendered inline during renderMarkdown() via placeholders
      // (No post-processing needed; KaTeX HTML is already in the rendered output)

      // 3. ABCJS / applyAbc (lazy-loaded, ~472 KB deferred)
      if (typeof window.applyAbc === 'function') {
        scheduleTask(() => {
          try {
            window.applyAbc(container);
          } catch (err) {
            console.error('applyAbc failed:', err);
          }
        });
      } else {
        // Check if there are ABC elements before loading the library
        const abcElements = container.querySelectorAll('.abc-notation, .abc-code');
        if (abcElements.length > 0) {
          scheduleTask(() => {
            (window.LazyLoader ? window.LazyLoader.abcjs() : Promise.resolve()).then(() => {
              if (!window.ABCJS) return;
              try {
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
            }).catch(err => console.error('Failed to load ABCjs:', err));
          });
        }
      }

      // 4. The kinds the page draws (Mermaid diagrams): render-registry.js
      if (window.Renderers) {
        scheduleTask(() => {
          try {
            window.Renderers.apply(container);
          } catch (err) {
            console.error('Drawing failed:', err);
          }
        });
      }

      // 5. DrawIO / applyDrawIO
      if (typeof window.applyDrawIO === 'function') {
        scheduleTask(() => {
          try {
            window.applyDrawIO(container);
          } catch (err) {
            console.error('applyDrawIO failed:', err);
          }
        });
      }
    },

    /**
     * Render and apply all renderers in one call
     *
     * @param {string} text - Markdown text
     * @param {HTMLElement} container - Container to insert rendered HTML
     */
    renderAndApply: function(text, container) {
      const html = this.render(text);
      if (container) {
        // Sanitize before the innerHTML sink (library panel, etc. render
        // stored model output through this path without createCard).
        container.innerHTML = typeof window.sanitizeModelHtml === 'function'
          ? window.sanitizeModelHtml(html)
          : window.escapeHtml(html);
        this.applyRenderers(container);
      }
      return html;
    }
  };

  // Export to global scope
  window.MarkdownRenderer = MarkdownRenderer;

})(window);
