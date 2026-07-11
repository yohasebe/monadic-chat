/**
 * PDF Export Module
 * Exports conversation history as a printable PDF using browser print functionality.
 *
 * Message bodies reuse the already-rendered on-screen HTML (the DOM `.card-text`
 * of each message card), and the live page's own stylesheets (markdown styling,
 * KaTeX, highlight.js, monadic.css, and print.css) are cloned into the print
 * iframe. As a result the PDF matches what the user sees on screen instead of
 * showing raw markdown.
 */

(function() {
  'use strict';

  /**
   * Get role label/color based on message role
   */
  function getRoleStyle(role) {
    const styles = {
      user: { icon: 'fa-face-smile', color: '#4CACDC', label: 'User' },
      assistant: { icon: 'fa-robot', color: '#DC4C64', label: 'Assistant' },
      system: { icon: 'fa-bars', color: '#22ad50', label: 'System' }
    };
    return styles[role] || styles.system;
  }

  /**
   * Escape HTML special characters
   */
  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * Render markdown the same way the live UI does, with a plain-text fallback.
   */
  function renderMarkdownSafe(text) {
    if (window.MarkdownRenderer && typeof window.MarkdownRenderer.render === 'function') {
      try {
        return window.MarkdownRenderer.render(text);
      } catch (e) {
        // fall through to escaped plain text
      }
    }
    return `<p>${escapeHtml(text || '').replace(/\n\n+/g, '</p><p>').replace(/\n/g, '<br>')}</p>`;
  }

  /**
   * Resolve the rendered HTML body for a message.
   * Prefers the exact HTML on screen (DOM .card-text), then server-sent HTML,
   * then a client-side markdown render, then escaped plain text.
   * Returns { html, complete } where complete=true means images/media are
   * already embedded in the html (so they must not be appended again).
   */
  function getRenderedMessage(message) {
    const mid = message.mid || message.id;
    if (mid) {
      const cardEl = document.getElementById(mid);
      const cardText = cardEl && cardEl.querySelector('.card-text');
      if (cardText) {
        return { html: cardText.innerHTML, complete: true };
      }
    }
    if (message.html) {
      return { html: message.html, complete: true };
    }
    if (message.text || message.content) {
      return { html: renderMarkdownSafe(message.text || message.content), complete: false };
    }
    return { html: '', complete: false };
  }

  /**
   * A static PDF can't play media; replace <audio>/<video> with a short note.
   */
  function neutralizeMedia(html) {
    if (!html || (html.indexOf('<audio') === -1 && html.indexOf('<video') === -1)) {
      return html;
    }
    const tmp = document.createElement('div');
    tmp.innerHTML = html;
    tmp.querySelectorAll('audio, video').forEach((el) => {
      let src = el.getAttribute('src');
      if (!src) {
        const source = el.querySelector('source');
        src = source ? source.getAttribute('src') : '';
      }
      let name = 'media';
      if (src) {
        const tail = src.split('/').pop();
        try { name = decodeURIComponent(tail); } catch (e) { name = tail; }
      }
      const note = document.createElement('div');
      note.className = 'pdf-media-note';
      note.style.cssText = 'margin:0.5em 0; padding:0.4rem 0.6rem; border:1px solid #ddd; border-radius:4px; color:#555;';
      note.textContent = (el.tagName.toLowerCase() === 'video' ? '🎬 ' : '🔊 ') + name;
      el.replaceWith(note);
    });
    return tmp.innerHTML;
  }

  /**
   * Image markup for messages that came from a text-only fallback. The DOM and
   * server-HTML paths already include their images, so this is only used when
   * the body was rebuilt from plain text.
   */
  function buildImageHTML(message) {
    const img = message.image || message.images;
    if (!img) return '';
    if (Array.isArray(img)) {
      return img.map((item) => {
        if (item && item.type === 'application/pdf') {
          return `<div style="margin:1em 0; padding:0.5rem; border:1px solid #ddd; border-radius:4px;">📄 ${escapeHtml(item.title || 'PDF Document')}</div>`;
        }
        const src = (item && (item.data || item.src)) || '';
        return `<img src="${src}" alt="${escapeHtml((item && item.title) || 'Image')}" style="max-width:100%; height:auto; margin:1em 0;" />`;
      }).join('');
    }
    if (typeof img === 'string') {
      return `<img src="${img}" alt="Image" style="max-width:100%; height:auto; margin:1em 0;" />`;
    }
    return '';
  }

  /**
   * Clone the live page's stylesheets so the print iframe renders identically.
   * Brings in markdown styling (monadic.css), KaTeX, highlight.js, and the
   * print-tuned rules in print.css (media="print").
   */
  function clonePageStyles() {
    let out = '';
    document.querySelectorAll('link[rel="stylesheet"]').forEach((link) => {
      if (!link.href) return;
      // link.href is already resolved to an absolute URL, so it loads correctly
      // inside the document.write()'n iframe regardless of its base URL.
      const media = (link.media && link.media !== 'all') ? ` media="${link.media}"` : '';
      out += `<link rel="stylesheet" href="${link.href}"${media}>`;
    });
    document.querySelectorAll('style').forEach((style) => {
      out += `<style>${style.textContent}</style>`;
    });
    return out;
  }

  /**
   * Print-context overrides applied AFTER the cloned page styles to neutralize
   * the app's screen layout (flex/sidebar) and keep messages flowing across
   * pages without wasted space.
   */
  function getPrintOverrides() {
    return `
      <style>
        html, body {
          display: block !important;
          width: auto !important;
          height: auto !important;
          min-height: 0 !important;
          max-width: none !important;
          background: #fff !important;
          color: #000 !important;
          margin: 0 !important;
          padding: 0 !important;
          overflow: visible !important;
        }
        @page { size: A4; margin: 1.5cm; }
        #pdf-root { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; }
        .pdf-message { margin-bottom: 1.5rem; page-break-inside: auto; }
        .pdf-message-header { font-weight: bold; margin-bottom: 0.5rem; color: #333; page-break-after: avoid; }
        .pdf-message-box { background: #fff; padding: 1rem; border: 1px solid #ddd; border-radius: 4px; }
        .pdf-message-box > .card-text { color: #000; }
        .pdf-message-box .card-text img { max-width: 100% !important; height: auto !important; }
        audio, video { display: none !important; }
      </style>
    `;
  }

  /**
   * Create HTML for a single message using the on-screen rendered body.
   */
  function createMessageHTML(message) {
    const roleStyle = getRoleStyle(message.role);
    const roleClass = 'role-' + (message.role || 'system');

    const rendered = getRenderedMessage(message);
    let bodyHTML = neutralizeMedia(rendered.html);
    if (!rendered.complete) {
      bodyHTML += buildImageHTML(message);
    }

    let thinkingHTML = '';
    if (message.thinking && message.thinking.trim()) {
      thinkingHTML = `
        <div class="thinking-block">
          <div class="thinking-block-header">Thinking Process</div>
          <div class="card-text">${neutralizeMedia(renderMarkdownSafe(message.thinking))}</div>
        </div>`;
    }

    return `
      <div class="pdf-message">
        <div class="pdf-message-header">${roleStyle.label}</div>
        <div class="pdf-message-box ${roleClass}">
          ${thinkingHTML}
          <div class="card-text">${bodyHTML}</div>
        </div>
      </div>
    `;
  }

  /**
   * Get current app information
   */
  function getAppInfo() {
    const appTitleEl = $id('base-app-title');
    const modelSelectedEl = $id('model-selected');
    const appName = (appTitleEl && appTitleEl.textContent) || 'Monadic Chat';
    const modelText = (modelSelectedEl && modelSelectedEl.textContent) || 'Unknown Model';

    // Parse provider and model from text like "OpenAI (gpt-4o)" or "OpenAI (gpt-4o - high)"
    let provider = 'Unknown Provider';
    let model = modelText;

    const match = modelText.match(/^([^(]+)\s*\(([^)]+)\)$/);
    if (match) {
      provider = match[1].trim();
      model = match[2].trim();
    }

    return { appName, provider, model };
  }

  /**
   * Generate header HTML for the print document
   */
  function generateHeaderHTML(appInfo) {
    const now = new Date();
    const dateStr = now.toLocaleString();

    // Get translated labels (with English fallback)
    const title = webUIi18n ? webUIi18n.t('ui.messages.pdfExportTitle') : 'Monadic Chat - Conversation Export';
    const appLabel = webUIi18n ? webUIi18n.t('ui.messages.pdfApp') : 'App';
    const providerLabel = webUIi18n ? webUIi18n.t('ui.messages.pdfProvider') : 'Provider';
    const modelLabel = webUIi18n ? webUIi18n.t('ui.messages.pdfModel') : 'Model';
    const exportedLabel = webUIi18n ? webUIi18n.t('ui.messages.pdfExported') : 'Exported';

    return `
      <div style="border-bottom: 2px solid #333; padding-bottom: 1rem; margin-bottom: 2rem;">
        <h1 style="margin: 0; font-size: 1.5rem;">${title}</h1>
        <div style="margin-top: 0.5rem; color: #666;">
          <div><strong>${appLabel}:</strong> ${escapeHtml(appInfo.appName)}</div>
          <div><strong>${providerLabel}:</strong> ${escapeHtml(appInfo.provider)}</div>
          <div><strong>${modelLabel}:</strong> ${escapeHtml(appInfo.model)}</div>
          <div><strong>${exportedLabel}:</strong> ${escapeHtml(dateStr)}</div>
        </div>
      </div>
    `;
  }

  /**
   * Busy state for the export button: building the print document and
   * cloning stylesheets takes a moment, so show a spinner until the
   * print dialog opens (or the export fails). Restored on every exit
   * path of exportConversationToPDF.
   */
  function setExportPdfBusy(busy) {
    const btn = (typeof $id === 'function') ? $id('export-pdf') : document.getElementById('export-pdf');
    if (!btn) return;
    btn.disabled = busy;
    const icon = btn.querySelector('i');
    if (icon) {
      icon.className = busy ? 'fas fa-spinner fa-spin' : 'fas fa-file-pdf';
    }
  }

  /**
   * Main export function
   */
  window.exportConversationToPDF = function() {
    setExportPdfBusy(true);
    try {
      // Get messages from SessionState if available, otherwise use global messages array
      let messagesToExport;
      if (window.SessionState && window.SessionState.getMessages) {
        messagesToExport = window.SessionState.getMessages();
      } else if (window.messages) {
        messagesToExport = window.messages;
      } else {
        const noMessagesText = webUIi18n ? webUIi18n.t('ui.messages.noMessagesToExport') : 'No messages to export';
        setExportPdfBusy(false);
        alert(noMessagesText);
        return;
      }

      // Check if there are messages to export
      if (!messagesToExport || messagesToExport.length === 0) {
        const noMessagesText = webUIi18n ? webUIi18n.t('ui.messages.noMessagesToExport') : 'No messages to export';
        setExportPdfBusy(false);
        alert(noMessagesText);
        return;
      }

      // Deduplicate messages by mid (keep last) or identical role+text to avoid double assistant entries
      const dedupedMessages = (() => {
        const result = [];
        const seen = new Map(); // mid -> index

        messagesToExport.forEach((msg) => {
          const mid = msg.mid || msg.id;
          if (mid) {
            if (seen.has(mid)) {
              // Replace existing entry with newer one
              result[seen.get(mid)] = msg;
            } else {
              seen.set(mid, result.length);
              result.push(msg);
            }
          } else {
            const prev = result[result.length - 1];
            if (prev && prev.role === msg.role && (prev.text || prev.content) === (msg.text || msg.content)) {
              // Skip exact duplicate
              return;
            }
            result.push(msg);
          }
        });
        return result;
      })();

      // Get app information
      const appInfo = getAppInfo();

      // Generate header
      const headerHTML = generateHeaderHTML(appInfo);

      // Generate message cards HTML (exclude system messages)
      const messagesHTML = dedupedMessages
        .filter(msg => msg.role !== 'system')
        .map(msg => createMessageHTML(msg))
        .join('\n');

      // Reuse the live page's stylesheets so rendered content looks identical.
      const stylesHTML = clonePageStyles() + getPrintOverrides();

      // Create the complete HTML document
      const printHTML = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Monadic Chat - ${escapeHtml(appInfo.appName)} - ${new Date().toLocaleDateString()}</title>
          ${stylesHTML}
        </head>
        <body>
          <div id="pdf-root">
            ${headerHTML}
            ${messagesHTML}
          </div>
        </body>
        </html>
      `;

      // Create hidden iframe for printing
      const iframe = document.createElement('iframe');
      iframe.style.position = 'absolute';
      iframe.style.width = '0';
      iframe.style.height = '0';
      iframe.style.border = 'none';
      iframe.style.visibility = 'hidden';
      document.body.appendChild(iframe);

      // Write content to iframe
      const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
      iframeDoc.open();
      iframeDoc.write(printHTML);
      iframeDoc.close();

      // Wait for content to load, then print
      iframe.onload = function() {
        // Give cloned stylesheets (and any KaTeX fonts) a moment to load
        setTimeout(() => {
          try {
            setExportPdfBusy(false);
            iframe.contentWindow.print();
            setTimeout(() => {
              if (iframe.parentNode) {
                document.body.removeChild(iframe);
              }
            }, 100);
          } catch (error) {
            console.error('Error during print:', error);
            setExportPdfBusy(false);
            // Clean up iframe even on error
            if (iframe.parentNode) {
              document.body.removeChild(iframe);
            }
            const errorText = webUIi18n ? webUIi18n.t('ui.messages.exportError') : 'Error exporting to PDF';
            alert(`${errorText}: ${error.message}`);
          }
        }, 500);
      };

    } catch (error) {
      console.error('Error exporting to PDF:', error);
      setExportPdfBusy(false);
      const errorText = webUIi18n ? webUIi18n.t('ui.messages.exportError') : 'Error exporting to PDF';
      alert(`${errorText}: ${error.message}`);
    }
  };

})();
