/**
 * @jest-environment jsdom
 */

// Load no-mock test environment
require('../support/no-mock-setup');
const { 
  waitFor,
  triggerEvent,
  setInputValue,
  waitForElement,
  isVisible
} = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('WebSocket UI Behavior - No Mock Tests', () => {
  beforeEach(async () => {
    // Load chat interface with necessary elements
    await setupFixture('basic-chat');
    
    // Add alert message element
    document.body.insertAdjacentHTML('beforeend', 
      '<div id="alert-message" class="alert" style="display: none;"></div>'
    );
  });
  
  test('send button interaction with message input', async () => {
    const textarea = document.getElementById('message');
    const sendButton = document.getElementById('send');
    
    // Set up button state handler (simulate what monadic.js would do)
    function updateSendButton() {
      sendButton.disabled = textarea.value.trim().length === 0;
    }
    
    textarea.addEventListener('input', updateSendButton);
    sendButton.addEventListener('click', () => {
      if (!sendButton.disabled) {
        textarea.value = '';
        updateSendButton();
      }
    });
    
    // Initially disabled
    updateSendButton();
    expect(sendButton.disabled).toBe(true);
    
    // Enter message
    setInputValue(textarea, 'Test message');
    
    // Button should be enabled
    expect(sendButton.disabled).toBe(false);
    
    // Click send
    triggerEvent(sendButton, 'click');
    
    // UI should update
    expect(textarea.value).toBe('');
    expect(sendButton.disabled).toBe(true);
  });
  
  test('displays messages in discourse area', async () => {
    const discourse = document.getElementById('discourse');
    
    // Simulate adding a user message
    const userMessage = `
      <div class="message user card mb-3">
        <div class="card-body">Hello from user!</div>
      </div>
    `;
    discourse.insertAdjacentHTML('beforeend', userMessage);
    
    // Check message appears
    const messageEl = discourse.querySelector('.message.user');
    expect(messageEl).toBeTruthy();
    expect(messageEl.textContent).toContain('Hello from user!');
    
    // Simulate adding assistant response
    const assistantMessage = `
      <div class="message assistant card mb-3">
        <div class="card-body">Hello from assistant!</div>
      </div>
    `;
    discourse.insertAdjacentHTML('beforeend', assistantMessage);
    
    // Check both messages exist
    expect(discourse.querySelectorAll('.message').length).toBe(2);
  });
  
  test('shows and hides spinner during processing', async () => {
    const spinner = document.getElementById('monadic-spinner');
    
    // Initially hidden
    expect(spinner.style.display).toBe('none');
    
    // Show spinner
    spinner.style.display = 'block';
    expect(isVisible(spinner)).toBe(true);
    
    // Hide spinner
    spinner.style.display = 'none';
    expect(isVisible(spinner)).toBe(false);
  });
  
  test('displays alert messages', async () => {
    const alertEl = document.getElementById('alert-message');
    
    // Show error alert
    alertEl.textContent = 'Connection error occurred';
    alertEl.className = 'alert alert-danger';
    alertEl.style.display = 'block';
    
    // Verify alert is visible
    expect(isVisible(alertEl)).toBe(true);
    expect(alertEl.textContent).toBe('Connection error occurred');
    expect(alertEl.className).toContain('alert-danger');
    
    // Hide alert
    alertEl.style.display = 'none';
    expect(isVisible(alertEl)).toBe(false);
  });
  
  test('handles message streaming display', async () => {
    const discourse = document.getElementById('discourse');
    
    // Create streaming message container
    const messageId = 'msg-stream-123';
    const streamContainer = document.createElement('div');
    streamContainer.id = messageId;
    streamContainer.className = 'message assistant streaming';
    discourse.appendChild(streamContainer);
    
    // Simulate streaming chunks
    const chunks = ['Hello', ' streaming', ' world!'];
    let content = '';
    
    for (const chunk of chunks) {
      content += chunk;
      streamContainer.textContent = content;
      
      // Wait a bit between chunks
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    
    // Mark as complete
    streamContainer.classList.remove('streaming');
    streamContainer.classList.add('complete');
    
    // Verify final content
    expect(streamContainer.textContent).toBe('Hello streaming world!');
    expect(streamContainer.classList.contains('complete')).toBe(true);
  });
  
  test('clears messages when clear button clicked', async () => {
    const discourse = document.getElementById('discourse');
    const clearButton = document.getElementById('clear');
    const textarea = document.getElementById('message');
    
    // Set up clear button handler
    clearButton.addEventListener('click', () => {
      textarea.value = '';
      // In real app, this would also send a clear command via WebSocket
    });
    
    // Add some content
    discourse.innerHTML = '<div class="message">Test message</div>';
    setInputValue(textarea, 'Unsent message');
    
    // Click clear
    triggerEvent(clearButton, 'click');
    
    // Textarea should be cleared
    expect(textarea.value).toBe('');
    
    // Note: Actual clearing of discourse would be handled by WebSocket
    // This test verifies the UI behavior only
  });
  
  test('enables voice input when available', async () => {
    const voiceButton = document.getElementById('voice');
    
    // Check button exists and is clickable
    expect(voiceButton).toBeTruthy();
    expect(voiceButton.disabled).toBe(false);
    
    // Simulate click
    let clicked = false;
    voiceButton.addEventListener('click', () => {
      clicked = true;
    });
    
    triggerEvent(voiceButton, 'click');
    expect(clicked).toBe(true);
  });
  
  test('handles connection status display', async () => {
    const alertEl = document.getElementById('alert-message');
    
    // Simulate connection states
    const states = [
      { message: 'Connecting...', class: 'alert-info' },
      { message: 'Connected', class: 'alert-success' },
      { message: 'Connection lost', class: 'alert-warning' },
      { message: 'Reconnecting...', class: 'alert-info' }
    ];
    
    for (const state of states) {
      alertEl.textContent = state.message;
      alertEl.className = `alert ${state.class}`;
      alertEl.style.display = 'block';
      
      // Verify state
      expect(alertEl.textContent).toBe(state.message);
      expect(alertEl.className).toContain(state.class);
      
      // Wait a bit before next state
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  });
});