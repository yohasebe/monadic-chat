# Claude Code Documentation

## Testing Commands

The Monadic Chat project uses both Ruby and JavaScript tests. You can run the tests using the following Rake tasks:

- `rake spec` - Run Ruby tests only
- `rake jstest` - Run only passing JavaScript tests
- `rake jstest_all` - Run all JavaScript tests
- `rake test` - Run both Ruby and JavaScript tests

You can also run the JavaScript tests directly using npm:

- `npm test` - Run all JavaScript tests
- `npm run test:watch` - Run JavaScript tests in watch mode
- `npm run test:coverage` - Run JavaScript tests with coverage report

## Test Environment

- Ruby tests use RSpec and are located in docker/services/ruby/spec
- JavaScript tests use Jest and are located in test/frontend
- The Jest configuration is defined in jest.config.js
- Global test setup for JavaScript is in test/setup.js
- Shared testing utilities are in test/helpers.js

## Test Fixes Implemented

The JavaScript tests have been fixed to address several issues:

1. **FormData Mock Improvements**:
   - Created proper class-based mocks for FormData
   - Used local mock instances instead of global mock tracking
   - Added proper spy functionality to track FormData.append calls
   - Fixed ajax calls to properly resolve in tests

2. **jQuery Mock Improvements**:
   - Fixed attr(), val(), and other chainable method implementations
   - Created reliable selector state tracking with Map
   - Implemented proper return values for method chains

3. **Test Isolation**:
   - Created isolated mocks for each test
   - Used more try-catch blocks for error testing instead of expect().rejects
   - Fixed async test handling with proper Promise resolution

4. **Test Environment**:
   - Added implementation for expect.objectContaining()
   - Improved timer mocking with jest.useFakeTimers() and jest.runAllTimers()
   - Fixed modal testing with proper event handling

5. **Standardized Test Utilities**:
   - Created a shared helpers.js utility file with common testing functions
   - Implemented setupTestEnvironment() for consistent test environment setup
   - Added createJQueryObject() and createJQueryMock() for consistent jQuery mocking
   - Added cleanup functions to restore the original environment after tests

## Best Practices

When updating JavaScript files or tests, consider these points:

1. **Mock Management**: Create local mocks for tests instead of relying on global mocks
2. **Isolation**: Store and restore original implementations when overriding globals
3. **Error Testing**: Use try-catch blocks for testing errors in async functions
4. **jQuery Testing**: Use the createJQueryObject helper for consistent jQuery mocking
5. **FormData Testing**: Create a class-based mock with proper append tracking
6. **Ajax Testing**: Use mockImplementation to create proper responses and avoid timeouts
7. **Environment Setup**: Use setupTestEnvironment() from helpers.js for consistent test setup
8. **Test Cleanup**: Always use the cleanup function returned by setupTestEnvironment() to restore the original state

## Code Coverage

The JavaScript tests now provide improved coverage:

- form-handlers.js: 90.76% statements, 86.66% branches, 100% functions
- websocket-handlers.js: 98.61% statements, 98.11% branches, 85.71% functions
- ui-utilities.js: 88.88% statements, 64.28% branches, 90% functions
- cards.js: Basic test coverage with mock implementations
- websocket.js: Basic test coverage for key functions

The remaining uncovered code mostly relates to edge cases and error handling.

## Using Test Helpers

Here's an example of how to use the new test helpers:

```javascript
// Import the helpers
const { setupTestEnvironment } = require('../helpers');

describe('My Test Suite', () => {
  // Keep track of the test environment
  let testEnv;
  
  beforeEach(() => {
    // Set up a standard test environment with HTML
    testEnv = setupTestEnvironment({
      bodyHtml: '<div id="test-element"></div>',
      messages: [], // Optional messages array
      mids: new Set() // Optional message IDs set
    });
    
    // Your additional setup code...
  });
  
  afterEach(() => {
    // Clean up the test environment
    testEnv.cleanup();
    
    // Reset all mocks
    jest.resetAllMocks();
  });
  
  it('should do something with jQuery', () => {
    // Create a mock jQuery object for a selector
    const mockElement = testEnv.createJQueryObject('#test-selector');
    
    // Set up the mock element
    mockElement.val('test');
    
    // Use the mock in your test
    // ...
    
    // Make assertions
    expect(mockElement.val()).toBe('test');
  });
});
```