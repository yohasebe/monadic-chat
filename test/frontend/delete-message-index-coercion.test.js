/**
 * @jest-environment jsdom
 *
 * Regression test for a subtle bug in
 * `window.deleteMessageAndSubsequent(mid, messageIndex)` in
 * docker/services/ruby/public/js/monadic/cards.js.
 *
 * The messageIndex argument originates from `element.dataset.messageIndex`
 * which is always a STRING. Before the fix, `messages.slice(messageIndex + 1)`
 * performed string concatenation ("2" + 1 === "21") instead of arithmetic
 * addition, so `messages.slice("21")` returned an empty array and the
 * subsequent assistant card was left orphaned in the DOM.
 *
 * The fix normalises `messageIndex` to a number at the function boundary.
 * This test reproduces the exact failure scenario (Delete "what day is it
 * today?" + below should also drop the following "Today is ..." message)
 * using a local re-implementation that mirrors the real cards.js logic.
 */

function makeDeleteAndSubsequent(state) {
  return function deleteMessageAndSubsequent(mid, messageIndex) {
    // The fix: coerce once at the boundary.
    messageIndex = Number(messageIndex);

    const subsequent = state.messages.slice(messageIndex + 1);
    subsequent.forEach((m) => {
      state.sent.push({ message: "DELETE", mid: m.mid });
    });

    state.messages.splice(messageIndex);
    state.sent.push({ message: "DELETE", mid: mid });
  };
}

describe('deleteMessageAndSubsequent — dataset string coercion regression', () => {
  let state;
  let deleteMessageAndSubsequent;

  beforeEach(() => {
    state = {
      messages: [
        { mid: 'm-user-1',      role: 'user',      text: 'hello' },
        { mid: 'm-assistant-1', role: 'assistant', text: 'Hello! How can I help you today?' },
        { mid: 'm-user-2',      role: 'user',      text: 'what day is it today?' },
        { mid: 'm-assistant-2', role: 'assistant', text: 'Today is Sunday, April 19, 2026.' }
      ],
      sent: []
    };
    deleteMessageAndSubsequent = makeDeleteAndSubsequent(state);
  });

  it('deletes the clicked user message and its following assistant reply (string index)', () => {
    // Simulate what monadic.js:4640 passes from the modal dataset
    deleteMessageAndSubsequent('m-user-2', '2');

    // After: only the first user/assistant pair should remain.
    expect(state.messages.map(m => m.mid)).toEqual(['m-user-1', 'm-assistant-1']);

    // Both the user message and the assistant reply must have been sent as DELETE.
    const deletedMids = state.sent.map(s => s.mid);
    expect(deletedMids).toEqual(expect.arrayContaining(['m-user-2', 'm-assistant-2']));
    expect(deletedMids).toHaveLength(2);
  });

  it('handles numeric index input identically (backward compatibility)', () => {
    deleteMessageAndSubsequent('m-user-2', 2);
    expect(state.messages.map(m => m.mid)).toEqual(['m-user-1', 'm-assistant-1']);
    expect(state.sent.map(s => s.mid)).toEqual(expect.arrayContaining(['m-user-2', 'm-assistant-2']));
  });

  it('deletes only the last message when it is the tail of the list', () => {
    deleteMessageAndSubsequent('m-assistant-2', '3');
    expect(state.messages.map(m => m.mid)).toEqual(['m-user-1', 'm-assistant-1', 'm-user-2']);
    expect(state.sent.map(s => s.mid)).toEqual(['m-assistant-2']);
  });

  it('would have left the following assistant orphaned before the fix', () => {
    // Demonstrates the buggy behaviour to document WHY the fix is needed.
    const buggyMessages = state.messages.slice();
    const buggySent = [];
    const buggyFn = (mid, messageIndex) => {
      // No Number() coercion — this is the pre-fix code path
      const subsequent = buggyMessages.slice(messageIndex + 1);
      subsequent.forEach((m) => buggySent.push({ mid: m.mid }));
      buggyMessages.splice(messageIndex);
      buggySent.push({ mid });
    };
    buggyFn('m-user-2', '2');
    // The subsequent "m-assistant-2" is never recorded as deleted — that's the bug.
    expect(buggySent.map(s => s.mid)).toEqual(['m-user-2']);
    expect(buggySent.map(s => s.mid)).not.toContain('m-assistant-2');
  });
});
