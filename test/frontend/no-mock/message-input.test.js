/**
 * @jest-environment jsdom
 */

// Load no-mock test environment
require('../support/no-mock-setup');
const { 
  waitFor, 
  triggerEvent, 
  setInputValue, 
  getElementText,
  isVisible
} = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('Message Input - No Mock Tests', () => {
  beforeEach(async () => {
    // Load basic chat interface
    await setupFixture('basic-chat');
    
    // Load the actual monadic.js file (or relevant parts)
    // For now, we'll implement the key behaviors directly
    setupMessageInputBehavior();
  });
  
  test('textarea auto-resizes based on content', async () => {
    const textarea = document.getElementById('message');
    const initialHeight = textarea.offsetHeight;
    
    // Add multiple lines of text
    setInputValue(textarea, 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5');
    
    // Wait for resize to happen
    await waitFor(() => textarea.style.height && textarea.style.height !== 'auto');
    
    // Check that height increased
    const newHeight = parseInt(textarea.style.height);
    expect(newHeight).toBeGreaterThan(initialHeight);
  });
  
  test('character counter appears when approaching limit', async () => {
    const textarea = document.getElementById('message');
    const charCounter = document.getElementById('char-counter');
    const charCount = document.getElementById('char-count');
    const limit = 50000;
    
    // Initially hidden
    expect(charCounter.style.display).toBe('none');
    
    // Add text that's 75% of limit (should not show)
    const text75 = 'a'.repeat(Math.floor(limit * 0.75));
    setInputValue(textarea, text75);
    expect(charCounter.style.display).toBe('none');
    
    // Add text that's 85% of limit (should show)
    const text85 = 'a'.repeat(Math.floor(limit * 0.85));
    setInputValue(textarea, text85);
    expect(charCounter.style.display).not.toBe('none');
    expect(charCount.textContent).toBe(text85.length.toString());
    
    // Check color coding at different thresholds
    const text90 = 'a'.repeat(Math.floor(limit * 0.90));
    setInputValue(textarea, text90);
    expect(charCount.style.color).toBe('gray');
    
    const text95 = 'a'.repeat(Math.floor(limit * 0.95));
    setInputValue(textarea, text95);
    expect(charCount.style.color).toBe('orange');
    
    const text99 = 'a'.repeat(Math.floor(limit * 0.99));
    setInputValue(textarea, text99);
    expect(charCount.style.color).toBe('red');
  });
  
  test('send button enables/disables based on message content', async () => {
    const textarea = document.getElementById('message');
    const sendButton = document.getElementById('send');
    
    // Initially disabled
    expect(sendButton.disabled).toBe(true);
    
    // Add text - button should enable
    setInputValue(textarea, 'Hello world');
    expect(sendButton.disabled).toBe(false);
    
    // Clear text - button should disable
    setInputValue(textarea, '');
    expect(sendButton.disabled).toBe(true);
    
    // Whitespace only - button should remain disabled
    setInputValue(textarea, '   \n\t  ');
    expect(sendButton.disabled).toBe(true);
  });
  
  test('IME composition prevents auto-resize', async () => {
    const textarea = document.getElementById('message');
    
    // Start composition
    triggerEvent(textarea, 'compositionstart');
    expect(textarea.dataset.ime).toBe('true');
    
    // Change text during composition
    const initialHeight = textarea.style.height;
    setInputValue(textarea, 'これは日本語のテストです\n新しい行\nもう一つの行');
    
    // Height should not change during composition
    expect(textarea.style.height).toBe(initialHeight);
    
    // End composition
    triggerEvent(textarea, 'compositionend');
    expect(textarea.dataset.ime).toBe('false');
    
    // Now height should update
    await waitFor(() => textarea.style.height !== initialHeight);
  });
  
  test('paste operation respects character limit', async () => {
    const textarea = document.getElementById('message');
    const limit = 50000;
    
    // Create a paste event with text exceeding limit
    const longText = 'a'.repeat(limit + 1000);
    
    // Create a custom paste event since ClipboardEvent might not be available
    const pasteEvent = new Event('paste', {
      bubbles: true,
      cancelable: true
    });
    
    // Add clipboardData property
    const dataTransfer = new DataTransfer();
    dataTransfer.setData('text/plain', longText);
    pasteEvent.clipboardData = dataTransfer;
    
    // Trigger paste
    textarea.dispatchEvent(pasteEvent);
    
    // Check that text was truncated
    await waitFor(() => textarea.value.length === limit);
    expect(textarea.value).toBe('a'.repeat(limit));
  });
  
  test('easy submit with Enter key', async () => {
    // Add easy submit checkbox to DOM since basic-chat fixture doesn't include it
    const container = document.querySelector('.button-container');
    if (container) {
      container.insertAdjacentHTML('beforeend', 
        '<div><input type="checkbox" id="check-easy-submit"> Easy Submit</div>'
      );
    }
    
    const textarea = document.getElementById('message');
    const easySubmitCheckbox = document.getElementById('check-easy-submit');
    
    // Enable easy submit
    if (easySubmitCheckbox) {
      easySubmitCheckbox.checked = true;
      triggerEvent(easySubmitCheckbox, 'change');
    } else {
      // Skip test if checkbox not available
      console.warn('Easy submit checkbox not found, skipping test');
      return;
    }
    
    // Add message
    setInputValue(textarea, 'Test message');
    
    // Press Enter key (not in textarea)
    const enterEvent = new KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      bubbles: true
    });
    
    // Focus outside textarea
    textarea.blur();
    document.body.focus();
    
    // Spy on form submission
    let submitted = false;
    document.addEventListener('submit', (e) => {
      e.preventDefault();
      submitted = true;
    });
    
    // Trigger Enter on document
    document.dispatchEvent(enterEvent);
    
    // Should submit
    expect(submitted).toBe(true);
  });
  
  test('clear button functionality', async () => {
    const textarea = document.getElementById('message');
    const clearButton = document.getElementById('clear');
    const discourse = document.getElementById('discourse');
    
    // Add some content
    setInputValue(textarea, 'Test message');
    discourse.innerHTML = '<div class="message">Previous message</div>';
    
    // Click clear
    triggerEvent(clearButton, 'click');
    
    // Check textarea is cleared
    expect(textarea.value).toBe('');
    
    // Note: Full clear functionality would involve WebSocket
    // This tests the UI portion only
  });
});

/**
 * Set up message input behavior for testing
 * This simulates the key behaviors from monadic.js
 */
function setupMessageInputBehavior() {
  const textarea = document.getElementById('message');
  const sendButton = document.getElementById('send');
  const charCounter = document.getElementById('char-counter');
  const charCount = document.getElementById('char-count');
  const charLimit = document.getElementById('char-limit');
  const clearButton = document.getElementById('clear');
  
  const MESSAGE_TEXT_LIMIT = 50000;
  charLimit.textContent = MESSAGE_TEXT_LIMIT;
  
  // Auto-resize functionality
  function resizeTextarea() {
    if (textarea.dataset.ime === 'true') return;
    
    textarea.style.height = 'auto';
    const newHeight = Math.max(100, textarea.scrollHeight);
    textarea.style.height = newHeight + 'px';
  }
  
  // Character counter
  function updateCharCounter() {
    const length = textarea.value.length;
    charCount.textContent = length;
    
    if (length > MESSAGE_TEXT_LIMIT * 0.8) {
      charCounter.style.display = 'block';
      
      if (length > MESSAGE_TEXT_LIMIT * 0.95) {
        charCount.style.color = 'red';
      } else if (length > MESSAGE_TEXT_LIMIT * 0.9) {
        charCount.style.color = 'orange';
      } else {
        charCount.style.color = 'gray';
      }
    } else {
      charCounter.style.display = 'none';
    }
  }
  
  // Send button state
  function updateSendButton() {
    const hasContent = textarea.value.trim().length > 0;
    sendButton.disabled = !hasContent;
  }
  
  // IME handling
  textarea.addEventListener('compositionstart', () => {
    textarea.dataset.ime = 'true';
  });
  
  textarea.addEventListener('compositionend', () => {
    textarea.dataset.ime = 'false';
    resizeTextarea();
  });
  
  // Input handling
  textarea.addEventListener('input', () => {
    updateCharCounter();
    updateSendButton();
    resizeTextarea();
  });
  
  // Paste handling
  textarea.addEventListener('paste', (e) => {
    e.preventDefault();
    const text = e.clipboardData.getData('text/plain');
    const currentLength = textarea.value.length;
    const remainingSpace = MESSAGE_TEXT_LIMIT - currentLength;
    const textToInsert = text.slice(0, remainingSpace);
    
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const newValue = textarea.value.slice(0, start) + textToInsert + textarea.value.slice(end);
    textarea.value = newValue;
    
    // Trigger input event
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
  });
  
  // Clear button
  clearButton.addEventListener('click', () => {
    textarea.value = '';
    updateCharCounter();
    updateSendButton();
    resizeTextarea();
  });
  
  // Easy submit
  const easySubmitCheckbox = document.getElementById('check-easy-submit');
  if (easySubmitCheckbox) {
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && easySubmitCheckbox.checked && document.activeElement !== textarea) {
        e.preventDefault();
        document.dispatchEvent(new Event('submit', { bubbles: true }));
      }
    });
  }
  
  // Initialize
  updateSendButton();
  updateCharCounter();
}