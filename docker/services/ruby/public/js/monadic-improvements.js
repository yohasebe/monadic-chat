// Improvements for monadic context display

document.addEventListener('DOMContentLoaded', function() {
  // Function to check if content is empty
  function isEmptyContent(contentElement) {
    if (!contentElement) return true;
    
    const text = contentElement.textContent.trim();
    return text === '' || text === '{}' || text === '[]';
  }
  
  // An empty object of a JSON tree (kept in cards of earlier versions) does
  // not open: within root, or the whole document.
  function handleEmptyObjects(root) {
    (root || document).querySelectorAll('.json-item').forEach(item => {
      const header = item.querySelector('.json-header');
      const content = item.querySelector('.json-content');

      if (header && content && isEmptyContent(content)) {
        item.classList.add('empty-object');
        header.onclick = null;
        content.style.display = 'none';
      }
    });
  }

  // "no value" in such a tree is shown as one
  function styleNoValueText(root) {
    (root || document).querySelectorAll('.json-item span').forEach(span => {
      if (span.textContent.trim() === 'no value') {
        span.classList.add('no-value');
      }
    });
  }

  // Run on page load
  handleEmptyObjects();
  styleNoValueText();

  // New content: only what was added is looked at, and only when it holds
  // such a tree. A reply that streams adds nodes many times a second.
  const observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      mutation.addedNodes.forEach(function(node) {
        if (node.nodeType !== 1) return;
        const root = node.closest('.json-item') || node;
        if (!root.matches('.json-item') && !root.querySelector('.json-item')) return;
        const scope = root.matches('.json-item') ? root.parentNode || root : root;
        handleEmptyObjects(scope);
        styleNoValueText(scope);
      });
    });
  });

  // Observe the document body for changes
  observer.observe(document.body, {
    childList: true,
    subtree: true
  });

  // Store observer globally for cleanup
  if (!window.monadicObservers) {
    window.monadicObservers = [];
  }
  window.monadicObservers.push(observer);
});

// Override the existing toggleItem function to check for empty content
if (typeof toggleItem === 'function') {
  const originalToggleItem = toggleItem;
  
  window.toggleItem = function(element) {
    // Check if parent is marked as empty object
    const parentItem = element.closest('.json-item');
    if (parentItem && parentItem.classList.contains('empty-object')) {
      return; // Do nothing for empty objects
    }
    
    // Call original function
    originalToggleItem(element);
  };
}