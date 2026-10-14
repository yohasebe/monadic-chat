# No-Mock UI Tests

The tests in `test/frontend/no-mock/` run real code against a real jsdom DOM: they load HTML fixtures, fire real DOM events and check the resulting DOM state, without global mocks.

## Running

```bash
npm run test:no-mock                          # all no-mock tests
npm run test:no-mock:watch                    # watch mode
npm run test:no-mock message-input.test.js    # one file
```

`JEST_MODE=no-mock` selects the no-mock configuration in `config/jest/jest.config.js`: only `test/frontend/no-mock/**/*.test.js`, with no `setupFilesAfterEnv`. The regular `npm test` also runs these files.

## Files

| File | Content |
|---|---|
| `message-input.test.js` | Message textarea behavior and validation |
| `message-cards.test.js` | Message display and interaction |
| `websocket-ui-behavior.test.js` | UI behavior around WebSocket messages |
| `test/frontend/support/no-mock-setup.js` | jsdom environment |
| `test/frontend/support/test-utilities.js` | Interaction helpers |
| `test/frontend/support/fixture-loader.js` | HTML fixtures |

## Helpers

`test-utilities.js`:

- `waitFor(fn)`, `waitForElement(selector, timeout)`
- `triggerEvent(elementOrSelector, eventType, data)`, `setInputValue(elementOrSelector, value)`, `selectFile(selector, fileData)`
- `getElementText(selector)`, `isVisible(elementOrSelector)`
- `loadFixture`, `loadScript`
- `createTestWSServer(port = 8081)` returns `{ server, getMessages, clearMessages, broadcast(message), waitForMessage(matcher, timeout) }`

`fixture-loader.js`:

- `setupFixture(nameOrHTML)` puts a named fixture (`basic-chat`, `chat-with-modals`, `settings-panel`, `message-display`) or an HTML string into the DOM.
- `createMinimalFixture(options)`, `loadCommonFixture(name)`, `extractHTMLSection`, `prepareDOM`.

## Writing a Test

```javascript
require('../support/no-mock-setup');
const { waitFor, triggerEvent, setInputValue } = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('Feature', () => {
  beforeEach(async () => {
    await setupFixture('basic-chat');
  });

  test('user action changes the DOM', async () => {
    setInputValue('#message', 'Hello world');
    triggerEvent('#send', 'click');
    await waitFor(() => document.querySelectorAll('.message').length > 0);
    expect(document.querySelector('.message').textContent).toBe('Hello world');
  });
});
```

Rules:

- Check what the user sees (DOM state), not calls on a stand-in.
- Fire events on elements instead of calling handlers directly.
- Wait for asynchronous changes with `waitFor` / `waitForElement`, not fixed timeouts.
- Close any test WebSocket server in the test.

## Debugging

- `console.log(document.body.innerHTML)` shows the DOM.
- Raise the timeout of `waitFor` / `waitForElement` for slow steps.
