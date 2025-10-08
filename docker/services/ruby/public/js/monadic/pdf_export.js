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
   * Create HTML for a single message
   */
  function createMessageHTML(message) {
    const roleStyle = getRoleStyle(message.role);
    // Use the HTML property if available (already rendered), otherwise fall back to text or content
    const messageText = message.html || message.text || message.content || '';

    // Handle images if present
    let imageHTML = '';
    if (message.image) {
      if (Array.isArray(message.image)) {
        imageHTML = message.image.map(img => {
          if (img.type === 'application/pdf') {
            return `<div class="pdf-preview mb-3">
              <i class="fas fa-file-pdf text-danger"></i>
              <span class="ms-2">${img.title || 'PDF Document'}</span>
            </div>`;
          } else {
            return `<img class="base64-image mb-3" src="${img.data}" alt="${img.title || 'Image'}" style="max-width: 100%; height: auto;" />`;
          }
        }).join('');
      } else if (typeof message.image === 'string') {
        imageHTML = `<img class="base64-image mb-3" src="${message.image}" alt="Image" style="max-width: 100%; height: auto;" />`;
      }
    }

    // Handle thinking block if present
    let thinkingHTML = '';
    if (message.thinking && message.thinking.trim()) {
      thinkingHTML = `
        <div class="thinking-block mt-3">
          <div class="fw-bold mb-2">
            <i class="fas fa-brain"></i> Thinking Process
          </div>
          <div>${message.thinking}</div>
        </div>
      `;
    }

    return `
      <div class="card mt-3">
        <div class="card-header p-2 ps-3 d-flex justify-content-between">
          <div class="fs-5 card-title mb-0">
            <i class="fas ${roleStyle.icon}" style="color: ${roleStyle.color};"></i>
            <span class="fw-bold" style="color: ${roleStyle.color};">${roleStyle.label}</span>
          </div>
        </div>
        <div class="card-body role-${message.role}">
          <div class="card-text">
            ${thinkingHTML}
            ${messageText}
            ${imageHTML}
          </div>
        </div>
      </div>
    `;
  }

  /**
   * Get current app information
   */
  function getAppInfo() {
    const appName = $('#base-app-title').text() || 'Monadic Chat';
    const model = $('#model-selected').text() || 'Unknown Model';
    return { appName, model };
  }

  /**
   * Generate header HTML for the print document
   */
  function generateHeaderHTML(appInfo) {
    const now = new Date();
    const dateStr = now.toLocaleString();

    return `
      <div style="border-bottom: 2px solid #333; padding-bottom: 1rem; margin-bottom: 2rem;">
        <h1 style="margin: 0; font-size: 1.5rem;">Monadic Chat - Conversation Export</h1>
        <div style="margin-top: 0.5rem; color: #666;">
          <div><strong>App:</strong> ${appInfo.appName}</div>
          <div><strong>Model:</strong> ${appInfo.model}</div>
          <div><strong>Exported:</strong> ${dateStr}</div>
        </div>
      </div>
    `;
  }

  /**
   * Collect all CSS needed for printing
   */
  function collectStyles() {
    const styles = [];

    // Collect all style tags
    $('style').each(function() {
      styles.push(this.outerHTML);
    });

    // Collect all link tags for stylesheets
    $('link[rel="stylesheet"]').each(function() {
      const href = $(this).attr('href');
      // Create a new link tag for the print window
      styles.push(`<link rel="stylesheet" href="${href}">`);
    });

    return styles.join('\n');
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

      // Generate message cards HTML
      const messagesHTML = messagesToExport.map(msg => createMessageHTML(msg)).join('\n');

      // Collect all styles
      const stylesHTML = collectStyles();

      // Create the complete HTML document
      const printHTML = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>Monadic Chat - ${appInfo.appName} - ${new Date().toLocaleDateString()}</title>
          ${stylesHTML}
          <style>
            /* Additional print-specific styles */
            * {
              box-sizing: border-box;
            }

            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              line-height: 1.6;
              color: #333;
              max-width: 100%;
              margin: 0;
              padding: 20px;
              background: white;
            }

            .print-content {
              width: 100%;
              max-width: 100%;
              overflow: visible;
            }

            .messages-container {
              width: 100%;
              max-width: 100%;
            }

            @page {
              size: A4;
              margin: 1cm;
            }

            @media print {
              * {
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
                color-adjust: exact !important;
              }

              body {
                margin: 0;
                padding: 0;
                background: white;
                overflow: visible;
              }

              .print-content {
                width: 100%;
                overflow: visible;
              }

              .messages-container {
                width: 100%;
                overflow: visible;
              }

              /* Prevent page breaks inside message cards when possible */
              .card {
                page-break-inside: avoid;
                break-inside: avoid;
                margin-bottom: 1rem;
                overflow: visible;
              }

              /* If card is too long, allow breaking but keep header/body together */
              .card-header {
                page-break-after: avoid;
                break-after: avoid;
              }

              .card-body {
                page-break-before: avoid;
                break-before: avoid;
              }

              /* Keep header on first page */
              .print-content > div:first-child {
                page-break-after: avoid;
                break-after: avoid;
              }

              /* Handle images properly across pages */
              img {
                max-width: 100%;
                height: auto;
                page-break-inside: avoid;
                break-inside: avoid;
              }

              /* Ensure code blocks don't break badly */
              pre {
                page-break-inside: avoid;
                break-inside: avoid;
                white-space: pre-wrap;
                word-wrap: break-word;
                overflow: visible;
              }

              code {
                white-space: pre-wrap;
                word-wrap: break-word;
              }

              /* Ensure tables render properly */
              table {
                page-break-inside: avoid;
                break-inside: avoid;
                width: 100%;
              }

              /* Remove any fixed positioning or transforms */
              * {
                position: static !important;
                transform: none !important;
              }
            }
          </style>
        </head>
        <body>
          <div class="print-content">
            ${headerHTML}
            <div class="messages-container">
              ${messagesHTML}
            </div>
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
