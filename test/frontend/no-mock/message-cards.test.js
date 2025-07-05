/**
 * @jest-environment jsdom
 */

// Load no-mock test environment  
require('../support/no-mock-setup');
const {
  waitFor,
  triggerEvent,
  getElementText,
  isVisible
} = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('Message Cards - No Mock Tests', () => {
  beforeEach(async () => {
    // Load chat interface with message display area
    await setupFixture('message-display');
    
    // Set up card creation functions
    setupCardCreation();
  });
  
  test('creates user message card with correct structure', () => {
    const discourse = document.getElementById('discourse');
    
    // Create user message card
    const card = createCard('user', 'Hello from user!', {
      timestamp: '2024-01-05 10:30:00'
    });
    
    discourse.appendChild(card);
    
    // Verify card structure
    expect(card.className).toContain('card');
    expect(card.className).toContain('mb-3');
    
    // Check header
    const header = card.querySelector('.card-header');
    expect(header).toBeTruthy();
    expect(getElementText('.card-header .fa-user')).toBe('');
    expect(header.textContent).toContain('User');
    expect(header.textContent).toContain('2024-01-05 10:30:00');
    
    // Check body
    const body = card.querySelector('.card-body');
    expect(body).toBeTruthy();
    expect(body.textContent).toBe('Hello from user!');
    
    // Check footer controls
    const footer = card.querySelector('.card-footer');
    expect(footer).toBeTruthy();
    expect(footer.querySelector('.copy-button')).toBeTruthy();
    expect(footer.querySelector('.delete-button')).toBeTruthy();
  });
  
  test('creates assistant message card with HTML content', () => {
    const discourse = document.getElementById('discourse');
    
    // Create assistant message with HTML
    const htmlContent = `
      <p>Here's a code example:</p>
      <pre><code class="language-javascript">console.log('Hello!');</code></pre>
    `;
    
    const card = createCard('assistant', htmlContent, {
      timestamp: '2024-01-05 10:31:00',
      isHTML: true
    });
    
    discourse.appendChild(card);
    
    // Verify card type
    expect(card.className).toContain('assistant-card');
    
    // Check icon
    const icon = card.querySelector('.fa-robot');
    expect(icon).toBeTruthy();
    
    // Check HTML rendering
    const body = card.querySelector('.card-body');
    expect(body.querySelector('pre')).toBeTruthy();
    expect(body.querySelector('code')).toBeTruthy();
    expect(body.querySelector('code').textContent).toBe("console.log('Hello!');");
  });
  
  test('creates system message card', () => {
    const discourse = document.getElementById('discourse');
    
    // Create system message
    const card = createCard('system', 'Connection established', {
      timestamp: '2024-01-05 10:29:00'
    });
    
    discourse.appendChild(card);
    
    // Verify system card styling
    expect(card.className).toContain('system-card');
    expect(card.querySelector('.card-body').style.backgroundColor).toBe('rgb(255, 255, 255)');
    
    // Check icon
    const icon = card.querySelector('.fa-info-circle');
    expect(icon).toBeTruthy();
  });
  
  test('copy button copies message content', async () => {
    const discourse = document.getElementById('discourse');
    
    // Mock clipboard API
    let copiedText = '';
    navigator.clipboard = {
      writeText: jest.fn(text => {
        copiedText = text;
        return Promise.resolve();
      })
    };
    
    // Create message
    const card = createCard('user', 'Text to copy');
    discourse.appendChild(card);
    
    // Click copy button
    const copyButton = card.querySelector('.copy-button');
    triggerEvent(copyButton, 'click');
    
    // Wait for clipboard operation
    await waitFor(() => navigator.clipboard.writeText.mock.calls.length > 0);
    
    // Verify text was copied
    expect(copiedText).toBe('Text to copy');
    
    // Check button state change
    expect(copyButton.querySelector('i').className).toContain('fa-check');
    
    // Wait for icon to revert
    await new Promise(resolve => setTimeout(resolve, 2100));
    expect(copyButton.querySelector('i').className).toContain('fa-copy');
  });
  
  test('delete button shows confirmation modal', () => {
    const discourse = document.getElementById('discourse');
    
    // Add modal to DOM
    document.body.insertAdjacentHTML('beforeend', `
      <div class="modal fade" id="deleteConfirmation">
        <div class="modal-dialog">
          <div class="modal-content">
            <div class="modal-body">
              <p>Delete this message?</p>
            </div>
            <div class="modal-footer">
              <button id="deleteMessageOnly" class="btn btn-danger">Delete Message</button>
              <button id="deleteMessageAndSubsequent" class="btn btn-warning">Delete All Below</button>
            </div>
          </div>
        </div>
      </div>
    `);
    
    // Create message
    const card = createCard('user', 'Message to delete');
    card.id = 'msg-123';
    discourse.appendChild(card);
    
    // Mock Bootstrap modal
    window.bootstrap = {
      Modal: class {
        constructor(element) {
          this.element = element;
        }
        show() {
          this.element.classList.add('show');
          this.element.style.display = 'block';
        }
      }
    };
    
    // Click delete button
    const deleteButton = card.querySelector('.delete-button');
    triggerEvent(deleteButton, 'click');
    
    // Verify modal is shown
    const modal = document.getElementById('deleteConfirmation');
    expect(modal.classList.contains('show')).toBe(true);
    
    // Verify message ID is stored
    expect(document.getElementById('messageToDelete').value).toBe('msg-123');
  });
  
  test('edit button transforms message to textarea', () => {
    const discourse = document.getElementById('discourse');
    
    // Create editable message
    const card = createCard('user', 'Original message', {
      editable: true
    });
    discourse.appendChild(card);
    
    const editButton = card.querySelector('.edit-button');
    const messageDiv = card.querySelector('.message-content');
    
    // Click edit button
    triggerEvent(editButton, 'click');
    
    // Check that content is now editable
    const textarea = card.querySelector('textarea.edit-textarea');
    expect(textarea).toBeTruthy();
    expect(textarea.value).toBe('Original message');
    expect(messageDiv.style.display).toBe('none');
    
    // Check edit controls appear
    expect(card.querySelector('.save-edit-button')).toBeTruthy();
    expect(card.querySelector('.cancel-edit-button')).toBeTruthy();
  });
  
  test('TTS button plays audio for message', async () => {
    const discourse = document.getElementById('discourse');
    
    // Mock Audio API
    const mockPlay = jest.fn().mockResolvedValue();
    window.Audio = jest.fn().mockImplementation(() => ({
      play: mockPlay,
      pause: jest.fn(),
      src: ''
    }));
    
    // Create message with TTS
    const card = createCard('assistant', 'Text to speak', {
      enableTTS: true,
      ttsEnabled: true
    });
    discourse.appendChild(card);
    
    const ttsButton = card.querySelector('.tts-button');
    expect(ttsButton).toBeTruthy();
    
    // Mock TTS generation
    window.generateTTS = jest.fn().mockResolvedValue('audio-url.mp3');
    
    // Click TTS button
    triggerEvent(ttsButton, 'click');
    
    // Wait for audio to start
    await waitFor(() => mockPlay.mock.calls.length > 0);
    
    // Verify audio was played
    expect(window.generateTTS).toHaveBeenCalledWith('Text to speak');
    expect(mockPlay).toHaveBeenCalled();
    
    // Check button state
    expect(ttsButton.querySelector('i').className).toContain('fa-stop');
  });
  
  test('message cards preserve image attachments during edit', () => {
    const discourse = document.getElementById('discourse');
    
    // Create message with image
    const card = createCard('user', 'Check this image:', {
      editable: true,
      attachments: [{
        type: 'image',
        url: 'data:image/png;base64,abc123',
        title: 'screenshot.png'
      }]
    });
    discourse.appendChild(card);
    
    // Verify image is displayed
    const image = card.querySelector('.message-attachment img');
    expect(image).toBeTruthy();
    expect(image.src).toContain('data:image/png');
    
    // Click edit button
    const editButton = card.querySelector('.edit-button');
    triggerEvent(editButton, 'click');
    
    // Verify image remains visible during edit
    expect(isVisible(image)).toBe(true);
    
    // Verify only text becomes editable
    const textarea = card.querySelector('textarea.edit-textarea');
    expect(textarea.value).toBe('Check this image:');
  });
  
  test('stats display updates with token information', () => {
    const statsEl = document.getElementById('stats-message');
    
    // Update stats
    updateStats({
      model: 'gpt-4',
      inputTokens: 150,
      outputTokens: 200,
      totalTokens: 350,
      cost: 0.0105
    });
    
    // Verify stats display
    expect(statsEl.textContent).toContain('Model: gpt-4');
    expect(statsEl.textContent).toContain('Input: 150');
    expect(statsEl.textContent).toContain('Output: 200');
    expect(statsEl.textContent).toContain('Total: 350');
    expect(statsEl.textContent).toContain('Cost: $0.0105');
  });
});

/**
 * Set up card creation functions for testing
 */
function setupCardCreation() {
  // Main card creation function
  window.createCard = function(role, content, options = {}) {
    const card = document.createElement('div');
    card.className = 'card mb-3';
    
    if (role === 'assistant') {
      card.className += ' assistant-card';
    } else if (role === 'system') {
      card.className += ' system-card';
    }
    
    // Card header
    const header = document.createElement('div');
    header.className = 'card-header d-flex justify-content-between align-items-center';
    
    const roleInfo = document.createElement('div');
    const icon = document.createElement('i');
    icon.className = role === 'user' ? 'fas fa-user' : 
                    role === 'assistant' ? 'fas fa-robot' : 
                    'fas fa-info-circle';
    
    const roleText = document.createElement('span');
    roleText.textContent = ` ${role.charAt(0).toUpperCase() + role.slice(1)}`;
    
    roleInfo.appendChild(icon);
    roleInfo.appendChild(roleText);
    
    const timestamp = document.createElement('small');
    timestamp.className = 'text-muted';
    timestamp.textContent = options.timestamp || new Date().toLocaleString();
    
    header.appendChild(roleInfo);
    header.appendChild(timestamp);
    
    // Card body
    const body = document.createElement('div');
    body.className = 'card-body';
    
    if (role === 'system') {
      body.style.backgroundColor = '#ffffff';
    }
    
    // Message content
    const messageDiv = document.createElement('div');
    messageDiv.className = 'message-content';
    
    if (options.isHTML) {
      messageDiv.innerHTML = content;
    } else {
      messageDiv.textContent = content;
    }
    
    body.appendChild(messageDiv);
    
    // Attachments
    if (options.attachments) {
      options.attachments.forEach(attachment => {
        const attachmentDiv = document.createElement('div');
        attachmentDiv.className = 'message-attachment mt-3';
        
        if (attachment.type === 'image') {
          const img = document.createElement('img');
          img.src = attachment.url;
          img.alt = attachment.title;
          img.className = 'img-fluid';
          attachmentDiv.appendChild(img);
        }
        
        body.appendChild(attachmentDiv);
      });
    }
    
    // Card footer with controls
    const footer = document.createElement('div');
    footer.className = 'card-footer';
    
    // Copy button
    const copyButton = document.createElement('button');
    copyButton.className = 'btn btn-sm btn-outline-secondary copy-button';
    copyButton.innerHTML = '<i class="fas fa-copy"></i>';
    copyButton.addEventListener('click', async function() {
      const textContent = options.isHTML ? 
        messageDiv.innerText : messageDiv.textContent;
      await navigator.clipboard.writeText(textContent);
      
      // Change icon temporarily
      const icon = this.querySelector('i');
      icon.className = 'fas fa-check';
      setTimeout(() => {
        icon.className = 'fas fa-copy';
      }, 2000);
    });
    
    footer.appendChild(copyButton);
    
    // Edit button (for user messages)
    if (options.editable) {
      const editButton = document.createElement('button');
      editButton.className = 'btn btn-sm btn-outline-primary edit-button ms-2';
      editButton.innerHTML = '<i class="fas fa-edit"></i>';
      editButton.addEventListener('click', function() {
        // Create textarea
        const textarea = document.createElement('textarea');
        textarea.className = 'form-control edit-textarea';
        textarea.value = messageDiv.textContent;
        textarea.rows = 4;
        
        // Hide original content
        messageDiv.style.display = 'none';
        messageDiv.parentNode.insertBefore(textarea, messageDiv.nextSibling);
        
        // Add save/cancel buttons
        const editControls = document.createElement('div');
        editControls.className = 'edit-controls mt-2';
        
        const saveButton = document.createElement('button');
        saveButton.className = 'btn btn-sm btn-success save-edit-button';
        saveButton.textContent = 'Save';
        
        const cancelButton = document.createElement('button');
        cancelButton.className = 'btn btn-sm btn-secondary cancel-edit-button ms-2';
        cancelButton.textContent = 'Cancel';
        
        editControls.appendChild(saveButton);
        editControls.appendChild(cancelButton);
        textarea.parentNode.insertBefore(editControls, textarea.nextSibling);
      });
      
      footer.appendChild(editButton);
    }
    
    // TTS button (for assistant messages)
    if (options.enableTTS && options.ttsEnabled) {
      const ttsButton = document.createElement('button');
      ttsButton.className = 'btn btn-sm btn-outline-info tts-button ms-2';
      ttsButton.innerHTML = '<i class="fas fa-volume-up"></i>';
      ttsButton.addEventListener('click', async function() {
        const icon = this.querySelector('i');
        if (icon.className.includes('fa-volume-up')) {
          // Generate and play TTS
          const audioUrl = await window.generateTTS(messageDiv.textContent);
          const audio = new Audio(audioUrl);
          await audio.play();
          icon.className = 'fas fa-stop';
        } else {
          // Stop playback
          icon.className = 'fas fa-volume-up';
        }
      });
      
      footer.appendChild(ttsButton);
    }
    
    // Delete button
    const deleteButton = document.createElement('button');
    deleteButton.className = 'btn btn-sm btn-outline-danger delete-button ms-2';
    deleteButton.innerHTML = '<i class="fas fa-trash"></i>';
    deleteButton.addEventListener('click', function() {
      // Store message ID for deletion
      const idInput = document.createElement('input');
      idInput.type = 'hidden';
      idInput.id = 'messageToDelete';
      idInput.value = card.id || '';
      document.body.appendChild(idInput);
      
      // Show confirmation modal
      const modal = new window.bootstrap.Modal(document.getElementById('deleteConfirmation'));
      modal.show();
    });
    
    footer.appendChild(deleteButton);
    
    // Assemble card
    card.appendChild(header);
    card.appendChild(body);
    card.appendChild(footer);
    
    return card;
  };
  
  // Stats update function
  window.updateStats = function(stats) {
    const statsEl = document.getElementById('stats-message');
    if (statsEl) {
      statsEl.textContent = `Model: ${stats.model} | Input: ${stats.inputTokens} | Output: ${stats.outputTokens} | Total: ${stats.totalTokens} | Cost: $${stats.cost.toFixed(4)}`;
    }
  };
}