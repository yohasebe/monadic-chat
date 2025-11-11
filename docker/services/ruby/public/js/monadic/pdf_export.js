/**
 * PDF Export Module
 * Exports conversation history as a printable PDF using browser print functionality
 */

(function() {
  'use strict';

  /**
   * Get role icon and color based on message role
   */
  function getRoleStyle(role) {
    const styles = {
      user: {
        icon: 'fa-face-smile',
        color: '#4CACDC',
        label: 'User'
      },
      assistant: {
        icon: 'fa-robot',
        color: '#DC4C64',
        label: 'Assistant'
      },
      system: {
        icon: 'fa-bars',
        color: '#22ad50',
        label: 'System'
      }
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
   * Create HTML for a single message
   */
  function createMessageHTML(message) {
    const roleStyle = getRoleStyle(message.role);

    // Always use the plain text property to preserve line breaks
    // Prefer text over html to avoid pre-rendered formatting issues
    let rawText = message.text || message.content || '';

    // Escape HTML characters
    let messageText = escapeHtml(rawText);

    // Convert newlines to proper HTML
    // Replace double newlines with paragraph breaks, single newlines with <br>
    messageText = messageText.replace(/\n\n+/g, '</p><p>').replace(/\n/g, '<br>');

    // Wrap in paragraph tags if not empty
    if (messageText.trim()) {
      messageText = `<p>${messageText}</p>`;
    }

    // Handle images if present
    let imageHTML = '';
    if (message.image) {
      if (Array.isArray(message.image)) {
        imageHTML = message.image.map(img => {
          if (img.type === 'application/pdf') {
            return `<div style="margin: 1em 0; padding: 0.5rem; border: 1px solid #ddd; border-radius: 4px;">
              📄 ${img.title || 'PDF Document'}
            </div>`;
          } else {
            return `<img src="${img.data}" alt="${img.title || 'Image'}" style="max-width: 100%; height: auto; margin: 1em 0;" />`;
          }
        }).join('');
      } else if (typeof message.image === 'string') {
        imageHTML = `<img src="${message.image}" alt="Image" style="max-width: 100%; height: auto; margin: 1em 0;" />`;
      }
    }

    // Handle thinking block if present
    let thinkingHTML = '';
    if (message.thinking && message.thinking.trim()) {
      const thinkingText = escapeHtml(message.thinking).replace(/\n\n+/g, '</p><p>').replace(/\n/g, '<br>');
      thinkingHTML = `
        <div style="margin-bottom: 1rem; padding: 0.75rem; background: #f5f5f5; border-left: 3px solid #999; border-radius: 2px;">
          <div style="font-weight: bold; margin-bottom: 0.5rem; color: #666;">Thinking Process</div>
          <div style="color: #555;"><p>${thinkingText}</p></div>
        </div>
      `;
    }

    return `
      <div style="margin-bottom: 1.5rem; page-break-inside: avoid;">
        <div style="font-weight: bold; margin-bottom: 0.5rem; color: #333;">
          ${roleStyle.label}
        </div>
        <div style="background: white; padding: 1rem; border: 1px solid #ddd; border-radius: 4px;">
          ${thinkingHTML}
          ${messageText}
          ${imageHTML}
        </div>
      </div>
    `;
  }

  /**
   * Get current app information
   */
  function getAppInfo() {
    const appName = $('#base-app-title').text() || 'Monadic Chat';
    const modelText = $('#model-selected').text() || 'Unknown Model';

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
          <div><strong>${appLabel}:</strong> ${appInfo.appName}</div>
          <div><strong>${providerLabel}:</strong> ${appInfo.provider}</div>
          <div><strong>${modelLabel}:</strong> ${appInfo.model}</div>
          <div><strong>${exportedLabel}:</strong> ${dateStr}</div>
        </div>
      </div>
    `;
  }

  /**
   * Get minimal CSS for printing (no external stylesheets)
   */
  function getPrintStyles() {
    return `
      <style>
        /* Font Awesome icons - minimal subset */
        .fa-face-smile:before { content: "\\1F642"; }
        .fa-robot:before { content: "\\1F916"; }
        .fa-bars:before { content: "\\2630"; }
      </style>
    `;
  }

  /**
   * Main export function
   */
  window.exportConversationToPDF = function() {
    try {
      // Get messages from SessionState if available, otherwise use global messages array
      let messagesToExport;
      if (window.SessionState && window.SessionState.getMessages) {
        messagesToExport = window.SessionState.getMessages();
      } else if (window.messages) {
        messagesToExport = window.messages;
      } else {
        const noMessagesText = webUIi18n ? webUIi18n.t('ui.messages.noMessagesToExport') : 'No messages to export';
        alert(noMessagesText);
        return;
      }

      // Check if there are messages to export
      if (!messagesToExport || messagesToExport.length === 0) {
        const noMessagesText = webUIi18n ? webUIi18n.t('ui.messages.noMessagesToExport') : 'No messages to export';
        alert(noMessagesText);
        return;
      }

      // Get app information
      const appInfo = getAppInfo();

      // Generate header
      const headerHTML = generateHeaderHTML(appInfo);

      // Generate message cards HTML (exclude system messages)
      const messagesHTML = messagesToExport
        .filter(msg => msg.role !== 'system')
        .map(msg => createMessageHTML(msg))
        .join('\n');

      // Get minimal print styles (no external CSS)
      const stylesHTML = getPrintStyles();

      // Create the complete HTML document
      const printHTML = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Monadic Chat - ${appInfo.appName} - ${new Date().toLocaleDateString()}</title>
          ${stylesHTML}
          <style>
            /* Simple print-specific styles */
            * {
              box-sizing: border-box;
              margin: 0;
              padding: 0;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              line-height: 1.6;
              color: #333;
              background: white !important;
              padding: 20px;
            }

            p {
              margin: 0.5em 0;
              white-space: pre-wrap;
              word-wrap: break-word;
            }

            p:first-of-type {
              margin-top: 0;
            }

            p:last-of-type {
              margin-bottom: 0;
            }

            img {
              max-width: 100%;
              height: auto;
              display: block;
              margin: 1em 0;
            }

            @page {
              size: A4;
              margin: 1cm;
            }

            @media print {
              body {
                background: white !important;
              }

              * {
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
                background: white !important;
              }
            }
          </style>
        </head>
        <body>
          ${headerHTML}
          ${messagesHTML}
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
        // Wait a bit for styles to load
        setTimeout(() => {
          try {
            // Check if MathJax is available in the iframe
            if (iframe.contentWindow.MathJax && iframe.contentWindow.MathJax.typesetPromise) {
              iframe.contentWindow.MathJax.typesetPromise().then(() => {
                iframe.contentWindow.print();
                // Remove iframe after print dialog is shown
                setTimeout(() => {
                  if (iframe.parentNode) {
                    document.body.removeChild(iframe);
                  }
                }, 100);
              }).catch((err) => {
                console.error('MathJax rendering error:', err);
                iframe.contentWindow.print();
                setTimeout(() => {
                  if (iframe.parentNode) {
                    document.body.removeChild(iframe);
                  }
                }, 100);
              });
            } else {
              // No MathJax, print immediately
              iframe.contentWindow.print();
              setTimeout(() => {
                if (iframe.parentNode) {
                  document.body.removeChild(iframe);
                }
              }, 100);
            }
          } catch (error) {
            console.error('Error during print:', error);
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
      const errorText = webUIi18n ? webUIi18n.t('ui.messages.exportError') : 'Error exporting to PDF';
      alert(`${errorText}: ${error.message}`);
    }
  };

})();
