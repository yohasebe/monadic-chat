# No-Mock UI Testing Refactoring Plan

## Overview
This document outlines the strategy for refactoring Monadic Chat's UI tests from a heavily mocked approach to a no-mock approach that tests real behavior.

## Current State Analysis

### Problems with Current Mock-Based Tests
1. **Over-mocking**: Tests are testing mock implementations rather than actual behavior
2. **Brittle Tests**: Changes to jQuery usage require mock updates
3. **False Confidence**: Tests pass but don't reflect real browser behavior
4. **Maintenance Burden**: Complex mock system in `test/setup.js` and `test/helpers.js`

### Current Mock Infrastructure
- Global jQuery mock with chained methods
- Mock DOM elements created manually
- WebSocket mocks instead of real connections
- Event handlers stored in global variables
- Browser API mocks (Audio, MediaSource, etc.)

## No-Mock Testing Strategy

### Core Principles
1. **Use Real DOM**: Let jsdom provide actual DOM functionality
2. **Real Libraries**: Load actual jQuery, MathJax, mermaid libraries
3. **Integration Focus**: Test user workflows, not isolated functions
4. **Event-Driven**: Use real DOM events instead of manual triggers
5. **State Verification**: Check actual DOM state, not mock calls

### Implementation Approach

#### Phase 1: Infrastructure Setup
1. Create new test setup that loads real libraries
2. Build test utilities for common operations
3. Create DOM fixture loader for test HTML
4. Set up proper test isolation/cleanup

#### Phase 2: Core Component Tests
1. Message input and submission flow
2. WebSocket message handling (using test server)
3. UI state management (buttons, modals, etc.)
4. File upload and display

#### Phase 3: Integration Tests
1. Complete conversation flow
2. App switching behavior
3. Settings persistence
4. Error handling scenarios

### Test Structure Example

```javascript
// Old mock-based approach
test('send button triggers message submission', () => {
  const sendHandler = global.eventHandlers['#send']['click'];
  $('#message').val.mockReturnValue('test message');
  sendHandler();
  expect(global.WebSocketClient.send).toHaveBeenCalledWith('test message');
});

// New no-mock approach
test('send button triggers message submission', async () => {
  // Load actual HTML fixture
  document.body.innerHTML = await loadFixture('chat-interface.html');
  
  // Load real jQuery
  await loadScript('/js/jquery.min.js');
  await loadScript('/js/monadic.js');
  
  // Set up test WebSocket server
  const wsServer = new WS.Server({ port: 8081 });
  wsServer.on('connection', (ws) => {
    ws.on('message', (data) => {
      receivedMessages.push(JSON.parse(data));
    });
  });
  
  // Perform actual user interaction
  const messageInput = document.getElementById('message');
  messageInput.value = 'test message';
  
  const sendButton = document.getElementById('send');
  sendButton.click();
  
  // Wait for WebSocket message
  await waitFor(() => {
    expect(receivedMessages).toHaveLength(1);
    expect(receivedMessages[0].content).toBe('test message');
  });
  
  // Verify UI state
  expect(messageInput.value).toBe('');
  expect(sendButton.disabled).toBe(true);
});
```

## Implementation Steps

### Step 1: Create Test Infrastructure
- [ ] Create `test/frontend/support/no-mock-setup.js`
- [ ] Create `test/frontend/support/test-utilities.js`
- [ ] Create `test/frontend/support/fixture-loader.js`
- [ ] Set up test WebSocket server utility

### Step 2: Refactor Core Tests
- [ ] `monadic.test.js` - Core functionality
- [ ] `websocket.test.js` - Real WebSocket communication
- [ ] `cards.test.js` - Message card creation/display
- [ ] `form-handlers.test.js` - Form submission flows

### Step 3: Create Integration Tests
- [ ] Complete conversation flow test
- [ ] Multi-modal input test (text + image + voice)
- [ ] Error recovery scenarios
- [ ] Session persistence tests

### Step 4: Clean Up
- [ ] Remove old mock infrastructure
- [ ] Update test documentation
- [ ] Update CI/CD configuration if needed

## Benefits of No-Mock Approach

1. **Reliability**: Tests reflect actual user behavior
2. **Maintainability**: No mock updates needed
3. **Confidence**: Catching real integration issues
4. **Documentation**: Tests serve as usage examples
5. **Debugging**: Easier to debug real code vs mocks

## Test Utilities Needed

### DOM Utilities
```javascript
// Wait for element to appear
async function waitForElement(selector, timeout = 5000);

// Wait for condition
async function waitFor(condition, timeout = 5000);

// Trigger real DOM event
function triggerEvent(element, eventType, eventData);
```

### WebSocket Test Server
```javascript
// Create test WebSocket server
function createTestWSServer(port);

// Wait for WebSocket message
async function waitForWSMessage(server, matcher);
```

### Fixture Management
```javascript
// Load HTML fixture
async function loadFixture(filename);

// Load script dynamically
async function loadScript(src);

// Clean up after test
function cleanupDOM();
```

## Migration Priority

1. **High Priority** (Core functionality)
   - Message sending/receiving
   - WebSocket communication
   - UI state management

2. **Medium Priority** (Features)
   - File uploads
   - Voice input
   - Settings management

3. **Low Priority** (Edge cases)
   - Browser-specific behavior
   - Performance optimizations
   - Advanced features

## Success Metrics

- All tests pass consistently
- No flaky tests
- Test execution time < 30 seconds
- Zero mock-related maintenance
- New features easily testable