/**
 * JSON Tree Toggle for Monadic Chat
 *
 * Manages expand/collapse animations and state persistence for JSON tree views
 * in the context panel. Uses CSS transitions for smooth animations.
 *
 * Extracted from utilities.js for modularity.
 */
(function() {
'use strict';

var collapseStates = {};

/**
 * Toggle expand/collapse of a JSON tree item with animation.
 * @param {HTMLElement} element - The toggle header element
 */
function toggleItem(element) {
  var content = element.nextElementSibling;
  var chevron = element.querySelector('.fa-chevron-down, .fa-chevron-right');
  var toggleText = element.querySelector('.toggle-text');

  if (!content || !chevron) {
    console.error("Element not found");
    return;
  }

  var isOpening = content.style.display === 'none' || content.style.maxHeight === '0px';

  if (isOpening) {
    // Opening: measure actual height and animate
    content.style.display = 'block';
    content.style.overflow = 'hidden';
    content.style.maxHeight = 'none';
    var actualHeight = content.scrollHeight;
    content.style.maxHeight = '0';
    content.style.transition = 'max-height 0.3s ease-out, opacity 0.3s ease-out';
    content.style.opacity = '0';

    // Force reflow
    content.offsetHeight;

    // Animate to actual height
    content.style.maxHeight = actualHeight + 'px';
    content.style.opacity = '1';

    chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Show', 'Hide');
    }

    // Remove inline max-height after animation completes
    setTimeout(function() {
      if (content.style.maxHeight !== '0px') {
        content.style.maxHeight = 'none';
        content.style.overflow = 'visible';
      }
    }, 300);
  } else {
    // Closing: set current height first, then animate to 0
    var currentHeight = content.scrollHeight;
    content.style.maxHeight = currentHeight + 'px';
    content.style.overflow = 'hidden';
    content.style.transition = 'max-height 0.3s ease-in, opacity 0.3s ease-in';

    // Force reflow
    content.offsetHeight;

    // Animate to 0
    content.style.maxHeight = '0';
    content.style.opacity = '0';

    chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
    if (toggleText) {
      toggleText.textContent = toggleText.textContent.replace('Hide', 'Show');
    }

    // Hide element after animation
    setTimeout(function() {
      if (content.style.maxHeight === '0px') {
        $hide(content);
      }
    }, 300);
  }
}

/**
 * Apply saved collapse states to all .json-item elements in the DOM.
 * Handles depth-2 context items with cross-context state propagation.
 */
function updateItemStates() {
  var items = document.querySelectorAll('.json-item');
  var contextStates = {};

  items.forEach(function(item) {
    var key = item.dataset.key;
    var depth = parseInt(item.dataset.depth);
    var content = item.querySelector('.json-content');
    var chevron = item.querySelector('.fa-chevron-down, .fa-chevron-right');

    if (!content || !chevron) return;

    var isCollapsed;
    var context = item.closest('.context');

    if (depth === 2 && context) {
      var contextKey = 'context_' + key;
      var contextIndex = Array.from(context.parentElement.children).indexOf(context);

      if (contextIndex > 0) {
        var prevContextState = contextStates[contextKey];
        if (prevContextState !== undefined) {
          isCollapsed = prevContextState;
        } else {
          isCollapsed = collapseStates[contextKey];
          if (isCollapsed === undefined) {
            isCollapsed = false;
          }
        }
      } else {
        isCollapsed = collapseStates[contextKey];
        if (isCollapsed === undefined) {
          isCollapsed = false;
        }
      }

      contextStates[contextKey] = isCollapsed;
    } else {
      isCollapsed = collapseStates[key];
      if (isCollapsed === undefined) {
        isCollapsed = false;
      }
    }

    collapseStates[key] = isCollapsed;

    if (isCollapsed) {
      $hide(content);
      chevron.classList.replace('fa-chevron-down', 'fa-chevron-right');
    } else {
      content.style.display = 'block';
      chevron.classList.replace('fa-chevron-right', 'fa-chevron-down');
    }
  });
}

/**
 * Callback for when a new element is added to the DOM.
 * Re-applies collapse states to ensure consistency.
 */
function onNewElementAdded() {
  updateItemStates();
}

/**
 * Public API to re-apply collapse states.
 */
function applyCollapseStates() {
  updateItemStates();
}

// Apply states on DOM ready
document.addEventListener('DOMContentLoaded', function() {
  updateItemStates();
});

// Export for browser environment
window.toggleItem = toggleItem;
window.updateItemStates = updateItemStates;
window.onNewElementAdded = onNewElementAdded;
window.applyCollapseStates = applyCollapseStates;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { toggleItem, updateItemStates, onNewElementAdded, applyCollapseStates };
}
})();
