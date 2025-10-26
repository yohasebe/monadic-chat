# No-Mock UI Testing

This directory contains UI tests that follow a no-mock approach, testing real behavior instead of mock implementations.

## Current Status

✅ **24 tests passing** across 3 test suites
- Message Input: 7 tests passing  
- Message Cards: 9 tests passing
- WebSocket UI Behavior: 8 tests passing

All tests are successfully running without mocks!

## Philosophy

### Problems with Heavy Mocking

Traditional mock-based frontend testing has several issues:

1. **Over-Mocking**: Tests verify mock behavior, not real code
   - Mock implementations may not match actual library behavior
   - Changes to library usage require updating mocks
   - False confidence: tests pass but real browser fails

2. **Brittleness**: Tests break when implementation details change
   - Tightly coupled to jQuery method calls
   - Requires maintaining complex mock systems
   - Refactoring becomes difficult

3. **Maintenance Burden**: Complex mock infrastructure
   - Global mock objects in `test/setup.js`
   - Event handler tracking in global variables
   - Mock chaining for jQuery-style APIs

4. **Limited Coverage**: Mocks can't catch integration issues
   - Real DOM interactions
   - Browser API quirks
   - Timing and race conditions

### Benefits of No-Mock Approach

The no-mock approach provides significant advantages:

1. **Reliability**: Tests reflect actual user behavior
2. **Maintainability**: No mock updates needed when implementation changes
3. **Confidence**: Catches real integration issues
4. **Documentation**: Tests serve as usage examples
5. **Debugging**: Easier to debug real code vs mock interactions

### Core Principles

- **Use Real DOM**: jsdom provides actual DOM functionality
- **Load Real Libraries**: Actual jQuery, MathJax, mermaid
- **Test User Workflows**: Focus on integration over isolated functions
- **Verify Actual State**: Check actual DOM state, not mock calls
- **Real Event Handling**: Use real DOM events and propagation

### Example: Mock-Based vs No-Mock

**Mock-Based Pattern (❌ Fragile)**:
```javascript
test('send button triggers message submission', () => {
  // Setup mocks
  const sendHandler = global.eventHandlers['#send']['click'];
  $('#message').val.mockReturnValue('test message');
  global.WebSocketClient.send = jest.fn();

  // Execute mock handler
  sendHandler();

  // Verify mock calls
  expect(global.WebSocketClient.send).toHaveBeenCalledWith('test message');
});
```

**Problems**:
- Tests mock implementation, not real behavior
- Requires global event handler tracking
- Doesn't test actual DOM updates
- Can't catch real WebSocket issues

**No-Mock Pattern (✅ Robust)**:
```javascript
test('send button triggers message submission', async () => {
  // Load real HTML fixture
  document.body.innerHTML = await loadFixture('chat-interface.html');

  // Load real JavaScript libraries
  await loadScript('/js/jquery.min.js');
  await loadScript('/js/monadic/websocket.js');

  // Set up test WebSocket server
  const wsServer = new WS.Server({ port: 8081 });
  const receivedMessages = [];
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

  // Wait for real WebSocket message
  await waitFor(() => {
    expect(receivedMessages).toHaveLength(1);
    expect(receivedMessages[0].content).toBe('test message');
  });

  // Verify actual DOM state
  expect(messageInput.value).toBe('');
  expect(sendButton.disabled).toBe(true);

  // Cleanup
  wsServer.close();
});
```

**Benefits**:
- Tests real user flow from input to WebSocket
- Uses actual DOM and libraries
- Catches real integration issues
- No mock maintenance needed

## Running Tests

```bash
# Install dependencies first
npm install

# Run all no-mock tests
npm run test:no-mock

# Run in watch mode for development
npm run test:no-mock:watch

# Run a specific test file
npm run test:no-mock message-input.test.js
```

## Test Structure

### Test Environment Setup
- `support/no-mock-setup.js` - Configures jsdom with real DOM environment
- `support/test-utilities.js` - Helper functions for common test operations
- `support/fixture-loader.js` - Loads HTML fixtures for testing

### Test Categories
- `message-input.test.js` - Message textarea behavior and validation
- `websocket-ui-behavior.test.js` - WebSocket UI behavior and handling
- `message-cards.test.js` - Message display and interaction

## Writing No-Mock Tests

### Basic Test Structure

```javascript
// Load the no-mock environment
require('../support/no-mock-setup');
const { waitFor, triggerEvent, setInputValue } = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('Feature Name', () => {
  beforeEach(async () => {
    // Load HTML fixture
    await setupFixture('basic-chat');
    
    // Initialize any required behavior
    setupFeatureBehavior();
  });
  
  test('user interaction produces expected result', async () => {
    // Perform real user actions
    const input = document.getElementById('message');
    setInputValue(input, 'Hello world');
    
    const button = document.getElementById('send');
    triggerEvent(button, 'click');
    
    // Wait for and verify results
    await waitFor(() => {
      const messages = document.querySelectorAll('.message');
      return messages.length > 0;
    });
    
    // Check actual DOM state
    expect(document.querySelector('.message').textContent).toBe('Hello world');
  });
});
```

### Available Test Utilities

#### DOM Interaction
- `waitForElement(selector, timeout)` - Wait for element to appear
- `triggerEvent(element, eventType, data)` - Trigger real DOM events
- `setInputValue(element, value)` - Set input value with events
- `getElementText(selector)` - Get normalized text content
- `isVisible(element)` - Check if element is visible

#### WebSocket Testing
- `createTestWSServer(port)` - Create test WebSocket server
- `waitForMessage(server, matcher)` - Wait for specific message
- `broadcast(server, message)` - Send message to clients

#### Fixture Loading
- `setupFixture(name)` - Load predefined HTML fixture
- `createMinimalFixture(options)` - Create custom fixture
- `loadScript(path)` - Load JavaScript files

## Best Practices

1. **Test User Behavior, Not Implementation**
   ```javascript
   // Good - tests what user sees
   expect(getElementText('#alert')).toBe('Connection error');
   
   // Bad - tests implementation detail
   expect(mockAlert.calls[0][0]).toBe('Connection error');
   ```

2. **Use Real Events**
   ```javascript
   // Good - real event propagation
   triggerEvent(button, 'click');
   
   // Bad - calling handler directly
   buttonClickHandler();
   ```

3. **Wait for Async Operations**
   ```javascript
   // Good - waits for actual change
   await waitFor(() => document.querySelector('.success'));
   
   // Bad - assumes timing
   setTimeout(() => {
     expect(document.querySelector('.success')).toBeTruthy();
   }, 1000);
   ```

4. **Test Complete Workflows**
   ```javascript
   // Good - tests full user flow
   test('user can send and edit message', async () => {
     // Send message
     setInputValue('#message', 'Hello');
     triggerEvent('#send', 'click');
     
     // Wait for display
     await waitForElement('.message');
     
     // Edit message
     triggerEvent('.edit-button', 'click');
     setInputValue('.edit-textarea', 'Hello edited');
     triggerEvent('.save-button', 'click');
     
     // Verify edit
     expect(getElementText('.message')).toBe('Hello edited');
   });
   ```

## Debugging Tests

1. **Console Logging**: Real console methods work in tests
2. **DOM Inspection**: `console.log(document.body.innerHTML)`
3. **Event Debugging**: Add event listeners to track flow
4. **Timeout Issues**: Increase timeout in `waitFor` calls
5. **WebSocket Debugging**: Server logs all messages

## Migration from Mock-Based Tests

When migrating existing tests:

1. Remove all mock setup code
2. Load actual HTML fixtures
3. Replace mock method calls with real DOM interactions
4. Use `waitFor` instead of expecting immediate changes
5. Verify actual DOM state instead of mock call counts
6. Test complete user workflows

## Future Improvements

- Add Playwright for browser-based testing of critical paths
- Create more comprehensive fixtures
- Add performance benchmarks
- Implement visual regression testing
- Add accessibility testing utilities