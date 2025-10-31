// Improvements for monadic context display

document.addEventListener('DOMContentLoaded', function() {
  // Function to check if content is empty
  function isEmptyContent(contentElement) {
    if (!contentElement) return true;
    
    const text = contentElement.textContent.trim();
    return text === '' || text === '{}' || text === '[]';
  }
  
  // Function to handle empty objects
  function handleEmptyObjects() {
    const jsonItems = document.querySelectorAll('.json-item');
    
    jsonItems.forEach(item => {
      const header = item.querySelector('.json-header');
      const content = item.querySelector('.json-content');
      
      if (header && content && isEmptyContent(content)) {
        // Mark the parent json-item as empty
        item.classList.add('empty-object');
        
        // Remove click handler from header
        header.onclick = null;
        
        // Hide the content completely
        content.style.display = 'none';
      }
    });
  }
  
  // Function to style "no value" text
  function styleNoValueText() {
    const spans = document.querySelectorAll('.json-item span');
    
    spans.forEach(span => {
      if (span.textContent.trim() === 'no value') {
        span.classList.add('no-value');
      }
    });
  }
  
  // Run on page load
  handleEmptyObjects();
  styleNoValueText();
  
  // Also run when new content is added (for dynamic updates)
  const observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      if (mutation.addedNodes.length) {
        handleEmptyObjects();
        styleNoValueText();
      }
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